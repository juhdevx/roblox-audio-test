# Testing

## Automated (run in CI on every push)

| Suite | Where | Count | What it proves |
|---|---|---|---|
| Native DSP + engine core | `tests/native` (CTest, host compiler) | 45 | FFT vs DFT, ring buffer (incl. 2 M-element threaded order test), biquad responses, gate, AGC convergence, compressor curve, limiter ceiling, resampler accuracy/anti-aliasing, tone detector, latency probe, pitch accuracy (±1 %), formant movement, noise reduction, identity reconstruction, bounded output, duplex bypass/mute/NaN containment/tone/tap, AI bridge timestamps, neural path with a threaded fake worker and automatic DSP fallback, YIN pitch tracker, monitor queue under ±500 ppm clock drift |
| `core-dsp` | JVM | 15 | parameter model; **C++/Kotlin contract** parsed from `VoiceParams.h`; pitch calibration suggestions |
| `core-audio` | JVM | 11 | engine controller lifecycle, optional monitor device fallback/restore, start failure, missing native lib, **USB unplug → default → automatic restore**, recovery give-up, diffed parameter updates, stats contract parsed from `OboeEngine.h` |
| `core-models` | JVM | 16 | atomic JSON storage, corruption recovery, presets CRUD, model import/duplicates/revisions/consent/size/invalid files, memory-aware load planner |
| `core-inference` | JVM + real ONNX Runtime | 18 | stream-v1 analyzer rules, RVC/encoder detection, real model validation + smoke test, context handling, worker timestamps, slow-model and error stop |
| `bridge-usb` | JVM | 7 | Route A checks and the staged validation procedure |
| `bridge-network` | JVM | 8 | packet codec, malformed input, jitter buffer reorder/loss/late/duplicate/wrap/rebuffer, **real UDP loopback stream** |
| `diagnostics` | JVM | 4 | `/proc` CPU parsing, log rotation, report rendering, thermal mapping |
| `app-android` | Robolectric | 2 | launches `MainActivity` with the production Hilt graph, navigates all tabs, native-unavailable path; screenshots (CI artifact) |

Run locally:
```bash
cd VoiceShiftVR
./gradlew testDebugUnitTest :core-dsp:test :core-models:test
cmake -S tests/native -B tests/native/build -DCMAKE_BUILD_TYPE=Release && cmake --build tests/native/build -j && ctest --test-dir tests/native/build --output-on-failure
```

All of the above also run in GitHub Actions on every push (first green run: #1, 2026-11-17).

Not automated: instrumented tests on a device/emulator (no emulator available in this development
environment). The Oboe code path itself (`OboeEngine.cpp`) is compiled for every ABI in CI but only
exercised on real hardware.

## Manual hardware test matrix

**Status of every row: NOT RUN.** Do not mark rows passed without performing them on a device.
Record results in the app's validation section and attach the diagnostic report.

| ID | Area | Procedure | Pass criteria |
|---|---|---|---|
| M1 | Mic permission | Fresh install → Start voice → deny → Start again → "Open app settings" → allow | Clear explanation, no crash, engine starts after granting |
| M2 | Background | Start, press Home, open another app for 5 min | Notification visible; audio continues; Stop in notification works |
| M3 | Background restrictions | Same with battery saver on / app battery-optimised | Behaviour documented; app recovers when reopened |
| M4 | Wired headset | Plug/unplug during processing | Recovering → Running; meters resume |
| M5 | USB interface | Select USB output, unplug, replug | Falls back to default, returns to USB automatically |
| M6 | Bluetooth | Select BT headset | Works; latency noted (expect higher) |
| M7 | Quest external mic | QUEST_BRIDGE stages 1-3 | Probe detects tone |
| M8 | Roblox | ROBLOX_TESTING steps 1-8 | Listener hears processed voice |
| M9 | Feedback/echo | Phone speaker + mic | Warning shown; Mute stops howling; Echo-cancel mic mode reduces it |
| M10 | Thermal | 30 min continuous, phone in hand/case | Thermal state shown; no xrun growth > 1/min |
| M11 | Long duration | 2 h session | No crash, memory stable (Settings → report) |
| M12 | Latency | Loopback cable probe, both DSP qualities | Values recorded vs targets (<100 ms ideal, ≤200 ms acceptable) |
| M13 | AI pipeline | Import diagnostic passthrough model, load, AI mode | Worker running, RTF < 1, audible; stopping worker falls back to DSP |
| M14 | Model hygiene | Import RVC export, garbage file, duplicate, real-voice without consent | Unsupported / rejected / duplicate / rejected |
| M15 | Quest Lab DSP | Route B local engine on headset | Load and latency recorded |
| M17 | Monitor output | Main output = USB/cable, monitor = wired/BT headphones | Both play; monitor underruns stay low; unplugging the monitor keeps the main output running |
| M18 | Calibration | Voice tab → calibrate while reading aloud | Measured pitch plausible; suggestion applied |
| M16 | Wi-Fi bridge | Phone → Quest Lab receiver | Audio plays; loss/late counters reasonable on home Wi-Fi |
