"""Check optional phase/pan fitting without changing the stable converter default."""
import contextlib
import io
import tempfile
from pathlib import Path
import unittest

import numpy as np
import convert_song
from phase_pan_fit import refine_amplitudes


def fixture():
    rate, fps = 24000, 60
    data = np.zeros((fps, 16, 4), dtype='<u2')
    hz, pan, phase, amplitude = 440., -.3, .4, .2
    data[:, 0, 0] = round(np.log(hz/20)/np.log(440)*65534)+1
    data[:, 0, 1] = round((20*np.log10(amplitude*.5)+100)/100*65534)+1
    data[:, 0, 2] = round((pan+1)*32767.5)
    data[:, 0, 3] = np.rint(((phase/(2*np.pi)+np.arange(fps)*hz/fps) % 1)*65535).astype('<u2')
    wave = amplitude*np.sin(2*np.pi*hz*np.arange(rate)/rate+phase)
    angle = (pan+1)*np.pi/4
    return wave[:, None]*np.array([[np.cos(angle), np.sin(angle)]]), data


def decode_gain(data):
    encoded = data[:, :, 1].astype(float)
    return np.where(encoded > 0, 10**(((encoded-1)/65534*100-100)/20), 0)


class PhasePanFitTests(unittest.TestCase):
    def fit(self, samples, data, **options):
        with contextlib.redirect_stdout(io.StringIO()):
            return refine_amplitudes(samples, 24000, 60, data, **options)

    def test_known_gain_recovery_and_no_input_mutation(self):
        samples, data = fixture(); original = data.copy()
        result = self.fit(samples, data)
        self.assertLess(abs(decode_gain(result)[30, 0]-.2), .005)
        np.testing.assert_array_equal(data, original)
        np.testing.assert_array_equal(result[:, :, [0, 2, 3]], data[:, :, [0, 2, 3]])

    def test_quiet_slots_are_untouched(self):
        samples, data = fixture(); data[:, 1, 0] = 1234; data[:, 1, 1] = 1
        result = self.fit(samples, data)
        np.testing.assert_array_equal(result[:, 1:], data[:, 1:])

    def test_duplicate_frequencies_remain_bounded(self):
        samples, data = fixture(); data[:, 1] = data[:, 0]
        result = self.fit(samples*20, data)
        self.assertTrue(np.all(decode_gain(result) <= decode_gain(data)*3.001+.000501))
        self.assertTrue(np.all(np.isfinite(result)))

    def test_quantized_local_objective_does_not_increase(self):
        samples, data = fixture(); result = self.fit(samples, data)
        # The known isolated tone has a convex quadratic in amplitude.
        before = abs(decode_gain(data)[30, 0]-.2)
        after = abs(decode_gain(result)[30, 0]-.2)
        self.assertLess(after, before)

    def test_invalid_or_nonfinite_input_is_rejected(self):
        samples, data = fixture()
        for rate, fps, size, ridge in [(48000, 60, 2048, .01), (24000, 1, 2048, .01),
                (24000, 60, 129, .01), (24000, 60, 2048, 0)]:
            with self.subTest(settings=(rate, fps, size, ridge)):
                with self.assertRaises(ValueError):
                    refine_amplitudes(samples, rate, fps, data, size, ridge)
        with self.assertRaises(ValueError):self.fit(samples, data[:-1])
        samples[0, 0] = np.nan
        with self.assertRaises(ValueError):self.fit(samples, data)

    def test_manifest_marks_experiment_and_preserves_default_and_legacy(self):
        samples, _ = fixture(); samples = samples[:4800]
        scratch = Path(__file__).resolve().parent/'_test_scratch'
        scratch.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='phase-pan-fit-', dir=scratch) as temporary:
            root = Path(temporary)
            with contextlib.redirect_stdout(io.StringIO()):
                stable = convert_song.serialize_track(samples, 24000, 20, 16, 1, 'Stable', root/'stable')
                optional = convert_song.serialize_track(samples, 24000, 20, 16, 1, 'Optional', root/'optional', analysis='phase-pan-fit')
                legacy_a = convert_song.serialize_track(samples, 24000, 20, 16, 1, 'Legacy', root/'legacyA', legacy=True, analysis='peaks')
                legacy_b = convert_song.serialize_track(samples, 24000, 20, 16, 1, 'Legacy', root/'legacyB', legacy=True, analysis='phase-pan-fit')
            self.assertEqual(stable['Analysis'], 'source-fit-v1')
            self.assertNotIn('Experimental', stable)
            self.assertEqual(optional['Analysis'], 'phase-pan-fit-v1')
            self.assertTrue(optional['Experimental'])
            self.assertEqual(legacy_a, legacy_b)
            self.assertEqual((root/'legacyA/Legacy_000.spc').read_bytes(), (root/'legacyB/Legacy_000.spc').read_bytes())


if __name__ == '__main__':unittest.main()
