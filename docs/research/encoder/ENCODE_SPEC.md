# Encode spec and validation-domain table

> **Historical record.** Kept as evidence of how behavior was established; not updated for later changes. Status, corrections and the maintained references: [research index](../README.md).

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

### Complex builder (`setMalcolmParam`)

`setMalcolmParam([I a, [I b, [F c, int d, [I e)` -> `Encode::setMalcolmParam`.
Pinned against the oracle (`gid_*`, `sub97_*`, `f95*`, `grp_*` vectors) and the
x86 decompilation (`Encode::setMalcolmParam` @ 0x17200, validator
`FUN_000159e0` @ 0x159e0).

**Arrays.** `a[i]` = parameter group id, `b[i]` = sub-index within the group,
`c[i]` = float value. The JNI wrapper requires
`a.length == b.length == c.length == N`; any mismatch returns an empty `byte[]`
(marshalling guard, confirmed by `len_mismatch`). `e` must have length >= 2; on
success it receives `[lastGroupBytes, groupCount]` (the `e=` field in the
corpus). `d` is the group-size seed, not a wire field.

**Group-splitting.** Group size `gs` and per-full-group byte size `gb`:

- `d < 16` -> `gs = 2`, `gb = 16`;
- else `gs = (d - 1) / 6`; if `gs < 43` then `gb = gs*6 + 4`, else `gs = 42`,
  `gb = 256`.

Then `full = N / gs`, `rem = N % gs`. Output is `full` frames of `gs` params
followed, if `rem != 0`, by one frame of `rem` params. Each group frame is
`5a 12 <cnt*6+1> <cnt>` then `cnt` params; each param is 6 bytes
`<a[i]&0xff> <b[i]&0xff> <c[i] float32 LE>`. Emitted length =
`full*gb + (rem ? rem*6+4 : 0)`. `N == 0` emits a 0-length frame via the success
path with `e = [gb, 0]` (`grp_n0`). `e[0]` = byte size of the last emitted group
(`gb`, or `rem*6+4` when a remainder frame exists); `e[1] = full + (rem != 0)`.

**Per-param validation (`FUN_000159e0(a[i], b[i], c[i])`).** Returns 0 (accept)
or non-zero (reject -> whole call emits an empty frame):

- group id `a[i]` must be one of `0x49, 0x8f, 0x95, 0x96, 0x97` (else `0x18`);
  the full int is compared, so `0x195` is rejected though its low byte is `0x95`
  (`gid_0x195`).
- sub-index `b[i]` must be a case the group defines (else `0x19`).
- `c[i]` must lie in that `(group, sub)` float domain (else `0x2f`). Boolean
  fields accept only `{0.0, 1.0}`; continuous fields use the rodata bounds at
  `.rodata` `0x13ae4..0x13b58` (image base 0x10000), e.g. `0x95/1 -> [0, 11.66]`
  (`DAT_00023aec = 11.6599998`), `0x49/1 -> [1.0, 20.0]`. The full switch and its
  30 float constants are reproduced verbatim in `ctprotocol-core`.

The builder's own null guards (`0x1b` count<0, `0x1c`/`0x1d`/`0x23` for null
`a`/`b`/`c`, `0x24`/`0x25` for null `e` outputs) are not reachable from the Java
path without the JNI array marshalling aborting first, so they carry no oracle
vector.

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
