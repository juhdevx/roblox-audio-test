"""Local-only media import workbench; converts files and prepares one Studio definition."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import math
import mimetypes
import os
from pathlib import Path
import queue
import re
import secrets
import signal
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from urllib.parse import parse_qs, quote, urlsplit
import uuid
import webbrowser
import zipfile

TOOLS = Path(__file__).resolve().parent
PACKAGE = TOOLS.parent
MAX_UPLOAD_BYTES = 1024 * 1024 * 1024
MAX_BATCH_FILES = 20
MAX_BATCH_BYTES = 18 * 1024 * 1024
PROFILES = {
    'leve': {'Title': 'Lightweight', 'Width': 256, 'FPS': 15, 'MaxVideoKiB': 256, 'Voices': 96,
             'Description': 'Less data and faster preparation. A good starting point for mobile.'},
    'equilibrado': {'Title': 'Balanced', 'Width': 384, 'FPS': 20, 'MaxVideoKiB': 512, 'Voices': 128,
                   'Description': 'More detail and motion, with a moderate file size.'},
    'detalhado': {'Title': 'High detail', 'Width': 512, 'FPS': 24, 'MaxVideoKiB': 512, 'Voices': 128,
                 'Description': 'Prioritizes image detail; requires more data and preparation time.'},
    'cinema': {'Title': 'Cinema (desktop)', 'Width': 960, 'FPS': 24, 'MaxVideoKiB': 512, 'Voices': 128,
               'Description': 'Targets up to 960 pixels wide. Resolution adapts to the data limit; longer conversions and more temporary disk space. Recommended for desktop.'},
    'ultra': {'Title': 'Ultra (desktop, 30 FPS)', 'Width': 1024, 'FPS': 30, 'MaxVideoKiB': 640, 'Voices': 128,
              'Description': 'Codec limit: up to 1024 px wide at 30 FPS with a 640 KiB/s video budget (RVF2 maximum). Longest conversion and most disk space; desktop only, test on a busy server before relying on it.'},
}
MEDIA_EXTENSIONS = {'.mp4', '.m4v', '.webm', '.mov', '.mp3', '.m4a', '.wav', '.ogg'}
VIDEO_EXTENSIONS = {'.mp4', '.m4v', '.webm', '.mov'}
AUDIO_ANALYSES = {'source-fit', 'phase-pan-fit', 'peaks'}
COMPARISON_FILES = {'original.wav', 'rendered.wav', 'baseline.wav', 'report.json'}
MAX_COMPARISON_BYTES = 4 * 1024 * 1024
WINDOWS_RESERVED = re.compile(r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$', re.I)
LUA_RESERVED = set('and break do else elseif end false for function if in local nil not or repeat return then true until while continue export type'.split())


def safe_name(value):
    if not isinstance(value, str) or not re.fullmatch(r'[A-Za-z0-9_]{1,40}', value) or WINDOWS_RESERVED.fullmatch(value):
        raise ValueError('Use 1 to 40 letters, digits or underscores; avoid reserved Windows names.')
    return value


def safe_filename(value):
    if (not isinstance(value, str) or not value or len(value) > 180 or value in ('.', '..')
            or any(char in value for char in '/\\:\x00<>"|?*') or any(ord(char) < 32 for char in value)
            or value.rstrip(' .') != value or WINDOWS_RESERVED.fullmatch(Path(value).stem)):
        raise ValueError('Invalid filename.')
    if Path(value).suffix.lower() not in MEDIA_EXTENSIONS:
        raise ValueError('Choose an MP4, MP3, WAV, OGG, M4A, WEBM, M4V or MOV file.')
    return value


def safe_repository(value):
    if (not isinstance(value, str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9_.-]{1,100}', value)
            or value.split('/')[-1] in ('.', '..')):
        raise ValueError('Invalid repository. Use owner/repository.')
    if value != 'juhdevx/roblox-audio-test':
        raise ValueError('This project only allows juhdevx/roblox-audio-test. Configure another repository on the server first.')
    return value


def safe_folder(value):
    if (not isinstance(value, str) or not value or len(value) > 160 or value.startswith('/') or value.endswith('/')
            or any(not re.fullmatch(r'[A-Za-z0-9_-]+', part) for part in value.split('/'))):
        raise ValueError('Invalid folder. Example: media/my_video/v1.')
    return value


def safe_revision(value):
    if value != 'main' and (not isinstance(value, str) or not re.fullmatch(r'[a-f0-9]{40}', value)):
        raise ValueError('The revision must be main or a complete 40-character commit SHA.')
    return value


def contained(path, root):
    path, root = Path(path), Path(root).resolve()
    resolved = path.resolve()
    if resolved == root or not resolved.is_relative_to(root):
        raise ValueError('The path must stay inside the work folder.')
    current = path.absolute()
    while current != root and current != current.parent:
        if current.is_symlink() or (hasattr(current, 'is_junction') and current.is_junction()):
            raise ValueError('Folder shortcuts and links are not allowed in the output.')
        current = current.parent
    return resolved


def file_sha256(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as source:
        for block in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def atomic_write(path, data):
    path = Path(path)
    if path.is_symlink():
        raise ValueError('The output cannot be a link.')
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(prefix='.' + path.name + '-', suffix='.tmp', dir=path.parent, delete=False) as output:
            temporary = Path(output.name)
            output.write(data.encode('utf-8') if isinstance(data, str) else data)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()


def atomic_install(staging, destination, root, replace=False):
    root = Path(root).resolve()
    staging, destination = contained(staging, root), contained(destination, root)
    if (destination.parent != root or not staging.is_dir() or staging == destination
            or staging.is_relative_to(destination) or destination.is_relative_to(staging)):
        raise ValueError('Invalid conversion destination.')
    backup = None
    if destination.exists():
        if not replace or not destination.is_dir():
            raise ValueError('That name already exists. Choose another or enable update with backup.')
        backups = root / 'backups'
        contained(backups, root)
        backups.mkdir(exist_ok=True)
        stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
        backup = backups / f'{destination.name}_{stamp}_{uuid.uuid4().hex[:8]}'
        contained(backup, root)
        os.replace(destination, backup)
    try:
        os.replace(staging, destination)
    except OSError:
        if backup is not None:
            os.replace(backup, destination)
        raise
    return backup


def lua_value(value, indent=0):
    if value is None:
        return 'nil'
    if isinstance(value, bool):
        return 'true' if value else 'false'
    if isinstance(value, (int, float)):
        if not math.isfinite(value):
            raise ValueError('A registry number is not finite.')
        return repr(value)
    if isinstance(value, str):
        if any(ord(char) < 32 for char in value):
            raise ValueError('Registry text contains control characters.')
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, dict):
        if not value:
            return '{}'
        lines = ['{']
        for key, item in value.items():
            field = key if re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', key) and key not in LUA_RESERVED else '[' + lua_value(key) + ']'
            lines.append('\t' * (indent + 1) + field + ' = ' + lua_value(item, indent + 1) + ',')
        lines.append('\t' * indent + '}')
        return '\n'.join(lines)
    raise ValueError('Unsupported registry value type.')


def definition_records(name, audio, video, options):
    safe_name(name)
    repo, folder, revision = safe_repository(options['Repository']), safe_folder(options['Folder']), safe_revision(options['Revision'])
    base = f'https://raw.githubusercontent.com/{repo}/{revision}/{folder}'
    audio_keys = ('Frames', 'FPS', 'Voices', 'SegmentFrames', 'Segments', 'Encoding', 'NoiseBands', 'MixGain')
    audio_entry = {key: audio[key] for key in audio_keys if key in audio}
    audio_entry.update(BaseUrl=base + '/audio', Preload=False)
    song = {'Backend': 'Spectral', 'Track': name, 'Volume': 1, 'PlaybackSpeed': 1}
    entry = {'Audio': audio_entry}
    if video is not None:
        video_keys = ('Width', 'Height', 'FPS', 'Frames', 'Duration', 'SegmentFrames', 'Segments', 'Encoding')
        entry['Video'] = {key: video[key] for key in video_keys if key in video}
        entry['Video'].update(AudioTrack=name, Title=options.get('Title') or name, Preload=False, BaseUrl=base + '/video')
        song['Video'] = name
    emote = {'Template': safe_name(options['Template']), 'Order': options['Order'],
             'Default': options['Default'], 'Exclusive': options['Exclusive'],
             'ReplaceExisting': options['ReplaceExisting'], 'Song': song}
    if video is not None:
        emote['DisableEmoteCamera'] = True
    entry['Emote'] = emote
    full = {'Version': 1, 'Entries': {name: entry}}
    public = {'Version': 1, 'Entries': {name: {'Emote': emote}}}
    return full, public


def definition_sources(name, audio, video, options):
    full, public = definition_records(name, audio, video, options)
    header = '--!strict\n-- Registers one media entry without editing the playback systems.\nreturn '
    return header + lua_value(full) + '\n', header + lua_value(public) + '\n'


def long_string(value):
    equals = '='
    while ']' + equals + ']' in value:
        equals += '='
    return '[' + equals + '[' + value + ']' + equals + ']'


HOSTED_PREFLIGHT = r'''
assert(HttpService.HttpEnabled, "Enable Game Settings > Security > Allow HTTP Requests before importing. No changes were made.")
local audioFolder = existing(shared, "SpectralAudio", "Folder")
local audioModule = existing(audioFolder, "Format", "ModuleScript")
assert(audioModule, "Update the audio system first: Shared > SpectralAudio > Format")
local AudioFormat = require(audioModule :: ModuleScript)
local VideoFormat: any = nil
if expected.Video then
    local videoFolder = existing(shared, "VideoSequence", "Folder")
    local videoModule = existing(videoFolder, "Format", "ModuleScript")
    assert(videoModule, "Update the video system first: Shared > VideoSequence > Format")
    VideoFormat = require(videoModule :: ModuleScript)
end
local function fetch(url: string, limit: number): string
    local ok, response = pcall(function() return HttpService:RequestAsync({Url = url, Method = "GET", Timeout = 10}) end)
    assert(ok, "Could not reach GitHub. Check Allow HTTP Requests and your connection, then retry. No changes were made.")
    if response.StatusCode == 404 then
        error("File not uploaded yet, or folder/SHA is incorrect: " .. url .. ". Upload all batches before importing. No changes were made.")
    end
    assert(response.Success and response.StatusCode == 200,
        "GitHub returned HTTP " .. tostring(response.StatusCode) .. ". Check the public repository and retry. No changes were made.")
    assert(type(response.Body) == "string" and #response.Body > 0 and #response.Body <= limit,
        "Invalid hosted file size: " .. url)
    return response.Body
end
local function checkTrack(kind: string, track: any, format: any)
    local metadataBody = fetch(track.BaseUrl .. "/" .. name .. ".json", 2 * 1024 * 1024)
    local decoded, metadata = pcall(function() return HttpService:JSONDecode(metadataBody) end)
    assert(decoded and type(metadata) == "table", "Invalid hosted manifest: " .. kind)
    local fields = if kind == "audio" then {"Frames", "FPS", "Voices", "SegmentFrames", "Segments", "Encoding", "NoiseBands"}
        else {"Width", "Height", "FPS", "Frames", "SegmentFrames", "Segments", "Encoding"}
    for _, field in fields do
        assert(metadata[field] == track[field], "The hosted version of " .. kind .. " differs from the package in " .. field .. ". Check the folder and commit SHA before importing.")
    end
    assert((if kind == "audio" then metadata.Name else metadata.Id) == name,
        "The hosted filename does not match the emote: " .. kind)
    assert(type(metadata.Files) == "table" and #metadata.Files == track.Segments,
        "The hosted segment list is incomplete: " .. kind)
    local parts = if track.Segments == 1 then {0} else {0, track.Segments - 1}
    for _, part in parts do
        local filename = name .. "_" .. string.format(if kind == "audio" then "%03d" else "%04d", part)
            .. (if kind == "audio" then ".spc" else ".rvf")
        local row = metadata.Files[part + 1]
        assert(type(row) == "table" and (row.File or row.file) == filename, "Invalid hosted segment name: " .. filename)
        local data = buffer.fromstring(fetch(track.BaseUrl .. "/" .. filename, 4 * 1024 * 1024))
        local valid, problem = format.Validate(data)
        assert(valid, "Corrupt or incompatible hosted file: " .. filename .. ": " .. tostring(problem))
        local header
        if kind == "audio" then
            local job = format.Begin(data)
            header = if job then job.Header else nil
        else header = format.Header(data) end
        assert(header, "Invalid hosted header: " .. filename)
        local first = part * track.SegmentFrames
        local count = math.min(track.SegmentFrames, track.Frames - first)
        assert(header.FPS == track.FPS and header.TotalFrames == track.Frames and header.Encoding == track.Encoding,
            "The header belongs to another version: " .. filename)
        if kind == "audio" then
            assert(header.Voices == track.Voices and header.NoiseBands == track.NoiseBands
                and header.First == first and header.Frames == count, "Hosted audio dimensions do not match: " .. filename)
        else
            assert(header.Width == track.Width and header.Height == track.Height
                and header.SegmentFrames == track.SegmentFrames and header.FirstFrame == first and header.FrameCount == count,
                "Hosted video dimensions do not match: " .. filename)
        end
        assert(buffer.len(data) == (row.Bytes or row.bytes) and header.Checksum == (row.Checksum or row.checksum),
            "Hosted checksum or size differs from the manifest: " .. filename)
    end
end
print("Checking the audio manifest and first/last segments on GitHub...")
checkTrack("audio", expected.Audio, AudioFormat)
if expected.Video then
    print("Checking the video manifest and first/last segments on GitHub...")
    checkTrack("video", expected.Video, VideoFormat)
end
print("Hosted files verified. Preparing the import...")
'''


def studio_import(name, server_source, public_source, replace=False, expected=None):
    if not isinstance(expected, dict) or not isinstance(expected.get('Audio'), dict):
        raise ValueError('The installer needs audio/video metadata to verify hosted files before importing.')
    template = '''--!strict
-- Paste this complete installer into Studio's Command Bar while Play is stopped.
local RunService = game:GetService("RunService")
assert(not RunService:IsRunning(), "Stop Play before importing media")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Editor = game:GetService("ScriptEditorService")
local HttpService = game:GetService("HttpService")
local name = NAME
local replacement = REPLACEMENT
local privateSource = PRIVATE_SOURCE
local publicSource = PUBLIC_SOURCE
local expected = EXPECTED_MEDIA
local function existing(parent: Instance?, childName: string, className: string): Instance?
    if not parent then return nil end
    local child = parent:FindFirstChild(childName)
    assert(not child or child.ClassName == className, "Incorrect instance class: " .. childName)
    return child
end
local shared = existing(ReplicatedStorage, "Shared", "Folder")
assert(shared, "Install the emote and media systems first")
local utils = existing(shared, "Utils", "Folder")
assert(existing(utils, "MediaLibrary", "ModuleScript"), "Update the system: Shared > Utils > MediaLibrary is missing")
local registries = existing(shared, "Registries", "Folder")
local registryModule = existing(registries, "EmoteRegistry", "ModuleScript")
assert(registryModule, "The emote registry is not installed")
local Registry = require(registryModule :: ModuleScript)
assert(type(Registry) == "table" and type(Registry.ResolveName) == "function" and type(Registry.Get) == "function", "Incompatible emote registry")
local resolved = Registry.ResolveName(name)
assert(not resolved or resolved == name, "That name already exists with different capitalization. Use the exact name: " .. tostring(resolved))
assert(Registry.Get(TEMPLATE_NAME), "Reference dance not found: " .. TEMPLATE_NAME)
local privateRoot = existing(ServerStorage, "MediaLibrary", "Folder")
local publicRoot = existing(shared, "MediaLibrary", "Folder")
local backupRoot = existing(ServerStorage, "MediaLibraryBackups", "Folder")
for _, root in {privateRoot, publicRoot} do
    if root then
        for _, child in root:GetChildren() do
            assert(string.lower(child.Name) ~= string.lower(name) or child.Name == name,
                "A definition already uses that name with different capitalization: " .. child.Name)
        end
    end
end
local private = existing(privateRoot, name, "ModuleScript") :: ModuleScript?
local public = existing(publicRoot, name, "ModuleScript") :: ModuleScript?
assert(not private or private.Source == privateSource or replacement, "A private definition already exists; enable update with backup")
assert(not public or public.Source == publicSource or replacement, "A public definition already exists; enable update with backup")
assert(not resolved or replacement or (private and private.Source == privateSource) or (public and public.Source == publicSource),
    "That emote already exists; use the exact name and enable update with backup")
HOSTED_PREFLIGHT
if private and public and private.Source == privateSource and public.Source == publicSource then
    print("Media already installed and hosted files verified: " .. name)
    return
end
local created: {Instance} = {}
local changed: {{Target: ModuleScript, Source: string}} = {}
local function create(parent: Instance, childName: string, className: string): Instance
    local value = Instance.new(className)
    value.Name = childName
    value.Parent = parent
    table.insert(created, value)
    return value
end
local function update(parent: Instance, target: ModuleScript?, source: string, side: string)
    if target and target.Source == source then return end
    if target then
        if not backupRoot then backupRoot = create(ServerStorage, "MediaLibraryBackups", "Folder") end
        local suffix = tostring(os.time()) .. "_" .. HttpService:GenerateGUID(false):gsub("%-", "")
        local backup = Instance.new("ModuleScript")
        backup.Name = name .. "_" .. side .. "_" .. suffix
        Editor:UpdateSourceAsync(backup, function() return target.Source end)
        backup.Parent = backupRoot
        table.insert(changed, {Target = target, Source = target.Source})
    else target = create(parent, name, "ModuleScript") :: ModuleScript end
    Editor:UpdateSourceAsync(target, function() return source end)
end
local ok, problem = pcall(function()
    if not privateRoot then privateRoot = create(ServerStorage, "MediaLibrary", "Folder") end
    if not publicRoot then publicRoot = create(shared :: Instance, "MediaLibrary", "Folder") end
    update(privateRoot :: Instance, private, privateSource, "Server")
    update(publicRoot :: Instance, public, publicSource, "Shared")
end)
if not ok then
    local failed = 0
    for _, old in changed do
        local restored = pcall(function() Editor:UpdateSourceAsync(old.Target, function() return old.Source end) end)
        if not restored then failed += 1 end
    end
    for index = #created, 1, -1 do
        local object = created[index]
        if object.Parent and (#object:GetChildren() == 0 or object:IsA("ModuleScript")) then object:Destroy() end
    end
    if failed > 0 then error("Import interrupted; restore the sources from ServerStorage > MediaLibraryBackups: " .. tostring(problem)) end
    error("Import cancelled; previous sources restored: " .. tostring(problem))
end
print("Media installed: " .. name .. ". Stop and restart Play to refresh the catalog.")
'''
    parsed_template = re.search(r'\bTemplate\s*=\s*("(?:[^"\\]|\\.)*")', server_source)
    if not parsed_template:
        raise ValueError('The definition does not contain a valid reference dance.')
    values = {'PRIVATE_SOURCE': long_string(server_source), 'PUBLIC_SOURCE': long_string(public_source),
              'REPLACEMENT': 'true' if replace else 'false', 'NAME': lua_value(safe_name(name)),
              'TEMPLATE_NAME': parsed_template[1], 'EXPECTED_MEDIA': lua_value(expected), 'HOSTED_PREFLIGHT': HOSTED_PREFLIGHT}
    return re.sub(r'\b(PRIVATE_SOURCE|PUBLIC_SOURCE|REPLACEMENT|TEMPLATE_NAME|EXPECTED_MEDIA|HOSTED_PREFLIGHT|NAME)\b', lambda match: values[match[1]], template)


def split_batches(files, max_files=MAX_BATCH_FILES, max_bytes=MAX_BATCH_BYTES):
    if max_files < 1 or max_bytes < 1:
        raise ValueError('Invalid batch limits.')
    batches, current, size = [], [], 0
    for item in files:
        weight = item['Bytes']
        if not isinstance(weight, int) or weight < 0 or weight > max_bytes:
            raise ValueError('A file exceeds the 18 MiB batch limit.')
        if current and (len(current) >= max_files or size + weight > max_bytes):
            batches.append(current); current, size = [], 0
        current.append(item); size += weight
    if current:
        batches.append(current)
    return batches


def metadata_files(upload, name, kind):
    upload = Path(upload)
    if upload.is_symlink() or (hasattr(upload, 'is_junction') and upload.is_junction()):
        raise ValueError('The upload folder cannot be a link.')
    upload = upload.resolve()
    manifest_path = upload / (name + '.json')
    if not manifest_path.is_file() or manifest_path.is_symlink():
        raise ValueError('The manifest for ' + kind + ' was not found.')
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    extension = '.rvf' if kind == 'video' else '.spc'
    rows = manifest.get('Files')
    if not isinstance(rows, list) or len(rows) != manifest.get('Segments'):
        raise ValueError('The manifest segment list is incomplete.')
    expected, records = {name + '.json'}, []
    for row in rows:
        filename = row.get('File', row.get('file'))
        pattern = re.escape(name) + (r'_\d{4}\.rvf' if kind == 'video' else r'_\d{3,4}\.spc')
        if not isinstance(filename, str) or not re.fullmatch(pattern, filename) or filename in expected:
            raise ValueError('Invalid segment name in the manifest.')
        expected.add(filename)
        path = contained(upload / filename, upload)
        if not path.is_file() or path.stat().st_size != row.get('Bytes', row.get('bytes')):
            raise ValueError('Incorrect size: ' + filename)
        digest = file_sha256(path)
        if row.get('SHA256') is not None and row['SHA256'] != digest:
            raise ValueError('Incorrect hash: ' + filename)
        records.append({'Name': filename, 'Bytes': path.stat().st_size, 'SHA256': digest})
    actual = {path.name for path in upload.iterdir() if path.is_file()}
    if actual != expected:
        raise ValueError('The upload folder contains extra files or missing segments: ' + kind)
    records.insert(0, {'Name': manifest_path.name, 'Bytes': manifest_path.stat().st_size, 'SHA256': file_sha256(manifest_path)})
    return manifest, records


def comparison_files(bundle):
    root = Path(bundle) / 'Comparison'
    if not root.exists():
        return []
    contained(root, bundle)
    if not root.is_dir():
        raise ValueError('Invalid listening comparison folder.')
    names = {path.name for path in root.iterdir()}
    if not {'original.wav', 'rendered.wav', 'report.json'}.issubset(names) or not names.issubset(COMPARISON_FILES):
        raise ValueError('The listening comparison is incomplete or contains unexpected files.')
    paths = []
    for name in sorted(names):
        path = contained(root / name, bundle)
        if not path.is_file() or not 0 < path.stat().st_size <= MAX_COMPARISON_BYTES:
            raise ValueError('The listening comparison exceeds the local preview limit.')
        paths.append(path)
    return paths


def prepare_bundle(bundle, name, options, source_sha='', validate=None):
    bundle = Path(bundle).resolve()
    video_path = bundle / 'upload' / (name + '.json')
    contained(video_path, bundle)
    has_video = video_path.is_file() and json.loads(video_path.read_text(encoding='utf-8')).get('Format', '').startswith('RVF')
    audio_upload = bundle / 'audio/upload' if has_video else bundle / 'upload'
    contained(audio_upload, bundle)
    audio_path = audio_upload / (name + '.json')
    if validate:
        validate('audio', audio_path)
        if has_video:
            validate('video', video_path)
    audio, audio_files = metadata_files(audio_upload, name, 'audio')
    video, video_files = metadata_files(bundle / 'upload', name, 'video') if has_video else (None, [])
    comparisons = comparison_files(bundle)
    private, public = definition_sources(name, audio, video, options)
    atomic_write(bundle / 'MediaDefinitions.luau', private)
    atomic_write(bundle / 'MediaDefinitions.Public.luau', public)
    expected = definition_records(name, audio, video, options)[0]['Entries'][name]
    atomic_write(bundle / 'StudioImport.luau', studio_import(name, private, public, options['ReplaceExisting'], expected))
    batches = []
    batch_root = bundle / 'UploadBatches'
    if batch_root.exists():
        contained(batch_root, bundle)
        if batch_root.is_symlink():
            raise ValueError('Invalid batch folder.')
        shutil.rmtree(batch_root)
    for kind, upload, files in [('video', bundle / 'upload', video_files), ('audio', audio_upload, audio_files)]:
        for index, rows in enumerate(split_batches(files), 1):
            relative = f'UploadBatches/{kind}/{index:02d}'
            destination = bundle / relative
            destination.mkdir(parents=True, exist_ok=True)
            for row in rows:
                shutil.copy2(upload / row['Name'], destination / row['Name'])
            batches.append({'Kind': kind, 'Number': index, 'Folder': relative,
                'Bytes': sum(row['Bytes'] for row in rows), 'Files': rows,
                'UploadUrl': f'https://github.com/{options["Repository"]}/upload/main/{options["Folder"]}/{kind}'})
    report = {'Version': 1, 'Name': name, 'CreatedUtc': datetime.now(timezone.utc).isoformat(),
              'OriginalFileSHA256': source_sha, 'Repository': options['Repository'], 'Folder': options['Folder'],
              'Revision': options['Revision'], 'Options': options, 'Audio': audio, 'Video': video,
              'UploadBatches': batches, 'NothingUploaded': True}
    atomic_write(bundle / 'WorkbenchManifest.json', json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    lines = [f'READY: {name}', '', '1. UPLOAD THE BATCHES',
             'Each folder below contains at most 20 files and 18 MiB. Select its files, not the folder.',
             'Finish each batch with Commit changes before opening the next one.']
    for batch in batches:
        lines.extend(['', f'{batch["Folder"]} | {len(batch["Files"])} files | {batch["Bytes"] / 1048576:.2f} MiB', batch['UploadUrl']])
    lines.extend(['', '2. IMPORT INTO STUDIO', 'Stop Play. Open View > Command Bar.',
                  'Copy ALL of StudioImport.luau and run it in the Command Bar.',
                  'The installer creates a private definition in ServerStorage and an emote-only public copy.',
                  'Install the media systems first. You do not need to edit three registries.',
                  'To replace an existing definition, enable Update with backup in the Workbench.',
                  '', '3. TEST', 'Start Play, open the preview and equip the emote.',
                  'Check volume, synchronization, looping and mobile performance.',
                  '', 'Nothing was uploaded automatically to GitHub or Roblox. The original file was preserved.',
                  'Video and audio are reconstructed; review the result before releasing it in the game.'])
    if comparisons:
        lines.extend(['', 'LISTEN BEFORE IMPORTING',
                      'Comparison/original.wav and Comparison/rendered.wav contain matching source excerpts.',
                      'They share one gain. The reconstruction is an offline sine-model preview, not a recording from Roblox.',
                      'Listen to both, then test the complete emote in-game. Results vary by song.',
                      'Comparison files are local review artifacts; do not add them to the GitHub upload batches.'])
    atomic_write(bundle / 'COMECE_AQUI.txt', '\n'.join(lines) + '\n')
    archive = bundle / 'StudioMediaPackage.zip'
    with tempfile.NamedTemporaryFile(prefix='.package-', suffix='.zip', dir=bundle, delete=False) as temporary:
        temporary_path = Path(temporary.name)
    try:
        with zipfile.ZipFile(temporary_path, 'w', zipfile.ZIP_DEFLATED, compresslevel=2) as zipped:
            for filename in ('MediaDefinitions.luau', 'MediaDefinitions.Public.luau', 'StudioImport.luau', 'WorkbenchManifest.json', 'COMECE_AQUI.txt'):
                zipped.write(bundle / filename, filename)
            for path in comparisons:
                zipped.write(path, path.relative_to(bundle).as_posix())
            for path in sorted(batch_root.rglob('*')):
                if path.is_file():
                    zipped.write(path, path.relative_to(bundle).as_posix())
        os.replace(temporary_path, archive)
    finally:
        if temporary_path.exists():
            temporary_path.unlink()
    return report


def normalize_options(payload):
    name = safe_name(payload.get('Name'))
    profile = payload.get('Profile', 'equilibrado')
    if profile not in PROFILES:
        raise ValueError('Unknown profile.')
    analysis = payload.get('AudioAnalysis', 'source-fit')
    if not isinstance(analysis, str) or analysis not in AUDIO_ANALYSES:
        raise ValueError('Unknown audio analysis. Choose Standard or Phase-aware (experimental).')
    order = payload.get('Order', 0)
    if isinstance(order, bool) or not isinstance(order, int) or not 0 <= order <= 1000000:
        raise ValueError('Order must be between 0 and 1000000; use 0 for automatic ordering.')
    for key in ('Default', 'Exclusive', 'ReplaceExisting'):
        if key in payload and not isinstance(payload[key], bool):
            raise ValueError('Invalid option: ' + key)
    title = payload.get('Title', name)
    if not isinstance(title, str) or not 1 <= len(title) <= 80 or any(ord(char) < 32 for char in title):
        raise ValueError('Invalid media title.')
    return {'Name': name, 'Profile': profile, 'AudioAnalysis': analysis,
            'Repository': safe_repository(payload.get('Repository', 'juhdevx/roblox-audio-test')),
            'Folder': safe_folder(payload.get('Folder') or f'media/{name.lower()}/v1'),
            'Revision': safe_revision(payload.get('Revision', 'main')), 'Template': safe_name(payload.get('Template', 'PaniniEvent')),
            'Order': order, 'Default': payload.get('Default', False), 'Exclusive': payload.get('Exclusive', True),
            'ReplaceExisting': payload.get('ReplaceExisting', False), 'Title': title}


class ConversionCancelled(Exception):
    """A requested stop; staged output must never replace a finished package."""


def conversion_failure(lines):
    """Show the decoder's actual reason instead of only the subprocess exit code."""
    for raw in reversed(lines):
        line = str(raw).strip()
        if line.startswith(('Conversion failed:', 'Error:', 'TypeError:', 'RangeError:', 'ValueError:', 'RuntimeError:')):
            reason = line.split(':', 1)[1].strip()
            if not reason or 'returned non-zero exit status' in reason:
                continue
            if 'Cannot create a string longer than' in reason:
                return 'The media decoder exceeded its large-file reading limit. Update the converter and try again; the original file is unchanged.'
            return 'Conversion stopped: ' + reason[:600]
    return 'Conversion stopped. Check the log below; the previous version was preserved.'


