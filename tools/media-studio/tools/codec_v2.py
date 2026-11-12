"""RVF2: bounded full-color RGBA frames with native-compatible Zstd compression."""
import argparse
import ctypes
import ctypes.util
import hashlib
import json
import math
import re
from pathlib import Path
import struct
import time
import zlib
import os
import threading
from collections import deque
from concurrent.futures import ThreadPoolExecutor

import numpy as np
from PIL import Image

MAGIC=0x32465652
HEADER_BYTES=64
MAX_BYTES=4*1024*1024
MAX_SIDE=1024
MAX_PIXELS=1024*576


class Zstd:
    def __init__(self):
        try:
            import zstandard
            self.module=zstandard; self.dll=None
            return
        except ImportError:
            pass
        runtime=Path.home()/'.cache/codex-runtimes/codex-primary-runtime/dependencies/native'
        candidates=[ctypes.util.find_library('zstd'),
            str(runtime/'poppler/Library/bin/zstd.dll'),str(runtime/'poppler/Library/bin/libzstd.dll'),
            str(runtime/'git/mingw64/bin/libzstd.dll')]
        self.module=None; self.dll=None
        for path in candidates:
            if not path: continue
            try: self.dll=ctypes.CDLL(path); break
            except OSError: pass
        if self.dll is None: raise RuntimeError('Zstd not found. Install the Python zstandard package or use the bundled runtime.')
        dll=self.dll
        dll.ZSTD_compressBound.argtypes=[ctypes.c_size_t]; dll.ZSTD_compressBound.restype=ctypes.c_size_t
        dll.ZSTD_compress.argtypes=[ctypes.c_void_p,ctypes.c_size_t,ctypes.c_void_p,ctypes.c_size_t,ctypes.c_int]; dll.ZSTD_compress.restype=ctypes.c_size_t
        dll.ZSTD_decompress.argtypes=[ctypes.c_void_p,ctypes.c_size_t,ctypes.c_void_p,ctypes.c_size_t]; dll.ZSTD_decompress.restype=ctypes.c_size_t
        dll.ZSTD_isError.argtypes=[ctypes.c_size_t]; dll.ZSTD_isError.restype=ctypes.c_uint
        dll.ZSTD_getFrameContentSize.argtypes=[ctypes.c_void_p,ctypes.c_size_t]; dll.ZSTD_getFrameContentSize.restype=ctypes.c_uint64

    def compress(self,data,level=5):
        data=bytes(data)
        if self.module: return self.module.ZstdCompressor(level=level,write_content_size=True).compress(data)
        capacity=self.dll.ZSTD_compressBound(len(data)); result=ctypes.create_string_buffer(capacity)
        size=self.dll.ZSTD_compress(result,capacity,data,len(data),level)
        if self.dll.ZSTD_isError(size): raise ValueError('Zstd compression failed')
        return result.raw[:size]

    def decompress(self,data,expected):
        data=bytes(data)
        if self.module:
            if self.module.frame_content_size(data)!=expected: raise ValueError('Zstd frame size mismatch')
            result=self.module.ZstdDecompressor().decompress(data,max_output_size=expected)
        else:
            if self.dll.ZSTD_getFrameContentSize(data,len(data))!=expected: raise ValueError('Zstd frame size mismatch')
            destination=ctypes.create_string_buffer(expected)
            size=self.dll.ZSTD_decompress(destination,expected,data,len(data))
            if self.dll.ZSTD_isError(size) or size!=expected: raise ValueError('Zstd decompression failed')
            result=destination.raw
        if len(result)!=expected: raise ValueError('Incorrect decompressed size')
        return result


def rgba_frame(rgb,bits=(6,6,6)):
    rgb=np.asarray(rgb,dtype=np.uint8)
    result=np.empty((*rgb.shape[:2],4),dtype=np.uint8)
    for channel,precision in enumerate(bits):
        levels=(1<<precision)-1
        values=rgb[:,:,channel].astype(np.float32)
        result[:,:,channel]=np.rint(np.rint(values*levels/255)*255/levels).astype(np.uint8)
    result[:,:,3]=255
    return result


