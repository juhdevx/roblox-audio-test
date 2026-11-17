# Architecture

## Layers

```
 UI (Compose screens)            app-android/ui/*            stateless composables
   │ collectAsStateWithLifecycle
 ViewModels (@HiltViewModel)     app-android/ui/*            combine flows → UiState, launch actions
   │
 Domain orchestrator             app-android/session/VoiceSession (singleton)
   │  engine lifecycle · presets · models · neural worker · network bridge · reports
   ├── VoiceEngineController     core-audio   (start/stop, stats polling, device-loss recovery)
   │     └── AudioEngineNative → NativeAudioBridge (JNI) → OboeEngine (C++)
   │                                                   └── DuplexProcessor → VoiceChain (core-dsp/cpp)
   ├── PresetRepository / SettingsRepository / ModelRegistry   core-models (JSON, atomic writes)
   ├── OnnxModelValidator / OrtInferenceSession / StreamingInferenceWorker   core-inference
   ├── RouteDiagnostics / UsbAudioInspector / QuestValidationProcedure       bridge-usb
   ├── UdpPcmSender (Route C)                                                bridge-network
   └── DiagnosticsLog / PerformanceMonitor / DiagnosticReport               diagnostics
```

* **Dependency injection:** Hilt, wired only in `app-android/di/AppModule.kt`. Library modules have
  no Hilt annotations, so they compile and test as plain Kotlin/JVM code.
* **Clean boundaries:** `core-dsp` and `core-models` are pure Kotlin JVM modules; Android types stay
  in `core-audio`, `core-inference`, the bridges and the apps. The native engine sits behind the
  `AudioEngineNative` interface so the controller is tested with a fake.
* **Cross-language contracts** (parameter IDs/ranges, stats indices) are mirrored in Kotlin and C++
  and enforced by tests that parse the C++ headers (`VoiceParameterContractTest`,
  `NativeStatsContractTest`).

## Threads

| Thread | Work | Rules |
|---|---|---|
| Oboe output callback (real-time) | reads mic non-blocking, runs `DuplexProcessor`, writes output | no locks, no allocation, no logging, no JNI |
| Oboe monitor callback (optional) | pulls the processed voice from `MonitorBridge` for a second output | lock-free; never blocks the main callback |
| Oboe error thread | records disconnects/errors in atomics | |
| `VoiceShift-Inference` | pulls model-rate chunks, runs ONNX Runtime, pushes results | never touches the callback; JNI calls guarded by `workerMutex_` |
| `VoiceShift-UdpSender` | reads the output tap, sends UDP packets | |
| Coroutines (`Dispatchers.IO`) | native start/stop (blocking ~100–300 ms), file I/O, model import | |
| Main | Compose, ViewModels | |

Real-time ↔ worker communication uses `SpscRingBuffer` (lock-free, bounded, 64-bit stream positions
used as timestamps). Parameters are `std::atomic<float>` with a version counter; the callback copies
them once per block. Control calls (`setParam`, `setMode`, …) are stored by the engine even while
stopped and re-applied on every start.

## Audio engine

* **Full duplex on one clock:** the output stream is callback-driven (low-latency, exclusive when
  possible); the input stream is read non-blocking inside that callback (the technique of
  `oboe::FullDuplexStream`, implemented with Oboe's stable public API). Input that piles up due to
  clock drift is drained.
* **Formats:** 48 kHz requested, float, mono capture, stereo output (mono duplicated). Oboe's
  sample-rate/channel/format conversion covers devices that differ.
* **Mic modes:** Android input presets `VoicePerformance` (default), `VoiceRecognition`,
  `VoiceCommunication` (platform echo cancellation, more latency), `Unprocessed`.
* **Safety:** NaN/Inf input is sanitised and counted; a NaN inside the chain resets it and silences
  that block; a -1 dBFS limiter always ends the chain; mute and bypass are crossfaded (20 ms).
* **Neural path:** `AiBridge` resamples to the model rate, queues to the worker, upsamples the result
  and crossfades it in once primed. If the worker is late (`underrun`), the callback plays the DSP
  transform that runs in parallel — the "automatic safe bypass". If the model is persistently slower
  than real time or throws, the worker stops and the app switches back to DSP.

* **Monitor output (optional):** a second shared-mode output stream (e.g. headphones) receives the
  processed voice *before* the output mute through `MonitorBridge`, a lock-free queue that keeps its
  fill near two bursts: excess from clock drift is skipped, an empty queue re-primes. Losing the
  monitor never stops the main path. Android may refuse two simultaneous outputs on some phones; the
  app reports that instead of failing.

## Recovery

`VoiceEngineController` polls native stats every 50 ms. A `Disconnected` or `Error` state triggers up
to 5 reopen attempts with back-off. A selected device that disappeared falls back to the system
default; when it reappears, the engine switches back automatically. All of this is covered by
`VoiceEngineControllerTest`.

## Persistence

`files/settings.json`, `files/presets.json`, `files/models/index.json` + `files/models/<id>/model.onnx`,
`files/logs/voiceshift.log`. JSON writes are atomic (temp + rename); a corrupt file is moved aside and
defaults are used. Backups and device transfer are disabled so voice models never leave the device.

## Key decisions

| Decision | Why |
|---|---|
| Project in `VoiceShiftVR/` subfolder | The repository already hosts unrelated audio files; CI uses `working-directory`. |
| Phase vocoder + cepstral envelope instead of PSOLA | Independent pitch/formant control, deterministic and testable; PSOLA depends on fragile pitch marking. |
| 2048-point frames by default | 1024 points cannot resolve harmonics of ~100 Hz voices (verified by tests); 1024 kept as low-latency option. |
| Own minimal test harness for C++ | No network access needed to build tests; zero dependencies. |
| Optional second (monitor) stream | Lets you hear yourself while the main output feeds the Quest; failure is non-fatal. |
| `stream-v1` model contract | A complete, verifiable AI path today, without pretending RVC works. |
| Committed debug keystore | Phone-only users can update the app in place from each CI build. |
| arm64-v8a only by default | ONNX Runtime adds ~36 MB per ABI; Android 10+ phones and Quest 3S are arm64. |
