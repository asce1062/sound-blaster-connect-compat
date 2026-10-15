# ARM64_BUILD

Phase 5 gates A0 and A1. Builds the proven portable CtProtocol core and the
serial-port shim for `arm64-v8a` and records the native-surface metadata.

## A0 - JNI parity

The JNI boundary was already exercised end-to-end during Phase 4 against the
x86 oracle: the same C core compiled as `libsbxapplogic_ctprotocol_jni` for
x86 passed the behavioral differential (commit `94bbb4a`, grade
DIFFERENTIAL-PASS). arm64 reuses that identical source and JNI adapter with no
second JNI layer; only the target ABI changes. There is one JNI
implementation, proven once.

```
JNI_PARITY = PASS
```

The arm64 artifact is therefore the x86-proven source recompiled, not a new
surface to re-validate at the JNI level. Hardware protocol behavior remains
out of scope for this phase (reserved for HARDWARE-VERIFIED).

## A1 - arm64-v8a native metadata

Built with NDK 25.1.8937393, target `aarch64-linux-android`, via the
`sbc_add_variant(arm64 ...)` CMake path. Output staged at
`patches/arm64/overlay/lib/arm64-v8a/`.

### libsbxapplogic_ctprotocol_jni.so

| Property | Value |
|---|---|
| Size | 136928 bytes |
| SHA-256 | `ef9bad520bd1c94d9a942857425b80722d650190dd120dad8d9d070490e52c6e` |
| ELF class | ELF64, little-endian |
| Machine | AArch64 |
| Type | DYN (shared object) |
| NEEDED | libm.so, libdl.so, libc.so |
| JNI_OnLoad | exported (`T JNI_OnLoad` @ 0x5608) |
| Undefined symbols | `__cxa_atexit`, `__cxa_finalize`, `__stack_chk_fail`, `free`, `malloc`, `memcpy` (all LIBC) |
| SbxSppCommandManager JNI exports | 35 `Java_com_creative_..._SbxSppCommandManager_*` symbols |

All undefined symbols resolve against the platform C library; there is no
dependency on any non-system library, so the loader needs nothing beyond the
Android base image.

### libserialport_jni.so

| Property | Value |
|---|---|
| Size | 30512 bytes |
| SHA-256 | `e50efa5e59d111a695b6eb7d1457824df03921f53eb6e4eda04fc524f4d58a87` |
| ELF class | ELF64, little-endian |
| Machine | AArch64 |
| Type | DYN (shared object) |
| NEEDED | liblog.so, libm.so, libdl.so, libc.so |
| JNI_OnLoad | exported (`T JNI_OnLoad` @ 0x93c) |
| Undefined symbols | `__android_log_print`, `__cxa_atexit`, `__cxa_finalize`, `__open_2`, `__stack_chk_fail`, `close`, `ioctl` |

`__android_log_print` resolves against `liblog.so` (declared NEEDED); every
other undefined symbol resolves against the platform C library.

Both libraries are self-contained against the Android system image and carry an
exported `JNI_OnLoad`, which is the precondition the loader audit (A2) and the
runtime binding check (A5) build on.