def yuv420_frame(rgb,bits=(6,5,5)):
    height,width=rgb.shape[:2]
    converted=np.asarray(Image.fromarray(rgb).convert('YCbCr'))
    planes=[]
    for channel,precision in enumerate(bits):
        image=Image.fromarray(converted[:,:,channel])
        if channel: image=image.resize((math.ceil(width/2),math.ceil(height/2)),Image.Resampling.BOX)
        values=np.asarray(image).astype(np.float32); levels=(1<<precision)-1
        planes.append(np.rint(values*levels/255).astype(np.uint8))
    packed=np.concatenate([plane.flatten() for plane in planes])
    return packed,restore_yuv420(packed,width,height,bits)


def restore_yuv420(raw,width,height,bits=(6,5,5)):
    area=width*height; cw=math.ceil(width/2); ch=math.ceil(height/2); ca=cw*ch
    if (len(raw)!=area+2*ca or np.any(raw[:area]>=(1<<bits[0]))
            or np.any(raw[area:area+ca]>=(1<<bits[1])) or np.any(raw[area+ca:]>=(1<<bits[2]))):
        raise ValueError('RVF2 YCbCr code out of range')
    y=raw[:area].reshape(height,width).astype(np.float64)*255/((1<<bits[0])-1)
    cb=raw[area:area+ca].reshape(ch,cw).astype(np.float64)*255/((1<<bits[1])-1)
    cr=raw[area+ca:].reshape(ch,cw).astype(np.float64)*255/((1<<bits[2])-1)
    cb=np.repeat(np.repeat(cb,2,axis=0),2,axis=1)[:height,:width]-128
    cr=np.repeat(np.repeat(cr,2,axis=0),2,axis=1)[:height,:width]-128
    result=np.empty((height,width,4),dtype=np.uint8)
    result[:,:,0]=np.clip(np.floor(y+1.402*cr+.5),0,255).astype(np.uint8)
    green=-.344136*cb-.714136*cr
    result[:,:,1]=np.clip(np.floor(y+green+.5),0,255).astype(np.uint8)
    result[:,:,2]=np.clip(np.floor(y+1.772*cb+.5),0,255).astype(np.uint8)
    result[:,:,3]=255
    return result


def benchmark_yuv(rgb_path,output):
    rgb_path=Path(rgb_path); meta=json.loads(Path(str(rgb_path)+'.json').read_text(encoding='utf-8'))
    source=np.memmap(rgb_path,dtype=np.uint8,mode='r').reshape(-1,meta['height'],meta['width'],3)
    starts=np.linspace(0,max(0,len(source)-meta['fps']*2),12,dtype=int)
    reports=[]; zstd=Zstd()
    for bits in ((7,6,6),(6,6,6),(6,5,5),(5,5,5),(5,4,4)):
        count=0; total_bytes=0; error=0.; modes=[0,0,0]; maximum=0; start_time=time.monotonic()
        for first in starts:
            previous=None; sequence_bytes=0
            for index in range(first,min(len(source),first+meta['fps'])):
                rgb=source[index]; packed,rgba=yuv420_frame(rgb,bits)
                mode,compressed=choose_frame(zstd,packed,previous); previous=packed
                error+=float(((rgba[:,:,:3].astype(np.float32)-rgb.astype(np.float32))**2).mean())
                count+=1; modes[mode]+=1; total_bytes+=len(compressed)+12; sequence_bytes+=len(compressed)+12
            maximum=max(maximum,sequence_bytes)
        report={'Layout':'YUV420','Bits':bits,'Frames':count,'BytesPerSecond':total_bytes/count*meta['fps'],
            'PSNR':10*math.log10(255**2/max(error/count,1e-12)),'Modes':modes,
            'PeakOneSecondBytes':maximum,'Seconds':time.monotonic()-start_time}
        reports.append(report); print(json.dumps(report),flush=True)
    Path(output).write_text(json.dumps({'Source':str(rgb_path),'SourceWidth':meta['width'],
        'SourceHeight':meta['height'],'SourceFPS':meta['fps'],'Reports':reports},indent=2),encoding='utf-8')


