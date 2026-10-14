# Android emulator for authorized mobile testing

Tooling to stand up a **headless** Android emulator on this machine so an agent can drive an
in-scope mobile app via `adb` and capture its traffic — no GUI required.

## Prerequisites

- **Hardware acceleration:** access to `/dev/kvm`. On this machine the device exists but is
  `root:kvm`; if your user is not in the `kvm` group the emulator is unusable. One-time fix (with
  your password):
  ```sh
  sudo usermod -aG kvm $USER   # then log out/in
  # or, immediate but not persistent:
  sudo chmod 666 /dev/kvm
  ```
- A JDK (17+) and `unzip`.

## Setup

```sh
sh tools/android/emulator-setup.sh
```

The script downloads the Android command-line tools and SDK **under `$HOME/android-sdk`** (no
root), accepts licences, installs `platform-tools`, `emulator`, `platforms;android-34` and the
`google_apis_playstore;x86_64` system image (Play Services included), and creates an AVD named
`bounty-play`. It refuses to run without KVM access and prints the fix.

To obtain an app's APK without a physical phone: sign in to the Play Store inside the emulator,
install the app, then extract it:

```sh
adb shell pm path <package>          # base.apk + split_*.apk
adb pull <each path>                 # exact store build, ready for static analysis
```

### Alternatively, no emulator: `apkeep` + a Google account

The Play download can be done directly, without installing the SDK/emulator:

1. One-time OAuth token: open `https://accounts.google.com/EmbeddedSetup`, DevTools → Network →
   the last `accounts.google.com` request → Cookies → `oauth_token` (starts `oauth2_4/`). It is
   **single-use and short-lived**.
2. Exchange it for the long-lived **AAS** token (apkeep prints it):
   `apkeep -e '<email>' --oauth-token '<oauth2_4/...>'`
3. Download (split bundle): `apkeep -a <package> -d google-play -e '<email>' -t '<aas>' --accept-tos -o split_apk=true <dir>`

Read the resulting version **without** the SDK (`aapt`/`apkanalyzer` need build-tools):
`python3 tools/android/axml-version.py <app.apk>`. Keep the credential only in a git-ignored `.env`.

## Run (headless)

```sh
ANDROID_HOME="$HOME/android-sdk" "$HOME/android-sdk/emulator/emulator" \
  -avd bounty -no-window -no-audio -gpu swiftshader_indirect -no-snapshot -writable-system &
adb wait-for-device
adb install -r /path/to/app.apk
adb shell
```

An agent can drive all of this from the CLI: `adb shell`/`adb exec-out`, screenshots
(`adb exec-out screencap -p`), logs (`adb logcat`), file pulls.

## Traffic capture / instrumentation (optional)

```sh
python3 -m pip install --user mitmproxy frida-tools
```

- **mitmproxy:** run `mitmproxy` on the host, point the emulator at the host proxy, and install the
  mitmproxy CA. On the `google_apis` image install it as a **user** CA
  (Settings → Security → Encryption & credentials → Install a certificate → CA certificate); apps
  targeting API 24+ ignore user CAs, so for full coverage use a **writable-system** image and
  `adb root && adb remount` to place the CA in `/system/etc/security/cacerts`.
- **Certificate pinning:** if the app pins, add `frida-server` and hook the pinning check, or use a
  patched build. Never report "no pinning" as a finding (out of scope for most programs).
- Export a HAR/PCAP and hand it to the analysis lane.

## Boundaries

- Only apps/assets that are **explicitly in scope** for the program, with accounts you own.
- No captcha bypass, no attacking third-party services, no submission from here.
- Record what you ran and the app version/hash with every capture.
