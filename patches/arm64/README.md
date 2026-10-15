# arm64 patch

Adds `arm64-v8a` native libraries so the app can run on 64-bit-only devices
(Pixel 7/8 and other Tensor/ARMv9 phones that dropped the 32-bit execution
state). The `arm64` variant = `modernize` + this patch.

**This is the native bring-up track** and is empty until the libraries exist.
It is the hard part of "support recent devices" and the reason the stock app
shows *not compatible* on a Pixel: the APK ships only 32-bit `.so`
(`armeabi`, `armeabi-v7a`, `x86`), and a 64-bit-only device cannot load any
of them. Repackaging alone never fixes this.

## The two libraries

Both are stripped 32-bit ARM ELF, no source shipped:

- `libsbxapplogic_ctprotocol_jni.so` — the **CtProtocol** JNI: the actual
  Sound Blaster command protocol. This is also what the own-app effort needs
  to understand, so the reverse engineering here feeds both.
- `libserialport_jni.so` — serial-port JNI (device transport helper).

## Producing arm64 builds

No source, so an arm64 `.so` has to come from one of:

1. **Recompile from recovered source** — if the JNI is thin and the heavy
   logic is reconstructable from the RE, reimplement the exported JNI
   functions and build for `arm64-v8a` with the NDK. Preferred: it is the
   same protocol knowledge the own app needs.
2. **Static recompilation / lifting** — last resort; brittle.

Drop the result at `overlay/lib/arm64-v8a/<name>.so`. apktool packs whatever
is under `lib/<abi>/` in the staged tree, so no CMake edit is needed once the
files are here.

See `docs/FINDINGS.md` for the JNI symbol inventory and RE notes as they land.
