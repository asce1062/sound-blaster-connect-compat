# Decode differential result

Byte-for-byte differential of the portable `ctprotocol-core` decoder against the
stock x86 library. Both run through the same mirror harness
([`oracle/`](../../../oracle/)); their `DEC`/`CALL`/`CB` output is compared line
for line.

## Method

- Stock oracle: `libsbxapplogic_ctprotocol_jni.so` from `SBConnect_v1.04.02.apk`
  (SHA-256 `215a0bd1...bee7f0e`), run under `app_process32` on
  `Pixel_3a_API_30_x86` (API 30, ABI x86).
- Reimplementation: `ctprotocol-core` (`core/` + the `jni/` decode adapter),
  cross compiled for `x86` with NDK `25.1.8937393`, `android-21`,
  `-DCMAKE_BUILD_TYPE=Release`, loaded through the same harness and AVD.
- Corpora (committed): [`oracle/vectors/`](../../../oracle/vectors/)
  `dec_valid.txt` (`dec`), `dec_entry.txt` (`dec`), `dec_reject.txt` (`seq`),
  `dec_stream.txt` (`seq`), `dec_state.txt` (`seq`).
- Per-outcome status: `PASS_VALID` (recognized frame, callbacks equal),
  `PASS_REJECT` (frame produces no callback in both, equal), `MISMATCH`
  (differ), `UNREACHABLE_FROM_KNOWN_DISPATCH` (a cached callback with no
  dispatcher path - not counted as missing).

## Corpus results (reimpl vs stock, same corpus, matching mode)

| Corpus | Mode | Output lines | Result |
|---|---|---:|---|
| dec_valid | dec | 57 | PASS |
| dec_entry | dec | 6 | PASS |
| dec_reject | seq | 82 | PASS |
| dec_stream | seq | 52 | PASS |
| dec_state | seq | 65 | PASS |

`diff` is empty for every corpus: reimpl reproduces stock exactly, including
return value, callback identity, callback order, argument type, exact integer /
boolean / float-bit value, array length, and `null` vs empty.

The committed frozen `dec_reject.out.txt` and `dec_state.out.txt` predate a
comment-only edit to their corpus `.txt` files (both touched in the Phase 2
freeze commit). A literal diff of current output against those two frozen files
shows only echoed `#` comment lines; with comment lines removed the behaviour is
identical, and current stock exhibits the same echoed comments. No behavioural
line differs. The Phase 2 frozen files are left untouched.

## Callback-family matrix

All 25 reachable families `PASS_VALID` against the frozen vectors and the
distinct-value probe sweeps; the 3 cached-but-unreachable callbacks have no
dispatcher path.

| Family | Status |
|---|---|
| obsoleteAck | PASS_VALID |
| pendingAck | PASS_VALID |
| fileAck | PASS_VALID |
| dataAck | PASS_VALID |
| maxPls | PASS_VALID |
| requestControl | PASS_VALID |
| deviceInfo | PASS_VALID |
| fwInfo | PASS_VALID |
| devicefwString | PASS_VALID |
| profileInfoRecFirst | PASS_VALID |
| profileInfoRest | PASS_VALID |
| activeProfileRec | PASS_VALID |
| activeProfileMega | PASS_VALID |
| audioLvlRange | PASS_VALID |
| audioLvl | PASS_VALID |
| hwBtn | PASS_VALID |
| hwBtnSupport | PASS_VALID |
| hwBtnStatusSupport | PASS_VALID |
| hwBtnEnabled | PASS_VALID |
| batteryLevel | PASS_VALID |
| batteryLevelSupport | PASS_VALID |
| batteryStatus | PASS_VALID |
| batteryStatusSupport | PASS_VALID |
| btAutoConnect | PASS_VALID |
| voicePromptCtrl | PASS_VALID |
| audioCtrl | UNREACHABLE_FROM_KNOWN_DISPATCH |
| sbxProfileInfo | UNREACHABLE_FROM_KNOWN_DISPATCH |
| sbxProfileData | UNREACHABLE_FROM_KNOWN_DISPATCH |

## Rejection matrix

`dec_reject.txt` (11 groups) pairs each mutant frame with a known-good control.
Reimpl matches stock on all: truncation (drop payload byte, header-only), bad
declared length (plen too large / too small), magic-byte mutation, unknown
subcommand (`op26` sub 0x09, `op27` sub 0x03), unknown opcode (`op7f`, the one
`ret=0` case), minimum legal payload (`op03` plen 0, `op26` sub1 starved), and
maximum legal payload (`op03` plen 0xff). Each rejected frame produces no
callback, and the following control fires normally, in both libraries.

## Distinct-value confirmation

The frozen `dec_valid` vectors use mostly zero payloads. Seven distinct-value
probe sweeps (147 frames: per-byte float sweeps, `hwBtn` single-bit sweeps for
all four subcommands, multi-record `op19` recFirst/rest, `op02`/`op07`
code/length boundaries) were run reimpl vs stock during development; all matched.
These pinned the field maps that zero payloads cannot distinguish, including:

- `profileInfoRecFirst` arg 1 is the record index, not `sub & 0x7f`;
  `profileInfoRest` arg 0 is `X + record index`. A multi-record `dec_valid`
  vector caught the initial single-record assumption, which the probes then
  corrected.
- `op02` bad-code and bad-form, and `op07` bad-length, both return Java `false`
  (`ret=0`) - the same predicate stock applies, beyond the lone unknown-opcode
  case in the frozen reject matrix.

## Totals

- `MISMATCH` = 0 across all five corpora and the probe sweeps.
- `UNREACHABLE_FROM_KNOWN_DISPATCH` = 3 (not counted as `ORACLE_MISSING`).
- Every oracle-captured decoder family matches exactly; every frozen rejection
  vector matches; callback ordering matches; no unexplained parser state.

## Encoder regression

The decoder work added sources but did not touch the encoder. The encode
differential stays green: reimpl vs stock and reimpl vs the frozen
`enc_stock.txt`, 165 vectors, `diff` empty on both.

## arm64-v8a portability

The same `core/` + `jni/` sources cross-compile for `arm64-v8a` (NDK
`25.1.8937393`, `android-21`) with no changes. The arm64 `.so` exports
`JNI_OnLoad`, `Java_...SbxSppCommandManager_decode`, and all 35
`...SbxSppCommandManager_<m>` symbols (34 encode + decode) - the full set the
mirror declares. On-device staging and validation are ARM64-INTEGRATED (Phase
5); compilation alone does not advance the grade, and the arm64 `.so` is not
committed.

## Grade

The decoder earns **DIFFERENTIAL-PASS / ENCODE+DECODE**: every oracle-captured
family matches, every frozen rejection matches, callback ordering matches, zero
mismatches, and the encoder suite stays green against the frozen x86 oracle.
