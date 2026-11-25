# Toolchain

What the build needs, what it fetches, and what the analysis work used.
Install steps and commands are in [BUILDING.md](BUILDING.md).

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
| Java | JDK 17+ (`javac`) | apktool 3.x, uber-apk-signer, oracle harness; `javac` compiles the patch Java sources (`patches/modernize/java/`) to Java 8 bytecode |
| CMake | 3.22+ | the pipeline (the Android SDK's `cmake/3.22.1` works) |
| Ninja | any | generator (bundled with the SDK's CMake) |
| Android NDK | `25.1.8937393` (r25b), exact | arm64-v8a native libraries; the revision is pinned so the build reproduces the validated binaries |
| Android build-tools | 33.0.1 | `zipalign` (resign), `d8` (oracle harness) |
| Android build-tools | `37.0.0`, exact | `d8` for the patch Java sources (every variant that applies `modernize`); `apksigner`, `zipalign`, `aapt2` for test-release and release signing ([SIGNING.md](SIGNING.md)) |
| Android SDK platform | `android-34`, exact | `android.jar` on the `javac` class path for the patch Java sources ([cmake/sbc_java.cmake](../../cmake/sbc_java.cmake)) |
| adb | any | deploy target, oracle harness |

The NDK is located from `-Dandroid_ndk`, `ANDROID_NDK_ROOT`, `ANDROID_NDK_HOME`,
or `ndk/25.1.8937393` under `ANDROID_SDK_ROOT`, `ANDROID_HOME` or the Android
Studio default SDK directory (`cmake/sbc_native.cmake`). Without it the
`arm64` variant is not generated; `resign` and `modernize` still build.

apktool decodes and builds with a framework directory inside the build tree
(`build/apktool-framework`, passed as `-p`), so it uses the framework bundled
in the pinned apktool jar and never a per-user framework cache. An older
cached framework lacks `android:usesPermissionFlags`, which the `modernize`
manifest uses.

The host regression tests (`tests/ctprotocol/`) need only CMake 3.20+ and a C11
compiler; they pass with MSVC and gcc.

## Analysis tools (not needed to build)

- Ghidra 12.x for the native reverse engineering recorded in
  [`docs/research/`](../research/).
- jadx for the Java and smali side.
- A 32-bit x86 Android emulator (API 30 `google_apis/x86` image) for the
  oracle harness in `oracle/`.
