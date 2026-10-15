# Encode spec and validation-domain table

Static map of the stock `libsbxapplogic_ctprotocol_jni` encoder, extracted from
the x86 decompilation (SHA-256 `215a0bd1...bee7f0e`). It is the implementation
reference for the portable `ctprotocol-core` encoder. The stock library remains
the authority: every row here is confirmed byte-for-byte against the captured
oracle (`oracle/vectors/`) except `setMalcolmParam`, noted below.

## Wrapper / Context model

Each `Java_...SbxSppCommandManager_<m>` wrapper:

1. sets a 258-byte capacity (`local_40 = 0x102`) and a zeroed `Context`
   (`local_34 = 1`, the rest 0);
2. calls `Encode::<builder>(ctx, buf, &len, args...)` once;
3. on return 0, `NewByteArray` + `SetByteArrayRegion(0, len)` - the frame is
   `buf[0 .. len)`;
4. on a non-zero builder error, returns an **empty** `byte[]` (the Java side
   sees a 0-length array). This is the stock rejection behavior the
   reimplementation must preserve exactly.

The `if (iVar == 6)` branch in every wrapper is a stack-buffer re-alignment
retry (triggered by the `FUN_00017094` capacity helper); it re-runs the same
builder with the same args and produces identical bytes. Encode carries **no
cross-call state**: `Context` holds only buffer capacity, and no builder reads
or mutates persistent state. Output is a pure function of (method, args).
`FUN_00017094(ctx, buf, &len, needed)` is the capacity guard (needed <= 258 ->
0); it never alters output bytes.

## Frame grammar (outbound)

`5A <op> <sub/len> [<selector>] [payload...]`, little-endian scalars, **no
trailing checksum**. `buf[2]` is the opcode's sub/length byte (fixed per
command, or `payload_len + k` for variable-length commands). Lengths below are
the exact emitted `*len`.

## Reachable builders (35 bound methods)

`checksum` error codes in the reject column are the builder's return value; the
JNI effect of any non-zero is the same empty `byte[]`.

### Fixed getters (no args, constant frame)

| Java method | Builder | Frame (hex) | len |
|---|---|---|---|
| `getMaxPayloadSize` | getMaxPayloadSize | `5a 03 00` | 3 |
| `getGeneralInfo` | getGeneralInfo | `5a 07 01 00` | 4 |
| `getDeviceFwString` | getFirmwareString | `5a 07 01 02` | 4 |
| `releaseControl` | releaseControl | `5a 06 01 00` | 4 |
| `commitSettings` | commitSettings | `5a 08 00` | 3 |
| `getHwBtn` | getHwBtn | `5a 26 01 01` | 4 |
| `getHwBtnSupport` | getHwBtnSupport | `5a 26 01 02` | 4 |
| `getHwBtnStatusSupport` | getHwBtnStatusSupport | `5a 26 01 03` | 4 |
| `hwBtnEnabled` | hwBtnEnabled | `5a 26 01 04` | 4 |
| `getBatteryLevel` | getBattLvl | `5a 27 01 01` | 4 |
| `getBatteryLevelSupport` | getBattLvlSupport | `5a 27 01 02` | 4 |
| `getBatteryStatus` | getBattStatus | `5a 28 01 01` | 4 |
| `getBatteryStatusSupport` | getBattStatusSupport | `5a 28 01 02` | 4 |
| `getBtAutoConnect` | getBtAutoConnect | `5a 31 01 01` | 4 |
| `getVoicePromptCtrl` | getVoicePromptCtrl | `5a 99 01 01` | 4 |
| `resetFactoryDefault` | resetFactoryDefault | `5a 9b 01 01` | 4 |
| `cancelFileTransfer` | fileTransferCancel | `5a 98 02 82 00` | 5 |
| `getProfileInfoRec` | getMalcolmProfileInfo(sel=1) | `5a 19 01 01` | 4 |
| `getActiveProfileRec` | getMalcolmActiveProfile(sel=1) | `5a 1a 03 01 01 00` | 6 |
| `getActiveProfileMega` | getMalcolmActiveProfile(sel=2) | `5a 1a 03 01 02 00` | 6 |

The profile getters pass a constant selector (Rec=1, Mega=2) to a shared
builder; `getMalcolmActiveProfile` writes `buf[3]=0x01`, `buf[4]=sel`,
`buf[5]=0x00`.

