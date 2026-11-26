# Research and validation records

These records explain how the project's behavior was established: the static
map of the stock native libraries, the oracle captures that froze the
protocol contract, the differential results that admitted the reimplementation,
the Android compatibility audits and the device runs. They are **historical**.
Each one describes the repository at the time it was written and is kept as
evidence, not edited to match later changes. Where a record is wrong or out of
date, the correction is listed in [Errata](#errata) below rather than made
silently in the record.

The maintained descriptions of current behavior are in
[`docs/technical/`](../technical/). When a record and a technical reference
disagree, the technical reference and the code govern.

## Index

Classification: **Research** explains how behavior was recovered or decided;
**Validation** records a test, differential or device run and its result;
**Diary** records the state of a work stream at a point in time.

### Encoder

| Record | Class | Content |
|---|---|---|
| [ENCODE_SPEC.md](encoder/ENCODE_SPEC.md) | Research | Static map of the stock encoder: frame shape per builder and validation domains. |
| [ENCODE_VECTORS.md](encoder/ENCODE_VECTORS.md) | Validation | Catalog of the frozen encode corpus `oracle/vectors/enc_stock.txt` and its boundary coverage. |
| [ENCODE_DIFFERENTIAL.md](encoder/ENCODE_DIFFERENTIAL.md) | Validation | Portable encoder against the stock x86 library: identical on all 166 lines. Grade DIFFERENTIAL-PASS. |

### Decoder

| Record | Class | Content |
|---|---|---|
| [DECODE_ENTRY.md](decoder/DECODE_ENTRY.md) | Research | Entry contract of the stock inbound path: explicit length, per-call state, return value. |
| [DECODE_VECTORS.md](decoder/DECODE_VECTORS.md) | Validation | Valid-frame corpus: one accepted frame per reachable callback family. |
| [DECODE_STREAM_BEHAVIOR.md](decoder/DECODE_STREAM_BEHAVIOR.md) | Validation | Call boundaries, partial frames, concatenation and junk. |
| [DECODE_REJECTION_MATRIX.md](decoder/DECODE_REJECTION_MATRIX.md) | Validation | Single-mutation rejection vectors with paired controls; statefulness controls. |
| [DECODE_CALLBACK_MATRIX.md](decoder/DECODE_CALLBACK_MATRIX.md) | Research | Every inbound callback, the frame that reaches it and its typed arguments; three cached callbacks are unreachable. |
| [PHASE2_VERDICT.md](decoder/PHASE2_VERDICT.md) | Diary | Verdict of the decoder oracle capture, before any decoder code existed. |
| [DECODE_IMPLEMENTATION.md](decoder/DECODE_IMPLEMENTATION.md) | Research | Design of the portable decoder and its JNI adapter. |
| [DECODE_DIFFERENTIAL.md](decoder/DECODE_DIFFERENTIAL.md) | Validation | Portable decoder against the stock x86 library on the five decode corpora. Grade DIFFERENTIAL-PASS. |

### Native arm64 libraries

| Record | Class | Content |
|---|---|---|
| [RE.md](arm64/RE.md) | Research | Reverse-engineering notes on the two stock native libraries and the frame format. |
| [FREEZE.md](arm64/FREEZE.md) | Research | The frozen static contract (JNI surface, builder set) the reimplementation had to satisfy. Grade STATIC-MAPPED. |
| [CHECKPOINT.md](arm64/CHECKPOINT.md) | Diary | Close-out of the 32-bit oracle harness work. |
| [ARM64_BUILD.md](arm64/ARM64_BUILD.md) | Validation | JNI parity of the arm64 build and native-surface metadata. |
| [ARM64_PACKAGING.md](arm64/ARM64_PACKAGING.md) | Research | Audit of every native-library load site in the stock Java code; multi-ABI packaging. |
| [ARM64_RUNTIME.md](arm64/ARM64_RUNTIME.md) | Validation | Install and run on 64-bit-only devices (Pixel 7a, Android 13; Galaxy S24 Ultra, Android 16). |
| [ARM64_VERDICT.md](arm64/ARM64_VERDICT.md) | Diary | Verdict for the arm64 native work. Grade ARM64_INTEGRATED. |
| [runtime/](arm64/runtime/) | Validation | Excerpts of device output: ABI listing, crash excerpt, launch log excerpt, S24 launch record. |

### Android compatibility

| Record | Class | Content |
|---|---|---|
| [FINDINGS.md](android/FINDINGS.md) | Research | Compatibility analysis of the stock APK on current Android. |
| [PIPELINE.md](android/PIPELINE.md) | Research | The decode, patch, rebuild and sign pipeline and its recorded hashes for the 32-bit variants. |
| [COMPAT_MATRIX.md](android/COMPAT_MATRIX.md) | Research | Expected support per variant and device class; per-change ledger of `modernize`. |
| [PERMISSION_AUDIT.md](android/PERMISSION_AUDIT.md) | Validation | Every declared permission, its protection level and justification. |
| [RECEIVER_AUDIT.md](android/RECEIVER_AUDIT.md) | Validation | Export decision for each first-party component. Verdict HARDENING_PASS. |
| [APP_IDENTITY.md](android/APP_IDENTITY.md) | Research | Package identity, version, SDK range and signing of the rebuilt APK against the stock APK. |
| [PLAY_PROTECT_MATRIX.md](android/PLAY_PROTECT_MATRIX.md) | Validation | Observed Play Protect behavior toward the debug-signed build. |
| [HARDWARE_VALIDATION.md](android/HARDWARE_VALIDATION.md) | Validation | `compat` on the Galaxy S24 Ultra (API 37) with the Katana, next to an `arm64` install: coexistence, permissions, arm64 runtime, read and write, exports, boot, Play Protect, regression. |
| [PERMISSION_FINDINGS.md](android/PERMISSION_FINDINGS.md) | Research | Baseline of the permission and platform-API findings from the S24 run, observations kept apart from hypotheses. |
| [LIFECYCLE_VALIDATION.md](android/LIFECYCLE_VALIDATION.md) | Validation | Pixel 8 and emulator runs of the permission lifecycle; verdicts for the lifecycle, the security review and Play Protect installation. |
| [PERMISSION_REGRESSION.md](android/PERMISSION_REGRESSION.md) | Validation | Galaxy S24 Ultra runs of the permission lifecycle with the Katana (revocation while connected, retry, notifications and location denied, A/B/A, boot, hardening), the discovery-call fix, and the Pixel 8 Play Protect user route; the current verdicts. |
| [PERMISSION_LIFECYCLE.md](android/PERMISSION_LIFECYCLE.md) | Research | Bluetooth entry points, runtime-permission consumers, stock hidden-API calls and the manifest review behind the permission lifecycle of `modernize`. |
| [RELEASE_SIGNING.md](android/RELEASE_SIGNING.md) | Validation | `test-release` and `release` signing of `compat` with disposable keys: positive and fail-closed controls, credential exposure, and the emulator update rehearsal. |
| [PAGE_SIZE_16K.md](android/PAGE_SIZE_16K.md) | Validation | The arm64 libraries and the protocol drivers on a 16 KiB-page API 36 emulator: translated load, all suites pass; native arm64 at 16 KiB not established. |
| [BUILD_TIMES.md](android/BUILD_TIMES.md) | Validation | Stage times of the APK build, and a clean rebuild of `compat` that is content-identical to the accepted build. |
| [RELEASE_PIPELINE_REHEARSAL.md](android/RELEASE_PIPELINE_REHEARSAL.md) | Validation | The signing driver through the build target and the release workflow's sign step with a disposable key: fail-closed controls, identical outputs from both routes, `verify_release.py`. |

## Vocabulary

The records name their checks with short identifiers (gates `A0` to `A6`,
`D0` to `D5`, "Phase 2", "Phase 5A", "lane"). These are labels of the work
breakdown in force when each record was written; they carry no meaning outside
the records. The grades they assign are:

| Grade | Meaning |
|---|---|
| STATIC-MAPPED | Behavior read from the stock binary or smali, not executed. |
| ORACLE-CAPTURED | Behavior observed by running the stock x86 library in the oracle harness and recorded as a frozen vector file. |
| UNREACHABLE | A callback the stock library caches but no frame reaches through the known dispatcher (static finding). |
| DIFFERENTIAL-PASS | The reimplementation's harness output is byte-identical to the stock library's on the frozen vectors. |
| ARM64_INTEGRATED | The arm64-v8a libraries built from source are packaged, load and bind on a 64-bit-only device and the app reaches its connection UI. |
| HARDWARE-VERIFIED | Behavior checked against the speaker itself. Named in the records as a separate grade; no record assigns it. |
| HARDENING_PASS | Every first-party component was given the narrowest export that keeps its observed function, with the acceptance runs recorded in the audit. |

## Frozen evidence

The vector files in [`oracle/vectors/`](../../oracle/vectors/) are the
behavioral contract of the CtProtocol encoder and decoder and must not change.
The device excerpts are kept as recorded. SHA-256 of each file:

| File | SHA-256 |
|---|---|
| `oracle/vectors/enc_stock.txt` | `d4e54b2bbce9b724a4335b0da2d40b60e47afb6bd8a9486c72a547dc78f8bfd6` |
| `oracle/vectors/dec_entry.txt` | `c97d08b1bced009cd4a24a6bf4bc59e85eac42389f7d6afdb55e19f2694bb910` |
| `oracle/vectors/dec_entry.out.txt` | `2dce5e77432507c8a4a0b4b495ee9584ca224644ad16bdc7e45723c91f22c700` |
| `oracle/vectors/dec_valid.txt` | `8fe358beeffd541fa097175c9f708ea8705aaa319dd888a810c45e1dd53a6083` |
| `oracle/vectors/dec_valid.out.txt` | `1478e2cc610202462a18fe24f35c2f8047be844c74f44715dc5f0a7f7e496e9a` |
| `oracle/vectors/dec_reject.txt` | `3be0d97392332312e6f2a65ee9575e48786314322f4f0392132a69fa638290a6` |
| `oracle/vectors/dec_reject.out.txt` | `3cc1c5b76c132f63f0c6010f17c1da03a6322f1c83dacd8e1ec4a2f867a1d1c9` |
| `oracle/vectors/dec_state.txt` | `ae4e6135557bde41574dfcc168d7e140a3ca240b0d1e509df0d33e64799224d5` |
| `oracle/vectors/dec_state.out.txt` | `6bea2f6b18b576db09a692b22514d14730c5d30463ea5543f0d6930896f7315f` |
| `oracle/vectors/dec_stream.txt` | `16c7909259e1e21377068e5d04cc9857c3c3d5f72af944beecc126286eb98329` |
| `oracle/vectors/dec_stream.out.txt` | `f6bcb82f4e4d05ab58448fdb30926b303e3eeab6c5718ef0c9d1202f3e659014` |
| `docs/research/arm64/runtime/device_abi.txt` | `245149fc272da3196ea93c01d500ffe71f057cb51b37a0a7d7f7931a5adee483` |
| `docs/research/arm64/runtime/junit_crash_excerpt.txt` | `d85bd007b5cc5d6441062e383a91196dc04af5929dab6b91fab015e0c5611c1e` |
| `docs/research/arm64/runtime/launch_log_excerpt.txt` | `39fcace7ee1c7fc0a0dbb67a6e701998746c3dec752af55c3f5e555284c8fa10` |
| `docs/research/arm64/runtime/s24_launch.txt` | `4f2290ab408cea97658b5458320920b85cfa8a1e7f9cf6de39f86b5c6bfe44e9` |

The stock x86 library the oracle ran is identified in the records by its
SHA-256 (`215a0bd1...`, see [DECODE_ENTRY.md](decoder/DECODE_ENTRY.md)). The
harness and the vectors are described in [`oracle/README.md`](../../oracle/README.md);
[`tests/ctprotocol/`](../../tests/ctprotocol/) replays the same vectors on a
host compiler.

## Evidence limits

- **Raw runtime logs.** The device runs recorded in
  [ARM64_RUNTIME.md](arm64/ARM64_RUNTIME.md), the audits and the Play Protect
  matrix were made from October 2026 onward. Their full logcat and command
  output was not preserved. Only the excerpts in
  [`arm64/runtime/`](arm64/runtime/) and the tables in the records remain.
- **Decoder probe sweeps.** [DECODE_DIFFERENTIAL.md](decoder/DECODE_DIFFERENTIAL.md)
  and [DECODE_VECTORS.md](decoder/DECODE_VECTORS.md) cite probe sweeps (147
  frames) used to locate discriminants and field order. The sweep frames and
  their outputs are not in the repository. Claims that rest only on them are
  unrecorded; the frozen corpora are the recorded contract.
- **Corpus coverage gaps.** No frozen vector reaches three reject branches of
  the decoder
  ([`ctprotocol_decode.c`](../../patches/arm64/native/ctprotocol/core/ctprotocol_decode.c)):
  op02 with an unknown code, op02 with an unknown length, op07 with an unknown
  length. The supplementary set `dec_reject_gaps.txt`, captured from the stock
  x86 library after these records were written, covers them
  ([TESTING.md](../development/TESTING.md#supplementary-vector-set)).
- **No arm64 oracle run.** The harness runs on a 32-bit x86 runtime. The arm64
  libraries are built from the same source that passes the x86 differential and
  the 64-bit host tests; on arm64 they are checked only by the device runs. The
  host regression driver built for arm64 reproduces the frozen outputs under
  translation on a 16 KiB-page emulator ([PAGE_SIZE_16K.md](android/PAGE_SIZE_16K.md));
  that is the core compiled for arm64, not the JNI library.
- **Devices.** Hardware runs used two 64-bit-only phones and one Katana
  speaker. No 32-bit Android device was tested.

## Errata

Corrections to the records, by record. The record text is unchanged.

| Record | Statement | Correction |
|---|---|---|
| [COMPAT_MATRIX.md](android/COMPAT_MATRIX.md):7, [PIPELINE.md](android/PIPELINE.md):9 | No arm64 support is claimed. | Written before the arm64 variant existed. The `arm64` variant packages arm64-v8a libraries built from source; see [ARM64_VERDICT.md](arm64/ARM64_VERDICT.md). |
| [COMPAT_MATRIX.md](android/COMPAT_MATRIX.md):64, [FINDINGS.md](android/FINDINGS.md):126 | Runtime permission requests for Bluetooth and notifications are not wired. | The `modernize` patch requests `BLUETOOTH_CONNECT`, `BLUETOOTH_SCAN` and `POST_NOTIFICATIONS` at runtime, first through `BtPermCompat` ([ARM64_RUNTIME.md](arm64/ARM64_RUNTIME.md), fix 6), now through `PermissionLifecycle` ([PERMISSION_LIFECYCLE.md](android/PERMISSION_LIFECYCLE.md)). |
| [ARM64_RUNTIME.md](arm64/ARM64_RUNTIME.md), [RECEIVER_AUDIT.md](android/RECEIVER_AUDIT.md), [HARDWARE_VALIDATION.md](android/HARDWARE_VALIDATION.md) runs before the permission lifecycle | `BtPermCompat` after the stock request batch; `MainService` type `mediaPlayback`; the notification-listener service declared. | Superseded by `PermissionLifecycle`, type `connectedDevice` and the listener's removal ([ANDROID_COMPATIBILITY.md](../technical/ANDROID_COMPATIBILITY.md) rows 2, 7, 11 to 14). The device results in those records describe the earlier build. |
| [PERMISSION_FINDINGS.md](android/PERMISSION_FINDINGS.md) PF1, PF2, PF7 | Hypotheses on the Bluetooth gate coverage, the repeated microphone request and the hidden-API calls. | Settled by static reading in [PERMISSION_LIFECYCLE.md](android/PERMISSION_LIFECYCLE.md): the gate covered two of the Bluetooth entry points; the stock batch runs on every activity creation; both calls are stock reflection on hidden methods. |
| [PERMISSION_FINDINGS.md](android/PERMISSION_FINDINGS.md) PF5 | Discovery of an unpaired device without location not observed. | With `neverForLocation` on `BLUETOOTH_SCAN`, the Pixel 8 (API 37) discovers an unpaired Katana with location denied ([LIFECYCLE_VALIDATION.md](android/LIFECYCLE_VALIDATION.md)). The hypothesis about the build without the flag was not tested. |
| [PERMISSION_FINDINGS.md](android/PERMISSION_FINDINGS.md) PF6 | Cause of the older-Android warning to be settled from the permission controller. | None of the AOSP conditions holds for the app; the device's permission-controller build has no published source. The cause is not identified ([PERMISSION_LIFECYCLE.md](android/PERMISSION_LIFECYCLE.md)). |
| [LIFECYCLE_VALIDATION.md](android/LIFECYCLE_VALIDATION.md) | Verdicts for the lifecycle, the security review and Play Protect installation, with the speaker and user-route runs pending. | Replaced by the verdicts of [PERMISSION_REGRESSION.md](android/PERMISSION_REGRESSION.md), which ran them. That record also found and fixed discovery calls reachable with `BLUETOOTH_CONNECT` alone. |
| [PIPELINE.md](android/PIPELINE.md):90 | "This machine's" debug keystore hash. | The hash belongs to the debug keystore of the machine that built the recorded APK. Every build machine has its own. |
| [CHECKPOINT.md](arm64/CHECKPOINT.md):50 | The encode corpus holds 97 vectors (96 `ENC`, 1 `INT`). | The corpus was extended after the checkpoint. `enc_stock.txt` holds 164 `ENC` lines, 1 `INT` line and `DONE` (166 lines), as [ENCODE_DIFFERENTIAL.md](encoder/ENCODE_DIFFERENTIAL.md) states. |
| [ARM64_BUILD.md](arm64/ARM64_BUILD.md):29, [CHECKPOINT.md](arm64/CHECKPOINT.md):124, [RE.md](arm64/RE.md):115 | arm64 libraries are staged as prebuilt files under `patches/arm64/overlay/lib/arm64-v8a/`. | Prebuilt libraries are no longer in the repository. The build compiles them from `patches/arm64/native/` with a pinned NDK (`cmake/sbc_native.cmake`). |
| [RE.md](arm64/RE.md):273 | Build with `patches/arm64/native/build.ps1`. | No such script exists. The native libraries are built by the CMake pipeline. |
| [RE.md](arm64/RE.md):27 | `Encode` (79). | The same record and [FREEZE.md](arm64/FREEZE.md):134 count 76 command builders. The 79 is a class-level symbol count, not a builder count. |
| [runtime/s24_launch.txt](arm64/runtime/s24_launch.txt):22 | 78 two-arg `registerReceiver` sites are routed through `RcvCompat`. | The build asserts 96 sites across the whole smali tree ([`patches/modernize/patch.cmake`](../../patches/modernize/patch.cmake)), as [ARM64_RUNTIME.md](arm64/ARM64_RUNTIME.md):92 states. |
| [ARM64_RUNTIME.md](arm64/ARM64_RUNTIME.md):163-165 | The app connects over Bluetooth SPP to the Katana on both devices. | The only preserved S24 record, [runtime/s24_launch.txt](arm64/runtime/s24_launch.txt), captures the launch with the speaker not connected. No preserved artifact records the S24 connection. |
| `oracle/vectors/dec_reject.txt`, `dec_state.txt` | Header comments. | The comment lines were added after the matching `.out.txt` captures, so the harness's echoed comments differ from the recorded output. Comment lines carry no protocol behavior; comparisons ignore lines starting with `#`. |
| Commit hashes in [CHECKPOINT.md](arm64/CHECKPOINT.md):40 and [ARM64_BUILD.md](arm64/ARM64_BUILD.md):12 | Commit citations. | These cite the rewritten history. The history was rewritten before publication ([PROVENANCE.md](../PROVENANCE.md)); the original hashes are kept privately. |
| Decoder and encoder records | Decompiler function names and offsets (`FUN_...`, raw addresses). | Provenance of the static map in the stock x86 library. They identify locations in that binary only; behavior is described in [`docs/technical/CTPROTOCOL.md`](../technical/CTPROTOCOL.md). |
| [DECODE_ENTRY.md](decoder/DECODE_ENTRY.md), [DECODE_REJECTION_MATRIX.md](decoder/DECODE_REJECTION_MATRIX.md), [PHASE2_VERDICT.md](decoder/PHASE2_VERDICT.md):24 | `decode` returns false only for an unknown opcode. | That is the only case the vectors record. The decoder also reports an unrecognized frame for op02 with an unknown code or length and op07 with an unknown length, from the static map; the supplementary set `oracle/vectors/dec_reject_gaps.txt` records them from the stock library. |
| [DECODE_IMPLEMENTATION.md](decoder/DECODE_IMPLEMENTATION.md) | The data acknowledgement requires `b[4] == 0`. | The decoder accepts `b[4]` in {0, 0x80, 0x81}. |
| `oracle/vectors/dec_valid.txt` comments | `hwBtn` signature `(i,byte[])`. | The callback signature is `(IZZZZZZZ)V`, as in the harness and [JNI_INTERFACE.md](../technical/JNI_INTERFACE.md). |
| [FREEZE.md](arm64/FREEZE.md), [CHECKPOINT.md](arm64/CHECKPOINT.md) | A count of 35 native methods over a name list that omits `getHwBtn`. | The Java class declares 35 native methods, `getHwBtn` and `decode` included. |
| [FINDINGS.md](android/FINDINGS.md):21-27 | Causes of the Play Store "not compatible" listing. | Inferred from the manifest and platform rules, not tested against the Play Store. |
| [PLAY_PROTECT_MATRIX.md](android/PLAY_PROTECT_MATRIX.md):41 | A user sideload is expected to show a warning with an install-anyway choice. | On the S24 Ultra at API 37, a user sideload of the debug-signed `compat` build was blocked with no install-anyway choice ([HARDWARE_VALIDATION.md](android/HARDWARE_VALIDATION.md)). |
