"""Optional native sequential decoding with the same bounded RGB frame contract."""
from pathlib import Path
import json
import math
import os
import shutil
import subprocess
import time

TOOLS=Path(__file__).resolve().parent


def find_ffmpeg():
    local=TOOLS/'bin/ffmpeg.exe'
    candidate=local if local.is_file() else shutil.which('ffmpeg')
    return str(candidate) if candidate else None


def decode_video(source, output, capture_width, fps, source_metadata):
    binary=find_ffmpeg()
    if not binary:
        raise ValueError('Native decoder is not available')
    duration=source_metadata['duration']
    width=min(capture_width,source_metadata['sourceWidth'])
    height=max(1,math.floor(width*source_metadata['sourceHeight']/source_metadata['sourceWidth']+.5))
    if not math.isfinite(duration) or not 0<duration<=3600 or not 1<=fps<=30:
        raise ValueError('Invalid native video timing')
    if not 16<=width<=1024 or not 1<=height<=32768:
        raise ValueError('Invalid native video size')
    frames=math.ceil(duration*fps)
    output=Path(output)
    output.parent.mkdir(parents=True,exist_ok=True)
    partial=output.with_suffix(output.suffix+'.native-partial')
    metadata={**source_metadata,'width':width,'height':height,'fps':fps,'frames':frames,
              'duration':duration,'Decoder':'FFmpeg sequential'}
    # The container/audio can outlast the video packets. Pad that tail, then cap
    # the exact frame count expected by the existing codecs.
    filters=f'fps=fps={fps}:start_time=0:round=near,scale={width}:{height}:flags=lanczos,tpad=stop_mode=clone:stop_duration={duration}'
    command=[binary,'-hide_banner','-loglevel','error','-nostdin','-y',
             '-threads',str(min(8,os.cpu_count() or 1)),'-i',str(source),'-map','0:v:0','-an','-sn','-dn',
             '-vf',filters,'-frames:v',str(frames),'-pix_fmt','rgb24','-f','rawvideo',
             '-progress','pipe:1','-stats_period','0.5','-nostats',str(partial)]
    flags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0
    print(f'Native sequential video decoder: {width}x{height}, {fps} FPS, {frames} frames',flush=True)
    began=time.monotonic()
    last_report=0
    try:
        with subprocess.Popen(command,stdin=subprocess.DEVNULL,stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT,text=True,encoding='utf-8',errors='replace',
                              creationflags=flags) as process:
            errors=[]
            for raw in process.stdout:
                line=raw.strip()
                if line.startswith('frame='):
                    current=int(line.split('=',1)[1])
                    if current-last_report>=fps*2 or current==frames:
                        print(f'Decoded {current}/{frames}',flush=True)
                        last_report=current
                elif '=' not in line and line:
                    errors.append(line)
                    errors=errors[-8:]
            if process.wait():
                raise ValueError('Native video decoder failed: '+'; '.join(errors))
        expected=width*height*3*frames
        if not partial.is_file() or partial.stat().st_size!=expected:
            actual=partial.stat().st_size if partial.exists() else 0
            raise ValueError(f'Incomplete decoded video: expected {expected} bytes, got {actual}')
        partial.replace(output)
        Path(str(output)+'.json').write_text(json.dumps(metadata,indent=2),encoding='utf-8')
    finally:
        partial.unlink(missing_ok=True)
    print(f'Decoded {frames}/{frames}; native video completed in {time.monotonic()-began:.2f}s',flush=True)
    return metadata
