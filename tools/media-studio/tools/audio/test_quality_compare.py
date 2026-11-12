"""Check offline comparison metrics, bounded sampling and validated media files."""
import contextlib
import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest
import wave

import numpy as np
from convert_song import serialize_track
from quality_compare import compare, choose_starts, measure, signal_stats, synthesize, RATE


class QualityComparisonTests(unittest.TestCase):
    def setUp(self):
        scratch = Path(__file__).resolve().parent/'_test_scratch'
        scratch.mkdir(exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(prefix='quality-compare-', dir=scratch)
        self.root = Path(self.temporary.name)
        time = np.arange(RATE)/RATE
        signal = .2*np.sin(2*np.pi*440*time+.3)
        self.samples = np.column_stack((signal, signal)).astype('<f4')
        self.pcm = self.root/'source.pcm'; self.samples.tofile(self.pcm)
        Path(str(self.pcm)+'.json').write_text(json.dumps({'sampleRate':RATE, 'channels':2}))
        self.manifest = self.make_manifest('Tone')

    def tearDown(self):
        self.temporary.cleanup()

    def make_manifest(self, name, legacy=False):
        directory = self.root/name
        with contextlib.redirect_stdout(io.StringIO()):
            metadata = serialize_track(self.samples, RATE, 20, 16, 1, name, directory, legacy=legacy)
        metadata['SourceSHA256'] = hashlib.sha256(self.pcm.read_bytes()).hexdigest()
        path = directory/f'{name}.json'
        path.write_text(json.dumps(metadata), encoding='utf-8')
        return path

    def test_equal_signal_has_zero_spectral_error_and_known_stereo(self):
        report = measure(self.samples, self.samples)
        self.assertAlmostEqual(report['WaveformCorrelation'], 1)
        self.assertAlmostEqual(report['GainMatched']['Gain'], 1)
        for size in (512, 1024, 2048, 4096):
            self.assertEqual(report['RawGain'][f'SpectralConvergence{size}'], 0)
        self.assertAlmostEqual(report['Stereo']['ChannelCorrelation'], 1)

    def test_silence_metrics_are_finite(self):
        report = measure(np.zeros_like(self.samples), np.zeros_like(self.samples))
        json.dumps(report, allow_nan=False)
        self.assertEqual(report['RawGain']['SpectralConvergence4096'], 0)
        self.assertEqual(report['Loudness']['SamplePeak'], 0)

    def test_gain_fitting_is_separate_from_raw_gain(self):
        report = measure(self.samples, self.samples*.5)
        self.assertAlmostEqual(report['GainMatched']['Gain'], 2)
        self.assertGreater(report['RawGain']['SpectralConvergence1024'], .49)
        self.assertLess(report['GainMatched']['SpectralConvergence1024'], 1e-6)

    def test_sampling_is_bounded_and_invalid_ranges_rejected(self):
        ranges = choose_starts(115, 4, 3)
        self.assertEqual(len(ranges), 3)
        self.assertTrue(all(start >= 0 and start+length <= 115 for start, length in ranges))
        for options in [(115, 20, 3, None), (115, 4, 9, None), (115, 4, 3, [112]), (115, 4, 3, [float('nan')])]:
            with self.subTest(options=options):
                with self.assertRaises(ValueError):choose_starts(*options)

    def test_outputs_include_baseline_and_common_peak_safe_gain(self):
        output = self.root/'Comparison'
        report = compare(self.pcm, self.manifest, output, self.manifest, clip_seconds=1, clips=1)
        self.assertEqual(set(path.name for path in output.iterdir()), {'original.wav', 'rendered.wav', 'baseline.wav', 'report.json'})
        self.assertEqual(report['SchemaVersion'], 1)
        self.assertEqual(report['Summary']['Mode'], 'OFFLINE_SINE_MODEL')
        self.assertTrue(report['Summary']['HasBaseline'])
        self.assertIn('not a native Roblox', report['Scope'])
        self.assertEqual(report['Clips'][0]['Results']['Rendered'], report['Clips'][0]['Results']['Baseline'])
        for name in ('original.wav', 'rendered.wav', 'baseline.wav'):
            with wave.open(str(output/name), 'rb') as preview:
                self.assertEqual(preview.getframerate(), RATE)
                self.assertEqual(preview.getnchannels(), 2)
                self.assertEqual(preview.getnframes(), RATE)
                data = np.frombuffer(preview.readframes(RATE), dtype='<i2')
                self.assertLessEqual(np.max(np.abs(data.astype(float))), .98*32767+1)

    def test_checksum_and_source_mismatch_fail_before_output(self):
        metadata = json.loads(self.manifest.read_text())
        segment = self.manifest.parent/metadata['Files'][0]['file']
        original = segment.read_bytes(); damaged = bytearray(original); damaged[-1] ^= 1
        segment.write_bytes(damaged)
        with self.assertRaisesRegex(ValueError, 'checksum'):
            compare(self.pcm, self.manifest, self.root/'Bad', clips=1)
        self.assertFalse((self.root/'Bad').exists())
        segment.write_bytes(original)
        metadata['SourceSHA256'] = '0'*64
        self.manifest.write_text(json.dumps(metadata))
        with self.assertRaisesRegex(ValueError, 'different source'):
            compare(self.pcm, self.manifest, self.root/'Mismatch', clips=1)

    def test_legacy_segments_can_be_compared(self):
        legacy = self.make_manifest('Legacy', legacy=True)
        report = compare(self.pcm, legacy, self.root/'LegacyComparison', clip_seconds=1, clips=1)
        self.assertEqual(report['Summary']['ClipCount'], 1)
        json.dumps(report, allow_nan=False)

    def test_fractional_frame_boundaries_preserve_known_high_tone_phase(self):
        for fps in (60, 90, 89):
            with self.subTest(fps=fps):
                hz, phase = 8000., .3
                data = np.zeros((fps+1, 16, 4), dtype='<u2')
                data[:, 0, 0] = round(np.log(hz/20)/np.log(440)*65534)+1
                data[:, 0, 1] = round((20*np.log10(.2*np.sqrt(2))+100)/100*65534)+1
                data[:, 0, 2] = 32768
                data[:, 0, 3] = np.rint(((np.arange(fps+1)*hz/fps+phase/(2*np.pi)) % 1)*65535).astype('<u2')
                output = synthesize(data, fps)
                reference = .2*np.sin(2*np.pi*hz*np.arange(RATE)/RATE+phase)
                score = measure(np.column_stack((reference, reference)), output)
                self.assertEqual(output.shape, (RATE, 2))
                self.assertGreater(score['WaveformCorrelation'], .99999)
                self.assertGreater(score['RawGain']['WaveformSnrDb'], 60)


if __name__ == '__main__':unittest.main()
