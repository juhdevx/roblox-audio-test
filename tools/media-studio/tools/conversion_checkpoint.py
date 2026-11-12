"""Validate a local conversion checkpoint without loading RGB/PCM into memory."""
from __future__ import annotations

import json
import math
import os
from pathlib import Path
import re
import stat

MAX_MANIFEST_BYTES = 64 * 1024


def _unlinked(path: Path) -> bool:
    """Reject symlinks, junctions and other Windows reparse points before resolve()."""
    for candidate in (path, *path.parents):
        info = candidate.lstat()
        if stat.S_ISLNK(info.st_mode) or getattr(info, 'st_file_attributes', 0) & getattr(stat, 'FILE_ATTRIBUTE_REPARSE_POINT', 0x400):
            return False
    return True


def _exact(left, right) -> bool:
    # Python equality alone treats True == 1 and 24 == 24.0 as matches.
    if type(left) is not type(right):
        return False
    if isinstance(left, dict):
        return left.keys() == right.keys() and all(_exact(left[key], right[key]) for key in left)
    if isinstance(left, list):
        return len(left) == len(right) and all(_exact(a, b) for a, b in zip(left, right))
    return left == right


def _object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('Duplicate checkpoint JSON key')
        result[key] = value
    return result


def _invalid_constant(_value):
    raise ValueError('Non-finite checkpoint JSON number')


def _walk_error(error):
    raise error


def load_checkpoint(package_root, name, source_sha256, settings) -> Path | None:
    """Return only a matching, bounded, link-free checkpoint directory; else None.

    Call validate_rgb/validate_pcm separately before reusing its media. This does
    not accept a partial raw capture as a complete video, or mutate any files.
    """
    if (type(name) is not str or not re.fullmatch(r'[A-Za-z0-9_]{1,40}', name)
            or type(source_sha256) is not str or not re.fullmatch(r'[a-f0-9]{64}', source_sha256)
            or type(settings) is not dict):
        return None
    folder = Path(package_root).absolute() / 'workbench' / 'checkpoints' / name
    manifest = folder / 'Checkpoint.json'
    try:
        if not folder.is_dir() or not _unlinked(folder) or not _unlinked(manifest) or not manifest.is_file():
            return None
        # followlinks=False is complemented by explicit junction/reparse checks.
        for parent, directories, files in os.walk(folder, followlinks=False, onerror=_walk_error):
            for child in directories + files:
                if not _unlinked(Path(parent) / child):
                    return None
        with manifest.open('rb') as source:
            data = source.read(MAX_MANIFEST_BYTES + 1)
        if len(data) > MAX_MANIFEST_BYTES:
            return None
        value = json.loads(data.decode('utf-8'), object_pairs_hook=_object, parse_constant=_invalid_constant)
        if (type(value) is not dict or type(value.get('Version')) is not int or value['Version'] != 1
                or value.get('SourceSHA256') != source_sha256 or not _exact(value.get('Settings'), settings)):
            return None
        return folder
    except (OSError, UnicodeError, ValueError, TypeError, RecursionError):
        return None


def _positive_integer(metadata, name):
    value = metadata.get(name)
    if type(value) is not int or value <= 0:
        raise ValueError(f'Checkpoint {name} must be a positive integer')
    return value


def _duration(metadata):
    value = metadata.get('duration')
    if type(value) not in (int, float) or not 0 < value <= 3600 or not math.isfinite(value):
        raise ValueError('Checkpoint duration must be finite, positive and at most one hour')
    return value


def _media_size(path):
    path = Path(path).absolute()
    try:
        if not _unlinked(path) or not path.is_file():
            raise ValueError('Checkpoint media must be a regular file without links')
        return path.stat().st_size
    except OSError as error:
        raise ValueError('Checkpoint media file is missing or unreadable') from error


def validate_rgb(path, metadata):
    """Require every declared RGB24 frame, so an encoder cannot freeze the tail."""
    if type(metadata) is not dict:
        raise ValueError('Checkpoint RGB metadata must be an object')
    width = _positive_integer(metadata, 'width')
    height = _positive_integer(metadata, 'height')
    frames = _positive_integer(metadata, 'frames')
    fps = _positive_integer(metadata, 'fps')
    duration = _duration(metadata)
    if fps > 30:
        raise ValueError('Checkpoint RGB FPS exceeds the decoder limit of 30')
    if frames != math.ceil(duration * fps):
        raise ValueError('Checkpoint RGB frames do not cover its declared duration and FPS')
    expected = width * height * 3 * frames
    actual = _media_size(path)
    if actual != expected:
        raise ValueError(f'Checkpoint RGB is incomplete or mismatched: expected {expected} bytes, found {actual}')


def validate_pcm(path, metadata):
    """Require complete interleaved stereo float32 samples on the 24 kHz clock."""
    if type(metadata) is not dict:
        raise ValueError('Checkpoint PCM metadata must be an object')
    frames = _positive_integer(metadata, 'frames')
    sample_rate = _positive_integer(metadata, 'sampleRate')
    channels = _positive_integer(metadata, 'channels')
    duration = _duration(metadata)
    if sample_rate != 24000 or channels != 2:
        raise ValueError('Checkpoint PCM must be 24000 Hz stereo float32')
    if not math.isclose(duration, frames / sample_rate, rel_tol=0, abs_tol=1 / sample_rate):
        raise ValueError('Checkpoint PCM frame count and duration disagree')
    expected = frames * channels * 4
    actual = _media_size(path)
    if actual != expected:
        raise ValueError(f'Checkpoint PCM is incomplete or mismatched: expected {expected} bytes, found {actual}')