def runtime_check():
    try:
        import numpy
    except ImportError as error:
        raise ValueError('NumPy is missing from this Python. Open StartMediaWorkbench.cmd with the bundled runtime.') from error
    node = shutil.which('node') or str(Path.home() / '.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node.exe')
    if not Path(node).is_file():
        raise ValueError('Node.js was not found. Install Node.js or use the bundled runtime.')
    flags = subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0
    result = subprocess.run([node, str(TOOLS / 'check_runtime.cjs')], capture_output=True,
                            text=True, encoding='utf-8', errors='replace', timeout=30, creationflags=flags)
    if result.returncode:
        raise ValueError('Media runtime is not ready: ' + (result.stderr or result.stdout).strip()[-1200:])
    return {'Python': sys.version.split()[0], 'NumPy': numpy.__version__, 'Browser': result.stdout.strip()}


class Workbench:
    def __init__(self, package=PACKAGE):
        self.package = Path(package).resolve()
        self.tools = self.package / 'tools'
        self.root = self.package / 'workbench'
        self.imports = self.root / 'imports'
        self.generated = self.package / 'generated'
        for path in (self.root, self.imports, self.generated):
            path.mkdir(parents=True, exist_ok=True)
            if path.is_symlink() or (hasattr(path, 'is_junction') and path.is_junction()):
                raise ValueError('The work folder must be a real local folder.')
        self.token = secrets.token_urlsafe(32)
        self.uploads, self.jobs = {}, {}
        self.lock = threading.RLock()
        self.queue = queue.Queue(maxsize=4)
        threading.Thread(target=self._worker, daemon=True, name='MediaWorkbench').start()

    def log(self, job, message, phase=None, progress=None):
        with self.lock:
            if message:
                job['Log'].append(str(message).rstrip()[:2000])
                job['Log'] = job['Log'][-150:]
            if phase is not None:
                job['Phase'] = phase
            if progress is not None:
                job['Progress'] = progress

    def check_cancelled(self, job):
        if job.get('CancelEvent') is not None and job['CancelEvent'].is_set():
            raise ConversionCancelled()

    @staticmethod
    def stop_process(process):
        if process is None or process.poll() is not None:
            return
        if os.name == 'nt':
            subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                           creationflags=subprocess.CREATE_NO_WINDOW, timeout=15, check=False)
        else:
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass

    def cancel(self, identity):
        with self.lock:
            job = self.jobs.get(identity)
            if not job:
                raise ValueError('Conversion not found.')
            if job['State'] == 'Finalizing':
                raise ValueError('The checked package is being installed. Wait a moment for it to finish.')
            if job['State'] not in ('Queued', 'Running', 'Cancelling'):
                return self.public_job(job)
            queued = job['State'] == 'Queued'
            job['CancelEvent'].set()
            job['State'] = 'Cancelled' if queued else 'Cancelling'
            job['Phase'] = 'Cancelled' if queued else 'Stopping conversion'
            if queued:
                job['Ended'] = time.monotonic()
            process = job.get('Process')
            self.stop_process(process)
            return self.public_job(job)

    def install(self, job, bundle, destination, replace_existing):
        with self.lock:
            self.check_cancelled(job)
            job['State'] = 'Finalizing'
            job['Phase'] = 'Installing the verified local package'
            return atomic_install(bundle, destination, self.generated, replace_existing)

    def run(self, job, command):
        self.check_cancelled(job)
        self.log(job, ' '.join(str(part) for part in command))
        flags = subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0
        environment = dict(os.environ, PYTHONUNBUFFERED='1', PYTHONIOENCODING='utf-8')
        with subprocess.Popen([str(part) for part in command], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, text=True, encoding='utf-8', errors='replace',
                              env=environment, creationflags=flags, start_new_session=os.name != 'nt') as process:
            with self.lock:
                job['Process'] = process
                if job.get('CancelEvent') is not None and job['CancelEvent'].is_set():
                    self.stop_process(process)
            try:
                self.read_process(job, process)
                self.check_cancelled(job)
                if process.wait() != 0:
                    self.check_cancelled(job)
                    raise ValueError(conversion_failure(job.get('Log', [])))
            finally:
                with self.lock:
                    job.pop('Process', None)
            self.check_cancelled(job)

    def read_process(self, job, process):
        for line in process.stdout:
            self.log(job, line)
            match = re.search(r'(Decoded|Encoded)\s+(\d+)/(\d+)', line, re.I)
            if match:
                ratio = int(match[2]) / max(1, int(match[3]))
                decoding = match[1].lower() == 'decoded'
                self.log(job, '', 'Reading video frames' if decoding else 'Converting video',
                         max(job.get('Progress', 0), (0.1 + ratio * 0.25) if decoding else (0.35 + ratio * 0.15)))
            audio = re.search(r'Analyzed\s+([\d.]+)/([\d.]+)s', line)
            if audio:
                ratio = float(audio[1]) / max(0.001, float(audio[2]))
                self.log(job, '', 'Analyzing audio', max(job.get('Progress', 0), 0.5 + min(1, ratio) * 0.1))
            fitted = re.search(r'Fitted source amplitudes\s+([\d.]+)/([\d.]+)s', line)
            if fitted:
                ratio = float(fitted[1]) / max(0.001, float(fitted[2]))
                self.log(job, '', 'Refining audio detail', max(job.get('Progress', 0), 0.6 + min(1, ratio) * 0.12))

    def validate(self, job, kind, path):
        self.run(job, [sys.executable, self.tools / 'media_workbench.py', '--validate', kind, '--manifest', path])

    def video_command(self, source, name, options, stage_root, profile):
        tool = self.tools / 'add_video.py'
        command = [sys.executable, tool, source, '--name', name, '--repo', options['Repository'],
                   '--folder', options['Folder'], '--output-root', stage_root, '--width', profile['Width'],
                   '--fps', profile['FPS'], '--max-video-kib', profile['MaxVideoKiB']]
        flags = subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0
        probe = subprocess.run([sys.executable, str(tool), '--help'], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               text=True, encoding='utf-8', errors='replace', timeout=30, creationflags=flags, check=True)
        if '--codec' in probe.stdout:
            command.extend(['--codec', 'rvf2'])
        if '--audio-voices' in probe.stdout:
            command.extend(['--audio-voices', profile['Voices']])
        if '--analysis' in probe.stdout:
            command.extend(['--analysis', options['AudioAnalysis']])
        elif options['AudioAnalysis'] != 'source-fit':
            raise ValueError('Update the video converter before using experimental audio analysis.')
        if '--comparison' in probe.stdout:
            command.append('--comparison')
        return command

    def compare_audio(self, job, pcm, manifest, bundle):
        self.log(job, '', 'Preparing listening comparison', 0.76)
        self.run(job, [sys.executable, self.tools / 'audio/quality_compare.py', pcm, manifest,
                       '--output', Path(bundle) / 'Comparison', '--clip-seconds', 3, '--clips', 3])

    def comparison_file(self, job, filename):
        if not job or not job.get('Bundle') or filename not in COMPARISON_FILES:
            raise ValueError('Local comparison not found.')
        bundle = contained(job['Bundle'], self.generated)
        path = contained(bundle / 'Comparison' / filename, bundle)
        if not path.is_file() or not 0 < path.stat().st_size <= MAX_COMPARISON_BYTES:
            raise ValueError('Local comparison not found or exceeds the preview limit.')
        return path

    def comparison(self, job):
        if not job.get('Bundle'):
            return None
        try:
            report = json.loads(self.comparison_file(job, 'report.json').read_text(encoding='utf-8'))
            if (not isinstance(report, dict) or report.get('SchemaVersion') != 1
                    or not isinstance(report.get('Preview'), dict)):
                return None
            files = report['Preview'].get('Files', {})
            if not isinstance(files, dict) or files.get('Original') != 'original.wav' or files.get('Rendered') != 'rendered.wav':
                return None
            urls = {}
            for label, filename in (('Original', 'original.wav'), ('Rendered', 'rendered.wav'), ('Baseline', 'baseline.wav')):
                if label not in files:
                    continue
                if files[label] != filename:
                    return None
                self.comparison_file(job, filename)
                urls[label] = f'/comparison/{job["Id"]}/{filename}?token={self.token}'
            return {'Scope': 'Offline sine-model preview; in-game playback can differ.',
                    'Analysis': job['Options']['AudioAnalysis'],
                    'Experimental': job['Options']['AudioAnalysis'] == 'phase-pan-fit', 'Files': urls,
                    'Report': f'/comparison/{job["Id"]}/report.json?token={self.token}'}
        except (ValueError, OSError, TypeError):
            return None

    def previous_snapshot(self, name, bundle=None):
        name = safe_name(name)
        source = contained(bundle or self.generated / name, self.generated)
        manifest_path = contained(source / 'WorkbenchManifest.json', source)
        if not source.is_dir() or not manifest_path.is_file() or manifest_path.stat().st_size > 2 * 1024 * 1024:
            raise ValueError('This conversion has no valid WorkbenchManifest. Convert it again to save its settings safely.')
        manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
        required = {'Name', 'Profile', 'Repository', 'Folder', 'Revision', 'Template', 'Order', 'Default', 'Exclusive', 'ReplaceExisting'}
        if (not isinstance(manifest, dict) or manifest.get('Version') != 1 or manifest.get('Name') != name
                or not isinstance(manifest.get('Options'), dict) or not required.issubset(manifest['Options'])
                or manifest['Options'].get('Name') != name):
            raise ValueError('The saved settings do not match the selected name. No conversion was changed.')
        options = normalize_options(manifest['Options'])
        if any(manifest.get(field) != options[field] for field in ('Repository', 'Folder', 'Revision')):
            raise ValueError('The manifest and its saved settings use different destinations. Check the original conversion.')
        source_hash = manifest.get('OriginalFileSHA256')
        if not isinstance(source_hash, str) or (source_hash and not re.fullmatch(r'[a-f0-9]{64}', source_hash)):
            raise ValueError('The original file hash saved in the manifest is invalid.')
        return {'Options': options, 'Bundle': str(source), 'OriginalFileSHA256': source_hash,
                'ManifestSHA256': file_sha256(manifest_path)}

    def reuse(self, name):
        snapshot = self.previous_snapshot(name)
        return self.submit(snapshot['Options'], existing=True, snapshot=snapshot)

    def preserve_job_paths(self, destination, backup, current_id):
        if not backup:
            return
        with self.lock:
            for previous in self.jobs.values():
                if previous['Id'] == current_id:
                    continue
                if previous.get('Bundle') == str(destination):
                    previous['Bundle'] = str(backup)
                if previous.get('SourceBundle') == str(destination):
                    previous['SourceBundle'] = str(backup)

    def submit(self, payload, existing=False, snapshot=None):
        options = normalize_options(payload)
        name = options['Name']
        upload = None
        for path in self.generated.iterdir():
            if path.name.casefold() == name.casefold() and path.name != name:
                raise ValueError('That name already exists with different capitalization. Use exactly: ' + path.name)
        if existing:
            snapshot = snapshot or self.previous_snapshot(name)
        else:
            with self.lock:
                upload = self.uploads.get(payload.get('UploadId'))
            if not upload:
                raise ValueError('Select the file again.')
            for path in self.generated.iterdir():
                if path.name.casefold() == name.casefold() and not options['ReplaceExisting']:
                    raise ValueError('That name already exists. Choose another or enable update with backup.')
        job = {'Id': uuid.uuid4().hex, 'Name': name, 'State': 'Queued', 'Phase': 'Queued', 'Progress': 0,
               'Log': [], 'Started': time.monotonic(), 'Options': options, 'Upload': upload, 'Existing': existing,
               'CancelEvent': threading.Event()}
        if existing:
            job.update(SourceBundle=snapshot['Bundle'], SourceManifestSHA256=snapshot['ManifestSHA256'],
                       OriginalFileSHA256=snapshot['OriginalFileSHA256'])
        with self.lock:
            if any(previous['Name'].casefold() == name.casefold() and previous['State'] in
                   ('Queued', 'Running', 'Cancelling', 'Finalizing') for previous in self.jobs.values()):
                raise ValueError('A conversion with this name is already active. Wait or cancel it first.')
            self.jobs[job['Id']] = job
        try:
            self.queue.put_nowait(job)
        except queue.Full:
            with self.lock:
                self.jobs.pop(job['Id'], None)
            raise ValueError('The queue is full. Wait for a conversion to finish.')
        return self.public_job(job)

    def public_job(self, job):
        result = {key: job.get(key) for key in ('Id', 'Name', 'State', 'Phase', 'Progress', 'Log', 'Error', 'Summary')}
        result['Elapsed'] = round((job.get('Ended') or time.monotonic()) - job['Started'])
        result['Revision'] = job['Options']['Revision']
        if job.get('Bundle'):
            result['Artifacts'] = {name: f'/artifact/{job["Id"]}/{name}?token={self.token}' for name in
                ('StudioMediaPackage.zip', 'StudioImport.luau', 'MediaDefinitions.luau', 'COMECE_AQUI.txt', 'WorkbenchManifest.json')}
            image = Path(job['Bundle']) / 'VideoComparison.png'
            if image.is_file():
                result['Preview'] = f'/artifact/{job["Id"]}/VideoComparison.png?token={self.token}'
            result['Comparison'] = self.comparison(job)
        return result

    def finalize(self, identity, revision):
        with self.lock:
            previous = self.jobs.get(identity)
            if not previous or previous['State'] != 'Ready' or not previous.get('Bundle'):
                raise ValueError('Wait for the package to finish before pinning its revision.')
            options = dict(previous['Options'])
            bundle = previous['Bundle']
        options['Revision'] = safe_revision(revision)
        snapshot = self.previous_snapshot(options['Name'], bundle)
        return self.submit(options, existing=True, snapshot=snapshot)

    def state(self):
        with self.lock:
            return {'Profiles': PROFILES, 'Jobs': [self.public_job(job) for job in self.jobs.values()],
                    'Existing': sorted(path.name for path in self.generated.iterdir()
                                       if path.is_dir() and re.fullmatch(r'[A-Za-z0-9_]{1,40}', path.name) and path.name != 'backups'
                                       and (path / 'upload' / (path.name + '.json')).is_file())}

    def _worker(self):
        while True:
            job = self.queue.get()
            try:
                with self.lock:
                    self.check_cancelled(job)
                    job['State'] = 'Running'
                options, name = job['Options'], job['Name']
                profile = PROFILES[options['Profile']]
                if job['Existing']:
                    self.log(job, 'Checking the existing local conversion.', 'Verifying files', 0.7)
                    previous = contained(job['SourceBundle'], self.generated)
                    if file_sha256(previous / 'WorkbenchManifest.json') != job['SourceManifestSHA256']:
                        raise ValueError('This conversion changed after selection. Select it again to preserve the correct settings.')
                    with tempfile.TemporaryDirectory(prefix='.workbench-', dir=self.generated) as temporary:
                        bundle = Path(temporary) / name
                        for parent, folders, files in os.walk(previous, followlinks=False):
                            for child in folders + files:
                                candidate = Path(parent) / child
                                if candidate.is_symlink() or (hasattr(candidate, 'is_junction') and candidate.is_junction()):
                                    raise ValueError('The existing conversion contains a link; use real local files only.')
                        shutil.copytree(previous, bundle, ignore=shutil.ignore_patterns('UploadBatches', 'StudioMediaPackage.zip'))
                        report = prepare_bundle(bundle, name, options, job['OriginalFileSHA256'],
                                                validate=lambda kind, path: self.validate(job, kind, path))
                        destination = self.generated / name
                        backup = self.install(job, bundle, destination, True)
                        self.preserve_job_paths(destination, backup, job['Id'])
                        self.log(job, 'Previous version preserved at: ' + str(backup))
                    bundle = self.generated / name
                else:
                    self.log(job, '', 'Checking Python, audio and browser dependencies', 0.01)
                    self.run(job, [sys.executable, self.tools / 'media_workbench.py', '--check-runtime'])
                    source = Path(job['Upload']['Path'])
                    self.log(job, 'The file stays on this computer.', 'Preparing conversion', 0.05)
                    with tempfile.TemporaryDirectory(prefix='.workbench-', dir=self.generated) as temporary:
                        stage_root = Path(temporary)
                        bundle = stage_root / name
                        if source.suffix.lower() in VIDEO_EXTENSIONS:
                            self.run(job, self.video_command(source, name, options, stage_root, profile))
                        else:
                            bundle.mkdir()
                            pcm = stage_root / 'source.pcm'
                            node = shutil.which('node') or str(Path.home() / '.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node.exe')
                            if not Path(node).is_file():
                                raise ValueError('Node.js was not found. Use the complete package with its runtime installed.')
                            self.run(job, [node, self.tools / 'audio/decode_audio.cjs', source, pcm])
                            self.log(job, '', 'Converting audio', 0.4)
                            self.run(job, [sys.executable, self.tools / 'audio/convert_song.py', pcm, '--name', name,
                                           '--voices', profile['Voices'], '--analysis', options['AudioAnalysis'],
                                           '--output', bundle / 'upload'])
                            entry = bundle / 'upload' / (name + '.entry.txt')
                            if entry.exists():
                                entry.unlink()
                            self.compare_audio(job, pcm, bundle / 'upload' / (name + '.json'), bundle)
                        self.log(job, '', 'Verifying files and preparing Studio', 0.8)
                        report = prepare_bundle(bundle, name, options, job['Upload']['SHA256'],
                                                validate=lambda kind, path: self.validate(job, kind, path))
                        backup = self.install(job, bundle, self.generated / name, options['ReplaceExisting'])
                        self.preserve_job_paths(self.generated / name, backup, job['Id'])
                        bundle = self.generated / name
                        if backup:
                            self.log(job, 'Previous version preserved at: ' + str(backup))
                job['Bundle'] = str(bundle)
                job['Summary'] = {'AudioSeconds': report['Audio']['Duration'],
                    'Video': ({key: report['Video'][key] for key in ('Width', 'Height', 'FPS', 'Duration')} if report['Video'] else None),
                    'Batches': [{'Kind': batch['Kind'], 'Number': batch['Number'], 'Files': len(batch['Files']),
                                 'MiB': round(batch['Bytes'] / 1048576, 2), 'UploadUrl': batch['UploadUrl'], 'Folder': batch['Folder']}
                                for batch in report['UploadBatches']]}
                job['State'] = 'Ready'
                self.log(job, 'Ready. Nothing was uploaded.', 'Package ready', 1)
            except ConversionCancelled:
                job['State'] = 'Cancelled'
                self.log(job, 'Cancelled. The original file and previous package were preserved.', 'Cancelled')
            except Exception as error:
                job['State'], job['Error'] = 'Failed', str(error)
                self.log(job, str(error), 'Check the log')
            finally:
                job['Ended'] = time.monotonic()
                self.queue.task_done()


