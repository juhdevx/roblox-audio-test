# VoiceShift VR

Real-time feminine voice changer for Android, designed to feed a **Meta Quest 3S** external
microphone for **Roblox voice chat**. Offline, free and open source (Apache-2.0).

> **Read this first.** An Android app cannot inject audio into another app's microphone, and
> Horizon OS offers no public virtual-microphone API. VoiceShift processes your voice **on the
> phone** and plays it out of a cable/USB audio interface; the Quest must receive it through a
> **USB audio input device** (its experimental external-microphone support). That hardware path is
> **experimental and not yet verified on real devices** — see [docs/QUEST_BRIDGE.md](docs/QUEST_BRIDGE.md).

## Status at a glance

| Area | State |
|---|---|
| Android app (Kotlin, Compose, Hilt, MVVM) | **Implemented**, builds in CI, UI smoke-tested (Robolectric) |
| Live mic capture + playback (Oboe/AAudio full duplex, C++17) | **Implemented**; not yet run on a physical phone by the authors |
| DSP voice engine (pitch, formant, noise reduction, gate, AGC, EQ, compressor, limiter) | **Implemented and unit-tested** (35 native tests incl. pitch/formant accuracy) |
| Feminine presets, user presets, persistence | **Implemented** |
| Device selection + automatic recovery on unplug | **Implemented**, logic unit-tested with fakes |
| Latency/CPU/memory/thermal diagnostics, round-trip latency probe | **Implemented** |
| Neural engine (ONNX Runtime): import, validation, consent, memory check, streaming worker, auto DSP fallback | **Implemented** for the `stream-v1` contract, tested with real ONNX Runtime |
| RVC models | **Detected, not runnable** (needs encoder + F0 stages; see [docs/MODELS.md](docs/MODELS.md)) |
| No voice model is bundled | By design |
| Route A — USB/wired output to Quest USB mic input | Phone side **implemented** (routing, test tone, checks); **hardware path unverified** |
| Route B — native Quest app | **Research app** (`app-quest-experimental`): USB-mic probe, on-headset DSP benchmark |
| Route C — Wi-Fi bridge | **Experimental**: UDP stream + jitter buffer receiver. Does **not** create a microphone |
| Roblox in-game capture | **Not verified** — manual procedure in [docs/ROBLOX_TESTING.md](docs/ROBLOX_TESTING.md) |

## Get the APK (phone only, no computer)

1. Open this repository on GitHub in your phone browser → **Actions** → **VoiceShift VR Android**.
2. Open the newest green run → **Artifacts** → download **voiceshift-vr-debug-apk** (a ZIP).
3. Extract it (Files app), tap `app-android-debug.apk`, allow "Install unknown apps" for your browser/Files app.
4. Open VoiceShift VR → **Start voice** → allow the microphone. **Use headphones** (the phone speaker
   next to the microphone causes feedback).

Every CI build is signed with the same committed debug key, so new builds install over old ones.
Details, Codespaces and troubleshooting: [docs/BUILD_FROM_PHONE.md](docs/BUILD_FROM_PHONE.md).

## How it works

```
mic ─▶ Oboe input ─▶ low cut ─▶ noise gate ─▶ AGC ─┬─▶ Spectral voice shifter (DSP) ─────┐
                                                    │   noise suppression, pitch, formant   │
                                                    └─▶ [AI] resample ─▶ ONNX worker ─▶ ────┤ (crossfade, automatic
                                                                                            │  fallback to DSP)
          Oboe output ◀─ limiter ◀─ gain ◀─ compressor ◀─ body/presence/air EQ ◀───────────┘
          (selected device: headphones, USB interface → Quest)       └─▶ tap ─▶ Wi-Fi bridge (optional)
```

* **Engine A (DSP)** — phase vocoder with peak phase-locking moves the harmonics, while a cepstral
  spectral envelope keeps (or separately shifts) the formants. Not a playback-speed change. 42.7 ms
  algorithmic delay in quality mode, 21.3 ms in low-latency mode. [docs/DSP.md](docs/DSP.md)
