# arm64 patch

Adds `arm64-v8a` native libraries so the app runs on 64-bit-only devices
(Pixel 7/8, Galaxy S24 and other phones without a 32-bit execution state). The
`arm64` variant = `modernize` + this patch.

The stock APK ships only 32-bit `.so` (`armeabi`, `armeabi-v7a`, `x86`), which a
64-bit-only device cannot load, so the stock app reports *not compatible* there.
Repackaging alone does not change that; this patch adds 64-bit builds of both
libraries alongside the stock 32-bit ones, giving one APK for both kinds of
device.

Both libraries are reimplemented and built from source. The arm64 build has
been run on two 64-bit-only phones with a Katana speaker
([ARM64_RUNTIME.md](../../docs/research/arm64/ARM64_RUNTIME.md)); the
CtProtocol core matches the stock library on every frozen vector
([`oracle/vectors/`](../../oracle/vectors/)).

## The two libraries

- `libsbxapplogic_ctprotocol_jni.so`: the CtProtocol JNI, the Sound Blaster
  command protocol encoder and decoder. The JNI-free core is in
  `native/ctprotocol/core/`; the JNI glue in `native/ctprotocol/jni/`.
- `libserialport_jni.so`: serial-port JNI (device transport helper).

## Build

No prebuilt binary is tracked. The root CMake configure locates NDK
`25.1.8937393` (`cmake/sbc_native.cmake`), and building `apk-arm64` first
builds `native/` for arm64-v8a into `build/native/arm64-v8a/lib/`; `patch.cmake`
then copies both libraries into `lib/arm64-v8a/` of the staged tree.

```
native/
  CMakeLists.txt            NDK project for both libs
  serialport/serialport.c   serial-port JNI
  ctprotocol/core/          portable CtProtocol encode/decode (no JNI)
  ctprotocol/jni/           JNI binding to the stock Java class
patch.cmake                 copies the built libs into the staged tree
```

The output is stripped and built with `-ffile-prefix-map`, so it carries no
build-machine paths. With the pinned NDK the libraries are byte-identical
across source locations.

The JNI surface and library details are in
[NATIVE_LIBRARIES.md](../../docs/technical/NATIVE_LIBRARIES.md) and
[JNI_INTERFACE.md](../../docs/technical/JNI_INTERFACE.md); the command frame
format and the encoder and decoder contracts in
[CTPROTOCOL.md](../../docs/technical/CTPROTOCOL.md).