class Handler(BaseHTTPRequestHandler):
    server_version = 'LocalMediaWorkbench/1'

    def log_message(self, *_args):
        pass

    def allowed_host(self):
        return self.headers.get('Host') == f'127.0.0.1:{self.server.server_address[1]}'

    def authorized(self):
        query = parse_qs(urlsplit(self.path).query)
        token = self.headers.get('X-Media-Token') or query.get('token', [''])[0]
        expected_origin = f'http://127.0.0.1:{self.server.server_address[1]}'
        return (self.allowed_host() and secrets.compare_digest(token, self.server.app.token)
                and self.headers.get('Origin') in (None, expected_origin))

    def respond(self, code, value, content_type='application/json; charset=utf-8'):
        data = json.dumps(value, ensure_ascii=False).encode('utf-8') if isinstance(value, (dict, list)) else value
        if isinstance(data, str):
            data = data.encode('utf-8')
        self.send_response(code)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Content-Security-Policy', "default-src 'self'; script-src 'nonce-" + self.server.app.token
                         + "'; style-src 'unsafe-inline'; media-src 'self' blob:; img-src 'self' blob: data:; object-src 'none'; frame-ancestors 'none'")
        self.end_headers()
        if self.command != 'HEAD':
            self.wfile.write(data)

    def send_file(self, path, download=False):
        path = Path(path)
        size, start, end, code = path.stat().st_size, 0, path.stat().st_size - 1, 200
        requested = self.headers.get('Range')
        if requested:
            match = re.fullmatch(r'bytes=(\d+)-(\d*)', requested)
            if not match:
                self.respond(416, {'Error': 'Invalid byte range.'}); return
            start = int(match[1]); end = min(end, int(match[2]) if match[2] else end)
            if start > end:
                self.respond(416, {'Error': 'Byte range is outside the file.'}); return
            code = 206
        self.send_response(code)
        self.send_header('Content-Type', mimetypes.guess_type(path.name)[0] or 'application/octet-stream')
        self.send_header('Content-Length', str(end - start + 1))
        self.send_header('Accept-Ranges', 'bytes')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        if code == 206:
            self.send_header('Content-Range', f'bytes {start}-{end}/{size}')
        if download:
            self.send_header('Content-Disposition', 'attachment; filename="' + path.name + '"')
        self.end_headers()
        if self.command != 'HEAD':
            with path.open('rb') as source:
                source.seek(start)
                remaining = end - start + 1
                while remaining:
                    block = source.read(min(256 * 1024, remaining))
                    if not block:
                        break
                    self.wfile.write(block); remaining -= len(block)

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        try:
            path = urlsplit(self.path).path
            if not self.allowed_host():
                self.respond(403, {'Error': 'Invalid local access.'}); return
            if path == '/':
                self.respond(200, HTML.replace('__TOKEN__', self.server.app.token), 'text/html; charset=utf-8'); return
            if not self.authorized():
                self.respond(403, {'Error': 'Invalid local session.'}); return
            if path == '/api/state':
                self.respond(200, self.server.app.state()); return
            match = re.fullmatch(r'/comparison/([a-f0-9]{32})/([A-Za-z0-9_.-]+)', path)
            if match:
                job = self.server.app.jobs.get(match[1])
                artifact = self.server.app.comparison_file(job, match[2])
                self.send_file(artifact, download=match[2] == 'report.json'); return
            match = re.fullmatch(r'/source/([a-f0-9]{32})', path)
            if match:
                upload = self.server.app.uploads.get(match[1])
                if not upload:
                    raise ValueError('Local file not found.')
                self.send_file(upload['Path']); return
            match = re.fullmatch(r'/artifact/([a-f0-9]{32})/([A-Za-z0-9_.-]+)', path)
            if match:
                job = self.server.app.jobs.get(match[1])
                allowed = {'StudioMediaPackage.zip', 'StudioImport.luau', 'MediaDefinitions.luau', 'COMECE_AQUI.txt',
                           'WorkbenchManifest.json', 'VideoComparison.png'}
                if not job or not job.get('Bundle') or match[2] not in allowed:
                    raise ValueError('Local artifact not found.')
                artifact = contained(Path(job['Bundle']) / match[2], job['Bundle'])
                if not artifact.is_file():
                    raise ValueError('Local artifact not found.')
                self.send_file(artifact, download=match[2] != 'VideoComparison.png'); return
            self.respond(404, {'Error': 'Page not found.'})
        except (ValueError, OSError) as error:
            self.respond(400, {'Error': str(error)})

    def do_POST(self):
        if not self.authorized():
            self.respond(403, {'Error': 'Invalid local session.'}); return
        try:
            parts = urlsplit(self.path)
            length = int(self.headers.get('Content-Length', '-1'))
            if parts.path == '/api/upload':
                if length < 1 or length > MAX_UPLOAD_BYTES:
                    raise ValueError('Choose a file between 1 byte and 1 GiB.')
                filename = safe_filename(parse_qs(parts.query).get('name', [''])[0])
                if shutil.disk_usage(self.server.app.imports).free < length + 128 * 1024 * 1024:
                    raise ValueError('There is not enough free space to copy this file.')
                identity = uuid.uuid4().hex
                folder = self.server.app.imports / identity
                contained(folder, self.server.app.imports); folder.mkdir()
                partial, destination = folder / '.upload.partial', folder / filename
                digest, remaining = hashlib.sha256(), length
                try:
                    with partial.open('xb') as output:
                        while remaining:
                            block = self.rfile.read(min(1024 * 1024, remaining))
                            if not block:
                                raise ValueError('The local copy was interrupted. Select the file again.')
                            output.write(block); digest.update(block); remaining -= len(block)
                        output.flush(); os.fsync(output.fileno())
                    os.replace(partial, destination)
                finally:
                    if partial.exists():
                        partial.unlink()
                upload = {'Id': identity, 'Path': str(destination), 'Name': filename, 'Bytes': length, 'SHA256': digest.hexdigest()}
                with self.server.app.lock:
                    self.server.app.uploads[identity] = upload
                self.respond(200, {key: upload[key] for key in ('Id', 'Name', 'Bytes', 'SHA256')}); return
            if length < 0 or length > 65536:
                raise ValueError('Invalid local request.')
            payload = json.loads(self.rfile.read(length))
            if not isinstance(payload, dict):
                raise ValueError('Invalid local request.')
            if parts.path == '/api/jobs':
                self.respond(200, self.server.app.submit(payload)); return
            if parts.path == '/api/existing':
                self.respond(200, self.server.app.reuse(payload.get('Name'))); return
            if parts.path == '/api/cancel':
                self.respond(200, self.server.app.cancel(payload.get('JobId'))); return
            if parts.path == '/api/finalize':
                self.respond(200, self.server.app.finalize(payload.get('JobId'), payload.get('Revision'))); return
            self.respond(404, {'Error': 'Operation not found.'})
        except (ValueError, OSError, json.JSONDecodeError) as error:
            self.respond(400, {'Error': str(error)})


