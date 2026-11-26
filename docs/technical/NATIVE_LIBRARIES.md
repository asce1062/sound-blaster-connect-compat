# Native libraries

This document describes the two native libraries the arm64 variant adds to the APK, `libsbxapplogic_ctprotocol_jni.so` and `libserialport_jni.so`: which ABIs each variant ships, how the libraries are built from source with a pinned NDK, how they reach the APK, how the serial port library behaves, which stock 32-bit libraries are left untouched, what the loader expects, and which tests cover which part. The protocol behavior is in [CTPROTOCOL.md](CTPROTOCOL.md) and the Java-facing surface in [JNI_INTERFACE.md](JNI_INTERFACE.md). Where this document and the build files disagree the build files are correct.

## Verification tags

| Tag | Meaning |
|---|---|
| **Oracle** | Reproduced by a recorded vector in [`oracle/vectors/`](../../oracle/vectors/) run through the stock x86 library and the x86 build of this source on the emulator, with byte-identical output. |
| **Host test** | Covered by CTest in [`tests/ctprotocol/`](../../tests/ctprotocol/) on a 64-bit host. |
| **Device** | Observed on a Pixel 7a (Android 13) and a Galaxy S24 Ultra (Android 16), both 64-bit only ([ARM64_RUNTIME.md](../research/arm64/ARM64_RUNTIME.md)). Raw logs were not preserved; excerpts are in [`docs/research/arm64/runtime/`](../research/arm64/runtime/). |
| **Static** | Read from source, build files or recorded hashes. **Static (recorded)** marks a statement resting on a recorded hash or note that a rebuild has not re-derived. |

## Libraries

| Library | Purpose | Binding | Loaded by |
|---|---|---|---|
| `libsbxapplogic_ctprotocol_jni.so` | CtProtocol frame encoder and decoder behind `SbxSppCommandManager` | Static `Java_...` exports; `JNI_OnLoad` caches 28 callbacks ([JNI_INTERFACE.md](JNI_INTERFACE.md)) | `<clinit>` of `SbxSppCommandManager` |
| `libserialport_jni.so` | Raw tty open and close behind `com.creative.serialport.SerialPort` | `RegisterNatives` in `JNI_OnLoad` | `<clinit>` of `SerialPort`, inside a try/catch |

Both are reimplementations in C of the stock 32-bit libraries, built from the sources under [`patches/arm64/native/`](../../patches/arm64/native/). The ctprotocol library is portable C with no C++ runtime (the stock library links `libstdc++`). Its core is separable from the JNI glue and is what the host tests build. Basis: **Static**.

## ABIs shipped

| Variant | `lib/` entries | Native libraries |
|---|---|---|
| Stock APK | `armeabi`, `armeabi-v7a`, `x86` | 6 `.so` files (2 per ABI), all stock |
| `resign` | same | the 6 stock files, SHA-256 identical to the stock APK ([PIPELINE.md](../research/android/PIPELINE.md)) |
| `modernize` | same | the 6 stock files, SHA-256 identical to the stock APK |
| `arm64` | the stock ABIs plus `arm64-v8a` | 8 `.so` files: the 6 stock files plus the 2 libraries built here |

The stock APK also carries a non-ABI `lib/utility` entry, which no variant changes. The `arm64` row count is derived from the stock count plus the two added libraries; **Static**. Only `arm64-v8a` is built from source. No build exists for `x86_64`, and the stock `x86` libraries are not replaced. Device installs: the arm64 variant installs and launches on both 64-bit-only devices; the stock APK fails on them with `INSTALL_FAILED_NO_MATCHING_ABIS` (-113), which is the negative control. **Device**

## Build

### Inputs and pinned toolchain

