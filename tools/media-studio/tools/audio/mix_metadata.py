"""Estimate a fixed source-to-model gain without changing SPC1 music payloads."""
import argparse
import json
import math
from pathlib import Path
import struct
import zlib

import numpy as np

NOISE_MIX = 0.25
MIN_MIX_GAIN = 0.5
MAX_MIX_GAIN = 3.0
SILENCE_RMS = 1e-6


def decode_gain(encoded):
    encoded = np.asarray(encoded, dtype=np.float64)
    return np.where(encoded > 0, 10 ** (((encoded - 1) / 65534 * 100 - 100) / 20), 0)


def source_rms(samples):
    """Read stereo PCM in bounded chunks, including quiet passages and silence."""
    if samples.ndim != 2 or samples.shape[1] != 2 or not len(samples):
        raise ValueError('Nonempty stereo PCM is required')
    total = 0.0
    for first in range(0, len(samples), 24000 * 30):
        chunk = np.asarray(samples[first:first + 24000 * 30], dtype=np.float64)
        if not np.all(np.isfinite(chunk)):
            raise ValueError('PCM contains non-finite samples')
        total += float(np.sum(chunk * chunk))
    return math.sqrt(total / samples.size)


def model_power(encoded_gain, encoded_noise=None):
    """Return stereo mean power per frame before the renderer master gain.

    A constant-power stereo sine has mean-channel power amplitude squared / 4.
    Residual fields store per-channel RMS; the native residual mix is 0.25.
    This is an energy estimate, not an engine recording or a LUFS measurement.
    """
    amplitude = decode_gain(encoded_gain)
    if amplitude.ndim != 2 or not len(amplitude):
        raise ValueError('Expected nonempty (frames, voices) partial gains')
    power = np.sum(amplitude * amplitude, axis=1) / 4
    if encoded_noise is not None:
        noise = decode_gain(encoded_noise)
        if noise.ndim != 3 or noise.shape[0] != len(power) or noise.shape[2] != 2:
            raise ValueError('Expected matching (frames, bands, stereo) residuals')
        power += np.sum(noise * noise, axis=(1, 2)) * NOISE_MIX ** 2 / 2
    return power


def metadata_from_rms(original_rms, estimated_rms):
    if (not math.isfinite(original_rms) or not math.isfinite(estimated_rms)
            or original_rms < 0 or estimated_rms < 0):
        raise ValueError('RMS values must be finite and nonnegative')
    # Silence must stay silent; a missing model must not request maximum boost.
    gain = 1.0 if min(original_rms, estimated_rms) <= SILENCE_RMS else max(
        MIN_MIX_GAIN, min(MAX_MIX_GAIN, original_rms / estimated_rms))
    return dict(MixGain=round(gain, 8), SourceRms=round(original_rms, 10),
        ModelRms=round(estimated_rms, 10), MixAnalysis='SPC_ENERGY_V1')


def analyze(samples, encoded_gain, encoded_noise=None):
    power = model_power(encoded_gain, encoded_noise)
    return metadata_from_rms(source_rms(samples), math.sqrt(float(np.mean(power))))


def analyze_existing(pcm, manifest_path):
    """Analyze existing checked segments without rewriting or reconverting them."""
    manifest_path = Path(manifest_path)
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    pcm = Path(pcm)
    metadata = json.loads(Path(str(pcm) + '.json').read_text(encoding='utf-8'))
    if metadata.get('sampleRate') != 24000 or metadata.get('channels', 2) != 2:
        raise ValueError('Decode the source as 24000 Hz stereo PCM first')
    if pcm.stat().st_size == 0 or pcm.stat().st_size % 8:
        raise ValueError('PCM must contain interleaved float32 stereo samples')
    samples = np.memmap(pcm, dtype='<f4', mode='r').reshape(-1, 2)
    total_power = 0.0
    frames = 0
    for row in manifest['Files']:
        filename = row['file']
        if not isinstance(filename, str) or Path(filename).name != filename or '\\' in filename:
            raise ValueError('Segment file must be a plain filename')
        blob = bytearray((manifest_path.parent / filename).read_bytes())
        if len(blob) < 48:
            raise ValueError(f'Truncated segment: {filename}')
        magic, version, header, size, checksum, voices, fps, count, first, rate, total, root, encoding, bands = struct.unpack_from('<4sHHIIHHIIIIfII', blob)
        words = 3 if encoding == 1 and bands == 0 else 4 if encoding == 3 and 1 <= bands <= 16 else 0
        if (magic != b'SPC1' or version != 1 or header != 48 or not words
                or not 16 <= voices <= 128 or not 20 <= fps <= 90 or count < 1
                or first != frames or rate != 24000 or root != 440
                or size != len(blob) or size != row['bytes'] or checksum != row['checksum']
                or voices != manifest['Voices'] or fps != manifest['FPS']
                or total != manifest['Frames'] or count != row['frames']
                or first != row['first'] or encoding != manifest['Encoding']
                or bands != manifest['NoiseBands']
                or size != 48 + count * (voices * words * 2 + bands * 4)):
            raise ValueError(f'SPC1 dimensions do not match manifest: {filename}')
        struct.pack_into('<I', blob, 12, 0)
        if zlib.adler32(blob) & 0xffffffff != checksum:
            raise ValueError(f'SPC1 checksum mismatch: {filename}')
        records = np.frombuffer(blob, dtype='<u2', offset=48).reshape(count, -1)
        noise = records[:, voices * words:].reshape(count, bands, 2) if bands else None
        total_power += float(np.sum(model_power(records[:, 1:voices * words:words], noise)))
        frames += count
    if not frames or frames != manifest['Frames'] or len(manifest['Files']) != manifest['Segments']:
        raise ValueError('Manifest must describe every frame exactly once')
    if math.ceil(len(samples) * manifest['FPS'] / 24000) != frames:
        raise ValueError('PCM duration does not match the encoded track')
    return metadata_from_rms(source_rms(samples), math.sqrt(total_power / frames))


def main():
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument('pcm', type=Path)
    cli.add_argument('manifest', type=Path)
    args = cli.parse_args()
    try:
        print(json.dumps(analyze_existing(args.pcm, args.manifest), indent=2))
    except (OSError, ValueError, KeyError, struct.error) as error:
        cli.error(str(error))


if __name__ == '__main__':
    main()
