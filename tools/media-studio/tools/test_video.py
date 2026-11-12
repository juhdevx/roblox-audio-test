"""Exercise video bundle integrity and importer guardrails without network access."""
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib

import numpy as np

import add_video
from convert_video import encode, unpack_segment
from validate_video import validate_track


class VideoTests(unittest.TestCase):
    def test_complete_bundle_and_corruption(self):
        with tempfile.TemporaryDirectory(dir=Path.cwd()) as temporary:
            root=Path(temporary)
            source=np.zeros((20,18,32,3),dtype=np.uint8)
            y,x=np.indices((18,32))
            for frame in range(20):
                source[frame,:,:,0]=(x*8+frame*7)%256
                source[frame,:,:,1]=(y*14+frame*11)%256
                source[frame,:,:,2]=((x+y)*5+frame*3)%256
            rgb=root/'source.rgb'; source.tofile(rgb)
            Path(str(rgb)+'.json').write_text(json.dumps({'width':32,'height':18,'sourceWidth':320,
                'sourceHeight':180,'duration':2.,'fps':10,'frames':20}))
            manifest=encode(rgb,root/'Fixture/upload','Fixture',32,10)
            report=validate_track(root/'Fixture/upload/Fixture.json')
            self.assertTrue(report['AllFramesDecoded']); self.assertEqual(report['Frames'],20)
            path=root/'Fixture/upload/Fixture_0000.rvf'; original=path.read_bytes()
            _,decoded=unpack_segment(original); self.assertEqual(len(decoded),20)
            damaged=bytearray(original); damaged[-1]^=1
            with self.assertRaisesRegex(ValueError,'checksum'): unpack_segment(damaged)
            damaged=bytearray(original); damaged[44]=1; damaged[12:16]=b'\0'*4
            struct.pack_into('<I',damaged,12,zlib.adler32(damaged))
            with self.assertRaisesRegex(ValueError,'dimensions'): unpack_segment(damaged)
            path.write_bytes(damaged)
            with self.assertRaises(ValueError): validate_track(root/'Fixture/upload/Fixture.json')
            path.write_bytes(original)
            extra=path.with_name('Fixture_9999.rvf'); extra.write_bytes(original)
            with self.assertRaisesRegex(ValueError,'stale'): validate_track(root/'Fixture/upload/Fixture.json')
            self.assertLess(manifest['PeakSegmentBytes'],128*1024)

    def test_repository_folder_guards(self):
        self.assertEqual(add_video.safe_folder('media/new_video/v1'),'media/new_video/v1')
        for value in ('../x','media/../x','https://evil.test/x','/absolute','a//b','a/b/'):
            with self.assertRaises(Exception): add_video.safe_folder(value)

    def test_collision_preserves_existing_bundle(self):
        with tempfile.TemporaryDirectory(dir=Path.cwd()) as temporary:
            root=Path(temporary); original=root/'Fixture'; original.mkdir()
            proof=original/'keep.txt'; proof.write_text('keep')
            source=root/'input.mp4'; source.write_bytes(b'not decoded because name collides')
            result=subprocess.run([sys.executable,str(Path(add_video.__file__)),str(source),
                '--name','Fixture','--output-root',str(root)],capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0)
            self.assertIn('already exists',result.stderr)
            self.assertEqual(proof.read_text(),'keep')


if __name__=='__main__': unittest.main()
