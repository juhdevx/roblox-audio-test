"""Safety and packaging regression tests for the local media workbench."""
import hashlib
from http.server import ThreadingHTTPServer
import importlib.util
import json
from pathlib import Path
import tempfile
import threading
import time
import unittest
from unittest import mock
import urllib.error
import urllib.request
import zipfile

TEST_ROOT = Path(__file__).resolve().parents[3] / 'work/media_workbench_tests'
TEST_ROOT.mkdir(parents=True, exist_ok=True)
tempfile.tempdir = str(TEST_ROOT)

SPEC = importlib.util.spec_from_file_location('media_workbench', Path(__file__).with_name('media_workbench.py'))
wb = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(wb)


class WorkbenchTests(unittest.TestCase):
    def test_subprocess_failure_surfaces_actual_decoder_reason(self):
        lines = ['command', 'Error: Chromium cannot decode this video', '    at main (decoder.cjs:2:1)',
                 "Conversion failed: Command '['node', 'decode']' returned non-zero exit status 1."]
        self.assertEqual(wb.conversion_failure(lines), 'Conversion stopped: Chromium cannot decode this video')
        self.assertIn('large-file reading limit', wb.conversion_failure([
            'Error: Cannot create a string longer than 0x1fffffe8 characters']))
        self.assertIn('disk space', wb.conversion_failure(['Conversion failed: Insufficient disk space: 12 GiB required']))
        self.assertIn('Check the log', wb.conversion_failure(['unstructured output']))

    def test_failed_child_process_keeps_decoder_stderr_in_error_and_log(self):
        import sys
        app = object.__new__(wb.Workbench)
        app.lock = threading.RLock()
        job = {'Log': [], 'Progress': 0, 'CancelEvent': threading.Event()}
        with self.assertRaisesRegex(ValueError, 'Chromium cannot decode this video'):
            app.run(job, [sys.executable, '-c',
                'import sys; print("Error: Chromium cannot decode this video", file=sys.stderr); sys.exit(3)'])
        self.assertIn('Error: Chromium cannot decode this video', job['Log'])
        self.assertNotIn('Process', job)

    def options(self, name='Clip'):
        return wb.normalize_options({'Name': name})

    def fixture(self, root, name='Clip', video=True):
        root = Path(root)
        audio_dir = root / ('audio/upload' if video else 'upload')
        audio_dir.mkdir(parents=True)
        payload = b'checked-audio'
        filename = name + '_000.spc'
        (audio_dir / filename).write_bytes(payload)
        audio = {'Name': name, 'Frames': 120, 'FPS': 60, 'Voices': 96, 'SegmentFrames': 120,
                 'Segments': 1, 'Duration': 2, 'Encoding': 3, 'NoiseBands': 12, 'MixGain': 1.2,
                 'Files': [{'file': filename, 'bytes': len(payload), 'frames': 120, 'first': 0}]}
        (audio_dir / (name + '.json')).write_text(json.dumps(audio), encoding='utf-8')
        if video:
            upload = root / 'upload'
            upload.mkdir()
            payload = b'checked-video'
            filename = name + '_0000.rvf'
            (upload / filename).write_bytes(payload)
            meta = {'Id': name, 'Format': 'RVF2', 'Frames': 30, 'FPS': 15, 'Width': 256, 'Height': 144,
                    'SegmentFrames': 30, 'Segments': 1, 'Duration': 2, 'Encoding': 2,
                    'Files': [{'File': filename, 'Bytes': len(payload), 'Frames': 30, 'FirstFrame': 0,
                               'SHA256': hashlib.sha256(payload).hexdigest()}]}
            (upload / (name + '.json')).write_text(json.dumps(meta), encoding='utf-8')
        return root

    def test_names_and_windows_devices(self):
        for value in ('', '../x', 'foo/bar', 'bad name', 'x' * 41, 'CON', 'lpt1', 'NUL', 'COM9'):
            with self.subTest(value=value), self.assertRaises(ValueError):
                wb.safe_name(value)
        self.assertEqual(wb.safe_name('Minha_Midia2'), 'Minha_Midia2')

    def test_upload_names_never_become_paths(self):
        for value in ('../clip.mp4', 'C:\\clip.mp4', 'a/clip.mp4', 'clip?.mp4', 'CON.mp4', 'file.exe', 'clip.mp4 ', 'bad\x00.mp3'):
            with self.subTest(value=value), self.assertRaises(ValueError):
                wb.safe_filename(value)
        self.assertEqual(wb.safe_filename('Minha música.mp3'), 'Minha música.mp3')

    def test_repository_folder_and_revision_guards(self):
        for value in ('../owner/repo', 'https://github.com/a/b', 'a/..', 'a/b/c'):
            with self.subTest(value=value), self.assertRaises(ValueError):
                wb.safe_repository(value)
        for value in ('../x', '/media/x', 'media/../x', 'media//x', 'media/x?token=1', 'media/x/', 'media/x.y'):
            with self.subTest(value=value), self.assertRaises(ValueError):
                wb.safe_folder(value)
        for value in ('branch/name', 'abc', 'A' * 40):
            with self.subTest(value=value), self.assertRaises(ValueError):
                wb.safe_revision(value)
        self.assertEqual(wb.safe_revision('a' * 40), 'a' * 40)
        with self.assertRaisesRegex(ValueError, 'Configure another repository on the server'):
            wb.safe_repository('another/repository')

    def test_options_require_boolean_flags_and_integer_order(self):
        for payload in ({'Name': 'Clip', 'ReplaceExisting': 'true'}, {'Name': 'Clip', 'Order': True},
                        {'Name': 'Clip', 'Profile': 'remote'}, {'Name': 'Clip', 'Order': -1}):
            with self.subTest(payload=payload), self.assertRaises(ValueError):
                wb.normalize_options(payload)
        self.assertEqual(wb.normalize_options({'Name': 'Clip'})['Order'], 0)
        self.assertEqual(wb.normalize_options({'Name': 'Clip', 'Order': 16})['Order'], 16)

    def test_audio_analysis_defaults_and_rejects_unrecognized_modes(self):
        self.assertEqual(self.options()['AudioAnalysis'], 'source-fit')
        for mode in ('source-fit', 'phase-pan-fit', 'peaks'):
            self.assertEqual(wb.normalize_options({'Name': 'Clip', 'AudioAnalysis': mode})['AudioAnalysis'], mode)
        for mode in ('remote', '', None, [], True):
            with self.subTest(mode=mode), self.assertRaises(ValueError):
                wb.normalize_options({'Name': 'Clip', 'AudioAnalysis': mode})

    def test_containment_rejects_parent_and_root(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / 'generated'; root.mkdir()
            for path in (root, root / '../other'):
                with self.assertRaises(ValueError):
                    wb.contained(path, root)
            self.assertEqual(wb.contained(root / 'Clip', root), root / 'Clip')

    def test_atomic_write_keeps_old_file_when_replace_fails(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'MediaDefinitions.luau'
            path.write_text('old', encoding='utf-8')
            with mock.patch.object(wb.os, 'replace', side_effect=OSError('blocked')):
                with self.assertRaises(OSError):
                    wb.atomic_write(path, 'new')
            self.assertEqual(path.read_text(encoding='utf-8'), 'old')
            self.assertEqual(list(path.parent.glob('*.tmp')), [])

    def test_install_refuses_collision_and_keeps_previous_version(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            stage, destination = root / '.stage', root / 'Clip'
            stage.mkdir(); destination.mkdir()
            (stage / 'value').write_text('new'); (destination / 'value').write_text('old')
            with self.assertRaises(ValueError):
                wb.atomic_install(stage, destination, root)
            self.assertEqual((destination / 'value').read_text(), 'old')
            backup = wb.atomic_install(stage, destination, root, True)
            self.assertEqual((destination / 'value').read_text(), 'new')
            self.assertEqual((backup / 'value').read_text(), 'old')

    def test_install_rolls_back_after_failed_rename(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            stage, destination = root / '.stage', root / 'Clip'
            stage.mkdir(); destination.mkdir()
            (stage / 'value').write_text('new'); (destination / 'value').write_text('old')
            actual_replace = wb.os.replace
            def controlled(source, target):
                if Path(source) == stage:
                    raise OSError('simulated installation failure')
                return actual_replace(source, target)
            with mock.patch.object(wb.os, 'replace', side_effect=controlled):
                with self.assertRaises(OSError):
                    wb.atomic_install(stage, destination, root, True)
            self.assertEqual((destination / 'value').read_text(), 'old')
            self.assertEqual((stage / 'value').read_text(), 'new')

    def test_batches_obey_file_and_byte_caps(self):
        files = [{'Name': str(index), 'Bytes': 1024 * 1024} for index in range(41)]
        batches = wb.split_batches(files)
        self.assertEqual([len(batch) for batch in batches], [18, 18, 5])
        self.assertTrue(all(len(batch) <= 20 and sum(item['Bytes'] for item in batch) <= 18 * 1024 * 1024 for batch in batches))
        self.assertEqual([len(batch) for batch in wb.split_batches([{'Bytes': 1}] * 41)], [20, 20, 1])
        with self.assertRaises(ValueError):
            wb.split_batches([{'Bytes': 18 * 1024 * 1024 + 1}])

    def test_metadata_rejects_extra_files_and_tampered_hash(self):
        with tempfile.TemporaryDirectory() as temporary:
            bundle = self.fixture(temporary)
            path = bundle / 'upload/Clip_0000.rvf'
            wb.metadata_files(path.parent, 'Clip', 'video')
            path.write_bytes(b'x' * len(path.read_bytes()))
            with self.assertRaises(ValueError):
                wb.metadata_files(path.parent, 'Clip', 'video')
            (bundle / 'audio/upload/notes.txt').write_text('do not upload')
            with self.assertRaises(ValueError):
                wb.metadata_files(bundle / 'audio/upload', 'Clip', 'audio')

    def test_metadata_rejects_manifest_path_traversal(self):
        with tempfile.TemporaryDirectory() as temporary:
            bundle = self.fixture(temporary)
            path = bundle / 'upload/Clip.json'
            data = json.loads(path.read_text()); data['Files'][0]['File'] = '../outside.rvf'
            path.write_text(json.dumps(data))
            with self.assertRaises(ValueError):
                wb.metadata_files(path.parent, 'Clip', 'video')

    def test_definition_keeps_urls_out_of_public_module(self):
        with tempfile.TemporaryDirectory() as temporary:
            bundle = self.fixture(temporary)
            audio, _ = wb.metadata_files(bundle / 'audio/upload', 'Clip', 'audio')
            video, _ = wb.metadata_files(bundle / 'upload', 'Clip', 'video')
            private, public = wb.definition_sources('Clip', audio, video, self.options())
            self.assertIn('raw.githubusercontent.com', private)
            self.assertNotIn('raw.githubusercontent.com', public)
            self.assertNotIn('BaseUrl', public)
            self.assertIn('ReplaceExisting = false', public)
            self.assertIn('Encoding = 2', private)
            self.assertIn('DisableEmoteCamera = true', public)

    def test_installer_replacements_do_not_rewrite_inserted_source(self):
        options = self.options('NAME')
        private, public = wb.definition_sources('NAME', {'Frames': 1, 'FPS': 60}, None, options)
        expected = wb.definition_records('NAME', {'Frames': 1, 'FPS': 60}, None, options)[0]['Entries']['NAME']
        installer = wb.studio_import('NAME', private, public, expected=expected)
        self.assertIn(private, installer)
        self.assertIn(public, installer)
        self.assertIn('not RunService:IsRunning()', installer)
        self.assertIn('Registry.ResolveName(name)', installer)
        self.assertIn('MediaLibraryBackups', installer)
        self.assertIn('Update the system: Shared > Utils > MediaLibrary is missing', installer)
        self.assertLess(installer.index('checkTrack("audio", expected.Audio, AudioFormat)'), installer.index('local created:'))
        self.assertIn('HttpService.HttpEnabled', installer)
        self.assertIn('track.Segments - 1', installer)
        self.assertIn('header.FirstFrame == first', installer)
        self.assertIn('Upload all batches before importing', installer)
        self.assertIn('["end"]', wb.lua_value({'end': 1}))

    def test_bundle_contains_ready_sources_and_exact_upload_groups(self):
        with tempfile.TemporaryDirectory() as temporary:
            bundle = self.fixture(temporary)
            called = []
            report = wb.prepare_bundle(bundle, 'Clip', self.options(), validate=lambda kind, path: called.append(kind))
            self.assertEqual(called, ['audio', 'video'])
            self.assertEqual(len(report['UploadBatches']), 2)
            for batch in report['UploadBatches']:
                self.assertLessEqual(len(batch['Files']), 20)
                self.assertLessEqual(batch['Bytes'], 18 * 1024 * 1024)
                for row in batch['Files']:
                    self.assertEqual(wb.file_sha256(bundle / batch['Folder'] / row['Name']), row['SHA256'])
            with zipfile.ZipFile(bundle / 'StudioMediaPackage.zip') as zipped:
                names = zipped.namelist()
                self.assertIn('StudioImport.luau', names)
                self.assertIn('MediaDefinitions.luau', names)
                self.assertTrue(any(name.startswith('UploadBatches/video/') for name in names))
                self.assertFalse(any(name.endswith('.mp4') or name.endswith('.pcm') for name in names))

    def test_audio_only_bundle_uses_same_single_definition(self):
        with tempfile.TemporaryDirectory() as temporary:
            bundle = self.fixture(temporary, video=False)
            report = wb.prepare_bundle(bundle, 'Clip', self.options())
            self.assertIsNone(report['Video'])
            self.assertEqual([batch['Kind'] for batch in report['UploadBatches']], ['audio'])
            self.assertNotIn('Video =', (bundle / 'MediaDefinitions.luau').read_text())

    def test_adapter_adds_new_codec_flags_only_when_supported(self):
        app = object.__new__(wb.Workbench); app.tools = Path('tools')
        with mock.patch.object(wb.subprocess, 'run', return_value=mock.Mock(stdout='--codec rvf2 --audio-voices')):
            command = app.video_command(Path('source.mp4'), 'Clip', self.options(), Path('stage'), wb.PROFILES['detalhado'])
        self.assertEqual(command[-4:], ['--codec', 'rvf2', '--audio-voices', 128])
        with mock.patch.object(wb.subprocess, 'run', return_value=mock.Mock(stdout='--width --fps')):
            command = app.video_command(Path('source.mp4'), 'Clip', self.options(), Path('stage'), wb.PROFILES['leve'])
        self.assertNotIn('--codec', command)
        self.assertNotIn('--audio-voices', command)

    def test_video_adapter_passes_analysis_and_comparison_without_silent_fallback(self):
        app = object.__new__(wb.Workbench); app.tools = Path('tools')
        options = wb.normalize_options({'Name': 'Clip', 'AudioAnalysis': 'phase-pan-fit'})
        with mock.patch.object(wb.subprocess, 'run', return_value=mock.Mock(stdout='--codec --audio-voices --analysis --comparison')):
            command = app.video_command(Path('source.mp4'), 'Clip', options, Path('stage'), wb.PROFILES['leve'])
        self.assertEqual(command[-3:], ['--analysis', 'phase-pan-fit', '--comparison'])
        with mock.patch.object(wb.subprocess, 'run', return_value=mock.Mock(stdout='--codec --audio-voices')):
            with self.assertRaisesRegex(ValueError, 'Update the video converter'):
                app.video_command(Path('source.mp4'), 'Clip', options, Path('stage'), wb.PROFILES['leve'])

    def comparison_fixture(self, bundle):
        root = Path(bundle) / 'Comparison'; root.mkdir()
        (root / 'original.wav').write_bytes(b'RIFForiginal-wave')
        (root / 'rendered.wav').write_bytes(b'RIFFrendered-wave')
        report = {'SchemaVersion': 1, 'Preview': {'Files': {'Original': 'original.wav', 'Rendered': 'rendered.wav'}}}
        (root / 'report.json').write_text(json.dumps(report), encoding='utf-8')
        return root

    def test_comparison_is_packaged_for_local_review_and_never_uploaded(self):
        with tempfile.TemporaryDirectory() as temporary:
            bundle = self.fixture(temporary, video=False)
            self.comparison_fixture(bundle)
            report = wb.prepare_bundle(bundle, 'Clip', self.options())
            uploaded = [row['Name'] for batch in report['UploadBatches'] for row in batch['Files']]
            self.assertFalse(any(name.endswith('.wav') for name in uploaded))
            with zipfile.ZipFile(bundle / 'StudioMediaPackage.zip') as zipped:
                names = zipped.namelist()
                self.assertIn('Comparison/original.wav', names)
                self.assertIn('Comparison/rendered.wav', names)
                self.assertIn('Comparison/report.json', names)
                self.assertFalse(any(name.endswith('.pcm') for name in names))
            (bundle / 'Comparison/source.pcm').write_bytes(b'not-for-review')
            with self.assertRaisesRegex(ValueError, 'unexpected files'):
                wb.prepare_bundle(bundle, 'Clip', self.options())

    def test_comparison_paths_are_allowlisted_and_bounded(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = wb.Workbench(Path(temporary))
            bundle = self.fixture(app.generated / 'Clip', video=False)
            comparison = self.comparison_fixture(bundle)
            job = {'Id': 'a' * 32, 'Bundle': str(bundle), 'Options': self.options()}
            visible = app.comparison(job)
            self.assertIn('/comparison/' + 'a' * 32, visible['Files']['Original'])
            self.assertIn('Offline', visible['Scope'])
            for filename in ('../StudioImport.luau', 'source.pcm', 'arbitrary.wav'):
                with self.assertRaises(ValueError):
                    app.comparison_file(job, filename)
            with (comparison / 'rendered.wav').open('wb') as target:
                target.truncate(wb.MAX_COMPARISON_BYTES + 1)
            self.assertIsNone(app.comparison(job))
            with self.assertRaises(ValueError):
                app.comparison_file(job, 'rendered.wav')

    def test_comparison_command_uses_short_bounded_excerpts(self):
        app = object.__new__(wb.Workbench); app.tools = Path('tools')
        app.log = mock.Mock(); app.run = mock.Mock()
        app.compare_audio({}, Path('source.pcm'), Path('Clip.json'), Path('bundle'))
        command = app.run.call_args.args[1]
        self.assertEqual(command[-6:], ['--output', Path('bundle/Comparison'), '--clip-seconds', 3, '--clips', 3])

    def saved_bundle(self, app, name='Clip'):
        bundle = self.fixture(app.generated / name, name=name)
        options = wb.normalize_options({'Name': name, 'Order': 16, 'Default': True, 'Exclusive': False,
            'ReplaceExisting': True, 'Revision': 'a' * 40, 'Folder': 'media/clip/v3'})
        wb.prepare_bundle(bundle, name, options, 'b' * 64)
        return bundle, options

    def wait_job(self, app, identity):
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            job = app.jobs[identity]
            if job['State'] in ('Ready', 'Failed'):
                self.assertEqual(job['State'], 'Ready', job.get('Error'))
                return job
            time.sleep(0.01)
        self.fail('The local rebuild did not complete')

    def test_reuse_and_finalize_preserve_saved_rules_hash_and_job_snapshot(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = wb.Workbench(Path(temporary))
            bundle, original = self.saved_bundle(app)
            app.validate = lambda *_args: None
            reused = app.reuse('Clip')
            first_job = self.wait_job(app, reused['Id'])
            first = json.loads((bundle / 'WorkbenchManifest.json').read_text())
            self.assertEqual(first['Options'], original)
            self.assertEqual(first['OriginalFileSHA256'], 'b' * 64)
            finalized = app.finalize(first_job['Id'], 'c' * 40)
            second_job = self.wait_job(app, finalized['Id'])
            second = json.loads((bundle / 'WorkbenchManifest.json').read_text())
            self.assertEqual(second['Revision'], 'c' * 40)
            self.assertEqual(second['OriginalFileSHA256'], 'b' * 64)
            self.assertEqual(second['Options']['Order'], 16)
            self.assertTrue(second['Options']['Default'])
            self.assertFalse(second['Options']['Exclusive'])
            self.assertNotEqual(first_job['Bundle'], second_job['Bundle'])
            preserved = json.loads((Path(first_job['Bundle']) / 'WorkbenchManifest.json').read_text())
            self.assertEqual(preserved['Revision'], 'a' * 40)

    def test_reuse_rejects_mismatched_saved_options_and_invalid_provenance(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = wb.Workbench(Path(temporary))
            bundle, _ = self.saved_bundle(app)
            manifest_path = bundle / 'WorkbenchManifest.json'
            original = json.loads(manifest_path.read_text())
            for field, value in (('Name', 'AnotherClip'), ('Revision', 'main'), ('OriginalFileSHA256', 'invalid hash')):
                altered = dict(original); altered[field] = value
                manifest_path.write_text(json.dumps(altered))
                with self.subTest(field=field), self.assertRaises(ValueError):
                    app.reuse('Clip')
            altered = json.loads(json.dumps(original)); altered['Options']['Name'] = 'Other'
            manifest_path.write_text(json.dumps(altered))
            with self.assertRaises(ValueError):
                app.reuse('Clip')
            self.assertEqual(app.jobs, {})

    def test_legacy_saved_options_get_standard_analysis_without_changing_rules(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = wb.Workbench(Path(temporary))
            bundle, original = self.saved_bundle(app)
            manifest_path = bundle / 'WorkbenchManifest.json'
            data = json.loads(manifest_path.read_text())
            del data['Options']['AudioAnalysis']
            manifest_path.write_text(json.dumps(data))
            snapshot = app.previous_snapshot('Clip')
            self.assertEqual(snapshot['Options'], original)

    def test_experimental_mode_and_comparison_survive_rebuild_and_pin(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = wb.Workbench(Path(temporary)); app.validate = lambda *_args: None
            bundle, options = self.saved_bundle(app)
            options['AudioAnalysis'] = 'phase-pan-fit'
            self.comparison_fixture(bundle)
            wb.prepare_bundle(bundle, 'Clip', options, 'b' * 64)
            first = self.wait_job(app, app.reuse('Clip')['Id'])
            final = self.wait_job(app, app.finalize(first['Id'], 'd' * 40)['Id'])
            saved = json.loads((bundle / 'WorkbenchManifest.json').read_text())
            self.assertEqual(saved['Options']['AudioAnalysis'], 'phase-pan-fit')
            self.assertEqual(saved['Revision'], 'd' * 40)
            self.assertEqual(saved['OriginalFileSHA256'], 'b' * 64)
            self.assertTrue(app.comparison(final)['Experimental'])
            self.assertEqual((bundle / 'Comparison/original.wav').read_bytes(), b'RIFForiginal-wave')

    def test_local_http_requires_session_origin_and_safe_upload_path(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = wb.Workbench(Path(temporary))
            server = ThreadingHTTPServer(('127.0.0.1', 0), wb.Handler); server.app = app
            thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
            base = 'http://127.0.0.1:' + str(server.server_address[1])
            try:
                with urllib.request.urlopen(base + '/') as response:
                    self.assertIn(b'Media Studio', response.read())
                with self.assertRaises(urllib.error.HTTPError) as rejected:
                    urllib.request.urlopen(base + '/api/state')
                self.assertEqual(rejected.exception.code, 403)
                headers = {'X-Media-Token': app.token, 'Origin': base}
                request = urllib.request.Request(base + '/api/upload?name=clip.mp3', data=b'local-only', headers=headers)
                with urllib.request.urlopen(request) as response:
                    upload = json.load(response)
                self.assertEqual(upload['SHA256'], hashlib.sha256(b'local-only').hexdigest())
                stored = app.uploads[upload['Id']]
                self.assertTrue(Path(stored['Path']).resolve().is_relative_to(app.imports.resolve()))
                request = urllib.request.Request(base + '/api/upload?name=../clip.mp3', data=b'no', headers=headers)
                with self.assertRaises(urllib.error.HTTPError) as rejected:
                    urllib.request.urlopen(request)
                self.assertEqual(rejected.exception.code, 400)
                request = urllib.request.Request(base + '/api/state', headers={'X-Media-Token': app.token, 'Origin': 'https://evil.example'})
                with self.assertRaises(urllib.error.HTTPError) as rejected:
                    urllib.request.urlopen(request)
                self.assertEqual(rejected.exception.code, 403)
                request = urllib.request.Request(base + '/api/state', headers={'X-Media-Token': app.token, 'Host': 'evil.example'})
                with self.assertRaises(urllib.error.HTTPError) as rejected:
                    urllib.request.urlopen(request)
                self.assertEqual(rejected.exception.code, 403)
                bundle, saved = self.saved_bundle(app)
                app.validate = lambda *_args: None
                payload = {'Name': 'Clip', 'Order': 0, 'Exclusive': True, 'Default': False, 'Revision': 'main'}
                request = urllib.request.Request(base + '/api/existing', data=json.dumps(payload).encode('utf-8'),
                    headers={'X-Media-Token': app.token, 'Origin': base, 'Content-Type': 'application/json'})
                with urllib.request.urlopen(request) as response:
                    reused = json.load(response)
                self.wait_job(app, reused['Id'])
                rebuilt = json.loads((bundle / 'WorkbenchManifest.json').read_text())
                self.assertEqual(rebuilt['Options'], saved)
                self.assertEqual(rebuilt['OriginalFileSHA256'], 'b' * 64)
                comparison = self.comparison_fixture(bundle)
                job = app.jobs[reused['Id']]
                original = comparison / 'original.wav'
                clip_url = base + app.comparison(job)['Files']['Original']
                with urllib.request.urlopen(clip_url) as response:
                    self.assertEqual(response.read(), original.read_bytes())
                    self.assertIn('audio/', response.headers['Content-Type'])
                    self.assertNotIn('Content-Disposition', response.headers)
                request = urllib.request.Request(clip_url, headers={'Range': 'bytes=4-7'})
                with urllib.request.urlopen(request) as response:
                    self.assertEqual(response.status, 206)
                    self.assertEqual(response.read(), original.read_bytes()[4:8])
                for route, code in ((f'/comparison/{job["Id"]}/original.wav', 403),
                                    (f'/comparison/{job["Id"]}/source.pcm?token={app.token}', 400),
                                    (f'/comparison/{job["Id"]}/report.json?token=wrong', 403),
                                    (f'/comparison/{job["Id"]}/../WorkbenchManifest.json?token={app.token}', 404)):
                    with self.subTest(route=route), self.assertRaises(urllib.error.HTTPError) as rejected:
                        urllib.request.urlopen(base + route)
                    self.assertEqual(rejected.exception.code, code)
            finally:
                server.shutdown(); server.server_close(); thread.join(timeout=2)


    def test_cancel_before_install_preserves_previous_package_and_rejects_duplicate(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = wb.Workbench(Path(temporary))
            bundle, _ = self.saved_bundle(app)
            original = (bundle / 'WorkbenchManifest.json').read_bytes()
            entered, release = threading.Event(), threading.Event()
            def validate(*_args):
                entered.set()
                if not release.wait(5):
                    raise ValueError('Test validation timed out')
            app.validate = validate
            identity = app.reuse('Clip')['Id']
            try:
                self.assertTrue(entered.wait(3))
                with self.assertRaisesRegex(ValueError, 'already active'):
                    app.reuse('Clip')
                self.assertEqual(app.cancel(identity)['State'], 'Cancelling')
            finally:
                release.set()
            deadline = time.monotonic() + 5
            while app.jobs[identity]['State'] == 'Cancelling' and time.monotonic() < deadline:
                time.sleep(.01)
            self.assertEqual(app.jobs[identity]['State'], 'Cancelled')
            self.assertEqual((bundle / 'WorkbenchManifest.json').read_bytes(), original)
            self.assertNotIn('Bundle', app.jobs[identity])
            self.assertFalse((app.generated / 'backups').exists())

    def test_cancel_queued_job_never_rebuilds_it(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = wb.Workbench(Path(temporary))
            self.saved_bundle(app, 'First')
            second, _ = self.saved_bundle(app, 'Second')
            original = (second / 'WorkbenchManifest.json').read_bytes()
            entered, release = threading.Event(), threading.Event()
            def validate(*_args):
                entered.set()
                if not release.wait(5):
                    raise ValueError('Test validation timed out')
            app.validate = validate
            first = app.reuse('First')['Id']
            try:
                self.assertTrue(entered.wait(3))
                queued = app.reuse('Second')['Id']
                self.assertEqual(app.cancel(queued)['State'], 'Cancelled')
            finally:
                release.set()
            self.wait_job(app, first)
            self.assertEqual(app.jobs[queued]['State'], 'Cancelled')
            self.assertEqual((second / 'WorkbenchManifest.json').read_bytes(), original)

    def test_cancel_stops_a_running_subprocess_without_waiting_for_output(self):
        import sys
        app = object.__new__(wb.Workbench)
        app.lock, app.jobs = threading.RLock(), {}
        job = {'Id': 'c' * 32, 'Name': 'Stop', 'State': 'Running', 'Phase': 'Test', 'Progress': 0,
               'Log': [], 'Started': time.monotonic(), 'Options': self.options(), 'CancelEvent': threading.Event()}
        app.jobs[job['Id']] = job
        result = []
        def run():
            try:
                app.run(job, [sys.executable, '-c', 'import time; time.sleep(60)'])
            except wb.ConversionCancelled:
                result.append('cancelled')
            except Exception as error:
                result.append(str(error))
        worker = threading.Thread(target=run)
        worker.start()
        deadline = time.monotonic() + 5
        while 'Process' not in job and time.monotonic() < deadline:
            time.sleep(.01)
        self.assertIn('Process', job)
        process = job['Process']
        app.cancel(job['Id'])
        worker.join(timeout=5)
        self.assertFalse(worker.is_alive())
        self.assertEqual(result, ['cancelled'])
        self.assertIsNotNone(process.poll())
        self.assertNotIn('Process', job)

    def test_cancel_still_stops_child_that_closes_output_before_exiting(self):
        import sys
        app = object.__new__(wb.Workbench)
        app.lock, app.jobs = threading.RLock(), {}
        job = {'Id': 'd' * 32, 'Name': 'ClosedOutput', 'State': 'Running', 'Phase': 'Test', 'Progress': 0,
               'Log': [], 'Started': time.monotonic(), 'Options': self.options(), 'CancelEvent': threading.Event()}
        app.jobs[job['Id']] = job
        result = []
        def run():
            try:
                app.run(job, [sys.executable, '-c', 'import os,time; os.close(1); os.close(2); time.sleep(15)'])
            except wb.ConversionCancelled:
                result.append('cancelled')
        worker = threading.Thread(target=run)
        worker.start()
        deadline = time.monotonic() + 5
        while 'Process' not in job and time.monotonic() < deadline:
            time.sleep(.01)
        time.sleep(.25)
        self.assertIn('Process', job)
        process = job['Process']
        self.assertIsNone(process.poll())
        app.cancel(job['Id'])
        worker.join(timeout=5)
        self.assertFalse(worker.is_alive())
        self.assertEqual(result, ['cancelled'])
        self.assertIsNotNone(process.poll())

    def test_atomic_install_cannot_be_interrupted_after_commit_starts(self):
        app = object.__new__(wb.Workbench)
        app.lock = threading.RLock()
        job = {'Id': 'f' * 32, 'State': 'Finalizing', 'CancelEvent': threading.Event()}
        app.jobs = {job['Id']: job}
        with self.assertRaisesRegex(ValueError, 'being installed'):
            app.cancel(job['Id'])
        self.assertFalse(job['CancelEvent'].is_set())



if __name__ == '__main__':
    unittest.main(verbosity=2)
