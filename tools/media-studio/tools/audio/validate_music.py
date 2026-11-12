"""Check complete SPC1 upload bundles before publishing them."""
import argparse
import hashlib
import json
import math
import re
import struct
import sys
import zlib
from pathlib import Path

HEADER = struct.Struct('<4sHHIIHHIIIIfII')
TRACK_NAME = re.compile(r'[A-Za-z0-9_]{1,40}')


def integer(value, label, minimum, maximum):
    if type(value) is not int or not minimum <= value <= maximum:
        raise ValueError(f'{label}: expected an integer from {minimum} to {maximum}')
    return value


def validate_track(manifest_path):
    """Read every segment and return an integrity report without changing files."""
    manifest_path = Path(manifest_path).resolve()
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    if not isinstance(manifest, dict):
        raise ValueError('The manifest must be a JSON object')
    name = manifest.get('Name')
    if not isinstance(name, str) or not TRACK_NAME.fullmatch(name):
        raise ValueError('Name: use 1-40 ASCII letters, digits or underscores')
    if manifest_path.name != f'{name}.json':
        raise ValueError('Manifest filename must match Name exactly')
    frames = integer(manifest.get('Frames'), 'Frames', 1, 90 * 3600)
    fps = integer(manifest.get('FPS'), 'FPS', 20, 90)
    voices = integer(manifest.get('Voices'), 'Voices', 16, 128)
    segment_frames = integer(manifest.get('SegmentFrames'), 'SegmentFrames', 1, 2700)
    segments = integer(manifest.get('Segments'), 'Segments', 1, frames)
    if segments != math.ceil(frames / segment_frames):
        raise ValueError('Segments must cover Frames in consecutive SegmentFrames parts')
    encoding = manifest.get('Encoding', 1)
    bands = manifest.get('NoiseBands', 0)
    if type(encoding) is not int or type(bands) is not int:
        raise ValueError('Encoding and NoiseBands must be integers')
    if encoding == 1 and bands == 0:
        stride = voices * 6
    elif encoding == 3 and 1 <= bands <= 16:
        stride = voices * 8 + bands * 4
    else:
        raise ValueError('Only legacy SPC1 or phase-aware SPC1 with residual bands is supported')
    if manifest.get('SampleRate') != 24000 or manifest.get('BaseFrequency') != 440:
        raise ValueError('Expected 24000 Hz PCM and a 440 Hz base sample')
    if manifest.get('BaseSampleAssetId') != 9040512197:
        raise ValueError('BaseSampleAssetId differs from the configured sine sample')
    duration = manifest.get('Duration')
    if (isinstance(duration, bool) or not isinstance(duration, (int, float))
            or not math.isfinite(duration) or not 0 < duration <= 3600
            or math.ceil(duration * fps - 1e-8) != frames):
        raise ValueError('Duration does not match Frames/FPS')
    if 'MixGain' in manifest:
        gain = manifest['MixGain']
        if (isinstance(gain, bool) or not isinstance(gain, (int, float))
                or not math.isfinite(gain) or not 0.5 <= gain <= 3):
            raise ValueError('MixGain must be finite and between 0.5 and 3')
    rows = manifest.get('Files')
    if not isinstance(rows, list) or len(rows) != segments:
        raise ValueError('Files must list every segment exactly once')
    checked = []
    position = 0
    for index, row in enumerate(rows):
        if not isinstance(row, dict):
            raise ValueError(f'Files[{index}] must be an object')
        expected_name = f'{name}_{index:03d}.spc'
        if row.get('file') != expected_name:
            raise ValueError(f'Files[{index}]: expected plain filename {expected_name}')
        path = manifest_path.parent / expected_name
        if path.is_symlink() or path.resolve().parent != manifest_path.parent:
            raise ValueError(f'Segment must remain inside the upload folder: {expected_name}')
        blob = bytearray(path.read_bytes())
        if len(blob) < HEADER.size:
            raise ValueError(f'Truncated SPC1 header: {expected_name}')
        (magic, version, header_bytes, size, checksum, actual_voices, actual_fps,
         count, first, rate, total, root, actual_encoding, actual_bands) = HEADER.unpack_from(blob)
        expected_count = min(segment_frames, frames - position)
        if (magic != b'SPC1' or version != 1 or header_bytes != HEADER.size
                or size != len(blob) or size != HEADER.size + expected_count * stride
                or actual_voices != voices or actual_fps != fps or count != expected_count
                or first != position or rate != 24000 or total != frames or root != 440
                or actual_encoding != encoding or actual_bands != bands):
            raise ValueError(f'SPC1 header/dimensions differ from manifest: {expected_name}')
        for key, expected in (('bytes', size), ('checksum', checksum),
                              ('frames', count), ('first', first)):
            if type(row.get(key)) is not int or row[key] != expected:
                raise ValueError(f'Files[{index}].{key} differs from SPC1 header')
        struct.pack_into('<I', blob, 12, 0)
        if zlib.adler32(blob) & 0xffffffff != checksum:
            raise ValueError(f'SPC1 checksum mismatch: {expected_name}')
        struct.pack_into('<I', blob, 12, checksum)
        checked.append(dict(file=expected_name, bytes=size, sha256=hashlib.sha256(blob).hexdigest()))
        position += count
    if position != frames:
        raise ValueError('Segments leave a gap or extend past the final frame')
    expected_files = {item['file'] for item in checked}
    stale = sorted(path.name for path in manifest_path.parent.glob(f'{name}_*.spc')
        if re.fullmatch(re.escape(name) + r'_\d+\.spc', path.name) and path.name not in expected_files)
    if stale:
        raise ValueError(f'Unlisted old segment in upload folder: {stale[0]}')
    manifest_bytes = manifest_path.read_bytes()
    upload = [dict(file=manifest_path.name, bytes=len(manifest_bytes),
                   sha256=hashlib.sha256(manifest_bytes).hexdigest()), *checked]
    return dict(Status='READY', Name=name, Frames=frames, Duration=duration, Segments=segments,
        Encoding=encoding, NoiseBands=bands, UploadFiles=len(upload),
        UploadBytes=sum(item['bytes'] for item in upload), Files=upload,
        UploadBatches=[[item['file'] for item in upload[first:first + 95]]
                       for first in range(0, len(upload), 95)])


def main():
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument('path', type=Path, help='Manifest JSON file or upload folder')
    cli.add_argument('--json', type=Path, help='Optional path for the complete integrity report')
    args = cli.parse_args()
    try:
        paths = sorted(args.path.glob('*.json')) if args.path.is_dir() else [args.path]
        if not paths:
            raise ValueError('No manifest JSON found in this folder')
        reports = [validate_track(path) for path in paths]
        if args.json:
            if args.json.resolve().parent in {path.resolve().parent for path in paths}:
                raise ValueError('Write the integrity report outside the upload folder')
            args.json.write_text(json.dumps(reports, indent=2), encoding='utf-8')
        for report in reports:
            print(f'VALIDATED: {report["Name"]} | {report["Segments"]} parts | '
                  f'{report["Duration"]:.2f}s | {report["UploadFiles"]} files to upload')
    except (OSError, ValueError, KeyError, struct.error) as error:
        print(f'ERROR: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