def choose_frame(zstd,rgba,previous,level=5):
    raw=rgba.tobytes()
    best=zstd.compress(raw,level); mode=0
    if previous is not None:
        candidates=[(1,np.bitwise_xor(rgba,previous).tobytes())]
        if rgba.nbytes%4==0:
            candidates.append((2,(rgba.view('<u4')-previous.view('<u4')).astype('<u4').tobytes()))
        for candidate,filtered in candidates:
            compressed=zstd.compress(filtered,level)
            # Require a useful size saving before paying for a Luau reconstruction pass.
            if len(compressed)+64<len(best)*.94: mode,best=candidate,compressed
    return mode,best


def restore_frame(zstd,packed,mode,shape,previous,opaque=True):
    raw=zstd.decompress(packed,math.prod(shape))
    decoded=np.frombuffer(raw,dtype=np.uint8).reshape(shape)
    if mode==0: result=decoded.copy()
    elif mode==1 and previous is not None: result=np.bitwise_xor(decoded,previous)
    elif mode==2 and previous is not None: result=(decoded.view('<u4')+previous.view('<u4')).astype('<u4').view(np.uint8).reshape(shape)
    else: raise ValueError('Invalid RVF2 prediction mode')
    if opaque and np.any(result[:,:,3]!=255): raise ValueError('RVF2 alpha must be opaque')
    return result


def raw_frame_bytes(width,height,layout):
    return width*height*4 if layout==0 else width*height+2*math.ceil(width/2)*math.ceil(height/2)


def pack_segment(records,width,height,fps,first,total,segment_frames,duration,bits,layout=1):
    body=b''.join(records); header=bytearray(64)
    struct.pack_into('<IHHIIHHHHIIHHHHfI',header,0,MAGIC,1,64,64+len(body),0,width,height,fps,
        len(records),first,total,segment_frames,0,2,0,duration,raw_frame_bytes(width,height,layout))
    header[48:51]=bytes(bits); header[51]=1 # Standard Zstd compression, no dictionaries.
    header[52]=layout
    data=header+body; struct.pack_into('<I',data,12,zlib.adler32(data))
    if len(data)>MAX_BYTES: raise ValueError(f'RVF2 segment exceeds {MAX_BYTES} bytes')
    return data


def header(data):
    if len(data)<64+12 or len(data)>MAX_BYTES: raise ValueError('RVF2 size limit')
    fields=struct.unpack_from('<IHHIIHHHHIIHHHHfI',data)
    magic,version,header_bytes,size,checksum,width,height,fps,count,first,total,normal,palette,encoding,tile,duration,raw_bytes=fields
    if (magic!=MAGIC or version!=1 or header_bytes!=64 or size!=len(data) or palette!=0 or encoding!=2 or tile!=0
            or not 16<=width<=MAX_SIDE or not 16<=height<=MAX_SIDE or width*height>MAX_PIXELS or not 4<=fps<=30
            or not 1<=count<=normal<=fps*4 or first%normal or first+count>total or total>fps*3600
            or not 0<duration<=3600 or abs(total-math.ceil(duration*fps))>1 or data[52]>1
            or raw_bytes!=raw_frame_bytes(width,height,data[52])
            or not all(3<=value<=8 for value in data[48:51]) or data[51]!=1 or any(data[53:64])
            or (data[52]==1 and sum(data[48:51])>20)):
        raise ValueError('Invalid RVF2 header')
    check=bytearray(data); check[12:16]=b'\0'*4
    if zlib.adler32(check)!=checksum: raise ValueError('RVF2 checksum mismatch')
    return fields


def unpack_segment(data,zstd=None):
    fields=header(data); zstd=zstd or Zstd()
    _,_,_,_,_,width,height,fps,count,first,total,normal,_,_,_,duration,raw_bytes=fields
    position=64; previous=None; result=[]; layout=data[52]; bits=tuple(data[48:51])
    for index in range(count):
        if position+12>len(data): raise ValueError('Truncated RVF2 frame')
        length,raw_size,mode,reserved=struct.unpack_from('<IIB3s',data,position); position+=12
        if (length<6 or position+length>len(data) or raw_size!=raw_bytes or mode>2
                or (index==0 and mode!=0) or reserved!=b'\0'*3): raise ValueError('Invalid RVF2 frame')
        shape=(height,width,4) if layout==0 else (raw_bytes,)
        frame=restore_frame(zstd,data[position:position+length],mode,shape,previous,opaque=layout==0)
        result.append(frame if layout==0 else restore_yuv420(frame,width,height,bits)); previous=frame; position+=length
    if position!=len(data): raise ValueError('Unexpected RVF2 trailing bytes')
    return fields,result


