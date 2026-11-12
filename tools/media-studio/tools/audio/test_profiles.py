"""Check named audio profiles, bundle integrity and a known sine without external services."""
import json
import math
from pathlib import Path
import struct
import subprocess
import sys
import tempfile

import numpy as np

from validate_music import validate_track

TOOLS = Path(__file__).resolve().parent


def main():
    checks = 0

    def check(condition, label):
        nonlocal checks
        if not condition:
            raise AssertionError(label)
        checks += 1

    scratch = TOOLS / '_test_scratch'
    scratch.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='spc-profiles-', dir=scratch) as temporary:
        root = Path(temporary)
        if not root.resolve().is_relative_to(scratch.resolve()):
            raise ValueError('Test workspace escaped its scratch folder')
        rate = 24000
        time = np.arange(rate) / rate
        signal = .2 * np.sin(2 * np.pi * 443.7 * time + .17)
        pcm = root / 'Tone.pcm'
        np.column_stack((signal, signal)).astype('<f4').tofile(pcm)
        Path(str(pcm) + '.json').write_text(json.dumps({'sampleRate': rate, 'channels': 2}), encoding='utf-8')
        for label, options, voices, profile in (
            ('Default', [], 128, 'fidelity'),
            ('Balanced', ['--profile', 'balanced'], 96, 'balanced'),
            ('Custom', ['--profile', 'fidelity', '--voices', '64'], 64, 'custom'),
        ):
            output = root / label
            result = subprocess.run([sys.executable, str(TOOLS / 'convert_song.py'), str(pcm),
                '--name', 'Tone', '--output', str(output), *options], text=True, capture_output=True)
            check(result.returncode == 0, f'{label}: conversion succeeds: {result.stderr}')
            manifest = json.loads((output / 'Tone.json').read_text(encoding='utf-8'))
            check(manifest['Voices'] == voices and manifest['AudioProfile'] == profile,
                f'{label}: named profile or explicit override')
            check(manifest['FPS'] == 60 and manifest['PayloadBytesPerSecond'] <= 10 * 8192,
                f'{label}: sustained bytes stay within the configured audio transport')
            validate_track(output / 'Tone.json')
            checks += 1
            blob = (output / 'Tone_000.spc').read_bytes()
            stride = voices * 8 + 48
            row = np.frombuffer(blob, dtype='<u2', offset=48 + 30 * stride,
                count=voices * 4).reshape(voices, 4)
            frequency = np.where(row[:, 0] > 0, 20 * 440 ** ((row[:, 0].astype(float) - 1) / 65534), 0)
            slot = int(np.argmin(np.abs(frequency - 443.7)))
            amplitude = 10 ** (((int(row[slot, 1]) - 1) / 65534 * 100 - 100) / 20)
            phase = row[slot, 3] / 65535
            expected_phase = (443.7 * .5 + .17 / (2 * np.pi)) % 1
            check(abs(frequency[slot] - 443.7) < .2, f'{label}: known tone pitch')
            check(abs(amplitude - math.sqrt(2) * .2) < .015, f'{label}: stereo tone amplitude')
            check(abs((phase - expected_phase + .5) % 1 - .5) < .02, f'{label}: known tone phase')
            check(struct.unpack_from('<H', blob, 16)[0] == voices, f'{label}: encoded header matches profile')
        invalid = subprocess.run([sys.executable, str(TOOLS / 'convert_song.py'), str(pcm),
            '--profile', 'ultra'], capture_output=True)
        check(invalid.returncode != 0, 'unknown profile is rejected')
    print(json.dumps({'Checks': checks, 'Passed': True}))


if __name__ == '__main__':
    main()
