# Building and installing from a phone

No computer is needed. GitHub Actions builds everything; Codespaces is optional for editing.

## 1. Get an APK from GitHub Actions
1. Push any change under `VoiceShiftVR/` (or open **Actions → VoiceShift VR Android → Run workflow**).
2. Wait for the run (about 10–15 minutes the first time, faster with the Gradle cache).
3. Open the run → **Artifacts**:
   * `voiceshift-vr-debug-apk` — the phone app
   * `voiceshift-quest-lab-debug-apk` — the experimental Quest app
   * `diagnostic-onnx-models` — pass-through models to test the AI engine
   * `ui-screenshots` — rendered screens from the UI test
   * `reports` — test and lint reports
4. Artifacts download as ZIP files. Extract with your phone's Files app.

*Run workflow* has an **all_abis** switch to also package 32-bit ARM and x86_64 (larger APK).

## 2. Install on the phone
1. Tap `app-android-debug.apk`. Android asks to allow installs from that app (browser/Files) — allow it.
2. If Play Protect warns about an unknown developer, choose *Install anyway* (it is a debug build you
   built yourself).
3. Updates from later CI runs install over the old version: all builds use the same committed debug
   key (`VoiceShiftVR/keystore/debug.keystore`, password `android`). That key is public on purpose —
   never use it for a store release.

## 3. Install the Quest Lab app on the headset (optional, experimental)
Sideloading needs the Quest in developer mode. Without a computer, options include installing from
the headset's browser download (if your Horizon OS version allows opening APKs from its file manager)
or using an Android phone with a sideloading tool over USB/Wi-Fi debugging. Methods change between OS
versions; follow Meta's current developer documentation.

## 4. Edit and build in Codespaces (optional)
1. On GitHub: **Code → Codespaces → Create codespace** (choose 4 cores).
2. The dev container installs JDK 21, Android SDK/NDK/CMake (`tools/setup-android-sdk.sh`), CMake,
   Ninja and the `onnx` Python package automatically.
3. In the terminal:
   ```bash
   cd VoiceShiftVR
   ./gradlew assembleDebug          # first build downloads ~1-2 GB of dependencies
   ./gradlew testDebugUnitTest :core-dsp:test :core-models:test
   ```
4. Commit and push; CI builds the installable APK.

## When CI fails
* Open the red step. Gradle prints the cause under **What went wrong**.
* `e: file:///…/Foo.kt:12:5 …` is a Kotlin compile error (file, line, column).
* `error:` lines in C/C++ output come from the native build; `tests/native` failures print the
  failing check with expected and actual values.
* Test failures: download the **reports** artifact and open `…/reports/tests/…/index.html`.
* `Could not resolve …` / HTTP 429: a temporary Maven outage or rate limit — re-run the job.
* The run summary page lists APK sizes and test counts, plus these hints when something failed.
