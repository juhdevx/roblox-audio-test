"""Convert stereo PCM into phase-aware SPC1 partials and stochastic residual bands."""
import argparse
from functools import lru_cache
import hashlib
import json
import math
import os
import re
import struct
import zlib
from pathlib import Path

os.environ.setdefault('OPENBLAS_NUM_THREADS', '1')
import numpy as np

from hybrid_model import extract_residual
from mix_metadata import analyze

MIN_HZ = 20.0
MAX_HZ = 8800.0
HEADER_BYTES = 48
SAMPLE_RATE = 24000
NOISE_BANDS = 12
TAU = 2 * np.pi
_WINDOWS = {}
AUDIO_PROFILES = {
    'balanced': {'voices': 96, 'fps': 60},
    'fidelity': {'voices': 128, 'fps': 60},
}


@lru_cache(maxsize=8)
def _peak_constants(size, rate):
    if size not in _WINDOWS:
        _WINDOWS[size] = np.hanning(size)
    window = _WINDOWS[size]
    bins = np.arange(size // 2 + 1)
    frequencies = bins * rate / size
    allowed = (frequencies >= MIN_HZ) & (frequencies <= MAX_HZ)
    return window, 2.0 / window.sum(), frequencies, allowed


@lru_cache(maxsize=16)
def _phase_rotation(size, hop):
    bins = np.arange(size // 2 + 1)
    expected = 2 * np.pi * bins * hop / size
    return np.exp(-1j * expected)


def peaks(samples, center, size, rate, history=None):
    first = center - size // 2
    window, scale, bin_frequency, allowed = _peak_constants(size, rate)
    if first >= 0 and first + size <= len(samples):
        weighted = samples[first:first + size] * window[:, None]
    else:
        frame = np.zeros((size, 2), dtype=np.float64)
        lo, hi = max(first, 0), min(first + size, len(samples))
        frame[lo - first:hi - first] = samples[lo:hi]
        weighted = frame * window[:, None]
    spectrum = np.fft.rfft(weighted, axis=0)
    mags = np.abs(spectrum) * scale
    power = np.sqrt(np.sum(mags * mags, axis=1))
    indices = np.flatnonzero((power[1:-1] > power[:-2]) & (power[1:-1] >= power[2:]) & allowed[1:-1]) + 1
    if not len(indices):
        return np.empty((0, 5))
    log = np.log(np.maximum(power, 1e-12))
    left, mid, right = log[indices - 1], log[indices], log[indices + 1]
    shift = np.clip(0.5 * (left - right) / np.minimum(left - 2 * mid + right, -1e-12), -0.5, 0.5)
    frequency = (indices + shift) * rate / size
    # Phase advance removes the small frame-to-frame pitch wobble of peak fitting.
    # Use a single strong channel so opposite stereo phases cannot cancel.
    if history is not None and 'spectrum' in history:
        hop = center - history['center']
        if hop > 0:
            channels = np.argmax(mags[indices], axis=1)
            current = spectrum[indices, channels]
            previous = history['spectrum'][indices, channels]
            residual = np.angle(current * np.conj(previous) * _phase_rotation(size, hop)[indices])
            phase_frequency = bin_frequency[indices] + residual * rate / (2 * np.pi * hop)
            reliable = ((np.abs(previous) >= np.abs(current) * 0.2)
                        & (np.abs(phase_frequency - frequency) < rate / size * 0.75))
            frequency = np.where(reliable, phase_frequency * 0.85 + frequency * 0.15, frequency)
    if history is not None:
        history['spectrum'] = spectrum
        history['center'] = center
    # Correct Hann scalloping instead of boosting the fitted logarithmic peak.
    offset = np.clip(frequency * size / rate - indices, -0.5, 0.5)
    response = np.sinc(offset) / (1 - offset * offset)
    gain = power[indices] / np.maximum(response, 0.8)
    pan = np.arctan2(mags[indices, 1], mags[indices, 0]) * (4 / np.pi) - 1
    channels = np.argmax(mags[indices], axis=1)
    # STFT phase is at window start; convert to center time and to sine phase.
    phase = np.angle(spectrum[indices, channels]) + np.pi * indices + np.pi * (frequency - bin_frequency[indices]) / rate + np.pi / 2
    return np.column_stack((frequency, gain, pan, power[indices], np.mod(phase, 2 * np.pi)))


def tracked_frames(samples, rate, fps, voices):
    count = math.ceil(len(samples) * fps / rate)
    output = np.zeros((count, voices, 4), dtype='<u2')
    previous_frequency = np.zeros(voices)
    previous_gain = np.zeros(voices)
    previous_pan = np.zeros(voices)
    previous_phase = np.zeros(voices)
    release = np.zeros(voices, dtype=np.int16)
    low_history, high_history = {}, {}
    log_span = math.log2(MAX_HZ / MIN_HZ)
    for index in range(count):
        center = round(index * rate / fps)
        low = peaks(samples, center, 4096, rate, low_history)
        high = peaks(samples, center, 2048, rate, high_history)
        candidates = np.concatenate((low[low[:, 0] < 550], high[high[:, 0] >= 550]))
        if len(candidates):
            candidates = candidates[np.argsort(-candidates[:, 1])[:voices * 2]]
        candidate_state = candidates[:, [0, 1, 2, 4]]
        current = np.zeros((voices, 4))
        assigned = np.zeros(voices, dtype=bool)
        used = np.zeros(len(candidates), dtype=bool)
        # Resolve closest continuations globally; a strong neighbour must not steal
        # another trajectory and turn adjacent harmonics into a sweeping whistle.
        if len(candidates):
            tolerance = np.maximum(8.0, previous_frequency * 0.018)
            distance = np.abs(previous_frequency[:, None] - candidates[None, :, 0])
            cost = distance / tolerance[:, None]
            cost[(previous_gain <= 1e-5) | (release > 0)] = np.inf
            rows, columns = np.nonzero(cost <= 1)
            order = np.argsort(cost[rows, columns], kind='stable')
            for slot, candidate in zip(rows[order].tolist(), columns[order].tolist()):
                if assigned[slot] or used[candidate]:
                    continue
                current[slot] = candidate_state[candidate]
                # Weak partials have noisy stereo estimates; avoid frame-rate panning.
                current[slot, 2] = previous_pan[slot] * 0.35 + current[slot, 2] * 0.65
                assigned[slot] = True
                used[candidate] = True
        # A reused oscillator first reaches silence. Never interpolate an audible
        # old partial directly into an unrelated newly appearing frequency.
        fading = (~assigned) & (previous_gain > 1e-5)
        current[fading, 0] = previous_frequency[fading]
        current[fading, 1] = previous_gain[fading] * 0.2
        current[fading, 2] = previous_pan[fading]
        current[fading, 3] = np.mod(previous_phase[fading]
            + TAU * previous_frequency[fading] / fps, TAU)
        release = np.where(fading, release + 1, 0)
        finished = fading & (release >= 2)
        current[finished, 1] = 0
        free = np.flatnonzero((~assigned) & (previous_gain <= 1e-5) & (~fading))
        free = free[np.argsort(previous_gain[free], kind='stable')]
        for candidate, slot in zip(np.flatnonzero(~used), free):
            current[slot] = candidate_state[candidate]
            assigned[slot] = True
        active = current[:, 1] > 1e-5
        encoded_frequency = np.clip(np.rint(np.log2(np.maximum(current[:, 0], MIN_HZ) / MIN_HZ) / log_span * 65534) + 1, 1, 65535)
        db = 20 * np.log10(np.maximum(current[:, 1], 1e-8))
        encoded_gain = np.clip(np.rint((db + 100) / 100 * 65534) + 1, 1, 65535)
        output[index, :, 0] = np.where(active, encoded_frequency, 0).astype('<u2')
        output[index, :, 1] = np.where(active, encoded_gain, 0).astype('<u2')
        # Offset binary pan keeps all fields unsigned and easy to read in Luau.
        output[index, :, 2] = np.rint((np.clip(current[:, 2], -1, 1) + 1) * 32767.5).astype('<u2')
        output[index, :, 3] = np.rint(np.mod(current[:, 3], TAU) / TAU * 65535).astype('<u2')
        previous_frequency = current[:, 0]
        previous_gain = current[:, 1]
        previous_pan = current[:, 2]
        previous_phase = current[:, 3]
        if index % (fps * 10) == 0:
            print(f'Analyzed {index / fps:.0f}/{count / fps:.0f}s', flush=True)
    return output


def prioritize_voices(data):
    """Put the strongest complete trajectories first for reduced runtime profiles."""
    encoded = data[:, :, 1].astype(np.float64)
    gain = np.where(encoded > 0, 10 ** (((encoded - 1) / 65534 * 100 - 100) / 20), 0)
    energy = np.sum(gain * gain, axis=0)
    return np.ascontiguousarray(data[:, np.argsort(-energy, kind='stable')])


def encode_rms(rms):
    """Use the same -100..0 dB unsigned logarithmic convention as partial gain."""
    db = 20 * np.log10(np.maximum(rms, 1e-8))
    encoded = np.clip(np.rint((db + 100) / 100 * 65534) + 1, 1, 65535)
    return np.where(rms > 1e-5, encoded, 0).astype('<u2')


def serialize_track(samples, rate, fps, voices, segment_seconds, name, destination, legacy=False, analysis='source-fit'):
    """Write complete, independently checksummed segments and the registry metadata."""
    data = tracked_frames(samples, rate, fps, voices)
    if analysis not in ('source-fit', 'peaks', 'phase-pan-fit'):
        raise ValueError('Unknown audio analysis method')
    if analysis == 'source-fit' and not legacy:
        from amplitude_fit import refine_amplitudes
        data = refine_amplitudes(samples, rate, fps, data)
    elif analysis == 'phase-pan-fit' and not legacy:
        from phase_pan_fit import refine_amplitudes
        data = refine_amplitudes(samples, rate, fps, data)
    data = prioritize_voices(data)
    encoding = 1 if legacy else 3
    noise_bands = 0 if legacy else NOISE_BANDS
    if legacy:
        residual = None
        packed_frames = np.ascontiguousarray(data[:, :, :3]).view(np.uint8).reshape(len(data), -1)
    else:
        residual = encode_rms(extract_residual(samples, rate, fps, data[:, :, :3]))
        partial_bytes = data.view(np.uint8).reshape(len(data), -1)
        residual_bytes = residual.view(np.uint8).reshape(len(data), -1)
        packed_frames = np.concatenate((partial_bytes, residual_bytes), axis=1)
    destination.mkdir(parents=True, exist_ok=True)
    segment_frames = segment_seconds * fps
    files = []
    for part, first in enumerate(range(0, len(data), segment_frames)):
        frames = min(segment_frames, len(data) - first)
        payload = packed_frames[first:first + frames].tobytes()
        header = struct.pack('<4sHHIIHHIIIIfII', b'SPC1', 1, HEADER_BYTES,
            HEADER_BYTES + len(payload), 0, voices, fps, frames,
            first, rate, len(data), 440.0, encoding, noise_bands)
        blob = bytearray(header + payload)
        checksum = zlib.adler32(blob) & 0xffffffff
        struct.pack_into('<I', blob, 12, checksum)
        filename = f'{name}_{part:03d}.spc'
        (destination / filename).write_bytes(blob)
        files.append(dict(file=filename, bytes=len(blob), checksum=checksum, frames=frames, first=first))
    manifest = dict(Name=name, Frames=len(data), FPS=fps, Voices=voices,
        SegmentFrames=segment_frames, Segments=len(files), Duration=len(samples) / rate,
        SampleRate=rate, BaseSampleAssetId=9040512197, BaseFrequency=440,
        Encoding=encoding, NoiseBands=noise_bands, Files=files,
        Analysis=({'source-fit':'source-fit-v1', 'phase-pan-fit':'phase-pan-fit-v1'}.get(analysis, 'tracked-peaks')
            if not legacy else 'tracked-peaks'))
    if analysis == 'phase-pan-fit' and not legacy:
        manifest['Experimental'] = True
    manifest.update(analyze(samples, data[:, :, 1], residual))
    return manifest


def main():
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument('pcm', type=Path)
    cli.add_argument('--name', default='WoahUseIt')
    cli.add_argument('--output', type=Path, default=Path(__file__).parents[1] / 'publish')
    cli.add_argument('--profile', choices=tuple(AUDIO_PROFILES), default='fidelity',
        help='fidelity retains 128 partials; balanced retains 96 at lower network/render cost')
    cli.add_argument('--voices', type=int, help='Override the selected profile')
    cli.add_argument('--fps', type=int, help='Override the selected profile')
    cli.add_argument('--segment-seconds', type=int, default=2)
    cli.add_argument('--legacy', action='store_true', help='Write the phase-less 6-byte SPC1 encoding')
    cli.add_argument('--analysis', choices=('source-fit', 'peaks', 'phase-pan-fit'), default='source-fit',
        help='source-fit is the stable default; phase-pan-fit is an experimental alternative with mixed spectral results')
    args = cli.parse_args()
    profile = AUDIO_PROFILES[args.profile]
    args.voices = profile['voices'] if args.voices is None else args.voices
    args.fps = profile['fps'] if args.fps is None else args.fps
    if (not re.fullmatch(r'[A-Za-z0-9_]{1,40}', args.name) or not 16 <= args.voices <= 128
            or not 20 <= args.fps <= 90 or not 1 <= args.segment_seconds <= 30):
        cli.error('Use 1-40 ASCII letters/digits/underscores, 16-128 voices, 20-90 FPS and 1-30 second segments')
    try:
        meta = json.loads(Path(str(args.pcm) + '.json').read_text(encoding='utf-8'))
        rate = meta['sampleRate']
        if rate != SAMPLE_RATE or meta.get('channels', 2) != 2:
            cli.error('Decode the source as 24000 Hz stereo PCM first')
        size = args.pcm.stat().st_size
        if size == 0 or size % 8 or size // 8 > rate * 3600:
            cli.error('PCM must contain 1 sample to 1 hour of interleaved float32 stereo')
        samples = np.memmap(args.pcm, dtype='<f4', mode='r').reshape(-1, 2)
        for first in range(0, len(samples), rate * 30):
            if not np.all(np.isfinite(samples[first:first + rate * 30])):
                cli.error('PCM contains non-finite samples')
    except (OSError, ValueError, KeyError) as error:
        cli.error(f'Cannot read decoded PCM: {error}')
    manifest = serialize_track(samples, rate, args.fps, args.voices, args.segment_seconds,
        args.name, args.output, args.legacy, args.analysis)
    manifest['AudioProfile'] = args.profile if args.voices == profile['voices'] and args.fps == profile['fps'] else 'custom'
    manifest['PayloadBytesPerSecond'] = args.fps * (args.voices * (6 if args.legacy else 8) + (0 if args.legacy else NOISE_BANDS * 4))
    digest = hashlib.sha256()
    with args.pcm.open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(chunk)
    manifest['SourceSHA256'] = digest.hexdigest()
    (args.output / f'{args.name}.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    (args.output / f'{args.name}.entry.txt').write_text(
        f'["{args.name}"] = {{Frames = {manifest["Frames"]}, FPS = {args.fps}, Voices = {args.voices}, '
        f'SegmentFrames = {manifest["SegmentFrames"]}, Segments = {manifest["Segments"]}, '
        f'Encoding = {manifest["Encoding"]}, NoiseBands = {manifest["NoiseBands"]}, '
        f'MixGain = {manifest["MixGain"]:.8f}, '
        'BaseUrl = "YOUR_RAW_GITHUB_FOLDER_URL"},\n', encoding='utf-8')
    print(json.dumps({k:v for k,v in manifest.items() if k!='Files'},indent=2),flush=True)


if __name__ == '__main__':
    main()
