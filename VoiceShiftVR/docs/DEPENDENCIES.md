# Dependencies and licenses

All versions are pinned in `gradle/libs.versions.toml` and were resolved from Google Maven / Maven
Central on 2026-11-17. Everything is free and open source; no paid APIs or services are used.

## Build toolchain

| Tool | Version | License |
|---|---|---|
| Gradle (wrapper) | 9.9.1 | Apache-2.0 |
| Android Gradle Plugin | 9.5.1 | Apache-2.0 |
| Kotlin (+ Compose compiler, serialization plugins) | 2.4.21 | Apache-2.0 |
| KSP | 2.3.14 | Apache-2.0 |
| Android SDK platform / build-tools | 37.0 / 37.0.0 (targetSdk 36, minSdk 29) | Android SDK License |
| Android NDK | r28c (28.2.13676358) | Apache-2.0 and others (NDK notices) |
| CMake | 3.22.1 (SDK) | BSD-3-Clause |

targetSdk stays at 36 (latest is 37) until the app is tested against Android 17 behaviour changes.

## Runtime libraries (in the APK)

| Library | Version | License | Why |
|---|---|---|---|
| com.google.oboe:oboe | 1.11.0 | Apache-2.0 | Low-latency AAudio/OpenSL ES streams |
| com.microsoft.onnxruntime:onnxruntime-android | 1.32.0 | MIT | Neural engine (Engine B) |
| androidx.core:core-ktx | 1.19.1 | Apache-2.0 | Compat APIs (notifications, services) |
| androidx.activity:activity-compose | 1.13.0 | Apache-2.0 | Compose activity, permission launchers |
| androidx.lifecycle (runtime-compose, viewmodel-compose, service) | 2.11.0 | Apache-2.0 | Lifecycle-aware state |
| Compose BOM (ui 1.12.1, material3 1.4.0, material-icons-core 1.7.8) | 2026.09.00 | Apache-2.0 | UI |
| com.google.dagger:hilt-android | 2.60.1 | Apache-2.0 | Dependency injection |
| androidx.hilt:hilt-lifecycle-viewmodel-compose | 1.4.0 | Apache-2.0 | `hiltViewModel()` |
| kotlinx-coroutines | 1.11.0 | Apache-2.0 | Async work |
| kotlinx-serialization-json | 1.13.0 | Apache-2.0 | Presets, settings, model index |

## Test-only

| Library | Version | License |
|---|---|---|
| JUnit | 4.13.2 | EPL-1.0 |
| kotlinx-coroutines-test | 1.11.0 | Apache-2.0 |
| Robolectric | 4.18 | MIT |
| androidx.test.ext:junit | 1.3.0 | Apache-2.0 |
| Compose ui-test-junit4 / ui-test-manifest | BOM | Apache-2.0 |
| hilt-android-testing | 2.60.1 | Apache-2.0 |
| com.microsoft.onnxruntime:onnxruntime (desktop) | 1.32.0 | MIT |
| Python `onnx` (model generator script) | 1.19.0 | Apache-2.0 |

## CI actions

actions/checkout v7, actions/setup-java v6, gradle/actions/setup-gradle v6, actions/upload-artifact
v7, actions/setup-python v7 (all MIT).

## Project code

VoiceShift VR source is Apache-2.0 (see `LICENSE`). The DSP algorithms are original implementations
of published techniques (RBJ Audio EQ Cookbook filters; phase vocoder with identity phase locking after
Laroche & Dolson; cepstral envelope; minimum-statistics noise estimation). No third-party DSP code is
copied.

## Models

No model is bundled. Imported models keep their own licenses; the app shows `voiceshift.license`
metadata when present. Check every model's license and the speaker's consent before importing.
