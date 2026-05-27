# Getting Started

## Prerequisites

### Rust

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
rustup target add aarch64-apple-ios aarch64-apple-ios-sim  # iOS
rustup target add aarch64-linux-android                     # Android
```

### Git Submodules

```bash
git submodule update --init --recursive
```

### iOS

- Xcode 26+ (App Store) — `sudo xcodebuild -license accept`
- xcodegen: `brew install xcodegen`
- libimobiledevice: `brew install libimobiledevice` (for device logs)
- CocoaPods: `sudo gem install cocoapods`

### Android

- Android Studio / SDK (API 31+)
- Android NDK r25c+
- Set env vars:
  ```bash
  export ANDROID_NDK_ROOT=$HOME/Library/Android/sdk/ndk/<version>
  export ANDROID_HOME=$HOME/Library/Android/sdk
  ```
- `cargo install cargo-ndk`

## iOS Development

```bash
./scripts/run-ios.sh device          # full build + install + launch
./scripts/run-ios.sh sim             # simulator
./scripts/run-ios.sh device --release  # release build
./scripts/log-ios.sh                 # stream device logs
./scripts/log-ios.sh --filter zedra  # filtered logs
```

See `docs/IOS_WORKFLOW.md` for full pipeline details.

## Android Development

```bash
./scripts/build-android.sh                     # build Rust .so
cd android && ./gradlew installDebug && cd ..  # install APK
./scripts/log-android.sh start                 # background log monitor
./scripts/log-android.sh tail                  # view logs
```

Android release builds read signing credentials from Gradle properties. Gradle
loads `~/.gradle/gradle.properties` automatically, so a global config can use:

```properties
ZEDRA_KEYSTORE=/absolute/path/to/zedra-release.jks
ZEDRA_KEYSTORE_ALIAS=zedra
ZEDRA_KEYSTORE_PASSWORD=...
# Optional when the key password differs from the keystore password:
ZEDRA_KEY_PASSWORD=...
```

## Host Daemon

```bash
cargo run -p zedra-host -- start                    # start, show QR
cargo run -p zedra-host -- start --workdir ~/project  # specific directory
cargo run -p zedra-host -- start --detach           # keep running after SSH logout
cargo run -p zedra-host -- start --static-qr        # static startup QR for review/testing
cargo run -p zedra-host -- qr --workdir .           # refresh one-time QR
cargo run -p zedra-host -- qr --workdir . --static  # static QR for testing/store review
cargo run -p zedra-host -- logs --workdir .         # show recent daemon logs
cargo run -p zedra-host -- client                   # measure RTT
cargo run -p zedra-host -- stop                     # stop daemon
```

Scan the printed QR from the app, or pass the URL during development:

```bash
./scripts/run-ios.sh sim --no-build --launch-url 'zedra://connect?ticket=...'
```

### Windows Host CLI

Windows support is for the host daemon, not a native desktop client.

```powershell
powershell -c "irm https://zedra.dev/install.ps1 | iex"
zedra start --workdir C:\path\to\project --detach
zedra qr --workdir C:\path\to\project
zedra status --workdir C:\path\to\project
zedra logs --workdir C:\path\to\project
zedra client --workdir C:\path\to\project --count 3
zedra stop --workdir C:\path\to\project
```

Runtime files are stored under `%APPDATA%\zedra\workspaces\`. `daemon.lock` uses the lock hash for the workdir; `daemon.log`, `sessions.json`, `host-info.json`, and API discovery files use the stable workspace hash. Terminal sessions use `ZEDRA_SHELL` when set, otherwise Zedra detects the shell that launched the host, then falls back to `SHELL`, then `%ComSpec%` (`cmd.exe`). Supported launch shells are `cmd.exe`, `pwsh.exe`, `powershell.exe`, and Git Bash/POSIX-style shells.

To build from source instead, install the MSVC Rust toolchain and Git for Windows, then run `cargo build -p zedra-host`.

## Local Development Without Telemetry

Telemetry is disabled by default in local source builds. GA4 credentials (`ZEDRA_GA_MEASUREMENT_ID`, `ZEDRA_GA_API_SECRET`) are required only for release/distribution builds — if either is unset at compile time, the host produces a binary with telemetry silently disabled.

### Host (macOS / Linux)

Build and install a release binary without telemetry:

```sh
rm ~/.local/bin/zedra
cargo build --release -p zedra-host
cp target/release/zedra ~/.local/bin/zedra
codesign --force --sign - ~/.local/bin/zedra   # macOS only
```

The `rm` ensures a stale binary isn't left in `$PATH`. `codesign` is required on macOS to avoid Gatekeeper quarantine prompts.

Additional runtime opt-out if building with credentials present:

```sh
zedra start --no-telemetry              # CLI flag
ZEDRA_TELEMETRY=0 zedra start           # env var
zedra start --debug-telemetry           # log events to stderr instead of sending
```

### iOS App

Debug builds are telemetry-free by default:

- `GoogleService-Info.plist` is **optional** for debug — Firebase init becomes a no-op when absent.
- Release builds **require** the plist and will fail during Xcode build when it is missing.
- `debug-telemetry` Cargo feature logs event payloads to the Xcode console without sending to Firebase.

```sh
./scripts/run-ios.sh device                                # debug build (no telemetry)
./scripts/run-ios.sh device --debug-telemetry              # debug build, log events to console
```

### Android App

Debug builds disable Firebase collection at three layers — manifest placeholders, `BuildConfig.DEBUG` guard, and `ZedraFirebase.setCollectionEnabled()`:

```sh
./scripts/build-android.sh                                 # debug build (no telemetry)
./scripts/build-android.sh --debug-telemetry               # debug build, log events to logcat
```

Release builds require `android/google-services.json` and apply Firebase Gradle plugins automatically.

### Verifying Telemetry Is Off

| Check | Expected |
|-------|----------|
| Host: `zedra start` without GA4 env vars | No outbound HTTPS to GA4 |
| Host: `--debug-telemetry` flag | Events printed to stderr with `[telemetry]` prefix |
| iOS debug without `GoogleService-Info.plist` | Console: `Firebase disabled: GoogleService-Info.plist is not bundled` |
| Android debug build | `BuildConfig.DEBUG == true`, Firebase SDK collection disabled |

See `docs/TELEMETRY.md` for the full telemetry architecture.

## Pre-Commit Checks

```bash
cargo fmt
cargo check -p zedra-rpc -p zedra-session -p zedra-terminal -p zedra-host
```

## Troubleshooting

- **Black screen (Android)**: surface dimensions must be physical pixels. Check Vulkan 1.1+: `adb shell getprop ro.hardware.vulkan`
- **Submodule missing**: `git submodule update --init --recursive`
- **iOS provisioning**: check `DEVELOPMENT_TEAM` in `ios/project.yml`
- **Metal shader fail**: `xcodebuild -downloadComponent MetalToolchain`