def encode(rgb_path,output,name,width=None,fps=None,bits=(6,6,6),segment_seconds=2,level=5,layout=1,workers=None):
    rgb_path=Path(rgb_path); output=Path(output)
    meta=json.loads(Path(str(rgb_path)+'.json').read_text(encoding='utf-8'))
    source=np.memmap(rgb_path,dtype=np.uint8,mode='r').reshape(-1,meta['height'],meta['width'],3)
    width=width or meta['width']; height=round(width*meta['sourceHeight']/meta['sourceWidth']); fps=fps or meta['fps']
    if (not re.fullmatch(r'[A-Za-z0-9_]{1,40}',name) or len(bits)!=3 or not 16<=width<=MAX_SIDE
            or not 16<=height<=MAX_SIDE or width*height>MAX_PIXELS or not 4<=fps<=30
            or segment_seconds not in (1,2,3,4) or not all(type(v)is int and 3<=v<=8 for v in bits)
            or layout not in (0,1) or (layout==1 and sum(bits)>20) or not 1<=level<=19):
        raise ValueError('Invalid RVF2 encoder profile')
    total=math.ceil(meta['duration']*fps); segment_frames=fps*segment_seconds
    output.mkdir(parents=True,exist_ok=True); zstd=Zstd(); files=[]; pending=[]; previous=None
    mse_total=0.; modes=[0,0,0]; fixtures=[]; started=time.monotonic()
    local=threading.local()
    def encode_segment(first):
        if not hasattr(local,'zstd'): local.zstd=Zstd()
        worker_zstd=local.zstd
        records=[]; previous=None; errors=[]; counts=[0,0,0]; examples=[]
        ending=min(first+segment_frames,total)
        for index in range(first,ending):
            source_frame=source[min(len(source)-1,int(index*meta['fps']/fps))]
            if source_frame.shape[:2]!=(height,width): source_frame=np.asarray(Image.fromarray(source_frame).resize((width,height),Image.Resampling.LANCZOS))
            if layout==0:
                raw=rgba_frame(source_frame,bits); rgba=raw
            else:
                raw,rgba=yuv420_frame(source_frame,bits)
            mode,packed=choose_frame(worker_zstd,raw,previous,level)
            reconstructed=restore_frame(worker_zstd,packed,mode,raw.shape,previous,opaque=layout==0)
            if not np.array_equal(reconstructed,raw): raise ValueError('RVF2 encoder/decoder mismatch')
            previous=raw; counts[mode]+=1
            errors.append(float(((rgba[:,:,:3].astype(np.float32)-source_frame.astype(np.float32))**2).mean()))
            records.append(struct.pack('<IIB3s',len(packed),raw.nbytes,mode,b'\0'*3)+packed)
        data=pack_segment(records,width,height,fps,first,total,segment_frames,meta['duration'],bits,layout)
        checked,decoded=unpack_segment(data,worker_zstd)
        if not np.array_equal(decoded[-1],rgba): raise ValueError('RVF2 segment reconstruction mismatch')
        if first==0:
            for frame in sorted(set((0,len(decoded)//2,len(decoded)-1))):
                examples.append({'Frame':frame,'RGBAAdler32':zlib.adler32(decoded[frame].tobytes()),'RGBABytes':rgba.nbytes})
        return first,data,checked,ending-first,errors,counts,examples
    if workers is None: workers=min(4,os.cpu_count() or 1)
    if type(workers)is not int or not 1<=workers<=4: raise ValueError('RVF2 workers must be between 1 and 4')
    workers=min(workers,math.ceil(total/segment_frames))
    def results():
        if workers==1:
            for first in range(0,total,segment_frames): yield encode_segment(first)
        else:
            # Bound retained segments and consume in timeline order.
            with ThreadPoolExecutor(max_workers=workers) as pool:
                tasks=deque()
                for first in range(0,total,segment_frames):
                    tasks.append(pool.submit(encode_segment,first))
                    if len(tasks)>=workers: yield tasks.popleft().result()
                while tasks: yield tasks.popleft().result()
    for first,data,checked,count,errors,counts,examples in results():
        path=output/f'{name}_{first//segment_frames:04d}.rvf'; path.write_bytes(data)
        for error in errors: mse_total+=error
        for mode in range(3): modes[mode]+=counts[mode]
        fixtures.extend(examples)
        files.append({'File':path.name,'Bytes':len(data),'Checksum':checked[4],'FirstFrame':first,
            'Frames':count,'SHA256':hashlib.sha256(data).hexdigest()})
        if len(files)%10==0: print(f'RVF2 encoded {first+count}/{total}',flush=True)
    total_bytes=sum(row['Bytes'] for row in files)
    manifest={'Format':'RVF2','Encoding':2,'Id':name,'AudioTrack':name,'Width':width,'Height':height,
        'FPS':fps,'Frames':total,'Duration':meta['duration'],'SegmentFrames':segment_frames,'Segments':len(files),
        'ColorBits':list(bits),'Layout':('RGBA' if layout==0 else 'YCbCr420'),'Compression':'Zstd','Bytes':total_bytes,'BytesPerSecond':total_bytes/meta['duration'],
        'PeakSegmentBytes':max(row['Bytes'] for row in files),'PSNR':10*math.log10(255**2/max(mse_total/total,1e-12)),
        'PSNRReference':f'Source resized to {width}x{height}; excludes downscaling loss','ModeCounts':modes,
        'SecondsToEncode':time.monotonic()-started,'DecoderFixture':fixtures,'Files':files}
    (output/f'{name}.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    (output.parent/f'{name}.entry.txt').write_text(f'["{name}"] = {{Width={width}, Height={height}, FPS={fps}, '
        f'Frames={total}, Duration={meta["duration"]:.9f}, SegmentFrames={segment_frames}, Segments={len(files)}, '
        f'Encoding=2, AudioTrack="{name}", BaseUrl="YOUR_RAW_GITHUB_FOLDER_URL"}},\n',encoding='utf-8')
    return manifest


def validate_track(path):
    path=Path(path); meta=json.loads(path.read_text(encoding='utf-8')); zstd=Zstd(); total_bytes=0
    if (not isinstance(meta,dict) or not isinstance(meta.get('Id'),str)
            or not re.fullmatch(r'[A-Za-z0-9_]{1,40}',meta['Id']) or path.name!=f'{meta["Id"]}.json'
            or meta.get('Format')!='RVF2' or meta.get('Encoding')!=2): raise ValueError('Invalid RVF2 manifest identity')
    for key in ('Width','Height','FPS','Frames','Segments','SegmentFrames'):
        if type(meta.get(key))is not int or meta[key]<1: raise ValueError(f'Invalid RVF2 manifest {key}')
    if meta['Segments']!=math.ceil(meta['Frames']/meta['SegmentFrames']): raise ValueError('Incomplete RVF2 timeline')
    if not isinstance(meta.get('Files'),list) or len(meta['Files'])!=meta['Segments']: raise ValueError('Incomplete RVF2 file list')
    for part,row in enumerate(meta['Files']):
        expected=f'{meta["Id"]}_{part:04d}.rvf'
        if row['File']!=expected: raise ValueError('Unexpected RVF2 filename')
        data=(path.parent/expected).read_bytes(); fields,frames=unpack_segment(data,zstd)
        if (fields[5:8]!=(meta['Width'],meta['Height'],meta['FPS']) or fields[9]!=part*meta['SegmentFrames']
                or fields[10]!=meta['Frames'] or fields[11]!=meta['SegmentFrames'] or row['Bytes']!=len(data)
                or fields[8]!=min(meta['SegmentFrames'],meta['Frames']-fields[9])
                or row['FirstFrame']!=fields[9] or row['Frames']!=fields[8]
                or row['Checksum']!=fields[4] or row['SHA256']!=hashlib.sha256(data).hexdigest()):
            raise ValueError('RVF2 manifest/segment mismatch')
        total_bytes+=len(data)
    if total_bytes!=meta['Bytes'] or len(meta['Files'])!=meta['Segments']: raise ValueError('Incomplete RVF2 bundle')
    if set(p.name for p in path.parent.glob('*.rvf'))!={row['File'] for row in meta['Files']}: raise ValueError('Stale RVF2 segments in upload directory')
    return {'Name':meta['Id'],'Frames':meta['Frames'],'Segments':meta['Segments'],'Bytes':total_bytes,
        'AllChecksumsPassed':True,'AllFramesDecoded':True,'Width':meta['Width'],'Height':meta['Height'],
        'FPS':meta['FPS'],'Duration':meta['Duration'],'BytesPerSecond':meta['BytesPerSecond'],
        'Format':'RVF2','Encoding':2,'Layout':meta['Layout'],'ColorBits':meta['ColorBits']}


def benchmark(rgb_path,output):
    rgb_path=Path(rgb_path); meta=json.loads(Path(str(rgb_path)+'.json').read_text(encoding='utf-8'))
    source=np.memmap(rgb_path,dtype=np.uint8,mode='r').reshape(-1,meta['height'],meta['width'],3)
    starts=np.linspace(0,max(0,len(source)-meta['fps']*2),12,dtype=int)
    reports=[]; zstd=Zstd()
    for bits in ((8,8,8),(6,6,6),(5,6,5),(5,5,5),(4,5,4)):
        count=0; total_bytes=0; error=0.; modes=[0,0,0]; maximum=0; start_time=time.monotonic()
        for first in starts:
            previous=None; sequence_bytes=0
            for index in range(first,min(len(source),first+meta['fps'])):
                rgb=source[index]; rgba=rgba_frame(rgb,bits)
                mode,packed=choose_frame(zstd,rgba,previous); previous=rgba
                error+=float(((rgba[:,:,:3].astype(np.float32)-rgb.astype(np.float32))**2).mean())
                count+=1; modes[mode]+=1; total_bytes+=len(packed)+12; sequence_bytes+=len(packed)+12
            maximum=max(maximum,sequence_bytes)
        report={'Bits':bits,'Frames':count,'BytesPerSecond':total_bytes/count*meta['fps'],
            'PSNR':10*math.log10(255**2/max(error/count,1e-12)),'Modes':modes,
            'PeakOneSecondBytes':maximum,'Seconds':time.monotonic()-start_time}
        reports.append(report); print(json.dumps(report),flush=True)
    Path(output).write_text(json.dumps({'Source':str(rgb_path),'SourceWidth':meta['width'],
        'SourceHeight':meta['height'],'SourceFPS':meta['fps'],'Reports':reports},indent=2),encoding='utf-8')


def main():
    parser=argparse.ArgumentParser(description=__doc__); parser.add_argument('rgb',type=Path)
    parser.add_argument('--output',type=Path,required=True); parser.add_argument('--benchmark',action='store_true'); parser.add_argument('--benchmark-yuv',action='store_true')
    parser.add_argument('--name',default='YippeVideo'); parser.add_argument('--width',type=int); parser.add_argument('--fps',type=int)
    parser.add_argument('--bits',default='6,6,6'); parser.add_argument('--segment-seconds',type=int,default=2); parser.add_argument('--level',type=int,default=5)
    parser.add_argument('--layout',choices=('rgba','yuv420'),default='yuv420')
    args=parser.parse_args()
    if args.benchmark_yuv: benchmark_yuv(args.rgb,args.output)
    elif args.benchmark: benchmark(args.rgb,args.output)
    else:
        result=encode(args.rgb,args.output,args.name,args.width,args.fps,tuple(map(int,args.bits.split(','))),args.segment_seconds,args.level,0 if args.layout=='rgba' else 1)
        print(json.dumps({k:v for k,v in result.items() if k not in ('Files','DecoderFixture')},indent=2))


if __name__=='__main__': main()
