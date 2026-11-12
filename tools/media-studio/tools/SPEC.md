# RVF1: independently seekable video segments

RVF1 is a small, deliberately bounded indexed-color codec for `EditableImage`.
It transports decoded visual data rather than an external MP4 ContentId. Every
segment contains its own RGB palette and complete first frame. Frames after that
only replace changed 4 x 4 tiles. The decoder produces packed RGBA bytes, with
alpha fixed at 255, suitable for `EditableImage:WritePixelsBuffer`.

All integer fields are unsigned and little-endian. Header size is 64 bytes.

- 0: `u32` magic `0x31465652` (`RVF1`).
- 4: `u16` version, currently 1.
- 6: `u16` header size, 64.
- 8: `u32` total segment byte length.
- 12: `u32` Adler-32 of the entire segment, treating bytes 12..15 as zero.
- 16, 18: `u16` width and height.
- 20, 22: `u16` FPS and number of frames in this segment.
- 24, 28: `u32` first absolute frame and total frames in the complete video.
- 32, 34: `u16` normal segment frame count and palette entries (256).
- 36, 38: `u16` encoding (1) and tile edge length (4).
- 40: `f32` original source duration in seconds.
- 44..63: reserved zero bytes.

Bytes 64..831 contain 256 consecutive RGB triplets. Frame records follow.
Each record starts with `u32 payloadBytes`, followed by `u16 changedTileCount`.
`payloadBytes` includes the count and all tile data, but excludes its own four
bytes. Every tile starts with `u16 tileIndex` (row-major, zero-based) and `u8 mode`.

- Mode 0: one palette index, filling all 16 pixels.
- Mode 1: two indices plus a `u16` mask, one bit per pixel.
- Mode 2: four indices plus a `u32` mask, two bits per pixel.
- Mode 3: sixteen indices in row-major pixel order.

Mask bits start at the least significant bit. The palette index selection for
pixel `p` is `(mask >> p) & 1` or `(mask >> (p * 2)) & 3`. Partial right/bottom
tiles are padded by the encoder and clipped by the decoder. A tile may appear at
most once per frame. The first frame must contain every tile exactly once.

The public decoder accepts width/height 16..256, area at most 36,864 pixels,
FPS 4..20, segment length at most four seconds, complete video at most one hour,
and a hard limit of 2 MiB per segment. Structural checks reject duplicate tiles,
truncation, invalid modes, trailing data and unsupported extension bytes.

`Format.Begin` and `Format.Step` incrementally validate 8 KiB of checksum or one
frame of structure per call. `Format.Validate` is their yielding convenience
wrapper. `Format.Header` only validates the header. `Format.Decoder.new` expects
an accepted segment. `decoder:Step(targetFrame, budgetMs)` advances by complete
frames until its budget expires; it returns RGBA and true only when the target
is ready. `Seek` performs the same operation synchronously. `Destroy` releases
buffers and can be called repeatedly.

Audio uses a separate SPC1 track. The client derives video frame position from
the existing spectral audio clock, so rendering delay never slows or drifts the
song. Late visual frames can be skipped. A segment is independently decodable,
so recovery and seek work without downloading earlier segments.

The default converter uses one adaptive palette per full video for stable colors,
small tile palettes chosen by squared error, and a bounded temporal deadband.
This is a lossy, low-resolution reconstruction. PSNR in the manifest compares
against the already resized source; it does not include loss from resizing.