| Item | Value |
|---|---|
| NDK | 25.1.8937393 (r25b), pinned in [`cmake/sbc_native.cmake`](../../cmake/sbc_native.cmake) |
| Platform | `android-21` (the minimum for any 64-bit ABI) |
| Build type | Release |
| Language | C11 |
| Symbol visibility | hidden by default; JNI entry points are marked `JNIEXPORT` |
| Path remapping | `-ffile-prefix-map=<source dir>=.` and `-ffile-prefix-map=<binary dir>=build` |
| Link flags | `-Wl,--build-id=sha1 -s` (stripped, content-hash build id); on 64-bit ABIs also `-Wl,-z,max-page-size=16384` ([16 KiB page size](#16-kib-page-size)) |
| Root file | [`CMakeLists.txt`](../../CMakeLists.txt): `sbc_add_native_abi(arm64-v8a)` |
| Library definitions | [`patches/arm64/native/CMakeLists.txt`](../../patches/arm64/native/CMakeLists.txt), [`ctprotocol/CMakeLists.txt`](../../patches/arm64/native/ctprotocol/CMakeLists.txt) |

The ctprotocol target compiles `core/*.c` and `jni/*.c`; the serialport target compiles `serialport/serialport.c` and links `log`. **Static**

### NDK selection

`sbc_native.cmake` accepts an NDK only when the `Pkg.Revision` in its `source.properties` equals the pin. A different revision is rejected, not substituted. The search order is:

1. `-Dandroid_ndk=<path>`
2. `ANDROID_NDK_ROOT`
3. `ANDROID_NDK_HOME`
4. `$ANDROID_SDK_ROOT/ndk/25.1.8937393`
5. `$ANDROID_HOME/ndk/25.1.8937393`
6. `%LOCALAPPDATA%/Android/Sdk/ndk/25.1.8937393`

If no match is found, `sbc_native_available` is false and the `arm64` variant is not generated. The `resign` and `modernize` variants still build. **Static**

### Reproducibility

The pinned NDK, the fixed flags, the path remapping and the content-hash build id remove the inputs that otherwise make builds differ by checkout location or machine. Source and binary paths do not enter the binary. The sources contain no timestamps. Two builds of the same source with the same NDK are expected to match; the build id (a SHA-1 of the content) changes only when the content changes. **Static**. A clone in a separate directory built with the pinned NDK produces the same files as the pipeline build (**Build**):

| Library | Bytes | SHA-256 |
|---|---|---|
| `libsbxapplogic_ctprotocol_jni.so` | 27736 | `970d1744d765e80a3e4b82854add4dd1d96402f0841b0a78070f9d80432d7836` |
| `libserialport_jni.so` | 6696 | `ca380c7c549c197777d8b76a1c763806030992da4fe0af74e6cf47f8d9eff232` |

A build with a different NDK revision is not expected to match. Before the 16 KiB link flag, the same source built to `66797a4e...` and `2db91e4a...`, the hashes of the fresh-clone check in [PROVENANCE.md](../PROVENANCE.md); the two builds differ only as described under [16 KiB page size](#16-kib-page-size).

Hardware-validated builds, recorded as historical values ([ARM64_RUNTIME.md](../research/arm64/ARM64_RUNTIME.md), [ARM64_BUILD.md](../research/arm64/ARM64_BUILD.md)):

| Library | Bytes | SHA-256 | `NEEDED` |
|---|---|---|---|
| `libsbxapplogic_ctprotocol_jni.so` | 136928 | `ef9bad520bd1c94d9a942857425b80722d650190dd120dad8d9d070490e52c6e` | `libm`, `libdl`, `libc` |
| `libserialport_jni.so` | 30512 | `e50efa5e59d111a695b6eb7d1457824df03921f53eb6e4eda04fc524f4d58a87` | `liblog`, `libm`, `libdl`, `libc` |

These are the files the device runs used. The current from-source build does not have these hashes, and no recorded comparison relates it to them section by section. Do not use the table as a build-verification target.

### 16 KiB page size

64-bit Android devices may run with 16 KiB memory pages. On such a device the
dynamic linker of Android 15 and later refuses a library with a `PT_LOAD`
segment aligned to less than the page size (**Expected**, platform rule).
NDK r25b links with a 4 KiB maximum page size by default; NDK r27 and later
default to 16 KiB for 64-bit ABIs.

| Item | Before | Now | Basis |
|---|---|---|---|
| arm64-v8a `PT_LOAD` alignment, both libraries | `0x1000` | `0x4000` | **Build** (`llvm-readelf -l`) |
| Stock `armeabi`, `armeabi-v7a`, `x86` libraries | `0x1000` | unchanged | **Static**; 32-bit ABIs are outside the 16 KiB requirement |
| x86 oracle build of this source | default | unchanged, byte-identical to the build the oracle differential ran | **Build** |
| `.so` entries in the APK | deflated | deflated; `zipalign -c -P 16 4` passes | **Build** |
| `extractNativeLibs` | not set (installer extracts the libraries) | unchanged | **Static** |
| Page-size assumptions in the native source | none: no `getpagesize`, `sysconf` or `mmap` | unchanged | **Static** |

Because the libraries are compressed and extracted at install, only the ELF
segment alignment matters, not the alignment of the entries in the archive.

The flag is applied in
[`patches/arm64/native/CMakeLists.txt`](../../patches/arm64/native/CMakeLists.txt)
to 64-bit ABIs only. The NDK pin and the source are unchanged. Against the
4 KiB build, the flag moves the writable segments up by `0x3000` and `0x6000`
and changes nothing else in the code: every differing instruction word in
`.text` and `.plt` is an `adrp` whose target page moves by exactly that shift,
with the same destination register (37 in the ctprotocol library, 13 in
serialport). `.rodata`, `.dynsym`, `.dynstr`, `.eh_frame` and the data
contents are identical; `.rela.dyn`, `.rela.plt`, `.dynamic` and the build id
change with the addresses. File sizes are unchanged. **Build**

| Environment | Result | Basis |
|---|---|---|
| 4 KiB-page arm64 devices (Pixel 8, Galaxy S24 Ultra, API 37) | the 16 KiB-aligned libraries with the accepted hashes load; on the S24 Ultra the app connects to the Katana and reads and writes its state ([PERMISSION_REGRESSION.md](../research/android/PERMISSION_REGRESSION.md)) | **Device** |
| 16 KiB-page API 36 emulator, x86_64 guest | `libsbxapplogic_ctprotocol_jni.so` loads in the app and maps at 16 KiB-aligned offsets, translated by `libndk_translation`; the protocol core built for arm64 and for x86_64 reproduces all seven frozen outputs ([PAGE_SIZE_16K.md](../research/android/PAGE_SIZE_16K.md)) | **Emulator**, translated |
| 16 KiB-page arm64 device, native execution | not run | **Expected** |

A translated load does not show what a 16 KiB arm64 device's own linker
does with the libraries; native 16 KiB execution is a documented limitation
until such a device runs them.

### Verification baseline

- The oracle differential ran the stock x86 library and the x86 build of this source through the harness: byte-identical on all six frozen vector sets and on the supplementary set `dec_reject_gaps`. No arm64 run of the oracle vectors exists, because the harness needs a 32-bit x86 runtime.
- arm64 correctness rests on identical source, the 64-bit host tests and the device runs.

## How the libraries reach the APK

1. The root `CMakeLists.txt` builds both libraries for `arm64-v8a` with the pinned NDK.
2. The `arm64` variant is declared with `sbc_add_variant(arm64 PATCHES modernize arm64 NATIVE_LIB_DIR ... NATIVE_LIBS ...)` in [`cmake/sbc_patches.cmake`](../../cmake/sbc_patches.cmake). It applies the `modernize` patch first, then the `arm64` patch.
3. [`patches/arm64/patch.cmake`](../../patches/arm64/patch.cmake) copies both libraries into `${TREE}/lib/arm64-v8a/` of the decoded APK tree. It stops with a fatal error if either file is missing.
4. The pipeline rebuilds and signs the APK from the tree. The stock `lib/` entries are not touched.
5. The stock APK is a local input, not stored in the repository; the build takes it from a configured path ([`patches/arm64/README.md`](../../patches/arm64/README.md)).

**Static.** No binary is committed as an overlay: earlier records describe the libraries as staged under `patches/arm64/overlay/lib/arm64-v8a/`, which is superseded by the source build above.

## Stock 32-bit libraries

The stock `armeabi`, `armeabi-v7a` and `x86` copies of `libsbxapplogic_ctprotocol_jni.so` and `libserialport_jni.so` are left byte-identical in every variant. 32-bit devices continue to run the stock code. The stock x86 ctprotocol library (99672 bytes, SHA-256 `215a0bd15ef6f2dd9a5dca0a3c867824d9a61313b7a23cab8f6622779bee7f0e`) is also the behavioral oracle; its `armeabi-v7a` sibling begins `3097c0be`. **Static (recorded)**

## Loader expectations

| Item | Expectation |
|---|---|
| Process ABI | The linker loads `lib/<abi>/` matching the process ABI. A 64-bit-only device needs `lib/arm64-v8a/` or the install is refused. **Device** |
| Dependencies | ctprotocol: `libm`, `libdl`, `libc`. serialport: `liblog`, `libm`, `libdl`, `libc`. All are in the platform linker namespace for an app, no bundled runtime is needed. |
| `minSdk` | 64-bit Android requires API 21 or higher, consistent with `android-21`. |
| ctprotocol load | `JNI_OnLoad` must resolve its 28 callbacks or the load fails ([JNI_INTERFACE.md](JNI_INTERFACE.md#jni_onload-and-the-callback-cache)). |
| serialport load | `JNI_OnLoad` must find `com/creative/serialport/SerialPort` and register `open` and `close`, else it returns -1. The Java load is in a try/catch, so a failure leaves the class loaded but its natives unbound; calling them then raises `UnsatisfiedLinkError`. |
| Fallback path | The stock Java `System.load("/system/lib/...")` fallback names a 32-bit system path and cannot succeed for a 64-bit library. |

## serialport behavior

Source: [`patches/arm64/native/serialport/serialport.c`](../../patches/arm64/native/serialport/serialport.c). The library implements the two natives of `com.creative.serialport.SerialPort`:

```
private native FileDescriptor open(String path, int baudrate);
public  native int            close();
```

`JNI_OnLoad` registers them with `RegisterNatives` (signatures `(Ljava/lang/String;I)Ljava/io/FileDescriptor;` and `()I`) and returns `JNI_VERSION_1_6`, or -1 if `GetEnv`, `FindClass` or `RegisterNatives` fails.

| Behavior | Detail |
|---|---|
| Baud rates | A fixed table: 0, 50, 75, 110, 134, 150, 200, 300, 600, 1200, 1800, 2400, 4800, 9600, 19200, 38400 (code `0xf`), then the extended codes `0x1001` (57600) to `0x100f` (4000000). Any other rate logs an error and returns null before opening anything. |
| Open flags | `0x1102` (read/write, no controlling terminal, plus `0x1000` kept as in the stock code). |
| Line setup | `TCGETS`, then fixed masks: input flags `&= 0xfffffa14`, output flags `&= 0xfffffffe`, local flags `&= 0xffff7fb4`, control flags `= (flags & 0xffffeec0) \| 0x30 \| speed`, then `TCSETS`. This is raw 8N1 with no flow control change; `c_cc` is not modified. |
| Result | A new `java.io.FileDescriptor` whose `descriptor` field holds the descriptor number. |
| Failure | Returns null and logs under the tag `serialport_jni`, with no Java exception, when the baud rate is unsupported, `open` fails, or `TCGETS` or `TCSETS` fails. On a `TCGETS` or `TCSETS` failure the descriptor is closed and reset. |
| State | One process-global descriptor. A second `open` overwrites it without closing the first. The state is not synchronized. |
| `close` | Closes the global descriptor if one is open and resets it. Always returns 1, including when no port was open, and the returned `FileDescriptor` is not invalidated. |

All rows: **Static**.

**This library was never exercised on hardware.** The Katana path uses `BluzSocket` and the pure-Java `CtProtocolMgr`; `SerialPort` is reached only through `SbxSocketUART`, which that path does not use. No oracle vector, host test or device log touches it. The only evidence is that the library is part of the arm64 APK that installed and launched, and that the loader tolerated it. A loaded-but-unused library proves binding at most, which is itself **Static** here, since the `SerialPort` class is not reached. Treat its behavior as an unverified reimplementation of the stock contract.

## Test coverage matrix

Rows are components, columns are evidence sources. "Yes" means a recorded run covers the component; the description says what exactly. "No" means none.

| Component | Oracle x86 differential (stock vs this source, x86) | Host CTest (64-bit core) | Device (arm64) |
|---|---|---|---|
| Encoder frames and domains (`ctprotocol_encode.c`) | Yes: `enc_stock.txt`, 164 `ENC` rows (45 reject, 110 valid, 9 state), 1 `INT` row, byte-identical | Yes: `enc_stock` case compares the same file | Live frames sent during the SPP session; output not compared to a reference |
| `setMalcolmParam` validation | Yes for the listed accept and reject points (43 `ENC` rows); the rest of the domain table is static only | Same rows | Not shown |
| Decoder status and events (`ctprotocol_decode.c`) | Yes: `dec_valid` (27 frames), `dec_reject` (11 groups), `dec_state` (7 controls), `dec_stream` (8 scenarios), `dec_entry` (4 probes) | Yes: cases `dec_entry`, `dec_valid`, `dec_reject`, `dec_state`, `dec_stream` | Live inbound frames decoded; one `[handleProtocolEvent] SOUNDCORE_COMMAND_MAXPAYLOAD` event logged |
| Decoder field maps at non-zero values | Mostly no: the vectors use zero payloads; the exceptions are listed in [CTPROTOCOL.md](CTPROTOCOL.md#what-the-decode-vectors-pin) | No | Not shown |
| Rejects of op `0x02` with an unknown code or length, and of op `0x07` with an unknown length | Yes: supplementary `dec_reject_gaps` (11 groups), byte-identical | Yes: case `dec_reject_gaps` | Not shown |
| Three unreachable callbacks | Never produced (consistent with the static finding) | Not produced | Not produced |
| JNI marshalling and callback delivery (`ctprotocol_jni*.c`) | Yes (x86 glue); the harness prints each callback | No: `ctp_regress.c` re-implements the marshalling | Native binding and callback cache resolved on both devices; no payload comparison |
| `JNI_OnLoad` callback cache | Yes (x86) | No | Yes: loads on both devices |
| serialport (`serialport.c`) | No | No | No (never exercised) |
| Build reproducibility | n/a | n/a | n/a; two clean clones give identical library hashes ([Reproducibility](#reproducibility)) |
| arm64 install and launch | n/a | n/a | Yes: Pixel 7a, Galaxy S24 Ultra; RFCOMM connection to the Katana; dashboard and preset screens reached |
| Hardware protocol correctness | n/a | n/a | Not claimed |

The CTest names are `enc_stock`, `dec_entry`, `dec_valid`, `dec_reject`, `dec_state`, `dec_stream` and the supplementary `dec_reject_gaps`. `compare.cmake` ignores lines that begin with `#`, so comment-line differences between a run and the recorded file do not fail a case. The suite passes with MSVC and with gcc.

## Verification gaps

- No arm64 run of the oracle vectors exists. arm64 behavior is inferred from identical source, 64-bit host tests and device runs.
- The `.so` files are not checked into the repository, and no recorded rebuild compares the current build output with the hardware-validated hashes.
- `libserialport_jni.so` has no test of any kind.
- No arm64 device with 16 KiB pages has run the arm64 libraries natively; their 16 KiB readiness rests on the ELF alignment and a translated load on a 16 KiB-page x86_64 emulator ([16 KiB page size](#16-kib-page-size)). CI checks the alignment of every build.
- The device runs bound every native method and showed live traffic, but they do not compare encoder or decoder output against a reference. The stock Java `CtProtocolMgr` swallows an `ArrayIndexOutOfBoundsException` on some live frames; that is outside the native libraries ([ARM64_VERDICT.md](../research/arm64/ARM64_VERDICT.md)).
- The decoder probe sweeps described in [DECODE_DIFFERENTIAL.md](../research/decoder/DECODE_DIFFERENTIAL.md) are not stored, so claims that rest only on them are **Static (unrecorded)**.

## Where the research records are superseded

| Record statement | Current state |
|---|---|
| The libraries are staged at `patches/arm64/overlay/lib/arm64-v8a/` ([ARM64_BUILD.md](../research/arm64/ARM64_BUILD.md)) | They are built from source and copied by `patches/arm64/patch.cmake`; the hashes above are historical |
| The serialport library is loaded as `serialport` ([ARM64_PACKAGING.md](../research/arm64/ARM64_PACKAGING.md)) | The file is `libserialport_jni.so`, loaded as `serialport_jni` ([FREEZE.md](../research/arm64/FREEZE.md)) |
| The serialport library needs no reverse engineering and is rebuilt from public source ([RE.md](../research/arm64/RE.md)) | It is a behavior-faithful reimplementation of the stock library, with the stock masks and return values preserved |
| The encode corpus has 97 vectors ([CHECKPOINT.md](../research/arm64/CHECKPOINT.md)) | The file holds 164 `ENC`, 1 `INT` and a `DONE` marker |

## Sources

- [`patches/arm64/native/CMakeLists.txt`](../../patches/arm64/native/CMakeLists.txt), [`ctprotocol/CMakeLists.txt`](../../patches/arm64/native/ctprotocol/CMakeLists.txt), [`ctprotocol/core/`](../../patches/arm64/native/ctprotocol/core/), [`ctprotocol/jni/`](../../patches/arm64/native/ctprotocol/jni/), [`serialport/serialport.c`](../../patches/arm64/native/serialport/serialport.c)
- [`cmake/sbc_native.cmake`](../../cmake/sbc_native.cmake), [`cmake/sbc_patches.cmake`](../../cmake/sbc_patches.cmake), [`patches/arm64/patch.cmake`](../../patches/arm64/patch.cmake), [`CMakeLists.txt`](../../CMakeLists.txt), [`patches/arm64/README.md`](../../patches/arm64/README.md)
- [`tests/ctprotocol/`](../../tests/ctprotocol/), [`oracle/`](../../oracle/), [`oracle/vectors/`](../../oracle/vectors/)
- [ARM64_BUILD.md](../research/arm64/ARM64_BUILD.md), [ARM64_PACKAGING.md](../research/arm64/ARM64_PACKAGING.md), [ARM64_RUNTIME.md](../research/arm64/ARM64_RUNTIME.md), [ARM64_VERDICT.md](../research/arm64/ARM64_VERDICT.md), [FREEZE.md](../research/arm64/FREEZE.md), [RE.md](../research/arm64/RE.md), [CHECKPOINT.md](../research/arm64/CHECKPOINT.md)
- [PIPELINE.md](../research/android/PIPELINE.md), [PROVENANCE.md](../PROVENANCE.md), [TOOLCHAIN.md](../development/TOOLCHAIN.md)
- Companion documents: [CTPROTOCOL.md](CTPROTOCOL.md), [JNI_INTERFACE.md](JNI_INTERFACE.md)
