# Roadmap and phase status

"Done" means implemented **and** covered by automated tests that ran. Hardware criteria are only
marked done after execution on real devices — none has been yet.

| Phase | Deliverable | Status | Evidence / what is missing |
|---|---|---|---|
| P0 | Android project skeleton | **Done** | 9-module Gradle build; GitHub Actions run #1 green with APK artifacts |
| P1 | Microphone capture | **Implemented, device test pending** | Oboe duplex engine compiles for all ABIs; capture path unit-tested via `DuplexProcessor`; M1–M4 not run |
| P2 | DSP voice engine | **Done (algorithmic)** | 45 native tests incl. pitch ±1 %, formant shift, NR, identity, pitch tracking; listening tests on a phone pending |
| P3 | Audio monitoring | **Implemented, device test pending** | Output stream, mute/bypass crossfades, feedback warning |
| P4 | Device routing | **Implemented, device test pending** | Device lists, explicit selection, recovery + restore tested with fakes; M4–M6 not run |
| P5 | Presets and settings | **Done** | Built-ins + user presets, atomic JSON, corruption recovery (tests) |
| P6 | ONNX infrastructure | **Done for stream-v1** | Real ONNX Runtime validation/inference/worker tests; RVC detected but unsupported |
| P7 | Quest USB bridge | **Phone side done; path unverified** | Route checks, tone, probe, Quest Lab tone detector; M7 not run |
| P8 | Roblox validation | **Not started on hardware** | Procedure and in-app recording ready; M8 not run |
| P9 | Native Quest research | **Research app ready** | Quest Lab local DSP benchmark; feasibility data not yet collected |
| P10 | Performance optimisation | **Instrumented** (+ live pitch tracking) | Callback load, xruns, latency estimate, probe, CPU/memory/thermal; no on-device benchmarks yet |
| P11 | Documentation and release | **Done for debug builds** | README, docs, CI artifacts; no signed release build |

## Next engineering milestones

1. **First on-device run** (any Android 10+ phone with wired headphones): M1–M4, M9, M12; tune
   default preset by ear; record callback load for both DSP qualities.
2. **Route A hardware trial**: try wiring A1 with a capture-capable USB-C adapter on the Quest;
   fill stages 1–3; document the exact adapter models that work.
3. **Roblox in-game confirmation** (M8) with a second account.
4. ~~Second monitor output~~ — **done** (needs device testing, M17).
5. ~~Pitch detection and calibration~~ — **done** (needs listening tests, M18).
6. **RVC pipeline**: ContentVec encoder + RMVPE F0 + synthesizer as three ONNX sessions with a
   validated hop/sample-rate plan, NNAPI/XNNPACK execution providers, and a real-time-factor gate.
7. **Lower latency DSP**: 1536/1024-point frames with multi-resolution analysis for low voices.
8. **Release signing** via GitHub Actions secrets and an R8-minified release APK.
9. **Instrumented tests** on an emulator (CI with KVM) for permission and lifecycle flows.
10. **targetSdk 37** after reviewing Android 17 behaviour changes.
