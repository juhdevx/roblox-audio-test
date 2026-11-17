#!/usr/bin/env bash
# Installs the Android SDK/NDK packages VoiceShift VR needs, without Android Studio.
# Used by the Codespaces dev container (.devcontainer) and usable on any Linux machine.
#
#   bash VoiceShiftVR/tools/setup-android-sdk.sh            # installs to $ANDROID_HOME or ~/android-sdk
#
# Idempotent: packages that are already installed are skipped by sdkmanager.
set -euo pipefail

SDK_ROOT="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/android-sdk}}"
CMDLINE_TOOLS_ZIP="commandlinetools-linux-16111833_latest.zip"
NDK_VERSION="28.2.13676358"
PACKAGES=("platform-tools" "platforms;android-37.0" "build-tools;37.0.0" "ndk;${NDK_VERSION}" "cmake;3.22.1")

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project="$(dirname "$here")"

mkdir -p "$SDK_ROOT/cmdline-tools"
if [ ! -x "$SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" ]; then
  echo "Downloading Android command-line tools…"
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/tools.zip" "https://dl.google.com/android/repository/${CMDLINE_TOOLS_ZIP}"
  unzip -q "$tmp/tools.zip" -d "$tmp"
  rm -rf "$SDK_ROOT/cmdline-tools/latest"
  mv "$tmp/cmdline-tools" "$SDK_ROOT/cmdline-tools/latest"
  rm -rf "$tmp"
fi

SDKMANAGER="$SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"
echo "Accepting SDK licenses…"
yes | "$SDKMANAGER" --sdk_root="$SDK_ROOT" --licenses > /dev/null || true
echo "Installing: ${PACKAGES[*]}"
"$SDKMANAGER" --sdk_root="$SDK_ROOT" --install "${PACKAGES[@]}" > /dev/null

echo "sdk.dir=$SDK_ROOT" > "$project/local.properties"
echo
echo "Android SDK ready at $SDK_ROOT"
echo "Add to your shell:  export ANDROID_HOME=$SDK_ROOT"
echo "Build:              cd VoiceShiftVR && ./gradlew assembleDebug"
