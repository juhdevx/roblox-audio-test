"""Convert decoded RGB video to independent RVF1 palette/tile-delta segments."""
import argparse
import hashlib
import json
import math
import re
import struct
import zlib
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

HEADER_BYTES = 64
PALETTE_BYTES = 768
MAX_SEGMENT_BYTES = 2 * 1024 * 1024
MODE_BYTES = (1, 4, 8, 16)


def adaptive_palette(frames):
    indices = np.linspace(0, len(frames)-1, min(100, len(frames)), dtype=int)
    sample = np.concatenate([frames[index] for index in indices], axis=0)
    image = Image.fromarray(sample).quantize(colors=256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    palette = np.asarray(image.getpalette()[:768], dtype=np.uint8).reshape(256, 3)
    reference = Image.new('P', (1, 1))
    reference.putpalette(palette.flatten().tolist())
    return palette, reference


def quantize(colors, reference):
    shape = colors.shape[:-1]
    image = Image.fromarray(np.asarray(colors, dtype=np.uint8).reshape(-1, 1, 3))
    return np.asarray(image.quantize(palette=reference, dither=Image.Dither.NONE)).reshape(shape)


def cluster_tiles(tiles, count, palette, reference):
    # Farthest-point initialisation handles hue changes better than luminance endpoints.
    centers = [tiles.mean(axis=1)]
    nearest = ((tiles - centers[0][:, None, :])**2).sum(axis=2)
    for _ in range(1, count):
        point = tiles[np.arange(len(tiles)), nearest.argmax(axis=1)]
        centers.append(point)
        nearest = np.minimum(nearest, ((tiles-point[:, None, :])**2).sum(axis=2))
    centers = np.stack(centers, axis=1)
    for _ in range(3):
        distance = ((tiles[:, :, None, :] - centers[:, None, :, :])**2).sum(axis=3)
        labels = distance.argmin(axis=2)
        for cluster in range(count):
            selected = labels == cluster
            weight = selected.sum(axis=1)
            average = (tiles * selected[:, :, None]).sum(axis=1) / np.maximum(1, weight)[:, None]
            centers[:, cluster] = np.where((weight > 0)[:, None], average, centers[:, cluster])
    ids = quantize(np.clip(np.rint(centers), 0, 255), reference)
    colors = palette[ids].astype(np.float32)
    distance = ((tiles[:, :, None, :] - colors[:, None, :, :])**2).sum(axis=3)
    labels = distance.argmin(axis=2).astype(np.uint8)
    reconstructed = ids[np.arange(len(tiles))[:, None], labels]
    error = np.min(distance, axis=2).mean(axis=1)/3
    return ids, labels, reconstructed, error


def tile_candidates(rgb, palette, reference, quality):
    height, width = rgb.shape[:2]
    padded = np.pad(rgb, ((0, (-height) % 4), (0, (-width) % 4), (0, 0)), mode='edge')
    rows, columns = padded.shape[0]//4, padded.shape[1]//4
    tiles = padded.reshape(rows, 4, columns, 4, 3).transpose(0, 2, 1, 3, 4).reshape(-1, 16, 3).astype(np.float32)
    literal = quantize(tiles, reference)
    solid_ids = quantize(np.clip(np.rint(tiles.mean(axis=1)), 0, 255), reference)
    solid_error = ((tiles-palette[solid_ids, None, :])**2).mean(axis=(1, 2))
    two_ids, two_labels, two_result, two_error = cluster_tiles(tiles, 2, palette, reference)
    four_ids, four_labels, four_result, four_error = cluster_tiles(tiles, 4, palette, reference)
    modes = np.full(len(tiles), 3, dtype=np.uint8)
    modes[four_error <= 60 * quality] = 2
    modes[two_error <= 100 * quality] = 1
    modes[solid_error <= 180 * quality] = 0
    result = literal.copy()
    result[modes == 0] = solid_ids[modes == 0, None]
    result[modes == 1] = two_result[modes == 1]
    result[modes == 2] = four_result[modes == 2]
    records = []
    for tile, mode in enumerate(modes):
        if mode == 0:
            payload = bytes([solid_ids[tile]])
        elif mode == 1:
            mask = sum(int(label) << pixel for pixel, label in enumerate(two_labels[tile]))
            payload = bytes(two_ids[tile]) + struct.pack('<H', mask)
        elif mode == 2:
            mask = sum(int(label) << (pixel*2) for pixel, label in enumerate(four_labels[tile]))
            payload = bytes(four_ids[tile]) + struct.pack('<I', mask)
        else:
            payload = bytes(literal[tile])
        records.append(struct.pack('<HB', tile, mode) + payload)
    return tiles, result, records, modes, rows, columns


def restore_image(indices, palette, rows, columns, width, height):
    pixels = palette[indices].reshape(rows, columns, 4, 4, 3).transpose(0, 2, 1, 3, 4).reshape(rows*4, columns*4, 3)
    return pixels[:height, :width]


def pack_segment(frames, palette, width, height, fps, first, total, segment_frames, duration):
    body = palette.tobytes() + b''.join(frames)
    header = bytearray(64)
    struct.pack_into('<IHHIIHHHHIIHHHHf', header, 0, 0x31465652, 1, 64, 64+len(body), 0,
                     width, height, fps, len(frames), first, total, segment_frames, 256, 1, 4, duration)
    data = header + body
    struct.pack_into('<I', data, 12, zlib.adler32(data))
    if len(data) > MAX_SEGMENT_BYTES:
        raise ValueError(f'Segment {first//segment_frames} exceeds 2 MiB ({len(data)} bytes); reduce width, FPS or quality')
    return data


def unpack_segment(data):
    if len(data) < 838 or len(data) > MAX_SEGMENT_BYTES:
        raise ValueError('RVF1 size limit')
    values = struct.unpack_from('<IHHIIHHHHIIHHHHf', data)
    magic, version, header, size, checksum, width, height, fps, frames, first, total, segment_frames, colors, encoding, tile, duration = values
    check = bytearray(data); check[12:16] = b'\0'*4
    if (magic != 0x31465652 or version != 1 or header != 64 or size != len(data)
            or zlib.adler32(check) != checksum or colors != 256 or encoding != 1 or tile != 4):
        raise ValueError('Invalid RVF1 header/checksum')
    if (not 16 <= width <= 256 or not 16 <= height <= 256 or width*height > 36864
            or not 4 <= fps <= 20 or not 1 <= frames <= segment_frames <= fps*4
            or first % segment_frames or first+frames > total or not 0 < duration <= 3600
            or abs(total-math.ceil(duration*fps)) > 1 or any(data[44:64])):
        raise ValueError('Invalid RVF1 dimensions')
    palette = np.frombuffer(data[64:832], dtype=np.uint8).reshape(256, 3)
    rows, columns = math.ceil(height/4), math.ceil(width/4)
    tiles = np.zeros((rows*columns, 16), dtype=np.uint8)
    position = 832
    decoded = []
    for frame in range(frames):
        if position+6 > len(data): raise ValueError('Truncated frame')
        length, count = struct.unpack_from('<IH', data, position)
        ending = position+4+length; position += 6
        if length < 2 or ending > len(data) or count > len(tiles) or (frame == 0 and count != len(tiles)):
            raise ValueError('Invalid frame')
        seen = set()
        for _ in range(count):
            if position+3 > ending: raise ValueError('Truncated tile')
            index, mode = struct.unpack_from('<HB', data, position); position += 3
            if index >= len(tiles) or index in seen or mode > 3 or position+MODE_BYTES[mode] > ending:
                raise ValueError('Invalid tile')
            seen.add(index)
            if mode == 0: tiles[index] = data[position]
            elif mode == 1:
                mask = struct.unpack_from('<H', data, position+2)[0]
                tiles[index] = [data[position+((mask >> pixel) & 1)] for pixel in range(16)]
            elif mode == 2:
                mask = struct.unpack_from('<I', data, position+4)[0]
                tiles[index] = [data[position+((mask >> (pixel*2)) & 3)] for pixel in range(16)]
            else: tiles[index] = np.frombuffer(data[position:position+16], dtype=np.uint8)
            position += MODE_BYTES[mode]
        if position != ending: raise ValueError('Unexpected frame bytes')
        decoded.append(restore_image(tiles, palette, rows, columns, width, height).copy())
    if position != len(data): raise ValueError('Trailing segment bytes')
    return values, decoded


def encode(rgb_path, output, name, width=None, fps=None, quality=1, sample_stride=1):
    metadata = json.loads(Path(str(rgb_path)+'.json').read_text(encoding='utf-8'))
    source = np.memmap(rgb_path, dtype=np.uint8, mode='r').reshape(-1, metadata['height'], metadata['width'], 3)
    width = width or metadata['width']; fps = fps or metadata['fps']
    height = max(16, round(width*metadata['sourceHeight']/metadata['sourceWidth']))
    total = math.ceil(metadata['duration']*fps)
    source_indices = np.minimum(np.floor(np.arange(total)*metadata['fps']/fps).astype(int), len(source)-1)
    selected = []
    for index in source_indices:
        frame = source[index]
        if width != metadata['width'] or height != metadata['height']:
            frame = np.asarray(Image.fromarray(frame).resize((width,height), Image.Resampling.LANCZOS))
        selected.append(frame)
    selected = np.stack(selected)
    palette, reference = adaptive_palette(selected)
    output.mkdir(parents=True, exist_ok=True)
    segment_frames = fps*2
    files, pending = [], []
    previous = None; total_error=0.; mode_histogram=np.zeros(4,dtype=np.int64); changed_total=0; maximum_mse=0.
    captures = {}; capture_indices=set(np.linspace(0,total-1,8,dtype=int))
    fixture = []
    for frame_index, rgb in enumerate(selected):
        tiles, candidates, records, modes, rows, columns = tile_candidates(rgb, palette, reference, quality)
        changed = np.ones(len(tiles),dtype=bool) if frame_index % segment_frames == 0 else ((tiles-palette[previous])**2).mean(axis=(1,2)) > 55*quality
        previous = candidates.copy() if previous is None else np.where(changed[:,None], candidates, previous)
        image = restore_image(previous, palette, rows, columns, width, height)
        mse = float(((image.astype(np.float32)-rgb.astype(np.float32))**2).mean())
        total_error += mse; maximum_mse=max(maximum_mse,mse)
        mode_histogram += np.bincount(modes[changed],minlength=4); changed_total+=int(changed.sum())
        body=struct.pack('<H',int(changed.sum()))+b''.join(record for record,write in zip(records,changed) if write)
        pending.append(struct.pack('<I',len(body))+body)
        if frame_index in capture_indices: captures[frame_index]=(rgb.copy(),image.copy())
        if len(pending)==segment_frames or frame_index==total-1:
            first=frame_index+1-len(pending)
            data=pack_segment(pending,palette,width,height,fps,first,total,segment_frames,metadata['duration'])
            path=output/f'{name}_{first//segment_frames:04d}.rvf'; path.write_bytes(data)
            values, decoded=unpack_segment(data)
            expected=image
            if not np.array_equal(decoded[-1],expected): raise ValueError('Python decoder differs from encoder')
            if first==0:
                for offset in sorted(set((0,len(decoded)//2,len(decoded)-1))):
                    rgba=np.dstack((decoded[offset],np.full((height,width),255,dtype=np.uint8))).tobytes()
                    fixture.append({'Frame':offset,'RGBAAdler32':zlib.adler32(rgba),'RGBABytes':len(rgba)})
            files.append({'File':path.name,'Bytes':len(data),'Checksum':values[4],
                          'FirstFrame':first,'Frames':len(pending),'SHA256':hashlib.sha256(data).hexdigest()})
            pending=[]
            if len(files)%10==0: print(f'Encoded {frame_index+1}/{total}',flush=True)
    bytes_total=sum(row['Bytes'] for row in files)
    manifest={'Format':'RVF1','Encoding':1,'Id':name,'AudioTrack':name,'Width':width,'Height':height,
              'FPS':fps,'Frames':total,'Duration':metadata['duration'],'SegmentFrames':segment_frames,'Segments':len(files),
              'SourceWidth':metadata['sourceWidth'],'SourceHeight':metadata['sourceHeight'],
              'Bytes':bytes_total,'BytesPerSecond':bytes_total/metadata['duration'],
              'PeakSegmentBytes':max(row['Bytes'] for row in files),'PSNR':10*math.log10(255**2/max(total_error/total,1e-12)),
              'PSNRReference':f'Source resized to {width}x{height}; excludes downscaling loss',
              'AverageMSE':total_error/total,'PeakFrameMSE':maximum_mse,'ChangedTilesPerFrame':changed_total/total,
              'ModeCounts':mode_histogram.tolist(),'Quality':quality,'DecoderFixture':fixture,'Files':files}
    (output/f'{name}.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    (output.parent/f'{name}.entry.txt').write_text(
        f'["{name}"] = {{Width={width}, Height={height}, FPS={fps}, Frames={total}, '
        f'Duration={metadata["duration"]:.9f}, SegmentFrames={segment_frames}, Segments={len(files)}, '
        f'Encoding=1, AudioTrack="{name}", BaseUrl="YOUR_RAW_GITHUB_FOLDER_URL"}},\n',encoding='utf-8')
    cell_width=width*3; cell_height=height*3+22
    sheet=Image.new('RGB',(cell_width*2,cell_height*len(captures)),(20,20,24)); draw=ImageDraw.Draw(sheet)
    for row,(frame,(original,reconstructed)) in enumerate(captures.items()):
        for column,(label,pixels) in enumerate((('Source',original),('RVF1',reconstructed))):
            sheet.paste(Image.fromarray(pixels).resize((width*3,height*3),Image.Resampling.NEAREST),(column*cell_width,row*cell_height+22))
            draw.text((column*cell_width+4,row*cell_height+4),f'{label} {frame/fps:.2f}s',fill='white')
    sheet.save(output.parent/'VideoComparison.png')
    print(json.dumps({key:value for key,value in manifest.items() if key not in ('Files','DecoderFixture')},indent=2),flush=True)
    return manifest


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('rgb',type=Path); parser.add_argument('--name',default='YippeVideo')
    parser.add_argument('--output',type=Path,required=True); parser.add_argument('--width',type=int)
    parser.add_argument('--fps',type=int); parser.add_argument('--quality',type=float,default=1)
    args=parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9_]{1,40}',args.name): parser.error('Name must use 1-40 ASCII letters, digits or underscores')
    if args.width is not None and not 16<=args.width<=256: parser.error('Width must be 16-256')
    if args.fps is not None and not 4<=args.fps<=20: parser.error('FPS must be 4-20')
    if not .1<=args.quality<=5: parser.error('Quality tolerance must be .1-5; lower means higher quality')
    encode(args.rgb,args.output,args.name,args.width,args.fps,args.quality)


if __name__=='__main__': main()
