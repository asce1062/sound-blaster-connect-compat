# JNI interface of libsbxapplogic_ctprotocol_jni

This document specifies the Java-facing surface of `libsbxapplogic_ctprotocol_jni.so` as built from [`patches/arm64/native/ctprotocol/jni/`](../../patches/arm64/native/ctprotocol/jni/): the 35 native methods of `com.creative.logic.sbxapplogic.vendor.sbx.SbxSppCommandManager`, how arguments and results are marshalled, what `JNI_OnLoad` caches, and which names the loader must be able to resolve. The protocol logic behind each method is in [CTPROTOCOL.md](CTPROTOCOL.md); how the library is built and packaged is in [NATIVE_LIBRARIES.md](NATIVE_LIBRARIES.md). Where this document and the C code disagree the code is correct. The JNI layer contains no protocol logic: every method converts its arguments, calls one core function and converts the result.

## Verification tags

| Tag | Meaning |
|---|---|
| **Oracle** | Reproduced by a recorded vector in [`oracle/vectors/`](../../oracle/vectors/) (file named in the row), run through the stock x86 library and through the x86 build of this source on the Android emulator. The two outputs are byte-identical on all six vector sets ([ENCODE_DIFFERENTIAL.md](../research/encoder/ENCODE_DIFFERENTIAL.md), [DECODE_DIFFERENTIAL.md](../research/decoder/DECODE_DIFFERENTIAL.md)). Only this tag covers the JNI glue itself. |
| **Host test** | Covered by CTest in [`tests/ctprotocol/`](../../tests/ctprotocol/). The suite builds the core, not the JNI glue; `ctp_regress.c` re-implements the marshalling rules below in its own code, so the glue is not executed. |
| **Device** | Observed on a Pixel 7a (Android 13) and a Galaxy S24 Ultra (Android 16), both 64-bit only ([ARM64_RUNTIME.md](../research/arm64/ARM64_RUNTIME.md)). Raw logs were not preserved; excerpts are in [`docs/research/arm64/runtime/`](../research/arm64/runtime/). |
| **Static** | Read from the C source or the stock binary. **Static (unrecorded)** marks a claim resting on a probe sweep or decompilation note that is not stored in this repository. |

No oracle vector has been run on arm64: the harness requires a 32-bit x86 runtime. The arm64 JNI glue is the same source as the x86 glue that passed the differential, plus the **Device** observation that every method binds and the live SPP session runs.

## Class and binding

