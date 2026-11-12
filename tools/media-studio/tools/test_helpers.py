"""Check audio timeline repair and source-size caps without browsers or external services."""
import json
from pathlib import Path
import struct
import tempfile
import unittest

from add_video import align_audio_timeline, choose_video_width

TEST_ROOT = Path(__file__).resolve().parents[3] / 'work/video_helper_tests'
TEST_ROOT.mkdir(parents=True, exist_ok=True)


class ImportHelpersTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='alignment-', dir=TEST_ROOT)
        self.root = Path(self.temporary.name)
        if not self.root.resolve().is_relative_to(TEST_ROOT.resolve()):
            raise ValueError('Test workspace escaped its scratch folder')
        self.addCleanup(self.temporary.cleanup)

    def pcm(self, frames):
        path = self.root / 'source.pcm'
        original = b''.join(struct.pack('<ff', index + .25, -index - .5) for index in range(frames))
        path.write_bytes(original)
        Path(str(path) + '.json').write_text(json.dumps({'sampleRate': 24000, 'channels': 2,
            'frames': frames, 'duration': frames / 24000, 'SourceTag': 'preserve'}), encoding='utf-8')
        return path, original

    def test_padding_preserves_audio_and_adds_only_silence(self):
        path, original = self.pcm(2)
        report = align_audio_timeline(path, 5 / 24000)
        self.assertEqual(path.read_bytes(), original + bytes(3 * 8))
        self.assertEqual((report['OriginalFrames'], report['Frames'], report['AddedFrames'], report['TrimmedFrames']), (2, 5, 3, 0))
        metadata = json.loads(Path(str(path) + '.json').read_text())
        self.assertEqual(metadata['frames'], 5)
        self.assertEqual(metadata['duration'], 5 / 24000)
        self.assertEqual(metadata['SourceTag'], 'preserve')

    def test_trimming_preserves_complete_leading_stereo_samples(self):
        path, original = self.pcm(5)
        report = align_audio_timeline(path, 2 / 24000)
        self.assertEqual(path.read_bytes(), original[:2 * 8])
        self.assertEqual((report['AddedFrames'], report['TrimmedFrames']), (0, 3))
        self.assertEqual(json.loads(Path(str(path) + '.json').read_text())['frames'], 2)

    def test_already_aligned_pcm_is_not_rewritten(self):
        path, original = self.pcm(3)
        before = path.stat().st_mtime_ns
        report = align_audio_timeline(path, 3 / 24000)
        self.assertEqual(path.read_bytes(), original)
        self.assertEqual(path.stat().st_mtime_ns, before)
        self.assertFalse(report['Changed'])

    def test_partial_final_sample_rounds_up_to_cover_the_video(self):
        path, original = self.pcm(2)
        report = align_audio_timeline(path, 3.1 / 24000)
        self.assertEqual(report['Frames'], 4)
        self.assertEqual(path.read_bytes(), original + bytes(2 * 8))
        self.assertGreaterEqual(report['AudioDuration'], report['VideoDuration'])
        self.assertLess(report['AudioDuration'] - report['VideoDuration'], 1 / 24000)

    def test_invalid_duration_does_not_modify_audio(self):
        path, original = self.pcm(2)
        for duration in (0, -1, float('nan'), float('inf'), 3601, True, '2'):
            with self.subTest(duration=duration), self.assertRaises(ValueError):
                align_audio_timeline(path, duration)
            self.assertEqual(path.read_bytes(), original)

    def test_incompatible_or_truncated_pcm_is_rejected_before_editing(self):
        path, original = self.pcm(2)
        metadata_path = Path(str(path) + '.json')
        metadata_path.write_text(json.dumps({'sampleRate': 48000, 'channels': 2}))
        with self.assertRaises(ValueError): align_audio_timeline(path, 1)
        self.assertEqual(path.read_bytes(), original)
        metadata_path.write_text(json.dumps({'sampleRate': 24000, 'channels': 1}))
        with self.assertRaises(ValueError): align_audio_timeline(path, 1)
        self.assertEqual(path.read_bytes(), original)
        metadata_path.write_text(json.dumps({'sampleRate': 24000, 'channels': 2}))
        path.write_bytes(original + b'x')
        with self.assertRaises(ValueError): align_audio_timeline(path, 1)
        self.assertEqual(path.read_bytes(), original + b'x')

    def test_default_and_explicit_larger_profiles_cannot_upscale_a_small_source(self):
        metadata = {'sourceWidth': 256, 'sourceHeight': 144, 'width': 256}
        self.assertEqual(choose_video_width(metadata, None, 512, 147456), 256)
        self.assertEqual(choose_video_width(metadata, 512, 512, 147456), 256)
        self.assertEqual(choose_video_width(metadata, 128, 512, 147456), 128)

    def test_large_sources_still_obey_capture_and_codec_pixel_budgets(self):
        landscape = {'sourceWidth': 1920, 'sourceHeight': 1080, 'width': 384}
        self.assertEqual(choose_video_width(landscape, None, 512, 147456), 384)
        self.assertEqual(choose_video_width(landscape, 512, 512, 147456), 384)
        portrait = {'sourceWidth': 1080, 'sourceHeight': 1920, 'width': 384}
        self.assertEqual(choose_video_width(portrait, None, 512, 147456), 288)


if __name__ == '__main__': unittest.main(verbosity=2)
