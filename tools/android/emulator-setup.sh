#!/usr/bin/env bash
# Set up a headless Android emulator for authorized mobile testing, entirely under $HOME (no root).
# Requires access to /dev/kvm. If access is missing it prints the one-time fix and exits.
# Usage: tools/android/emulator-setup.sh
set -eu

ROOT="${ANDROID_ROOT:-$HOME/android-sdk}"
KVM=/dev/kvm
echo "== preflight =="
if [ ! -e "$KVM" ]; then echo "/dev/kvm missing (no hardware acceleration)"; exit 2; fi
if [ ! -r "$KVM" ] || [ ! -w "$KVM" ]; then
  echo "No access to /dev/kvm. Run ONE of these (with your password, once):"
  echo "  sudo usermod -aG kvm \$USER    # then log out/in"
  echo "  sudo chmod 666 /dev/kvm         # immediate; resets on reboot"
  exit 2
fi
if ! command -v java >/dev/null; then echo "A JDK (17+) is required: sudo apt install openjdk-17-jdk"; exit 2; fi
if ! command -v unzip >/dev/null; then echo "unzip is required"; exit 2; fi

mkdir -p "$ROOT/cmdline-tools" "$ROOT/avd"
if [ ! -x "$ROOT/cmdline-tools/latest/bin/sdkmanager" ]; then
  echo "downloading Android command-line tools..."
  curl -sSL "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip" -o "$ROOT/clt.zip"
  unzip -q -o "$ROOT/clt.zip" -d "$ROOT/cmdline-tools"
  [ -d "$ROOT/cmdline-tools/cmdline-tools" ] && mv "$ROOT/cmdline-tools/cmdline-tools" "$ROOT/cmdline-tools/latest"
fi

export ANDROID_HOME="$ROOT" ANDROID_SDK_ROOT="$ROOT"
export PATH="$ROOT/cmdline-tools/latest/bin:$ROOT/platform-tools:$ROOT/emulator:$PATH"

yes | sdkmanager --sdk_root="$ROOT" --licenses >/dev/null 2>&1 || true
sdkmanager --sdk_root="$ROOT" "platform-tools" "emulator" "platforms;android-34" \
  "system-images;android-34;google_apis_playstore;x86_64"

if ! "$ROOT/cmdline-tools/latest/bin/avdmanager" list avd 2>/dev/null | grep -q "Name: bounty-play"; then
  echo no | avdmanager create avd -n bounty-play -k "system-images;android-34;google_apis_playstore;x86_64" -d pixel_6 --force
fi

cat <<EOT

Setup complete.

Start the emulator headless (no GUI needed):
  ANDROID_HOME="$ROOT" "$ROOT/emulator/emulator" -avd bounty-play -no-window -no-audio \\
      -gpu swiftshader_indirect -no-snapshot -writable-system &
  adb wait-for-device

Sign in to the Play Store inside the emulator, install an app, then extract it:
  adb install -r /path/to/app.apk
  adb shell pm list packages | grep <app>
  adb shell

Optional traffic capture / instrumentation:
  python3 -m pip install --user mitmproxy frida-tools
  # MITM: run 'mitmproxy', set the emulator HTTP proxy to <host-ip>:8080, install the CA
  # (writable-system image + adb root/remount) — see tools/android/README.md
EOT