* **Engine B (AI)** — any waveform-to-waveform ONNX model with VoiceShift `stream-v1` metadata runs
  on a background thread; the audio callback never blocks and plays DSP whenever the model is late.
* Architecture and module map: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Repository layout

```
VoiceShiftVR/
├── app-android/            Phone app: Compose UI (5 screens), Hilt DI, VoiceSession, foreground service
├── app-quest-experimental/ "VoiceShift Quest Lab": USB-mic probe, on-headset DSP test, Wi-Fi receiver
├── core-audio/             Oboe full-duplex engine (C++ + JNI), Kotlin controller with device recovery
├── core-dsp/               Voice parameter model (Kotlin) + portable C++17 DSP library (core-dsp/cpp)
├── core-inference/         ONNX Runtime validator/session, stream-v1 analyzer, streaming worker
├── core-models/            Presets, settings, model registry, atomic JSON storage (pure Kotlin)
├── bridge-usb/             Route A diagnostics, USB audio inspection, Quest/Roblox validation steps
├── bridge-network/         Route C packet format, jitter buffer, UDP sender/receiver, AudioTrack sink
├── diagnostics/            Log ring + file, CPU/memory/thermal monitor, shareable report
├── tests/native/           Host C++ unit tests (CMake/CTest)
├── tools/                  Android SDK setup script, ONNX test/diagnostic model generator
├── keystore/               Debug-only signing key (public on purpose; never use for releases)
└── docs/                   Architecture, DSP, models, Quest bridge, Roblox testing, test plan, roadmap
```
CI lives at the repository root in `.github/workflows/voiceshift-android.yml`; the Codespaces
container in `.devcontainer/`.

## Build locally (Codespaces or Linux)

```bash
bash VoiceShiftVR/tools/setup-android-sdk.sh       # SDK, NDK r28c, CMake (no Android Studio needed)
cd VoiceShiftVR
./gradlew assembleDebug                            # APKs in */build/outputs/apk/debug/
./gradlew testDebugUnitTest :core-dsp:test :core-models:test
cmake -S tests/native -B tests/native/build && cmake --build tests/native/build -j && ctest --test-dir tests/native/build
```

Toolchain: Gradle 9.9.1 (wrapper), AGP 9.5.1, Kotlin 2.4.21, JDK 17+ (21 used in CI), compileSdk 37,
targetSdk 36, minSdk 29 (Android 10), NDK 28.2.13676358. Only `arm64-v8a` is packaged by default
(`-Pvoiceshift.abis=arm64-v8a,armeabi-v7a,x86_64` adds more). All dependencies and licenses:
[docs/DEPENDENCIES.md](docs/DEPENDENCIES.md).

## Responsible use

* Built-in presets are generic settings, not imitations of real people.
* Custom voice models of a real person require your explicit confirmation of their consent at import,
  and models declaring a voice owner cannot be imported without it.
* VoiceShift does not modify Roblox, Horizon OS or any other app, and does not bypass Roblox voice
  eligibility. Follow the Roblox Terms of Use and Community Standards; do not impersonate others.
* Everything runs offline. No analytics, no uploads; the only network feature is the user-started
  LAN bridge.

## Documentation

| Document | Contents |
|---|---|
| [docs/BUILD_FROM_PHONE.md](docs/BUILD_FROM_PHONE.md) | CI artifacts, installing, Codespaces, when CI fails |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Modules, threads, data flow, design decisions |
| [docs/DSP.md](docs/DSP.md) | Algorithms, parameters, latency budget |
| [docs/MODELS.md](docs/MODELS.md) | `stream-v1` contract, RVC status, consent, training notes |
| [docs/QUEST_BRIDGE.md](docs/QUEST_BRIDGE.md) | Routes A/B/C, wiring, limitations |
| [docs/ROBLOX_TESTING.md](docs/ROBLOX_TESTING.md) | Reproducible Roblox voice procedure |
| [docs/TESTING.md](docs/TESTING.md) | Automated tests and the manual hardware test matrix |
| [docs/ROADMAP.md](docs/ROADMAP.md) | Phase status P0–P11 and next milestones |
| [docs/DEPENDENCIES.md](docs/DEPENDENCIES.md) | Versions and licenses |
