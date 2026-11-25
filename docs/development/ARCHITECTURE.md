# Architecture

How the repository is organized and how a build turns the stock APK into the
variant APKs. The reasons behind the main choices are recorded as decisions in
[`docs/decisions/`](../decisions/).

## Repository layout

```
CMakeLists.txt         pipeline: input check, tool fetch, decode, variants, deploy
CMakePresets.json      configure preset and per-variant build presets
cmake/
  sbc_patches.cmake    variant framework (sbc_add_variant, sbc_add_resign_control)
  apply_patch.cmake    applies a patch list to a staged tree
  resign_control.cmake re-signs the stock archive without re-encoding it
  resign_verify.cmake  proves the re-signed payload is identical to stock
  sbc_native.cmake     locates the pinned NDK and builds the native libraries
  deploy_apk.cmake     adb install, launch and logcat watch
patches/
  modernize/           targetSdk 34 and the Android 12 to 14 fixes (patch.cmake, overlay/)
  arm64/               adds arm64-v8a libraries (patch.cmake) and their source (native/)
oracle/                Java mirror harness that runs a CtProtocol library on an x86 emulator
  vectors/             frozen encoder and decoder vectors (the behavioral contract)
tests/ctprotocol/      host regression: replays the vectors against the portable core
docs/                  documentation, see docs/README.md
inputs/                your stock APK (ignored by git)
```

## Build pipeline

1. **Input check.** Configure hashes `apk_input` and stops unless it is the
   1.04.02 release. It downloads apktool and uber-apk-signer and checks their
   hashes.
2. **Decode.** `apktool d` writes the pristine tree to `decompiled/`. Nothing
   modifies this tree afterwards.
3. **Variants.** Each variant is independent and has its own target:
   - `resign` (`sbc_add_resign_control`) does not use apktool. It copies the
     stock archive, aligns it only if needed, re-signs it, then extracts both
     archives and fails the build unless every non-signature entry is
     identical. It isolates the effect of signing from every other change.
   - `modernize` and `arm64` (`sbc_add_variant`) copy `decompiled/` to
     `build/<variant>/tree/`, apply their patches in order, rebuild with
     `apktool b` and sign with uber-apk-signer.
4. **Deploy.** Optional: installs one variant with adb, launches it and
   watches logcat.

## Patches

A patch is a directory `patches/<name>/` with either or both of:

- `overlay/`: files copied verbatim onto the staged tree, at paths that mirror
  the decoded layout (`smali/...`, `res/...`, `lib/<abi>/...`).
- `patch.cmake`: a CMake script run with `TREE` set to the staged tree, for
  edits that are not whole-file replacements.

Patches apply in the order a variant lists them, so `arm64` builds on
`modernize`. Every edit in `modernize/patch.cmake` asserts how many times its
anchor occurs. A stock tree that differs from 1.04.02 fails the build instead
of producing a partly patched APK.

## Native libraries

The stock APK ships its two native libraries for 32-bit ABIs only. The
`arm64` variant adds arm64-v8a builds compiled from source:

```
patches/arm64/native/
  CMakeLists.txt              NDK project for both libraries
  ctprotocol/core/            portable CtProtocol encoder and decoder: C11, no JNI, no OS calls
  ctprotocol/jni/             JNI adapter binding the core to the stock Java class
  serialport/serialport.c     libserialport_jni.so
```

The core holds all protocol behavior and compiles on any host, which is what
lets the same source run in the x86 oracle harness, in the host tests and on
arm64 devices. The JNI layer only marshals Java arrays and calls cached Java
callbacks. `sbc_native.cmake` builds the project with the pinned NDK during
the main build; `patches/arm64/patch.cmake` copies the outputs into
`lib/arm64-v8a/` of the staged tree. The stock 32-bit libraries stay in place.

Contracts: [CTPROTOCOL.md](../technical/CTPROTOCOL.md),
[JNI_INTERFACE.md](../technical/JNI_INTERFACE.md),
[NATIVE_LIBRARIES.md](../technical/NATIVE_LIBRARIES.md).

## Behavioral oracle

The stock x86 CtProtocol library is the reference for what the encoder and
decoder must do. `oracle/` holds a Java class with the stock class's exact
name, so either library binds to it; it drives a fixed set of inputs and
prints one deterministic line per result. The captured output of the stock
library is frozen in `oracle/vectors/`. A reimplementation is accepted when
its output matches. [TESTING.md](TESTING.md) describes both ways of running
the vectors.