### One-argument builders

| Java method | Builder | Frame | Domain | Reject |
|---|---|---|---|---|
| `getFwInfo(n)` | getFirmwareInfo | `5a 07 02 01 <n>` | `0 <= n <= 255` | n>=256 -> 0x1e |
| `getAudioLvl(n)` | getAudioLvl | `5a 23 04 01 <n> 00 00` | `0 <= n <= 255` | n>=256 -> 0x1e |
| `setBtAutoConnect(v)` | setBtAutoConnect | `5a 31 02 00 <v>` | `v in {0,1}` | v>=2 -> 0x69 |
| `setVoicePromptCtrl(v)` | setVoicePromptCtrl | `5a 99 02 00 <v>` | `v in {0,1,2}` | v>=3 -> 0xa3 |
| `setTime(t)` | setTime | `5a 3b 04 <t LE32>` | full int32 | none |

### Profile setters (constant selector, value byte)

`buf[3]` = mode (set=0x00, voice-preview=0x02), `buf[4]` = selector
(Rec=1, Mega=2), `buf[5]` = value. Domain `0 <= value <= 255` (value>=256 ->
0x1e). The selector constant is always valid.

| Java method | Builder(sel, value) | Frame |
|---|---|---|
| `setActiveProfileRec(n)` | setMalcolmActiveProfile(1,n) | `5a 1a 03 00 01 <n>` |
| `setActiveProfileMega(n)` | setMalcolmActiveProfile(2,n) | `5a 1a 03 00 02 <n>` |
| `setActiveProfileRecVoicePreview(n)` | ...VoicePreview(1,n) | `5a 1a 03 02 01 <n>` |
| `setActiveProfileMegaVoicePreview(n)` | ...VoicePreview(2,n) | `5a 1a 03 02 02 <n>` |

### Two-argument builders

| Java method | Builder | Frame | Domain | Reject |
|---|---|---|---|---|
| `setHwBtn(id,val)` | setHwBtn | `5a 26 03 00 <id> <val>` | `1 <= id <= 20`, `val in {0,1}` | id-1>=20 -> 0x5b; val>=2 -> 0x5c |
| `setFileSize(a,b)` | sendFile(a,b) | `5a 98 05 01 <b LE32>` | `a == 1` | a!=1 -> 0x9a |

`setFileSize`'s first arg is a fixed command type that must be 1; the second is
the size written LE32. Only `a==1` emits a frame.

### Variable-length builder

`getFileDataBlk(data[], len, flag)` -> `getFileDataBlk(data, len, off)` where
`off = flag ? 0x81 : 0x80`.

- Frame: `5a 98 <len+2> <off> <len> <data[0 .. len]>`, emitted length `len + 5`.
- Domain: `data != null` (else 0x9b); `1 <= len <= 253` (else 0x9c);
  `off in {0x80, 0x81, 0x82}` (else 0x9d) - the JNI flag only produces
  0x80 / 0x81.

### Complex builder (pending valid-input capture)

`setMalcolmParam([I gains, [I subIds, [F coeffs, int count, [I outFreqs, [I outN)`
-> `Encode::setMalcolmParam`. Builds one or more `5a 12 ...` group frames,
chunking `count` params into groups of a computed size (<= 0x2a per group, 6
bytes/param: `subId`, packed, 4-byte float LE), writing the realized frame
layout and returning group counts via the two output arrays. The stock harness
vectors `v1`/`v2` passed empty/short arrays and were rejected (empty frame);
valid-domain vectors require non-null gains/subIds/coeffs and `count>=1`.
Marshalling and group math to be pinned against the oracle in the
`setMalcolmParam` capture pass before it is implemented.

## Scalar getter (not a frame)

`getFileTransferMaxDataSize()` returns the int `253` (`0xfd`) directly - no
frame, no native buffer. The core exposes it as a constant.

## decode

`decode([B, int)` is the inbound dispatcher (Phase 3); not part of the encoder.

## Checksum primitive (not used in command framing)

`checksum(len, data, out)`: `*out = (0xFF - sum(data[0 .. len])) & 0xFF`;
returns `0x71` if len<0, `0x72` if data null, `0x73` if out null. It is an
exported file-transfer / integrity helper; **no** outbound command frame above
carries a trailing checksum.
