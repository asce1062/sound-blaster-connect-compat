# arm64 patch

Adds `arm64-v8a` native libraries so the app can run on 64-bit-only devices
(Pixel 7/8 and other Tensor/ARMv9 phones that dropped the 32-bit execution
state). The `arm64` variant = `modernize` + this patch.

**This is the native bring-up track.** It is the hard part of "support recent
devices" and the reason the stock app shows *not compatible* on a Pixel: the
APK ships only 32-bit `.so` (`armeabi`, `armeabi-v7a`, `x86`), and a 64-bit-only
device cannot load any of them. Repackaging alone never fixes this.

Status: `libserialport_jni.so` is rebuilt for arm64-v8a and staged.
`libsbxapplogic_ctprotocol_jni.so` is scoped but not yet built, so the arm64
variant does not run on a 64-bit-only device yet. Full RE and the port plan are
in [docs/arm64/RE.md](../../docs/arm64/RE.md).

## The two libraries

Both are stripped 32-bit ARM ELF, no source shipped:

- `libsbxapplogic_ctprotocol_jni.so` — the **CtProtocol** JNI: the actual
  Sound Blaster command protocol. This is also what the own-app effort needs
  to understand, so the reverse engineering here feeds both.
- `libserialport_jni.so` — serial-port JNI (device transport helper).

## Producing arm64 builds

The libs are reimplemented from the RE and cross-compiled with the NDK. Both
are thin JNI over reconstructable logic, so a faithful rebuild is also the
protocol knowledge the own app needs.

```
native/
  serialport/serialport.c   serial-port JNI (done)
  ctprotocol/               CtProtocol JNI (to be added)
  CMakeLists.txt            NDK project for both libs
  build.ps1                 cross-compile -> overlay/lib/arm64-v8a/
overlay/lib/arm64-v8a/      built .so (Git LFS); apktool packs these as-is
```

Build: `pwsh patches/arm64/native/build.ps1` (needs the Android SDK cmake +
NDK; paths overridable via its params). apktool packs whatever is under
`lib/<abi>/` in the staged tree, so staging into the overlay is all that is
needed.

See [docs/arm64/RE.md](../../docs/arm64/RE.md) for the symbol inventory, the
command frame spec, and the port plan.