| Item | Value |
|---|---|
| Java class | `com.creative.logic.sbxapplogic.vendor.sbx.SbxSppCommandManager` |
| Binding | Static export by name: each method is the C function `Java_com_creative_logic_sbxapplogic_vendor_sbx_SbxSppCommandManager_<method>`. There is no `RegisterNatives` call in this library. |
| Visibility | The library is built with hidden default visibility; only the `JNIEXPORT` functions and `JNI_OnLoad` are exported. |
| Method kind | All 35 methods are `private static native`. |
| Library | `libsbxapplogic_ctprotocol_jni.so`, loaded from the class initializer ([loading](#library-name-and-loading)). |

Basis: **Static** (JNI source), **Device** (no `UnsatisfiedLinkError` on either device; `[handleProtocolEvent]` log lines show the class running), **Oracle** (the harness calls every method by name through the mirror class).

## Native methods

The stock Java class declares 35 native methods in this build. 34 are encode-side, of which 33 return a frame as `byte[]` and one returns an `int`. The 35th is `decode`. The mirror class used by the harness ([`oracle/src/.../SbxSppCommandManager.java`](../../oracle/src/com/creative/logic/sbxapplogic/vendor/sbx/SbxSppCommandManager.java)) declares exactly these signatures.

The stock `.so` exports 41 `Java_` symbols. Six have no Java declaration in this APK and are not reimplemented: `requestControl`, `getMalcolmParam`, `setAudioLvl`, `getAudioLvlRange`, `getAudioCtrlInfo`, `setHwBtnWithSaveState`. Their absence is safe for this APK because nothing in it declares them, and a missing implementation would only matter if a declared native had no export. **Static** (symbol comparison with the stock library in [RE.md](../research/arm64/RE.md)).

### Frame getters with no argument (20)

Each returns the constant frame of the named core function. Reject behavior: none, these cannot fail. Frame bytes are in [CTPROTOCOL.md](CTPROTOCOL.md#fixed-getters-no-argument-constant-frame). Basis for all rows: **Oracle** (`enc_stock.txt`), **Host test** (`enc_stock`).

| Java signature | Core function |
|---|---|
| `byte[] getMaxPayloadSize()` | `ctp_getMaxPayloadSize` |
| `byte[] getGeneralInfo()` | `ctp_getGeneralInfo` |
| `byte[] getDeviceFwString()` | `ctp_getDeviceFwString` |
| `byte[] releaseControl()` | `ctp_releaseControl` |
| `byte[] commitSettings()` | `ctp_commitSettings` |
| `byte[] getHwBtn()` | `ctp_getHwBtn` |
| `byte[] getHwBtnSupport()` | `ctp_getHwBtnSupport` |
| `byte[] getHwBtnStatusSupport()` | `ctp_getHwBtnStatusSupport` |
| `byte[] hwBtnEnabled()` | `ctp_hwBtnEnabled` |
| `byte[] getBatteryLevel()` | `ctp_getBatteryLevel` |
| `byte[] getBatteryLevelSupport()` | `ctp_getBatteryLevelSupport` |
| `byte[] getBatteryStatus()` | `ctp_getBatteryStatus` |
| `byte[] getBatteryStatusSupport()` | `ctp_getBatteryStatusSupport` |
| `byte[] getBtAutoConnect()` | `ctp_getBtAutoConnect` |
| `byte[] getVoicePromptCtrl()` | `ctp_getVoicePromptCtrl` |
| `byte[] resetFactoryDefault()` | `ctp_resetFactoryDefault` |
| `byte[] cancelFileTransfer()` | `ctp_cancelFileTransfer` |
| `byte[] getProfileInfoRec()` | `ctp_getProfileInfoRec` |
| `byte[] getActiveProfileRec()` | `ctp_getActiveProfileRec` |
| `byte[] getActiveProfileMega()` | `ctp_getActiveProfileMega` |

### Builders with one integer argument (8)

The Java `int` is passed to the core unchanged. A core reject returns an empty `byte[]`. Domains are in [CTPROTOCOL.md](CTPROTOCOL.md#builders-with-arguments). Basis for all rows: **Oracle** (`enc_stock.txt`), **Host test**.

| Java signature | Core function | Rejects (empty `byte[]`) |
|---|---|---|
| `byte[] getFwInfo(int)` | `ctp_getFwInfo` | outside 0..255 |
| `byte[] getAudioLvl(int)` | `ctp_getAudioLvl` | outside 0..255 |
| `byte[] setBtAutoConnect(int)` | `ctp_setBtAutoConnect` | not 0 or 1 |
| `byte[] setVoicePromptCtrl(int)` | `ctp_setVoicePromptCtrl` | not 0, 1 or 2 |
| `byte[] setActiveProfileRec(int)` | `ctp_setActiveProfileRec` | outside 0..255 |
| `byte[] setActiveProfileMega(int)` | `ctp_setActiveProfileMega` | outside 0..255 |
| `byte[] setActiveProfileRecVoicePreview(int)` | `ctp_setActiveProfileRecVoicePreview` | outside 0..255 |
| `byte[] setActiveProfileMegaVoicePreview(int)` | `ctp_setActiveProfileMegaVoicePreview` | outside 0..255 |

### Other encode methods (6)

| Java signature | Core function | Reject behavior | Basis |
|---|---|---|---|
| `byte[] setTime(int)` | `ctp_setTime` | none; every int is accepted | **Oracle** (`enc_stock.txt`) |
| `byte[] setHwBtn(int, int)` | `ctp_setHwBtn` | empty `byte[]` when the first argument is outside 1..20 or the second is not 0 or 1 | **Oracle** |
| `byte[] setFileSize(int, int)` | `ctp_setFileSize` | empty `byte[]` when the first argument is not 1 | **Oracle** |
| `byte[] getFileDataBlk(byte[] data, int len, boolean flag)` | `ctp_getFileDataBlk` | empty `byte[]` for a null `data`, `len` outside 1..253, or fewer than `len` source bytes | **Oracle** for the `len` domain; the null and short-array rejects are **Static** and not vector-covered |
| `byte[] setMalcolmParam(int[] a, int[] b, float[] c, int d, int[] e)` | `ctp_malcolm_size` then `ctp_setMalcolmParam` | empty `byte[]` for unequal array lengths or any core reject; `e` untouched on reject | **Oracle** (`enc_stock.txt` `grp_*`, `mix_reject`, `len_mismatch`) |
| `int getFileTransferMaxDataSize()` | none; returns the constant 253 | none | **Oracle** (`INT` row) |

### Decoder entry (1)

| Java signature | Core function | Result |
|---|---|---|
| `boolean decode(byte[] frame, int len)` | `ctp_decode` | `false` only when the core returns `CTP_DECODE_UNRECOGNIZED` (`0x0b`); otherwise `true` |

Basis: **Oracle** (`dec_*.txt`, `ret=` field), **Host test** (the core status). Behavior of the core is in [CTPROTOCOL.md](CTPROTOCOL.md#decoder).

### Count

| Group | Methods |
|---|---|
| No-argument frame getters | 20 |
| One-integer-argument builders | 8 |
| `setTime`, `setHwBtn`, `setFileSize`, `getFileDataBlk`, `setMalcolmParam` | 5 |
| `getFileTransferMaxDataSize` | 1 |
| Exported by the encode source file | 34 |
| `decode` (decode source file) | 1 |
| Total | 35 |

The research records give both 34 and 35. 34 is the encode-side count; 35 includes `decode`. Two summaries omit `getHwBtn` from their name lists; the code and the mirror class declare it. Static.

## Marshalling

These rules are in the JNI source. All are **Static**; the rules marked **Oracle** are also pinned by a vector.

| Rule | Detail | Basis |
|---|---|---|
| Frame result | A core length of 0 or more becomes a `byte[]` of exactly that length. A negative length becomes an empty `byte[]` (length 0), never null. A zero-length success is also an empty `byte[]`. | **Oracle** (`enc_stock.txt`: empty rows) |
| Core buffer | Frame getters build into a fixed 258-byte stack buffer (`CTP_CAP`). `setMalcolmParam` allocates `ctp_malcolm_size(n, d)` bytes on the heap. | **Static** |
| Integers | `jint` is passed as `int` with no clamping or narrowing; the core owns the domain check. | **Oracle** |
| `getFileDataBlk` source array | The Java array is copied into a 256-byte local, truncated at 256. A `len` above the array length, or above 253, is rejected by the core. A null array returns an empty `byte[]`. | **Oracle** (`len` domain), **Static** (null; the stock marshalling reportedly aborts on a null array, so this is an unexercised divergence) |
| `getFileDataBlk` flag | The `boolean` is passed as 0 or 1. | **Oracle** |
| `setMalcolmParam` arrays | `a`, `b` and `c` must have equal length; otherwise an empty `byte[]`. They are copied to heap buffers, `n` is the common length, and the buffers are released before returning. A null `a`, `b` or `c` is not guarded and is outside the Java contract. | **Oracle** (`len_mismatch`), **Static** (null) |
| `setMalcolmParam` output array | `e`, when non-null and of length 2 or more, receives the two output counters (`e[0]` = byte count of the last group, `e[1]` = group count) only on success. A shorter or null `e` is left unwritten. Stock behavior for a short `e` is not recorded. | **Oracle** (length-2 `e`), **Static** (short `e`, unrecorded versus stock) |
| `decode` input | `len` is clamped to 0..258. A zeroed 258-byte buffer receives the first `min(len, array length)` bytes of the Java array. The core is called with the clamped `len`, not with the copied length, so a `len` above the array length decodes against zero padding. | **Oracle** (`dec_entry.txt`: exact-length cases), **Static** (over-length and above-258 cases, not vector-covered) |
| `decode` result | `result != 0x0b`. | **Oracle** |
| Callback arguments | Events are delivered by `CallStaticVoidMethod` with the signatures in the next section. Booleans are `jboolean`; `LE16` values are non-negative `jint`; `LE32` values are signed. | **Oracle** (`dec_valid.out.txt`) |
| `dataAck` payload | A new `byte[8]` is built per event. | **Oracle** (`dec_valid.txt`) |
| `devicefwString` payload | A new `int[64]` is built per event, each element 0..255. | **Oracle** |
| Allocation failure | If `NewByteArray` or `NewIntArray` returns null, that event is skipped silently. Pending Java exceptions are not checked. | **Static** |
| Threading | The core keeps no state. The JNI layer uses the `JNIEnv` of the calling thread and a global class reference created in `JNI_OnLoad`; concurrent calls are independent. | **Static** |

The out-of-contract inputs in the `decode` row cannot occur with real frames: an 8-bit length byte bounds a real frame at 258 bytes, and the Java caller passes the array length. With `frame[2] == 255` the clamp lets a 258-byte frame pass the length check where stock arithmetic would reject it. Static.

## JNI_OnLoad and the callback cache

`JNI_OnLoad` runs at library load and either caches everything or fails the load:

1. Obtain `JNIEnv` with `GetEnv(JNI_VERSION_1_6)`.
2. Resolve `com/creative/logic/sbxapplogic/vendor/sbx/SbxSppCommandManager` with `FindClass` and keep a global reference.
3. Resolve 28 static callback method IDs with `GetStaticMethodID`.
4. Return `JNI_VERSION_1_6` when all 28 resolve. Return -1 when any step fails, which makes `System.loadLibrary` throw `UnsatisfiedLinkError`.

There is no `JNI_OnUnload`; the global reference lives for the process. **Static**, **Device** (the library loads and the cache resolves on both devices).

The 28 callbacks are `private static` methods of the Java class. The "Reachable" column states whether the core can emit an event for the callback.

| # | Callback | Signature | Reachable | Opcode and selector |
|---|---|---|---|---|
| 1 | `requestControlCallback` | `(Z)V` | yes | `0x06` |
| 2 | `dataAckCallback` | `(II[B)V` | yes | `0x02`, 13 bytes |
| 3 | `obsoleteAckCallback` | `(II)V` | yes | `0x02`, 5 bytes |
| 4 | `pendingAckCallback` | `(III)V` | yes | `0x02`, 7 bytes |
| 5 | `fileAckCallback` | `(III)V` | yes | `0x02`, 6 bytes |
| 6 | `deviceInfoCallback` | `(II)V` | yes | `0x07`, 7 or 19 bytes |
| 7 | `fwInfoCallback` | `(IIIII)V` | yes | `0x07`, 9 bytes |
| 8 | `maxPlsCallback` | `(I)V` | yes | `0x03` |
| 9 | `hwBtnCallback` | `(IZZZZZZZ)V` | yes | `0x26`, sub 1 |
| 10 | `audioCtrlCallback` | `(IZ)V` | no | none |
| 11 | `audioLvlCallback` | `(IFI)V` | yes | `0x23` |
| 12 | `audioLvlRangeCallback` | `(IFFFIII)V` | yes | `0x22` |
| 13 | `batteryLevelCallback` | `(I)V` | yes | `0x27`, sub 1 |
| 14 | `batteryLevelSupportCallback` | `(III)V` | yes | `0x27`, sub 2 |
| 15 | `batteryStatusCallback` | `(ZZ)V` | yes | `0x28`, sub 1 |
| 16 | `batteryStatusSupportCallback` | `(ZZ)V` | yes | `0x28`, sub 2 |
| 17 | `hwBtnSupportCallback` | `(IZZZZZZZ)V` | yes | `0x26`, sub 2 |
| 18 | `hwBtnStatusSupportCallback` | `(IZZZZZZZ)V` | yes | `0x26`, sub 3 |
| 19 | `hwBtnEnabledCallback` | `(IZZZZZZZ)V` | yes | `0x26`, sub 4 |
| 20 | `sbxProfileInfoCallback` | `(II)V` | no | none |
| 21 | `sbxProfileDataCallback` | `(I)V` | no | none |
| 22 | `btAutoConnectCallback` | `(I)V` | yes | `0x31` |
| 23 | `devicefwStringCallback` | `([I)V` | yes | `0x07`, 67 bytes |
| 24 | `profileInfoRecFirstCallback` | `(IIIZIZZIZ)V` | yes | `0x19`, first-record form |
| 25 | `profileInfoRestCallback` | `(IIZIZZIZ)V` | yes | `0x19`, rest form |
| 26 | `activeProfileRecCallback` | `(IZ)V` | yes | `0x1a`, sub 1 |
| 27 | `activeProfileMegaCallback` | `(IZ)V` | yes | `0x1a`, sub 2 |
| 28 | `voicePromptCtrlCallback` | `(I)V` | yes | `0x99` |

25 callbacks are reachable. `audioCtrlCallback`, `sbxProfileInfoCallback` and `sbxProfileDataCallback` are cached so that the load matches the stock library and the Java class must declare them, but no stock dispatcher path reaches them and the core has no event for them. This is a **Static (unrecorded)** finding: no vector produces them, which is consistent with, not proof of, unreachability ([DECODE_CALLBACK_MATRIX.md](../research/decoder/DECODE_CALLBACK_MATRIX.md)). Argument mapping per event is in [CTPROTOCOL.md](CTPROTOCOL.md#dispatch-table).

Signature and name basis: **Oracle** (the mirror class declares the same 28 methods and the differential output names each callback that fires), **Static** (the cache table in `ctprotocol_jni_decode.c`).

Consequences of the all-or-nothing load:

- A Java class that lacks any of the 28 static methods, or declares one with a different signature, makes `JNI_OnLoad` return -1. In the stock APK all 28 exist. **Static**
- A failed load is not recoverable by the library; the Java class initializer's fallback applies ([loading](#library-name-and-loading)).

## Library name and loading

| Item | Value | Basis |
|---|---|---|
| File name | `libsbxapplogic_ctprotocol_jni.so` | **Static** |
| Java load call | `System.loadLibrary("sbxapplogic_ctprotocol_jni")` in the `<clinit>` of `SbxSppCommandManager`, with a fallback `System.load("/system/lib/libsbxapplogic_ctprotocol_jni.so")` | **Static** (stock Java) |
| Fallback path | A 32-bit system path; the fallback cannot load a 64-bit library and exists only for the stock 32-bit environment. | **Static** |
| Search | The platform linker resolves `loadLibrary` in the APK's `lib/<abi>/` for the process ABI. | **Device** (loads on 64-bit-only devices) |
| Dependencies | `NEEDED`: `libm.so`, `libdl.so`, `libc.so`. No C++ runtime. The stock library additionally needs `libstdc++`. | **Static** (arm64 ELF dynamic section, [ARM64_RUNTIME.md](../research/arm64/ARM64_RUNTIME.md)) |
| Load failure | `UnsatisfiedLinkError` from `loadLibrary` (library missing for the ABI, unresolved dependency, or `JNI_OnLoad` returning -1) | **Static** |
| First use | Any native method call on the class triggers `<clinit>`; no native method may be called before the load completes. | **Static** |

Expectations on the host application:

- The APK must carry `lib/<abi>/libsbxapplogic_ctprotocol_jni.so` for the ABI the process runs as. The arm64 variant adds `lib/arm64-v8a/` ([NATIVE_LIBRARIES.md](NATIVE_LIBRARIES.md)).
- The Java class must keep the 35 native declarations above (or a subset; unused exports are harmless) and the 28 callbacks with the listed signatures. Renaming the class or package breaks static binding.
- Callers must pass buffers shaped as described under [Marshalling](#marshalling); the Java layer is responsible for assembling complete frames before `decode` ([CTPROTOCOL.md](CTPROTOCOL.md#entry-contract)).

## Verification gaps

- The JNI glue is covered by the x86 emulator differential only. The host CTest runs the core, not the glue, and no arm64 oracle run exists. arm64 glue behavior rests on identical source and the device runs.
- The null `getFileDataBlk` array, the null `setMalcolmParam` arrays, a short `e` array, an over-length `decode` `len` and a `decode` `len` above 258 have no vector. The first has a known divergence from stock (stock aborts the VM; this library returns an empty `byte[]`).
- Callback behavior under allocation failure and pending exceptions is untested.
- Device runs bound all methods and exercised live `decode` calls, but no systematic hardware comparison of encode or decode output was made ([ARM64_VERDICT.md](../research/arm64/ARM64_VERDICT.md)).

## Where the research records are superseded

| Record statement | Current behavior (code) |
|---|---|
| `e` must have length 2 or more ([ENCODE_SPEC.md](../research/encoder/ENCODE_SPEC.md)) | `e` is written only when `e` is non-null and has two or more elements; a shorter array is left unwritten and no error is raised |
| A null data array aborts the VM in the stock marshalling ([ENCODE_VECTORS.md](../research/encoder/ENCODE_VECTORS.md)) | This library returns an empty `byte[]` |
| 34 versus 35 native methods, with `getHwBtn` missing from some name lists ([FREEZE.md](../research/arm64/FREEZE.md), [CHECKPOINT.md](../research/arm64/CHECKPOINT.md)) | 35 natives including `getHwBtn` and `decode`; 34 are exported by the encode source file |
| 41 exports ([RE.md](../research/arm64/RE.md)) | 41 is the stock library's export count; this library binds the 35 that the APK declares |
| `dec_valid.txt` comments describe `hwBtn` callbacks as `(i,byte[])` | The signature is `(IZZZZZZZ)V` |

## Sources

- [`patches/arm64/native/ctprotocol/jni/ctprotocol_jni.c`](../../patches/arm64/native/ctprotocol/jni/ctprotocol_jni.c) and [`ctprotocol_jni_decode.c`](../../patches/arm64/native/ctprotocol/jni/ctprotocol_jni_decode.c)
- [`oracle/src/com/creative/logic/sbxapplogic/vendor/sbx/SbxSppCommandManager.java`](../../oracle/src/com/creative/logic/sbxapplogic/vendor/sbx/SbxSppCommandManager.java) (mirror declaring the 35 natives and 28 callbacks); [`oracle/README.md`](../../oracle/README.md); [`oracle/vectors/`](../../oracle/vectors/)
- [`tests/ctprotocol/ctp_regress.c`](../../tests/ctprotocol/ctp_regress.c)
- [ENCODE_SPEC.md](../research/encoder/ENCODE_SPEC.md), [ENCODE_VECTORS.md](../research/encoder/ENCODE_VECTORS.md), [ENCODE_DIFFERENTIAL.md](../research/encoder/ENCODE_DIFFERENTIAL.md), [DECODE_IMPLEMENTATION.md](../research/decoder/DECODE_IMPLEMENTATION.md), [DECODE_CALLBACK_MATRIX.md](../research/decoder/DECODE_CALLBACK_MATRIX.md), [DECODE_ENTRY.md](../research/decoder/DECODE_ENTRY.md), [DECODE_DIFFERENTIAL.md](../research/decoder/DECODE_DIFFERENTIAL.md)
- [FREEZE.md](../research/arm64/FREEZE.md), [RE.md](../research/arm64/RE.md), [ARM64_RUNTIME.md](../research/arm64/ARM64_RUNTIME.md), [ARM64_VERDICT.md](../research/arm64/ARM64_VERDICT.md)
- Companion documents: [CTPROTOCOL.md](CTPROTOCOL.md), [NATIVE_LIBRARIES.md](NATIVE_LIBRARIES.md)
