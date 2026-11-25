# Building

How to build the variant APKs from your own copy of the stock app, and how to
install one on a device. Tool versions and where they come from are in
[TOOLCHAIN.md](TOOLCHAIN.md); what each variant changes is in
[ANDROID_COMPATIBILITY.md](../technical/ANDROID_COMPATIBILITY.md).

## Requirements

| Tool | Needed for |
|---|---|
| Java 17 or later on `PATH` (or `-Djava_bin=`) | apktool 3.x and uber-apk-signer |
| CMake 3.22 or later and Ninja | the pipeline; the Android SDK's `cmake/3.22.1` ships both |
| `zipalign` from Android build-tools on `PATH` (or `-Dzipalign_bin=`) | the `resign` alignment check |
| Android NDK `25.1.8937393`, exactly | the `arm64` and `compat` variants only |
| `adb` on `PATH` (or `-Dadb_bin=`) | the `deploy` target only |
| Network access on the first configure | downloading apktool 3.0.3 and uber-apk-signer 1.3.0 |

The configure step downloads both jars into `build/tools/` and fails if a
SHA-256 does not match its pin.

The NDK is found through `-Dandroid_ndk=<root>`, `ANDROID_NDK_ROOT`,
`ANDROID_NDK_HOME`, or `ndk/25.1.8937393` under `ANDROID_SDK_ROOT`,
`ANDROID_HOME` or `%LOCALAPPDATA%/Android/Sdk`. Only an NDK whose
`source.properties` reports revision `25.1.8937393` is accepted. Install it from
the Android Studio SDK Manager, or from the command line:

| Command-line tools | Command |
|---|---|
| Android CLI (`cmdline-tools/latest/bin/android`) | `android sdk install ndk/25.1.8937393` |
| Older `sdkmanager` releases | `sdkmanager "ndk;25.1.8937393"` |

In current command-line tools `sdkmanager` is a wrapper around the Android CLI.
It does not accept `;`-separated package names, installs nothing and still
exits 0. Check that `ndk/25.1.8937393/source.properties` exists after
installing. Without the NDK,
configure prints a warning, `resign` and `modernize` still build, and the
`arm64` and `compat` variants are not defined.

## Input: the stock APK

The stock APK is third-party software. It is not in this repository and the
project does not distribute it. Supply your own copy of Sound Blaster Connect
1.04.02, for example pulled with adb from a device where it is installed:

```sh
adb shell pm path com.creative.apps.sbconnect
adb pull <path printed above> inputs/SBConnect_v1.04.02.apk
```

Place it at `inputs/SBConnect_v1.04.02.apk` (the `inputs/` directory is
ignored by git), or pass `-Dapk_input=<path>`. Configure checks its SHA-256
against
`fe1ffe0c93b6476ae6ed1d2cb6891cde2fbe206d4e898d6ad8c75222e9bf99be` and stops
on a mismatch: every patch anchors on the exact bytes of that release.

## Build

```sh
cmake --preset default                 # check the input, fetch tools, decode to decompiled/
cmake --build --preset apks            # every variant
cmake --build --preset resign          # one variant
cmake --build --preset modernize
cmake --build build --target apk-arm64 # needs the NDK; there is no preset for it
cmake --build build --target apk-compat # needs the NDK; the distributable build
```

If CMake or Ninja is not on `PATH`, call the SDK copies directly and name
Ninja explicitly:

```sh
<sdk>/cmake/3.22.1/bin/cmake -S . -B build -G Ninja -DCMAKE_MAKE_PROGRAM=<sdk>/cmake/3.22.1/bin/ninja
<sdk>/cmake/3.22.1/bin/cmake --build build --target apks
```

Outputs, in `build/`:

| File | Variant |
|---|---|
| `sbc_resign-aligned-debugSigned.apk` | `resign`: the stock archive re-signed, payload verified identical |
| `sbc_modernize-aligned-debugSigned.apk` | `modernize`: targetSdk 34 and the platform fixes |
| `sbc_arm64-aligned-debugSigned.apk` | `arm64`: `modernize` plus arm64-v8a libraries built from source |
| `sbc_compat-aligned-debugSigned.apk` | `compat`: `arm64` with the application ID `io.github.asce1062.sbconnect.compat`, label SB Connect Compat and the project version |
| `release.env` | the version metadata of [`cmake/sbc_version.cmake`](../../cmake/sbc_version.cmake) as `KEY=VALUE` lines |

Each signed APK has a matching `.idsig` file (APK Signature Scheme v4) next to
it. All variants are signed with a debug key by uber-apk-signer. Release
signing is not part of the build.

The project version is set once, in `project(VERSION)` of the root
`CMakeLists.txt`. The `compat` versionName and versionCode, the release tag
and the release file name are derived from it; the scheme is in
[APPLICATION_IDENTITY.md](../technical/APPLICATION_IDENTITY.md#versions).

`decompiled/` in the source tree holds the pristine apktool decode. Variants
never modify it; each build stages a fresh copy under `build/<variant>/tree/`.
Editing files in `decompiled/` re-stages the variants on the next build.

### Targets

| Target | Builds |
|---|---|
| `decode` | `decompiled/` |
| `apk-resign`, `apk-modernize`, `apk-arm64`, `apk-compat` | one variant |
| `native-arm64-v8a` | the two native libraries, into `build/native/arm64-v8a/lib/` |
| `apks` (default) | every defined variant |
| `deploy` | installs and launches one variant, see below |

### Cache variables

| Variable | Default | Meaning |
|---|---|---|
| `apk_input` | `inputs/SBConnect_v1.04.02.apk` | stock APK |
| `apk_input_sha256` | pinned hash | expected input hash; empty prints the actual hash and skips the check |
| `java_bin`, `zipalign_bin`, `adb_bin` | `java`, `zipalign`, `adb` | tool paths |
| `apktool_jobs` | `8` | apktool thread count |
| `android_ndk` | empty | NDK root; empty searches the environment |
| `ndk_version` | `25.1.8937393` | required NDK revision |
| `native_platform` | `android-21` | `ANDROID_PLATFORM` of the native libraries |
| `deploy_variant` | `resign` | variant installed by `deploy` |
| `deploy_debug` | `ON` | `ON` tails logcat until interrupted; `OFF` watches for `deploy_watch_timeout` seconds and fails on a crash |
| `deploy_watch_timeout` | `15` | watch window in seconds |
| `adb_serial` | empty | device serial for `deploy` |
| `sbc_package` | `com.creative.apps.sbconnect` | stock application ID of the `resign`, `modernize` and `arm64` variants. `deploy` launches the package of the chosen variant, so `compat` launches `io.github.asce1062.sbconnect.compat` |

## Install on a device

`deploy` installs the chosen variant with `adb install -r -d`, launches it and
shows logcat. The variant is a configure-time choice:

```sh
cmake -S . -B build -Ddeploy_variant=compat
cmake --build build --target deploy
```

`compat` is its own package and installs next to the stock app. The other
variants share the stock package name. Their debug signature differs from
Creative's, so Android refuses to install them over the stock app. A
debug-signed build from another machine may also carry a different key. When `install -r` fails, `deploy` uninstalls the
package and installs again; **the uninstall deletes the app's data on the
device**. To keep control of that step, install by hand instead:

```sh
adb install -r build/sbc_compat-aligned-debugSigned.apk
```

Which variant suits which device, and what to expect at first launch, is in
[INSTALLATION.md](../user/INSTALLATION.md).

## Tests

The protocol regression tests and the emulator differential are described in
[TESTING.md](TESTING.md).
