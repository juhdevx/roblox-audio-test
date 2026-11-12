# Add music and videos

Open `StartMediaWorkbench.cmd` and keep its window open during conversion. The Workbench opens a local browser page; your files stay on this computer.

1. Choose an MP4 or music file and enter the emote name.
2. Select **Lightweight**, **Balanced** or **High detail**. The converter may reduce resolution to stay within the data budget.
3. Keep **Audio analysis → Standard** for the established amplitude fit, or select **Phase-aware (experimental)** to fit amplitudes against tracked phase and stereo balance while keeping both fixed. Results vary by song; experimental does not mean consistently better.
4. Click **Convert and build package**. After conversion, use **Listen before importing** to compare matching original and reconstructed excerpts. The buttons switch between the clips at the current position; the players share one preview gain. You can download the measurement report.
5. Download and extract the package. Upload the files inside each `UploadBatches` folder, one batch at a time, using its upload link. Each batch contains at most 20 files and 18 MiB. `Comparison` contains local listening clips and measurements; those files do not belong in the upload batches.
6. After the final upload, you can paste the complete commit SHA under **Pin the commit**. Download the updated installer.
7. In Studio, stop Play, open **View > Command Bar**, then run the complete contents of `StudioImport.luau`.

Before changing the project, the installer checks the hosted manifest and the first and last audio/video segments. A missing upload, incorrect commit SHA or disabled HTTP setting stops the import with a clear message. Install the media systems first.

You do not need to edit three registries. The installer creates one private definition at `ServerStorage > MediaLibrary > Name` and an emote-only public definition at `ReplicatedStorage > Shared > MediaLibrary > Name`. Hosted file URLs stay in the private definition.

Under **Destination and emote settings**, choose the reference dance and ownership rules. Order **0** selects the next available catalog position; positive numbers keep an explicit order. Video emotes disable the reference dance's special camera behavior so the video remains visible.

To update an existing name, use its exact capitalization and enable **Update an existing name and keep a backup**. Previous local conversions stay in `generated > backups`; replaced Studio definitions stay in `ServerStorage > MediaLibraryBackups`.

This project allows `juhdevx/roblox-audio-test`. The Workbench does not request credentials or upload files automatically. Audio and video are reconstructed: review the result in-game, with headphones and on mobile.

The listening comparison renders a bounded offline sine model of the encoded partials. It excludes residual noise, Roblox scheduling, carrier response, runtime smoothing and compression, and device behavior. It is a useful check for analysis differences, not a recording or guarantee of the in-game sound. The measurement report separates raw gain from gain-matched results and is not a perceptual listening score. Final verification still happens in Studio.

If conversion stops, open **Conversion log**. The previous version is preserved. To verify files that were already converted, use **I already have a conversion in this folder**. Rebuilding preserves the saved emote settings, catalog order, pinned commit and original file hash; defaults from the new-conversion form do not overwrite them. **Pin the commit** changes only the requested revision and preserves the other settings.

The selected analysis is saved with each conversion and preserved when rebuilding or pinning. Conversions created before this option use **Standard**. Rebuilding reuses the encoded files and any existing listening clips; to change analysis or create missing clips, convert the original file again with **Update an existing name and keep a backup** enabled.
