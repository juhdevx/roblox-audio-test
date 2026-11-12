"""Render bounded local SPC comparison clips; this is an offline sine model, not Roblox audio capture."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import sys
import wave

os.environ.setdefault('OPENBLAS_NUM_THREADS', '1')
import numpy as np
from validate_music import validate_track

RATE = 24000
SCOPE = ('Offline held-control sine model: frequency is held for each source frame; amplitude and equal-power pan '
    'are interpolated. Uses encoded phase and bounded phase-slope gates. Excludes stochastic residuals, native '
    'mixer scheduling, carrier response, smoothing, compression and device behavior. This is not a native Roblox '
    'recording, listening score, LUFS or true-peak measurement. RawGain applies only the manifest MixGain; '
    'GainMatched adds one nonnegative waveform least-squares gain. WAV files share one peak-safe preview gain.')


def load_source(path):
    path = Path(path).resolve()
    metadata = json.loads(Path(str(path)+'.json').read_text(encoding='utf-8'))
    size = path.stat().st_size
    if (metadata.get('sampleRate') != RATE or metadata.get('channels', 2) != 2
            or not size or size % 8 or size // 8 > RATE*3600):
        raise ValueError('Use nonempty 24000 Hz stereo float32 PCM, up to one hour')
    samples = np.memmap(path, dtype='<f4', mode='r').reshape(-1, 2)
    digest = hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda: source.read(1024*1024), b''):
            digest.update(block)
    return samples, digest.hexdigest()


def load_manifest(path, samples, source_sha):
    path = Path(path).resolve()
    validate_track(path)
    metadata = json.loads(path.read_text(encoding='utf-8'))
    if (math.ceil(len(samples)*metadata['FPS']/RATE) != metadata['Frames']
            or abs(metadata['Duration']-len(samples)/RATE) > 1/RATE):
        raise ValueError('The manifest duration does not match source PCM')
    if metadata.get('SourceSHA256', source_sha) != source_sha:
        raise ValueError('The manifest belongs to different source PCM')
    return path, metadata


def read_frames(path, metadata, first, last):
    """Decode only segments intersecting the requested bounded frame interval."""
    parts = []
    voices = metadata['Voices']; words = 4 if metadata.get('Encoding', 1) == 3 else 3
    for row in metadata['Files']:
        end = row['first']+row['frames']
        if end <= first or row['first'] >= last:
            continue
        records = np.frombuffer((path.parent/row['file']).read_bytes(), dtype='<u2', offset=48)
        records = records.reshape(row['frames'], -1)[:, :voices*words].reshape(-1, voices, words)
        low, high = max(first-row['first'], 0), min(last-row['first'], row['frames'])
        parts.append(records[low:high].copy())
    if not parts:
        raise ValueError('The requested clip contains no spectral frames')
    return np.concatenate(parts)


def synthesize(data, fps, encoding=3):
    """Reconstruct deterministic held-control partials; residual fields are excluded."""
    values = data.astype(float)
    frequency = np.where(values[:, :, 0] > 0, 20*440**((values[:, :, 0]-1)/65534), 0)
    amplitude = np.where(values[:, :, 1] > 0, 10**(((values[:, :, 1]-1)/65534*100-100)/20), 0)
    pan = values[:, :, 2]/32767.5-1
    phases = values[:, :, 3]/65535 if encoding == 3 else None
    phase = phases[0].copy() if phases is not None else np.arange(data.shape[1])*.61803398875 % 1
    held = np.full(data.shape[1], 440.)
    output = np.zeros((round(max(len(data)-1, 0)*RATE/fps), 2))
    for frame in range(len(data)-1):
        second = frame+1
        begin, end = round(frame*RATE/fps), round(second*RATE/fps)
        # A rounded output sample can lie either side of the ideal frame boundary.
        sample_times = (begin+np.arange(end-begin))[:, None]/RATE-frame/fps
        fraction = np.clip(sample_times*fps, 0, 1)
        f0, f1 = frequency[frame], frequency[second]
        stable = (f0 > 0) & (f1 > 0)
        hz = np.where(stable, f0, np.maximum(f0, f1))
        hz = np.where(hz > 0, hz, held)
        if phases is not None:
            arriving = (amplitude[frame] == 0) & (amplitude[second] > 0)
            phase[arriving] = (phases[second, arriving]-f1[arriving]/fps) % 1
            ratio = np.log(np.maximum(f1, 1)/np.maximum(f0, 1))
            average = np.where(np.abs(ratio) > 1e-7,
                f0*np.expm1(ratio)/np.where(np.abs(ratio) > 1e-7, ratio, 1), f0)
            error = (phases[second]-phases[frame]-average/fps+.5) % 1-.5
            correction = np.clip(error*fps, -np.minimum(f0, f1)*.04, np.minimum(f0, f1)*.04)
            valid = stable & ~((np.maximum(f0, f1)/np.maximum(np.minimum(f0, f1), 1) > 1.08)
                & (np.abs(f1-f0) > 18))
            valid &= (amplitude[frame] >= 1e-4) & (amplitude[second] >= 1e-4)
            valid &= (pan[frame] > 0) == (pan[second] > 0)
            hz = np.where(valid, hz+correction, hz)
        amp = amplitude[frame]+(amplitude[second]-amplitude[frame])*fraction
        stereo = pan[frame]+(pan[second]-pan[frame])*fraction
        oscillator = np.sin(2*np.pi*(phase+sample_times*hz))*amp
        angle = (stereo+1)*np.pi/4
        output[begin:end, 0] = np.sum(oscillator*np.cos(angle), axis=1)
        output[begin:end, 1] = np.sum(oscillator*np.sin(angle), axis=1)
        phase = (phase+hz/fps) % 1
        held = hz.copy()
    return output


def render_clip(path, metadata, start, duration):
    fps = metadata['FPS']
    first = max(0, math.floor(start*fps))
    last = min(metadata['Frames'], math.ceil((start+duration)*fps)+2)
    data = read_frames(path, metadata, first, last)
    # Repeat the final record to interpolate the final source frame safely.
    if last == metadata['Frames']:
        data = np.concatenate((data, data[-1:]))
    output = synthesize(data, fps, metadata.get('Encoding', 1))
    offset = round((start-first/fps)*RATE); length = round(duration*RATE)
    output = output[offset:offset+length]
    if len(output) != length:
        raise ValueError('The selected clip extends past encoded media')
    return output*metadata.get('MixGain', 1.)


def db(value):
    return float(20*np.log10(max(float(value), 1e-12)))


def signal_stats(samples):
    rms = float(np.sqrt(np.mean(samples*samples)))
    peak = float(np.max(np.abs(samples)))
    left, right = samples[:, 0], samples[:, 1]
    mid, side = (left+right)/2, (left-right)/2
    denominator = float(np.sqrt(np.sum(left*left)*np.sum(right*right)))
    correlation = float(np.sum(left*right)/denominator) if denominator > 1e-20 else 0.
    return {'Loudness':{'Rms':rms, 'RmsDbfs':db(rms), 'SamplePeak':peak, 'PeakDbfs':db(peak),
            'CrestDb':db(peak)-db(rms), 'SamplesOverFullScale':int(np.count_nonzero(np.abs(samples) > 1))},
        'Stereo':{'ChannelCorrelation':correlation, 'LeftRms':float(np.sqrt(np.mean(left*left))),
            'RightRms':float(np.sqrt(np.mean(right*right))),
            'SideMidDb':db(np.sqrt(np.mean(side*side)))-db(np.sqrt(np.mean(mid*mid)))}}


def measure(source, output):
    if source.shape != output.shape or len(source) < 4096:
        raise ValueError('Matching stereo clips of at least 4096 samples are required')
    source_power = float(np.sum(source*source)); output_power = float(np.sum(output*output))
    dot = float(np.sum(source*output))
    gain = max(0., dot/max(output_power, 1e-20))
    correlation = dot/math.sqrt(max(source_power*output_power, 1e-20))
    report = {'WaveformCorrelation':correlation, **signal_stats(output)}
    for label, scale in [('RawGain', 1.), ('GainMatched', gain)]:
        candidate = output*scale
        error = float(np.sum((source-candidate)**2))
        snr = float(10*np.log10(max(source_power, 1e-20)/max(error, 1e-20)))
        result = {'WaveformSnrDb':snr, 'RmsRatio':float(np.sqrt(np.sum(candidate*candidate)/max(source_power, 1e-20)))}
        if label == 'GainMatched':
            result['Gain'] = gain
        for size in (512, 1024, 2048, 4096):
            window = np.hanning(size)[None, :, None]
            def spectrum(signal):
                frames = np.lib.stride_tricks.sliding_window_view(signal, size, axis=0)[::400].transpose(0, 2, 1)
                return np.abs(np.fft.rfft(frames*window, axis=1))
            reference, estimated = spectrum(source), spectrum(candidate)
            result[f'SpectralConvergence{size}'] = float(np.linalg.norm(reference-estimated)/max(np.linalg.norm(reference), 1e-20))
        report[label] = result
    return report


def choose_starts(duration, clip_seconds, clips, starts=None):
    if (not math.isfinite(clip_seconds) or not 1 <= clip_seconds <= 12
            or type(clips) is not int or not 1 <= clips <= 8):
        raise ValueError('Use 1-12 second clips and 1-8 clips')
    actual = min(duration, clip_seconds)
    if actual < 4096/RATE:
        raise ValueError('At least 0.18 seconds of source audio is needed for comparison')
    maximum = max(0., duration-actual)
    if starts is None:
        starts = [maximum*(index+.5)/clips for index in range(clips)]
    if (not 1 <= len(starts) <= 8 or any(not math.isfinite(value) or value < 0 or value > maximum+1/RATE for value in starts)):
        raise ValueError('Clip starts must stay within the source duration; use at most eight')
    return [(round(value*RATE)/RATE, actual) for value in starts]


def write_wav(path, samples, gain):
    with wave.open(str(path), 'wb') as target:
        target.setnchannels(2); target.setsampwidth(2); target.setframerate(RATE)
        target.writeframes(np.rint(np.clip(samples*gain, -1, 1)*32767).astype('<i2').tobytes())


def compare(source_pcm, candidate_manifest, output, baseline_manifest=None, clip_seconds=4., clips=3, starts=None):
    samples, digest = load_source(source_pcm)
    path, metadata = load_manifest(candidate_manifest, samples, digest)
    manifests = {'Rendered':(path, metadata)}
    if baseline_manifest is not None:
        manifests['Baseline'] = load_manifest(baseline_manifest, samples, digest)
    output = Path(output).resolve()
    if any(output == item[0].parent for item in manifests.values()):
        raise ValueError('Save comparison files outside the upload folder')
    ranges = choose_starts(len(samples)/RATE, clip_seconds, clips, starts)
    waveforms = {label:[] for label in ['Original', *manifests]}
    report = {'SchemaVersion':1, 'Scope':SCOPE, 'Experimental':metadata.get('Experimental', False),
        'Analysis':metadata.get('Analysis', 'unknown'), 'SampleRate':RATE, 'SourceSHA256':digest,
        'SourceDuration':len(samples)/RATE, 'Clips':[],
        'Tracks':{label:{'Name':track['Name'], 'Analysis':track.get('Analysis', 'unknown'),
            'Experimental':track.get('Experimental', False), 'Voices':track['Voices'],
            'FPS':track['FPS'], 'Encoding':track.get('Encoding', 1), 'MixGain':track.get('MixGain', 1.)}
            for label, (_, track) in manifests.items()}}
    for start, duration in ranges:
        offset = round(start*RATE); length = round(duration*RATE)
        original = np.asarray(samples[offset:offset+length], dtype=float)
        if not np.all(np.isfinite(original)):
            raise ValueError('Comparison source contains non-finite samples')
        waveforms['Original'].append(original)
        results = {'Original':signal_stats(original)}
        for label, (manifest_path, track) in manifests.items():
            rendered = render_clip(manifest_path, track, start, duration)
            waveforms[label].append(rendered)
            results[label] = measure(original, rendered)
        report['Clips'].append({'StartSeconds':start, 'DurationSeconds':duration, 'Results':results})
    combined = {label:np.concatenate(parts) for label, parts in waveforms.items()}
    preview_gain = min(1., .98/max(max(float(np.max(np.abs(item))) for item in combined.values()), 1e-12))
    filenames = {'Original':'original.wav', 'Rendered':'rendered.wav'}
    if 'Baseline' in manifests:
        filenames['Baseline'] = 'baseline.wav'
    output.mkdir(parents=True, exist_ok=True)
    for label, filename in filenames.items():
        write_wav(output/filename, combined[label], preview_gain)
    report['Preview'] = {'CommonGain':preview_gain, 'DurationSeconds':len(combined['Original'])/RATE,
        'Files':filenames, 'ClipsConcatenated':True}
    report['Summary'] = {'ClipCount':len(ranges), 'Mode':'OFFLINE_SINE_MODEL',
        'HasBaseline':'Baseline' in manifests, 'Recommendation':'Compare both waveform and spectral results; no automatic quality winner is selected.'}
    if 'Baseline' in manifests:
        improved_waveform = sum(clip['Results']['Rendered']['RawGain']['WaveformSnrDb'] > clip['Results']['Baseline']['RawGain']['WaveformSnrDb'] for clip in report['Clips'])
        improved_spectral = sum(clip['Results']['Rendered']['RawGain'][f'SpectralConvergence{size}'] < clip['Results']['Baseline']['RawGain'][f'SpectralConvergence{size}'] for clip in report['Clips'] for size in (512, 1024, 2048, 4096))
        report['Summary'].update(RawSnrImprovedClips=improved_waveform, RawSpectralImprovedWindows=improved_spectral,
            SpectralWindows=len(ranges)*4, MixedResults=not(improved_waveform == len(ranges) and improved_spectral == len(ranges)*4))
    (output/'report.json').write_text(json.dumps(report, indent=2, allow_nan=False), encoding='utf-8')
    return report


def main():
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument('source_pcm', type=Path); cli.add_argument('candidate_manifest', type=Path)
    cli.add_argument('--output', type=Path, required=True)
    cli.add_argument('--baseline-manifest', type=Path)
    cli.add_argument('--clip-seconds', type=float, default=4.)
    cli.add_argument('--clips', type=int, default=3)
    cli.add_argument('--starts', help='Optional comma-separated clip starts in seconds')
    args = cli.parse_args()
    try:
        starts = [float(item) for item in args.starts.split(',')] if args.starts else None
        report = compare(args.source_pcm, args.candidate_manifest, args.output,
            args.baseline_manifest, args.clip_seconds, args.clips, starts)
        print(json.dumps({'Status':'READY', 'Report':str(args.output.resolve()/'report.json'), **report['Summary']}), flush=True)
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f'ERROR: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
