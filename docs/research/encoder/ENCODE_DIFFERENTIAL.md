# Encode differential result

> **Historical record.** Kept as evidence of how behavior was established; not updated for later changes. Status, corrections and the maintained references: [research index](../README.md).

Byte-for-byte differential of the portable `ctprotocol-core` encoder against
the stock x86 library. Both run through the same mirror harness
([`oracle/`](../../../oracle/)); their `ENC`/`INT` output is compared line for
line.

## Method

- Stock oracle: `libsbxapplogic_ctprotocol_jni.so` from `SBConnect_v1.04.02.apk`
  (SHA-256 `215a0bd1...bee7f0e`), run under `app_process32` on
  `Pixel_3a_API_30_x86` (API 30, ABI x86).
- Reimplementation: `ctprotocol-core` (`core/` + thin `jni/` adapter), cross
  compiled for `x86` with NDK `25.1.8937393`, `android-21`, `-DCMAKE_BUILD_TYPE=Release`,
  loaded through the same harness and AVD.
- Corpus: [`oracle/vectors/enc_stock.txt`](../../../oracle/vectors/enc_stock.txt),
  164 `ENC` + 1 `INT` lines (method vectors + statefulness probes).
- Per-vector status: `PASS_VALID` (non-empty frame, equal), `PASS_REJECT`
  (empty frame, equal), `MISMATCH` (differ), `ORACLE_MISSING` (a reachable
  method with no vector).

## Per-method status

All 34 reachable encoder methods (the 35th reachable native, `decode`, is the
decoder phase and is out of scope here).

| Method | VALID | REJECT | MISMATCH | Status |
|---|---:|---:|---:|---|
| cancelFileTransfer | 1 | 0 | 0 | PASS |
| commitSettings | 1 | 0 | 0 | PASS |
| getActiveProfileMega | 1 | 0 | 0 | PASS |
| getActiveProfileRec | 1 | 0 | 0 | PASS |
| getAudioLvl | 5 | 3 | 0 | PASS |
| getBatteryLevel | 1 | 0 | 0 | PASS |
| getBatteryLevelSupport | 1 | 0 | 0 | PASS |
| getBatteryStatus | 1 | 0 | 0 | PASS |
| getBatteryStatusSupport | 1 | 0 | 0 | PASS |
| getBtAutoConnect | 1 | 0 | 0 | PASS |
| getDeviceFwString | 1 | 0 | 0 | PASS |
| getFileDataBlk | 7 | 2 | 0 | PASS |
| getFileTransferMaxDataSize | 1 | 0 | 0 | PASS |
| getFwInfo | 5 | 3 | 0 | PASS |
| getGeneralInfo | 1 | 0 | 0 | PASS |
| getHwBtn | 1 | 0 | 0 | PASS |
| getHwBtnStatusSupport | 1 | 0 | 0 | PASS |
| getHwBtnSupport | 1 | 0 | 0 | PASS |
| getMaxPayloadSize | 1 | 0 | 0 | PASS |
| getProfileInfoRec | 1 | 0 | 0 | PASS |
| getVoicePromptCtrl | 1 | 0 | 0 | PASS |
| hwBtnEnabled | 1 | 0 | 0 | PASS |
| releaseControl | 1 | 0 | 0 | PASS |
| resetFactoryDefault | 1 | 0 | 0 | PASS |
| setActiveProfileMega | 5 | 3 | 0 | PASS |
| setActiveProfileMegaVoicePreview | 5 | 3 | 0 | PASS |
| setActiveProfileRec | 5 | 3 | 0 | PASS |
| setActiveProfileRecVoicePreview | 5 | 3 | 0 | PASS |
| setBtAutoConnect | 2 | 2 | 0 | PASS |
| setFileSize | 6 | 2 | 0 | PASS |
| setHwBtn | 6 | 4 | 0 | PASS |
| setMalcolmParam | 28 | 15 | 0 | PASS |
| setTime | 7 | 0 | 0 | PASS |
| setVoicePromptCtrl | 3 | 2 | 0 | PASS |

The three `STATE_*` labels (statefulness probes) reuse `getGeneralInfo`,
`setTime`, and `setMalcolmParam`; their 9 lines also matched.

## Totals

- `PASS_VALID` = 110
- `PASS_REJECT` = 45
- `MISMATCH` = 0
- `ORACLE_MISSING` = 0 (every reachable encoder method has at least one vector)

The full harness output is identical to the frozen corpus across all 166 lines
(`diff` is empty).

## Statefulness

- Repeated calls (`STATE_repeat_*`): byte-identical.
- Interleaved calls (`STATE_inter_probe` a/b/c around unrelated calls): the
  probe is byte-identical regardless of position.
- Fresh process: two independent `app_process32` runs of the stock library
  produce identical output.

Encode is stateless: output is a pure function of (method, args). No missing
state variable.

## arm64-v8a portability

The same `core/` + `jni/` sources cross-compile for `arm64-v8a` (NDK
`25.1.8937393`, `android-21`) with no changes and export the same 34
`...SbxSppCommandManager_<m>` encode symbols. The arm64 `.so` is not staged:
it is encoder-only until the decoder and the 28 callbacks exist, so it is not
yet a drop-in replacement. arm64 integration is Phase 5.

## Grade

The encoder earns **DIFFERENTIAL-PASS / ENCODE**: zero mismatches and zero
reachable `ORACLE_MISSING` against the frozen x86 oracle. Compilation for
arm64 does not advance the grade. The decoder has no oracle yet and is not
started.
