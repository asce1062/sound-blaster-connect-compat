# 16 KiB page-size emulator run

Validation record, 2026-11-26. Repository at `a5514d8` (the permission
lifecycle baseline). It records what a 16 KiB-page Android environment
established about the arm64 libraries and what it could not.

## Environment

| Item | Value |
|---|---|
| System image | `system-images;android-36;google_apis_ps16k;x86_64`, revision 7 |
| AVD | `sbc_ps16k`, headless (`-no-window`) |
| `getconf PAGE_SIZE` | `16384` |
| `ro.product.cpu.abilist` | `x86_64,arm64-v8a` |
| Native bridge | `libndk_translation.so` (Berberis, aarch64 guest) |
| Host | x86_64 Windows; the guest CPU is x86_64 |

The image runs x86_64 code natively. arm64 code runs only through the
translator. No arm64 CPU with 16 KiB pages was available, so native arm64
execution at 16 KiB pages was not established.

## Results

| Check | Result |
|---|---|
| Install of the debug-signed `compat` build | succeeds; `primaryCpuAbi=arm64-v8a` |
| Load of `libsbxapplogic_ctprotocol_jni.so` | the app's class loader namespace loads it (`nativeloader ... ok`); `/proc/<pid>/maps` shows it mapped at 16 KiB-aligned offsets with the arm64 `linker64` and `libndk_translation` mapped, so it ran translated |
| Load of `libserialport_jni.so` | not loaded: the app does not reach `SerialPort` |
| JNI calls by the app into the library | none observed; no speaker, so no connection path ran |
| ELF alignment of both arm64 libraries | every `PT_LOAD` aligned `0x4000` |
| Host regression driver (`ctp_regress`) built with the pinned NDK for x86_64, all seven suites | pass, native x86_64 execution |
| The same driver for arm64, all seven suites | pass, translated execution |
| x86_64 build of the JNI glue under a JNI test harness, all seven suites | pass |
| The real arm64 `.so` driven through an arm64 `app_process64` | no output; the run is not valid evidence and is not counted |

Each suite's output equals its frozen vector file in `oracle/vectors/`,
comment lines excluded, for both drivers: 14 comparisons.

## What it establishes

- The arm64 libraries are accepted by the Android 16 KiB-page loader path
  and map at 16 KiB-aligned offsets, under translation.
- The protocol core, compiled for x86_64 and arm64 with the pinned NDK,
  produces the frozen outputs on a 16 KiB-page system.

## What it does not establish

- Native arm64 execution on 16 KiB pages. A translated load goes through the
  translator's own loader, so it does not prove what the platform linker of
  a 16 KiB arm64 device does with the libraries.
- Any JNI call into the arm64 `.so` from the app, or any `serialport`
  behavior.

Verdict: NATIVE_16K_RUNTIME is a documented limitation. Raw logs and the
build scripts are kept outside the repository with the other runtime
evidence.
