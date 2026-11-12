# Video quality limits

RVF2 supports up to 1024 pixels per side and 589824 pixels per image (for example 1024×576). It retains its 4 MiB maximum compressed segment, 30 FPS maximum, existing prediction formats, color quantization and checksums. RVF1 retains its 256-side/36864-pixel/20 FPS limits.

The desktop HQ profile is optional: request 960×540 at 24 FPS with the existing 512 KiB/s encoded-video budget. The converter may reduce the final dimensions to meet that budget and the 4 MiB segment limit. A larger requested size is not a promise that every video can keep that size within the network budget.

The current video transport is 96 chunks/s × 8192 bytes = 768 KiB/s before other costs. Raising image limits does not increase that transport rate, client cache, automatic bandwidth budget or allocation guarantees. Larger images cost more decode time and EditableImage memory; existing converted packages keep their current dimensions.

Browser and native capture accept widths through 1024. Disk preflight includes the larger raw RGB capture. Encoders and Roblox manifest/header validators enforce the same RVF2 side/pixel limits before allocating decoded images. New HQ content needs the updated Roblox codec; existing RVF2 content remains compatible.
