"""Import a local video into checked, separately hosted video/audio with one Studio installer."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

from convert_video import encode as encode_legacy
from validate_video import validate_track as validate_legacy
from native_video import find_ffmpeg, decode_video as decode_native_video
from conversion_checkpoint import load_checkpoint, validate_rgb, validate_pcm

TOOLS=Path(__file__).resolve().parent
PACKAGE=TOOLS.parent


def safe_folder(value):
    if (not value or value.startswith('/') or value.endswith('/') or len(value)>160
            or any(not re.fullmatch(r'[A-Za-z0-9_-][A-Za-z0-9_.-]*',part) or part in ('.','..') for part in value.split('/'))):
        raise argparse.ArgumentTypeError('Use a repository folder such as media/myvideo/v1')
    return value


def find_node():
    candidates=[shutil.which('node'),str(Path.home()/'.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node.exe')]
    for candidate in candidates:
        if candidate and Path(candidate).is_file(): return candidate
    raise ValueError('Node.js was not found. Install Node.js and Playwright, or use the bundled Codex runtime.')


def file_sha256(path):
    digest=hashlib.sha256()
    with Path(path).open('rb') as source:
        for block in iter(lambda:source.read(1024*1024),b''): digest.update(block)
    return digest.hexdigest()


def run(command):
    subprocess.run([str(part) for part in command],check=True)


def estimate_workspace(metadata, capture_width, fps, max_video_kib, audio_voices):
    """Budget decoded scratch and all three copies of the checked output bundle."""
    if not isinstance(metadata, dict):
        raise ValueError('Os metadados do vídeo são inválidos.')
    duration = metadata.get('duration')
    if (isinstance(duration, bool) or not isinstance(duration, (int, float))
            or not math.isfinite(duration) or not 0 < duration <= 3600):
        raise ValueError('A duração do vídeo deve ser maior que zero e de até uma hora.')
    source_width, source_height = metadata.get('sourceWidth'), metadata.get('sourceHeight')
    if (type(source_width) is not int or type(source_height) is not int
            or source_width <= 0 or source_height <= 0):
        raise ValueError('As dimensões do vídeo são inválidas.')
    if (type(capture_width) is not int or not 16 <= capture_width <= 1024
            or type(fps) is not int or not 4 <= fps <= 30
            or isinstance(max_video_kib, bool) or not isinstance(max_video_kib, (int, float))
            or not math.isfinite(max_video_kib) or not 8 <= max_video_kib <= 1024
            or type(audio_voices) is not int or audio_voices not in (64, 96, 128)):
        raise ValueError('Invalid conversion profile for workspace estimation')
    width = min(capture_width, source_width)
    # Match positive Math.round in the video decoder, including portrait sources.
    height = max(1, math.floor(width * source_height / source_width + .5))
    rgb_bytes = width * height * 3 * math.ceil(duration * fps)
    pcm_bytes = math.ceil(duration * 24000) * 8
    video_bytes = math.ceil(duration * max_video_kib * 1024)
    # convert_song defaults: 60 Hz, 12 residual bands, two-second SPC1 segments.
    audio_bytes = math.ceil(duration * 60) * (audio_voices * 8 + 12 * 4)
    audio_bytes += math.ceil(duration / 2) * 48
    # Encoded sources, UploadBatches copies and the package ZIP coexist with scratch.
    bundle_bytes = 3 * (video_bytes + audio_bytes)
    subtotal = rgb_bytes + pcm_bytes + bundle_bytes
    margin = max(512 * 1024 * 1024, math.ceil(subtotal / 10))
    return {'CaptureWidth': width, 'CaptureHeight': height, 'RGBBytes': rgb_bytes,
            'PCMBytes': pcm_bytes, 'VideoBytes': video_bytes, 'AudioBytes': audio_bytes,
            'BundleBytes': bundle_bytes, 'MarginBytes': margin, 'RequiredBytes': subtotal + margin}


def check_workspace(root, metadata, capture_width, fps, max_video_kib, audio_voices):
    estimate = estimate_workspace(metadata, capture_width, fps, max_video_kib, audio_voices)
    free = shutil.disk_usage(root).free
    required = estimate['RequiredBytes']
    print(f'Espaço temporário estimado: {required / 1073741824:.2f} GiB; '
          f'disponível: {free / 1073741824:.2f} GiB.', flush=True)
    if free < required:
        raise ValueError(f'Espaço insuficiente para converter este vídeo: são necessários '
                         f'aproximadamente {required / 1073741824:.2f} GiB livres, '
                         f'mas há {free / 1073741824:.2f} GiB. '
                         'Libere espaço, escolha uma pasta em outro disco, use o perfil leve '
                         'ou converta um trecho menor.')
    return estimate


def align_audio_timeline(pcm, video_duration):
    """Pad or truncate derived stereo PCM so its clock covers the complete video."""
    if (isinstance(video_duration, bool) or not isinstance(video_duration, (int, float))
            or not math.isfinite(video_duration) or not 0 < video_duration <= 3600):
        raise ValueError('Video duration must be finite and between zero and one hour')
    pcm = Path(pcm)
    metadata_path = Path(str(pcm) + '.json')
    metadata = json.loads(metadata_path.read_text(encoding='utf-8'))
    if metadata.get('sampleRate') != 24000 or metadata.get('channels') != 2:
        raise ValueError('Timeline alignment requires 24000 Hz float32 stereo PCM')
    original_bytes = pcm.stat().st_size
    if original_bytes % 8:
        raise ValueError('PCM must contain complete interleaved float32 stereo samples')
    original_frames = original_bytes // 8
    target_frames = math.ceil(video_duration * 24000)
    target_bytes = target_frames * 8
    if original_bytes != target_bytes:
        with pcm.open('r+b') as output:
            if original_bytes > target_bytes:
                output.truncate(target_bytes)
            else:
                output.seek(0, os.SEEK_END)
                remaining = target_bytes - original_bytes
                silence = bytes(min(1024 * 1024, remaining))
                while remaining:
                    count = min(len(silence), remaining)
                    output.write(silence[:count])
                    remaining -= count
    metadata.update(frames=target_frames, duration=target_frames / 24000)
    metadata_path.write_text(json.dumps(metadata, indent=2), encoding='utf-8')
    return {'OriginalFrames': original_frames, 'Frames': target_frames,
            'AddedFrames': max(0, target_frames - original_frames),
            'TrimmedFrames': max(0, original_frames - target_frames),
            'Changed': original_frames != target_frames,
            'VideoDuration': video_duration, 'AudioDuration': target_frames / 24000}


def choose_video_width(metadata, requested_width, max_size, max_pixels):
    """Fit the codec budget without enlarging either the source or captured frames."""
    source_width, source_height = metadata['sourceWidth'], metadata['sourceHeight']
    if (not isinstance(source_width, int) or not isinstance(source_height, int)
            or source_width <= 0 or source_height <= 0):
        raise ValueError('The source video dimensions are invalid')
    aspect = source_width / source_height
    preferred = requested_width or (384 if max_size > 256 else 256)
    width = min(preferred, source_width, metadata.get('width', source_width), max_size,
                math.floor(max_size * aspect), math.floor(math.sqrt(max_pixels * aspect)))
    if width < 16 or round(width / aspect) < 16:
        raise ValueError('The source is too small or its aspect ratio is too extreme for this video profile')
    return width


def write_ready_files(staging,name,repo,folder,video,audio,source_hash,audio_timeline=None):
    # The single installer is generated below by prepare_bundle; remove intermediate snippets.
    for path in (staging/f'{name}.entry.txt', staging/'audio/upload'/f'{name}.entry.txt'):
        if path.is_file(): path.unlink()
    report={'Name':name,'OriginalFileSHA256':source_hash,'Repository':repo,'RepositoryFolder':folder,
            'Video':video,'Audio':audio,'NothingUploaded':True}
    audio_metadata=json.loads((staging/'audio/upload'/f'{name}.json').read_text(encoding='utf-8'))
    report['DerivedAudioPcmSHA256']=audio_metadata.get('SourceSHA256')
    report['AudioTimeline']=audio_timeline
    (staging/'IntegrityReport.json').write_text(json.dumps(report,indent=2),encoding='utf-8')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source',type=Path); parser.add_argument('--name')
    parser.add_argument('--repo',default='juhdevx/roblox-audio-test')
    parser.add_argument('--folder',type=safe_folder); parser.add_argument('--output-root',type=Path,default=PACKAGE/'generated')
    parser.add_argument('--width',type=int); parser.add_argument('--fps',type=int,default=20)
    parser.add_argument('--max-video-kib',type=float,default=512)
    parser.add_argument('--codec',choices=('rvf1','rvf2'),default='rvf2')
    parser.add_argument('--audio-voices',type=int,choices=(64,96,128),default=128)
    parser.add_argument('--analysis',choices=('source-fit','phase-pan-fit','peaks'),default='source-fit')
    parser.add_argument('--comparison',action='store_true',help='Build local original/reconstructed audio comparison clips')
    parser.add_argument('--replace',action='store_true')
    args=parser.parse_args()
    source=args.source.resolve()
    if not source.is_file(): parser.error('The video file does not exist')
    name=args.name or re.sub(r'[^A-Za-z0-9_]+','_',source.stem).strip('_')[:40]
    if not re.fullmatch(r'[A-Za-z0-9_]{1,40}',name): parser.error('Name must use 1-40 ASCII letters, digits or underscores')
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+',args.repo): parser.error('Repository must be owner/name')
    max_size,max_pixels,max_fps=(1024,589824,30) if args.codec=='rvf2' else (256,36864,20)
    if not 4<=args.fps<=max_fps or not 8<=args.max_video_kib<=1024: parser.error(f'Use 4-{max_fps} FPS and an 8-1024 KiB/s video budget')
    if args.width is not None and not 16<=args.width<=max_size: parser.error(f'Width must be 16-{max_size}')
    folder=args.folder or f'media/{name.lower()}/v1'
    root=args.output_root.resolve(); root.mkdir(parents=True,exist_ok=True)
    target=root/name
    if target.exists() and not args.replace:
        parser.error(f'{target} already exists. Use another --name or pass --replace to keep a backup first.')
    try:
        node=find_node()
        source_hash=file_sha256(source)
        with tempfile.TemporaryDirectory(prefix=f'.{name}-',dir=root) as temporary:
            staging=Path(temporary)/name; staging.mkdir()
            scratch=Path(temporary)/'scratch'; scratch.mkdir()
            rgb=scratch/'source.rgb'; pcm=scratch/'source.pcm'
            capture_width=max(128,args.width or (384 if args.codec=='rvf2' else 256))
            probe=scratch/'probe.rgb'
            run([node,TOOLS/'decode_video.cjs',source,probe,'--metadata'])
            probe_metadata=json.loads(Path(str(probe)+'.json').read_text(encoding='utf-8'))
            estimate=check_workspace(root,probe_metadata,capture_width,args.fps,
                                     args.max_video_kib,args.audio_voices)
            # Metadata-only probing captures no frames; validate the eventual capture size.
            choose_video_width(dict(probe_metadata,width=estimate['CaptureWidth']),
                               args.width,max_size,max_pixels)
            settings={'capture_width':capture_width,'fps':args.fps,'codec':args.codec,
                      'audio_voices':args.audio_voices,'analysis':args.analysis}
            checkpoint=load_checkpoint(PACKAGE,name,source_hash,settings)
            if checkpoint:
                rgb=checkpoint/'source.rgb'
                pcm=checkpoint/'source.pcm'
                print('Matching conversion checkpoint found; completed decoding will be reused.',flush=True)

            def video_ready():
                if checkpoint and rgb.is_file() and Path(str(rgb)+'.json').is_file():
                    try:
                        cached=json.loads(Path(str(rgb)+'.json').read_text(encoding='utf-8'))
                        validate_rgb(rgb,cached)
                        if (cached['width']==estimate['CaptureWidth'] and cached['height']==estimate['CaptureHeight']
                                and cached['fps']==args.fps
                                and math.isclose(cached['duration'],probe_metadata['duration'],abs_tol=1e-6)):
                            print('Reusing complete decoded video checkpoint.',flush=True)
                            return
                    except (ValueError,KeyError,OSError):pass
                if find_ffmpeg():
                    decode_native_video(source,rgb,capture_width,args.fps,probe_metadata)
                else:
                    run([node,TOOLS/'decode_video.cjs',source,rgb,capture_width,args.fps])
                validate_rgb(rgb,json.loads(Path(str(rgb)+'.json').read_text(encoding='utf-8')))

            def audio_ready():
                if checkpoint and pcm.is_file() and Path(str(pcm)+'.json').is_file():
                    try:
                        validate_pcm(pcm,json.loads(Path(str(pcm)+'.json').read_text(encoding='utf-8')))
                        print('Reusing complete decoded audio checkpoint.',flush=True)
                        return
                    except (ValueError,KeyError,OSError):pass
                run([node,TOOLS/'audio/decode_audio.cjs',source,pcm])
                validate_pcm(pcm,json.loads(Path(str(pcm)+'.json').read_text(encoding='utf-8')))

            with ThreadPoolExecutor(max_workers=2) as jobs:
                video_job=jobs.submit(video_ready)
                audio_job=jobs.submit(audio_ready)
                video_job.result(); audio_job.result()
            metadata=json.loads(Path(str(rgb)+'.json').read_text(encoding='utf-8'))
            aspect=metadata['sourceWidth']/metadata['sourceHeight']
            width=choose_video_width(metadata,args.width,max_size,max_pixels)
            audio_timeline=align_audio_timeline(pcm,metadata['duration'])
            manifest=None
            for attempt in range(5):
                try:
                    if args.codec=='rvf2':
                        from codec_v2 import encode as encode_modern
                        manifest=encode_modern(rgb,staging/'upload',name,width,args.fps,bits=(6,6,6))
                    else:
                        manifest=encode_legacy(rgb,staging/'upload',name,width,args.fps,quality=0.35)
                    if manifest['BytesPerSecond']<=args.max_video_kib*1024: break
                    width=max(16,int(width*math.sqrt(args.max_video_kib*1024/manifest['BytesPerSecond'])*.95))
                except ValueError as error:
                    if 'exceeds' not in str(error): raise
                    width=max(16,int(width*.8))
                if width<16 or round(width/aspect)<16: raise ValueError('Video cannot fit the bandwidth budget without excessive resolution loss')
            else: raise ValueError('Video still exceeds its bandwidth budget. Increase --max-video-kib or lower --fps.')
            run([sys.executable,TOOLS/'audio/convert_song.py',pcm,'--name',name,'--voices',args.audio_voices,
                 '--analysis',args.analysis,'--output',staging/'audio/upload'])
            sys.path.insert(0,str(TOOLS/'audio'))
            from validate_music import validate_track as validate_audio
            if args.codec=='rvf2':
                from codec_v2 import validate_track as validate_video
            else: validate_video=validate_legacy
            video_report=validate_video(staging/'upload'/f'{name}.json')
            audio_report=validate_audio(staging/'audio/upload'/f'{name}.json')
            if args.comparison:
                run([sys.executable,TOOLS/'audio/quality_compare.py',pcm,staging/'audio/upload'/f'{name}.json',
                     '--output',staging/'Comparison','--clip-seconds',3,'--clips',3])
            write_ready_files(staging,name,args.repo,folder,video_report,audio_report,source_hash,audio_timeline)
            from media_workbench import prepare_bundle, normalize_options
            options=normalize_options({'Name':name,'Repository':args.repo,'Folder':folder,'Template':'PaniniEvent',
                'Order':0,'Default':False,'Exclusive':True,'AudioAnalysis':args.analysis})
            prepare_bundle(staging,name,options,source_hash)
            shutil.copy2(staging/'COMECE_AQUI.txt',staging/'COMO_USAR.txt')
            if target.exists():
                backups=root/'backups'; backups.mkdir(exist_ok=True)
                suffix=datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
                target.rename(backups/f'{name}_{suffix}')
            staging.rename(target)
        print(f'\nREADY: {target}\nRead COMECE_AQUI.txt. Nothing was uploaded.',flush=True)
    except (ValueError,RuntimeError,OSError,subprocess.CalledProcessError) as error:
        parser.exit(1,f'Conversion failed: {error}\n')


if __name__=='__main__': main()
