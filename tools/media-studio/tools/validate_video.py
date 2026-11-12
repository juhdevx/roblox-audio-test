"""Validate every hosted RVF1 segment, its checksum, timeline and decoded dimensions."""
import argparse
import hashlib
import json
import math
import re
from pathlib import Path

from convert_video import unpack_segment


def validate_track(manifest_path):
    path=Path(manifest_path).resolve()
    meta=json.loads(path.read_text(encoding='utf-8'))
    name=meta.get('Id','')
    if not re.fullmatch(r'[A-Za-z0-9_]{1,40}',name) or path.name != f'{name}.json':
        raise ValueError('Invalid RVF1 manifest name')
    for field in ('Width','Height','FPS','Frames','SegmentFrames','Segments'):
        if type(meta.get(field)) is not int: raise ValueError(f'{field} must be an integer')
    if meta['Segments'] != math.ceil(meta['Frames']/meta['SegmentFrames']): raise ValueError('Incorrect segment count')
    rows=meta.get('Files')
    if not isinstance(rows,list) or len(rows)!=meta['Segments']: raise ValueError('Missing segment records')
    total_bytes=0
    for index,row in enumerate(rows):
        filename=f'{name}_{index:04d}.rvf'
        if row.get('File') != filename: raise ValueError('Incorrect segment filename')
        data=(path.parent/filename).read_bytes()
        header,frames=unpack_segment(data)
        if (header[5:8] != (meta['Width'],meta['Height'],meta['FPS'])
                or header[9] != index*meta['SegmentFrames'] or header[10] != meta['Frames']
                or header[11] != meta['SegmentFrames'] or header[14] != 4
                or header[8] != min(meta['SegmentFrames'],meta['Frames']-header[9])):
            raise ValueError(f'Timeline mismatch: {filename}')
        if (row.get('Bytes') != len(data) or row.get('Checksum') != header[4]
                or row.get('FirstFrame') != header[9] or row.get('Frames') != header[8]
                or row.get('SHA256') != hashlib.sha256(data).hexdigest()):
            raise ValueError(f'Integrity mismatch: {filename}')
        if len(frames) != header[8] or any(frame.shape != (meta['Height'],meta['Width'],3) for frame in frames):
            raise ValueError('Incorrect decoded frame dimensions')
        total_bytes+=len(data)
    if total_bytes!=meta.get('Bytes'): raise ValueError('Manifest byte total mismatch')
    if set(file.name for file in path.parent.glob('*.rvf')) != {row['File'] for row in rows}:
        raise ValueError('Upload directory contains stale or unexpected RVF files')
    return {'Name':name,'Segments':meta['Segments'],'Frames':meta['Frames'],'Width':meta['Width'],
            'Height':meta['Height'],'FPS':meta['FPS'],'Duration':meta['Duration'],'Bytes':total_bytes,
            'BytesPerSecond':total_bytes/meta['Duration'],'AllChecksumsPassed':True,'AllFramesDecoded':True}


def main():
    parser=argparse.ArgumentParser(description=__doc__); parser.add_argument('manifest',type=Path)
    args=parser.parse_args(); print(json.dumps(validate_track(args.manifest),indent=2))


if __name__=='__main__': main()