HTML = r'''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Media Studio · Local</title><style>
:root{color-scheme:dark;--bg:#0e1110;--panel:#161a17;--panel2:#1c221d;--line:#2c342c;--line2:#3a443a;--text:#eef2ea;--muted:#9ea89b;--accent:#bfe385;--accent2:#7fd3e0;--video:#7fd3e0;--audio:#e0b97f;--danger:#f0a99b;font-family:Inter,Segoe UI,Arial,sans-serif;background:var(--bg);color:var(--text)}*{box-sizing:border-box}body{margin:0;background:radial-gradient(1200px 500px at 20% -10%,#1b2a1c 0%,transparent 60%),var(--bg)}main{max-width:1120px;margin:auto;padding:36px 24px 60px}header{display:flex;justify-content:space-between;align-items:flex-end;gap:16px;margin-bottom:22px}h1{font-size:30px;letter-spacing:-1px;margin:0}.sub{font-size:14px;color:var(--muted);margin:6px 0 0}p{color:var(--muted);line-height:1.5}.local{font-size:12px;color:#c1d7ac;border:1px solid #3b4934;border-radius:20px;padding:8px 12px;white-space:nowrap}.steps{display:grid;grid-template-columns:repeat(3,1fr);gap:8px;margin:0 0 22px}.step{border:1px solid var(--line);border-radius:12px;padding:10px 14px;font-size:12px;color:var(--muted);background:var(--panel);display:flex;gap:10px;align-items:center}.step i{font-style:normal;width:22px;height:22px;border-radius:50%;display:grid;place-items:center;border:1px solid var(--line2);font-size:11px}.step.active{border-color:var(--accent);color:var(--text)}.step.active i{background:var(--accent);color:#17220d;border-color:var(--accent)}.step.done{color:#c5e5a4}.step.done i{background:#2f4a2a;border-color:#2f4a2a;color:#c5e5a4}.layout{display:grid;grid-template-columns:1.1fr .9fr;gap:22px}.panel{border:1px solid var(--line);background:var(--panel);border-radius:16px;padding:22px}h2{font-size:17px;margin:0 0 18px}.drop{display:block;border:1px dashed #59624f;background:var(--panel2);border-radius:12px;padding:26px 20px;cursor:pointer;text-align:center;transition:border-color .15s,background .15s}.drop:hover,.drop.over{border-color:var(--accent);background:#22291f}.drop strong{display:block;font-size:16px}.drop span{display:block;color:#a5ada1;font-size:13px;margin-top:8px}.kinds{display:flex;gap:8px;justify-content:center;margin-top:12px}.kind{font-size:11px;letter-spacing:.6px;text-transform:uppercase;border:1px solid var(--line2);border-radius:20px;padding:5px 10px;color:var(--muted)}.kind.video{border-color:var(--video);color:var(--video)}.kind.audio{border-color:var(--audio);color:var(--audio)}input[type=file]{width:100%;margin-top:16px;font-size:12px}label.field{display:block;margin-top:18px;font-size:13px;color:#c5ccc3}input:not([type=checkbox]):not([type=file]),select{width:100%;margin-top:7px;background:#101411;color:#f0f3ed;border:1px solid #444c40;border-radius:8px;padding:11px;font:inherit}input:focus,select:focus{outline:0;border-color:var(--accent)}select{cursor:pointer}.row{display:grid;grid-template-columns:1fr 1fr;gap:14px}.hint{font-size:12px;color:#9aa393;margin:7px 0 0}.spec{display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-top:12px}.spec div{border:1px solid var(--line);background:var(--panel2);border-radius:10px;padding:10px 12px}.spec b{display:block;font-size:11px;letter-spacing:.6px;text-transform:uppercase;margin-bottom:4px}.spec .v b{color:var(--video)}.spec .a b{color:var(--audio)}.spec span{font-size:13px;color:var(--text)}.spec small{display:block;color:var(--muted);font-size:11px;margin-top:3px}button,.link{border:0;border-radius:8px;background:var(--accent);color:#17220d;font-weight:650;font-size:14px;padding:12px 18px;cursor:pointer;text-decoration:none;display:inline-block;transition:filter .15s}button:hover,.link:hover{filter:brightness(1.08)}button:disabled{opacity:.5;cursor:wait}.primary{width:100%;margin-top:24px}.secondary{background:#30372c;color:#dfe8d8}.links{display:flex;gap:8px;flex-wrap:wrap;margin-top:18px}.links .link{font-size:12px}.error{color:var(--danger);white-space:pre-wrap}.badge{font-size:11px;text-transform:uppercase;letter-spacing:1px;color:#a8b6a0}.badge.ready{color:var(--accent)}.badge.failed{color:var(--danger)}.badge.running{color:var(--accent2)}.previewBox{position:relative}.previewBox .kind{position:absolute;top:10px;left:10px;background:#0d100ccc;z-index:2}.preview{width:100%;max-height:260px;background:#0d100c;border-radius:10px;margin:8px 0 16px;border:1px solid var(--line)}video,audio{width:100%}audio.preview{height:54px;padding:8px}progress{width:100%;height:10px;accent-color:#b8d88e;margin:16px 0 4px;border-radius:5px}details{margin-top:20px}summary{cursor:pointer;color:#b4bdb0;font-size:13px}details .field{margin-top:14px}.check{font-size:13px;display:block;margin-top:15px;color:#bcc4b7}pre{white-space:pre-wrap;font:12px/1.5 Consolas,monospace;max-height:260px;overflow:auto;background:#101410;padding:14px;border-radius:8px;color:#a9b8a1}.empty{padding:55px 16px;text-align:center;color:#8f9988;border:1px dashed var(--line2);border-radius:10px;background:var(--panel2)}.batch{display:flex;justify-content:space-between;align-items:center;gap:12px;border-bottom:1px solid #333b2d;padding:10px 0;font-size:12px}.batch a{color:#c5e5a4}.batch .kind{font-size:10px;padding:3px 8px;margin-right:8px}#summary p{font-size:13px;color:var(--text)}img.compare{width:100%;border-radius:8px}.hidden{display:none!important}footer{font-size:12px;color:#839078;margin-top:24px}@media(max-width:760px){.layout,.steps,.spec{grid-template-columns:1fr}main{padding:24px 16px}.row{grid-template-columns:1fr}.local{font-size:10px}header{gap:16px;align-items:center}}
</style><main><header><div><h1>Media Studio</h1><p class="sub">Video and audio go through the same three steps: pick a file, convert and verify, upload and import.</p></div><span class="local">● Only on this computer</span></header>
<div class="steps"><div id="step1" class="step active"><i>1</i>File and quality</div><div id="step2" class="step"><i>2</i>Convert and verify</div><div id="step3" class="step"><i>3</i>Upload and import</div></div>
<div class="layout"><section class="panel"><h2>Your next emote</h2><form id="form">
<label id="drop" class="drop"><strong>Video with audio, or music only</strong><span>MP4, MP3 and other local formats · up to 1 GiB · drag and drop works</span><div class="kinds"><span class="kind video">Video + audio</span><span class="kind audio">Audio only</span></div><input id="file" type="file" accept=".mp4,.m4v,.mov,.webm,.mp3,.m4a,.wav,.ogg"></label>
<div class="row"><label class="field">In-game name<input id="name" required maxlength="40" pattern="[A-Za-z0-9_]+" placeholder="MyEmote"></label><label class="field">Quality<select id="profile"><option value="leve">Lightweight (mobile)</option><option value="equilibrado">Balanced</option><option selected value="detalhado">High detail (recommended)</option><option value="cinema">Cinema (desktop, up to 960 px)</option><option value="ultra">Ultra (desktop, 1024 px · 30 FPS)</option></select></label></div><p id="profileHint" class="hint"></p>
<div id="spec" class="spec"><div class="v"><b>Video</b><span id="specVideo">—</span><small>Width adapts to the data budget; the audio below is always included.</small></div><div class="a"><b>Audio</b><span id="specAudio">—</span><small>Same spectral engine for music files and video soundtracks.</small></div></div>
<label class="field">Audio analysis<select id="analysis"><option value="source-fit" selected>Standard</option><option value="phase-pan-fit">Phase-aware (experimental)</option></select></label><p id="analysisHint" class="hint"></p>
<details><summary>Destination and emote settings</summary><label class="field">Project repository<input id="repository" value="juhdevx/roblox-audio-test" readonly></label><label class="field">Repository folder<input id="folder" placeholder="media/my_emote/v1"></label><label class="field">GitHub revision<input id="revision" value="main" maxlength="40"><span class="hint">Use main or the full SHA of a commit you have uploaded.</span></label><div class="row"><label class="field">Reference dance<input id="template" value="PaniniEvent"></label><label class="field">Catalog order<input id="order" type="number" min="0" max="1000000" value="0"><span class="hint">0 selects the next available position.</span></label></div><label class="check"><input id="exclusive" type="checkbox" checked> Exclusive emote</label><label class="check"><input id="default" type="checkbox"> Unlocked by default</label><label class="check"><input id="replace" type="checkbox"> Update an existing name and keep a backup</label></details>
<button id="convert" class="primary">Convert and build package</button><p id="formError" class="error"></p></form>
<details><summary>I already have a conversion in this folder</summary><select id="existing"></select><button id="reuse" class="secondary" style="margin-top:12px">Verify and rebuild package</button><p class="hint">Reuses local files without converting the original again.</p></details></section>
<section class="panel"><h2>Preview and progress</h2><label class="field">Recent conversions<select id="history" aria-label="Recent conversions"><option value="">No conversions yet</option></select></label><div id="empty" class="empty">Your selected file appears here.<br>Check it before converting.</div><div class="previewBox"><span id="kindBadge" class="kind hidden"></span><video id="video" class="preview hidden" controls playsinline preload="metadata"></video><audio id="audio" class="preview hidden" controls preload="metadata"></audio></div>
<div id="status" class="hidden"><span id="state" class="badge"></span><h2 id="phase" style="margin:10px 0 0"></h2><progress id="progress" max="1" value="0"></progress><p id="elapsed" class="hint" role="status" aria-live="polite"></p><button id="cancel" type="button" class="secondary hidden">Cancel conversion</button><p id="jobError" class="error"></p><div id="summary"></div><div id="comparison" class="hidden"></div><div id="artifacts" class="links"></div><div id="batches"></div><div id="pin" class="hidden"><label class="field">After uploading every batch: pin the commit<input id="finalRevision" maxlength="40" placeholder="Full SHA of the final commit"></label><button id="finalize" class="secondary" style="margin-top:10px">Update installer with this commit</button><p class="hint">Rebuilds the local package only. The installer checks hosted files before changing Studio.</p></div><details id="logsDetails"><summary>Conversion log</summary><pre id="logs"></pre></details></div>
</section></div><footer>The original file is preserved. Nothing is uploaded automatically to GitHub or Roblox. Listening comparisons are offline previews; check the final result in the game.</footer></main>
<script nonce="__TOKEN__">const token='__TOKEN__';let currentJob='',objectURL='',uploadId='',comparisonKey='',uploadRequest=null,operationBusy=false,cancelPending=false,currentSnapshot=null,cachedJobs=[];const $=id=>document.getElementById(id);const headers={'X-Media-Token':token,'Content-Type':'application/json'};
async function api(path,body){const response=await fetch(path,{method:body?'POST':'GET',headers,body:body?JSON.stringify(body):undefined});const data=await response.json();if(!response.ok)throw Error(data.Error||'The operation did not finish.');return data;}
let profiles={};function profileHint(){const key=$('profile').value;const text={leve:'Less data and faster preparation. Start here for mobile.',equilibrado:'More detail and motion, with a moderate file size.',detalhado:'Prioritizes image detail and uses more data. Check the result on mobile.',cinema:'Targets up to 960 pixels wide at 24 FPS. Resolution adapts to the data limit. Longer conversions and more temporary disk space; recommended for desktop.',ultra:'Codec maximum: 1024 px wide at 30 FPS with a 640 KiB/s video budget. Longest conversion; desktop only. Test on a busy server before relying on it.'};$('profileHint').textContent=text[key]||'';const p=profiles[key];if(p){$('specVideo').textContent=`up to ${p.Width} px wide · ${p.FPS} FPS · ${p.MaxVideoKiB} KiB/s`;$('specAudio').textContent=`${p.Voices} voices · 60 FPS spectral · phase + stereo tracked`;}}profileHint();$('profile').onchange=profileHint;
function setStep(n,done){for(const i of[1,2,3]){const el=$('step'+i);el.classList.toggle('active',i===n);el.classList.toggle('done',i<n||(i===n&&done));}}
function analysisHint(){$('analysisHint').textContent=$('analysis').value==='phase-pan-fit'?'Fits amplitudes against the tracked phase and stereo balance, keeping both fixed. Results vary by song; listen to the comparison before importing.':'Preserves the tracked phase and stereo balance while fitting amplitudes to the source. Recommended starting point.';}analysisHint();$('analysis').onchange=analysisHint;
$('file').onchange=()=>{const file=$('file').files[0];if(!file)return;if(objectURL)URL.revokeObjectURL(objectURL);objectURL=URL.createObjectURL(file);const isVideo=/\.(mp4|m4v|mov|webm)$/i.test(file.name);$('video').classList.toggle('hidden',!isVideo);$('audio').classList.toggle('hidden',isVideo);$(isVideo?'video':'audio').src=objectURL;$('empty').classList.add('hidden');const badge=$('kindBadge');badge.className='kind '+(isVideo?'video':'audio');badge.textContent=(isVideo?'Video + audio':'Audio only')+' · '+(file.size/1048576).toFixed(1)+' MiB';$('spec').classList.toggle('audioOnly',!isVideo);$('specVideo').parentElement.style.opacity=isVideo?'1':'.45';if(!$('name').value)$('name').value=file.name.replace(/\.[^.]+$/,'').replace(/[^A-Za-z0-9_]+/g,'_').slice(0,40)||'NewMedia';};
const drop=$('drop');for(const ev of['dragenter','dragover'])drop.addEventListener(ev,e=>{e.preventDefault();drop.classList.add('over');});for(const ev of['dragleave','drop'])drop.addEventListener(ev,e=>{e.preventDefault();drop.classList.remove('over');});drop.addEventListener('drop',e=>{if(e.dataTransfer&&e.dataTransfer.files.length){$('file').files=e.dataTransfer.files;$('file').onchange();}});
function options(){return{Name:$('name').value.trim(),Profile:$('profile').value,AudioAnalysis:$('analysis').value,Repository:$('repository').value.trim(),Folder:$('folder').value.trim(),Revision:$('revision').value.trim(),Template:$('template').value.trim(),Order:Number($('order').value),Exclusive:$('exclusive').checked,Default:$('default').checked,ReplaceExisting:$('replace').checked};}
function showStatus(phase){$('history').disabled=true;cancelPending=false;currentJob='';$('progress').value=0;$('state').textContent='Preparing';$('cancel').classList.remove('hidden');$('cancel').disabled=false;$('status').classList.remove('hidden');$('pin').classList.add('hidden');$('phase').textContent=phase;$('jobError').textContent='';$('summary').replaceChildren();$('artifacts').replaceChildren();$('batches').replaceChildren();comparisonKey='';$('comparison').querySelectorAll('audio').forEach(audio=>audio.pause());$('comparison').replaceChildren();$('comparison').classList.add('hidden');}
document.addEventListener('play',event=>{if(!['AUDIO','VIDEO'].includes(event.target.tagName))return;document.querySelectorAll('audio,video').forEach(media=>{if(media!==event.target)media.pause();});},true);
function renderComparison(job){const comparison=job.Comparison;if(!comparison)return;const key=job.Id+JSON.stringify(comparison.Files);if(key===comparisonKey)return;comparisonKey=key;const box=$('comparison');box.replaceChildren();box.classList.remove('hidden');const title=document.createElement('h2');title.style.marginTop='24px';title.textContent='Listen before importing';const note=document.createElement('p');note.className='hint';note.textContent=comparison.Scope+' Clips use one shared gain. '+(comparison.Experimental?'Experimental results vary by song.':'');box.append(title,note);const controls=[];let activeAudio=null;for(const [key,label]of[['Original','Original'],['Rendered','Reconstruction'],['Baseline','Previous analysis']]){if(!comparison.Files[key])continue;const caption=document.createElement('p');caption.className='hint';caption.textContent=label;const audio=document.createElement('audio');audio.controls=true;audio.preload='metadata';audio.src=comparison.Files[key];audio.setAttribute('aria-label',label+' comparison');audio.onplay=()=>{activeAudio=audio;};const button=document.createElement('button');button.type='button';button.className='secondary';button.style.margin='8px 0 12px';button.textContent='Listen to '+label.toLowerCase();button.onclick=()=>{const playing=controls.find(other=>!other.paused);const reference=playing||activeAudio;const position=reference&&!reference.ended?reference.currentTime:0;activeAudio=audio;controls.forEach(other=>{if(other!==audio)other.pause();});if(Number.isFinite(audio.duration))audio.currentTime=Math.min(position,Math.max(0,audio.duration-.02));audio.play().catch(error=>{if(error.name!=='AbortError')$('jobError').textContent=error.message;});};controls.push(audio);box.append(caption,audio,button);}const report=document.createElement('a');report.className='link secondary';report.href=comparison.Report;report.textContent='Download comparison measurements';box.append(report);}
function upload(file){return new Promise((resolve,reject)=>{const xhr=new XMLHttpRequest();uploadRequest=xhr;xhr.onabort=()=>reject(Error('Local copy cancelled.'));xhr.onloadend=()=>{if(uploadRequest===xhr)uploadRequest=null;};xhr.open('POST','/api/upload?name='+encodeURIComponent(file.name));xhr.setRequestHeader('X-Media-Token',token);xhr.upload.onprogress=event=>{if(event.lengthComputable){$('progress').value=event.loaded/event.total;$('elapsed').textContent='Copying to the local folder · '+Math.round(event.loaded/event.total*100)+'%';}};xhr.onload=()=>{try{const result=JSON.parse(xhr.responseText);if(xhr.status!==200)throw Error(result.Error);resolve(result);}catch(error){reject(error);}};xhr.onerror=()=>reject(Error('The local copy was interrupted.'));xhr.send(file);});}
$('form').onsubmit=async event=>{event.preventDefault();$('formError').textContent='';const file=$('file').files[0];if(!file){$('formError').textContent='Choose a file first.';return;}if(operationBusy)return;operationBusy=true;$('convert').disabled=true;$('reuse').disabled=true;$('finalize').disabled=true;showStatus('Copying the local file');try{const copied=await upload(file);if(cancelPending)throw Error('Conversion cancelled before it started.');uploadId=copied.Id;let job=await api('/api/jobs',{...options(),UploadId:uploadId});currentJob=job.Id;if(cancelPending)job=await api('/api/cancel',{JobId:job.Id});renderJob(job);}catch(error){$('formError').textContent=error.message;operationBusy=false;$('convert').disabled=false;$('reuse').disabled=false;$('finalize').disabled=false;$('cancel').classList.add('hidden');}};
$('reuse').onclick=async()=>{if(operationBusy)return;operationBusy=true;$('reuse').disabled=true;$('convert').disabled=true;try{if(!$('existing').value)throw Error('No local conversion was found.');showStatus('Verifying the existing conversion and preserving its settings');let job=await api('/api/existing',{Name:$('existing').value});currentJob=job.Id;if(cancelPending)job=await api('/api/cancel',{JobId:job.Id});$('convert').disabled=true;renderJob(job);}catch(error){$('formError').textContent=error.message;operationBusy=false;$('reuse').disabled=false;$('convert').disabled=false;$('cancel').classList.add('hidden');}};
$('finalize').onclick=async()=>{if(operationBusy)return;const previousId=currentJob,previousSnapshot=currentSnapshot;operationBusy=true;$('finalize').disabled=true;try{const revision=$('finalRevision').value.trim();if(!/^[a-f0-9]{40}$/.test(revision))throw Error('Paste the complete 40-character SHA of the final commit.');showStatus('Updating the package revision');let job=await api('/api/finalize',{JobId:previousId,Revision:revision});currentJob=job.Id;if(cancelPending)job=await api('/api/cancel',{JobId:job.Id});renderJob(job);}catch(error){currentJob=previousId;operationBusy=false;if(previousSnapshot){renderJob(previousSnapshot);$('pin').classList.toggle('hidden',previousSnapshot.State!=='Ready');}$('jobError').textContent=error.message;$('finalize').disabled=false;$('cancel').classList.add('hidden');}};
$('cancel').onclick=async()=>{cancelPending=true;if(uploadRequest){uploadRequest.abort();return;}if(!currentJob){$('cancel').disabled=true;return;}$('cancel').disabled=true;try{renderJob(await api('/api/cancel',{JobId:currentJob}));}catch(error){$('jobError').textContent=error.message;$('cancel').disabled=false;}};
function renderJob(job){currentSnapshot=job;const busy=['Queued','Running','Cancelling','Finalizing'].includes(job.State);operationBusy=busy;$('history').disabled=busy;$('convert').disabled=busy;$('reuse').disabled=busy;$('finalize').disabled=busy;$('cancel').classList.toggle('hidden',!['Queued','Running','Cancelling'].includes(job.State));$('cancel').disabled=job.State==='Cancelling';$('status').classList.remove('hidden');$('state').textContent=({Queued:'Queued',Running:'Running',Ready:'Ready',Failed:'Stopped',Cancelled:'Cancelled',Cancelling:'Stopping',Finalizing:'Finishing'})[job.State]||job.State;$('state').className='badge '+(job.State==='Ready'?'ready':job.State==='Failed'?'failed':busy?'running':'');setStep(job.State==='Ready'?3:2,false);$('phase').textContent=job.Phase;$('progress').value=job.Progress||0;$('elapsed').textContent=job.Elapsed+' s · '+job.Name;$('logs').textContent=(job.Log||[]).join('\n');$('jobError').textContent=job.Error||'';if(job.State==='Failed'){$('logsDetails').open=true;$('convert').disabled=false;}if(job.State==='Ready'){renderComparison(job);$('convert').disabled=false;$('summary').replaceChildren();const p=document.createElement('p');const v=job.Summary.Video;p.textContent=v?`Video ${v.Width} × ${v.Height} · ${v.FPS} FPS · ${v.Duration.toFixed(1)} s. Synchronized audio included.`:`Complete music track · ${job.Summary.AudioSeconds.toFixed(1)} s.`;$('summary').append(p);$('artifacts').replaceChildren();for(const [file,label]of[['StudioMediaPackage.zip','Download package'],['StudioImport.luau','Studio installer'],['COMECE_AQUI.txt','How to use']]){const link=document.createElement('a');link.className='link';link.href=job.Artifacts[file];link.textContent=label;$('artifacts').append(link);}$('batches').replaceChildren();for(const batch of job.Summary.Batches){const row=document.createElement('div');row.className='batch';const text=document.createElement('span');const tag=document.createElement('span');tag.className='kind '+batch.Kind;tag.textContent=batch.Kind==='video'?'Video':'Audio';text.append(tag,`batch ${batch.Number} · ${batch.Files} files · ${batch.MiB} MiB`);const link=document.createElement('a');link.href=batch.UploadUrl;link.target='_blank';link.rel='noreferrer';link.textContent='Open upload page';row.append(text,link);$('batches').append(row);}}}
$('history').onchange=()=>{if(operationBusy)return;const selected=$('history').value;const job=cachedJobs.find(item=>item.Id===selected);if(!job)return;showStatus(job.Phase);currentJob=selected;renderJob(job);$('pin').classList.toggle('hidden',job.State!=='Ready');};
async function poll(){try{const data=await api('/api/state');cachedJobs=data.Jobs;if(data.Profiles&&!Object.keys(profiles).length){profiles=data.Profiles;profileHint();}const selected=$('existing').value;const history=$('history');history.replaceChildren();for(const previous of [...data.Jobs].reverse()){const option=document.createElement('option');option.value=previous.Id;option.textContent=previous.Name+' · '+previous.State;history.append(option);}if(currentJob)history.value=currentJob;history.disabled=operationBusy;$('existing').replaceChildren();for(const name of data.Existing){const option=document.createElement('option');option.value=name;option.textContent=name;$('existing').append(option);}if(data.Existing.includes(selected))$('existing').value=selected;const job=data.Jobs.find(item=>item.Id===currentJob);if(job){renderJob(job);$('pin').classList.toggle('hidden',job.State!=='Ready');}}catch(error){if(currentJob)$('jobError').textContent=error.message;}setTimeout(poll,1000);}poll();
</script></html>'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=0)
    parser.add_argument('--no-browser', action='store_true')
    parser.add_argument('--check-runtime', action='store_true', help='Check local conversion dependencies and exit')
    parser.add_argument('--validate', choices=('audio', 'video'), help=argparse.SUPPRESS)
    parser.add_argument('--manifest', type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.check_runtime:
        try:
            print(json.dumps(runtime_check()), flush=True)
            return
        except (ValueError, OSError, subprocess.TimeoutExpired) as error:
            parser.exit(1, str(error) + '\n')
    if args.validate:
        if not args.manifest:
            parser.error('Select a manifest to validate.')
        try:
            if args.validate == 'audio':
                sys.path.insert(0, str(TOOLS / 'audio'))
                from validate_music import validate_track
            else:
                metadata = json.loads(args.manifest.read_text(encoding='utf-8'))
                if metadata.get('Format') == 'RVF2':
                    from codec_v2 import validate_track
                else:
                    from validate_video import validate_track
            print(json.dumps(validate_track(args.manifest), ensure_ascii=False, indent=2))
            return
        except (OSError, ValueError, KeyError, ImportError) as error:
            parser.exit(1, f'Could not validate media: {error}\n')
    if not 0 <= args.port <= 65535:
        parser.error('Port must be between 0 and 65535.')
    app = Workbench()
    server = ThreadingHTTPServer(('127.0.0.1', args.port), Handler)
    server.daemon_threads = True
    server.app = app
    url = f'http://127.0.0.1:{server.server_address[1]}/'
    print(f'Local Media Studio: {url}\nClose this window to stop. Nothing is uploaded automatically.', flush=True)
    if not args.no_browser:
        webbrowser.open(url)
    try:
        server.serve_forever(poll_interval=0.5)
    except KeyboardInterrupt:
        pass
    finally:
        for identity, job in list(app.jobs.items()):
            if job['State'] in ('Queued', 'Running', 'Cancelling'):
                app.cancel(identity)
        server.server_close()


if __name__ == '__main__':
    main()
