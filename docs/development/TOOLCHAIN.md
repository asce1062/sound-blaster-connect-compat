# Tooling

What the build needs, what it fetches, and what the analysis work used.
Install steps and commands are in `BUILDING.md`.

## Fetched by the configure step (SHA-256 verified)

The CMake configure downloads these to `build/tools/` and fails on a hash
mismatch:

| Tool | Version | Source |
|---|---|---|
| apktool | 3.0.3 | github.com/iBotPeaches/Apktool release asset |
| uber-apk-signer | 1.3.0 | github.com/patrickfav/uber-apk-signer release asset |

## Required locally

| Tool | Version | Used for |
|---|---|---|
| Java | 17+ | apktool 3.x, uber-apk-signer, oracle harness |
| CMake | 3.22+ | the pipeline (Android SDK's `cmake/3.22.1` works) |
| Ninja | any | generator (bundled with the SDK's CMake) |
| Android NDK | `25.1.8937393` (r25b), exact | arm64-v8a native libraries; the revision is pinned so the build reproduces the validated binaries |
| Android build-tools | 33.0.1 | `zipalign`, `apksigner`, `d8` (oracle) |
| adb | any | deploy target, oracle harness |

The NDK is located from `-Dandroid_ndk`, `ANDROID_NDK_ROOT`, `ANDROID_NDK_HOME`,
or `ndk/25.1.8937393` under `ANDROID_SDK_ROOT`, `ANDROID_HOME` or the Android
Studio default SDK directory (`cmake/sbc_native.cmake`). Without it the
`arm64` variant is not generated; `resign` and `modernize` still build.

## Analysis tools (not needed to build)

- Ghidra 12.x for the native reverse engineering behind `docs/arm64/`.
- jadx for the Java/smali side.
- An x86 Android emulator (API 30) for the oracle harness in `oracle/`.
