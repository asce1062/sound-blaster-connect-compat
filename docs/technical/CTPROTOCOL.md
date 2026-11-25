# CtProtocol frame encoder and decoder

This document specifies the CtProtocol behavior implemented by the portable C core in [`patches/arm64/native/ctprotocol/core/`](../../patches/arm64/native/ctprotocol/core/): the outbound command frames the encoder builds, the inbound frames the decoder accepts, the events it emits, and the stock behavior that the core preserves on purpose. The core has no JNI, Android or platform dependency; the JNI layer that binds it to the Java class is described in [JNI_INTERFACE.md](JNI_INTERFACE.md) and the libraries that contain it in [NATIVE_LIBRARIES.md](NATIVE_LIBRARIES.md). Protocol behavior is frozen: the stock 32-bit library is the reference, `oracle/vectors/` is the behavioral contract, and where this document and the C code disagree the code is correct. Constants are described by domain; exact values are in the source.

## Verification tags

| Tag | Meaning |
|---|---|
| **Oracle** | Reproduced by a recorded vector in [`oracle/vectors/`](../../oracle/vectors/) (file named in the row). The vectors are output captured from the stock x86 library; the x86 build of this source run through the same harness gives byte-identical output on all six vector sets ([encode](../research/encoder/ENCODE_DIFFERENTIAL.md), [decode](../research/decoder/DECODE_DIFFERENTIAL.md)). |
| **Host test** | Replayed by the CTest suite in [`tests/ctprotocol/`](../../tests/ctprotocol/), which builds the core for a 64-bit host and compares its output with the same vector files. Every **Oracle** claim is also a **Host test** claim. The suite exercises the core only; the JNI glue is re-implemented inside the test driver, not executed. |
| **Device** | Observed on hardware (Pixel 7a, Android 13; Galaxy S24 Ultra, Android 16) per [ARM64_RUNTIME.md](../research/arm64/ARM64_RUNTIME.md). Raw runtime logs were not preserved; only the excerpts in [`docs/research/arm64/runtime/`](../research/arm64/runtime/) exist. |
| **Static** | Read from the code or from the stock binary, not executed against a vector. **Static (unrecorded)** marks a claim that rests on a decompilation note or a probe sweep whose inputs and outputs are not stored in this repository. |

Verification baseline, stated once:

- No oracle run exists on arm64. The harness needs a 32-bit x86 runtime. arm64 correctness rests on identical source, the 64-bit host tests and the device runs.
- Device runs show that the arm64 library loads, binds all natives, connects to a Katana over Bluetooth SPP and processes live inbound commands. They are not a systematic hardware verification of encode or decode output ([ARM64_VERDICT.md](../research/arm64/ARM64_VERDICT.md)).
- The recorded vectors pin callback identity, argument count and type, and rejection behavior. For most decoder families the accepted-frame vectors carry zero payloads, so field-to-argument mappings for non-zero values are mostly **Static (unrecorded)**. [What the vectors pin](#what-the-decode-vectors-pin) lists the exceptions.

## Frame layout

```
outbound (host to device):  5A <op> <len> <payload[len]>
inbound  (device to host):  5A <op> <plen> <payload[plen]>      total length = plen + 3
```

- Byte 0 is the sync byte `0x5A`. Byte 1 is the opcode (feature group). Byte 2 is the payload length: the number of bytes that follow it. Payload byte 0 is usually a sub-selector or mode. **Static** (encoder frames: all rows below; decoder: [framing check](#entry-contract)).
- Scalars are little-endian. The core writes and reads them byte by byte, so the result does not depend on host endianness. **Static**
- There is no trailing checksum on any frame. **Oracle** (`enc_stock.txt`: no frame carries one). The stock library exports a `checksum` function (`(0xFF - sum(bytes)) & 0xFF`) that neither the stock encoder nor the stock decoder calls; the core does not reimplement it. **Static (unrecorded)**
- Outbound frames fit the 258-byte buffer (`CTP_CAP`) of the stock wrapper, except `setMalcolmParam`, whose output is sized from its arguments ([sizing](#sizing-and-the-e-outputs)). **Static**
- Inbound frames carry an 8-bit `plen`, so a real frame is at most 258 bytes. **Static**

## Encoder

Source: [`ctprotocol_encode.h`](../../patches/arm64/native/ctprotocol/core/ctprotocol_encode.h), [`ctprotocol_encode.c`](../../patches/arm64/native/ctprotocol/core/ctprotocol_encode.c). Every builder is a pure function of its arguments: `int ctp_<name>(uint8_t *out, ...)` writes the frame to `out` and returns its length, or `CTP_REJECT` (-1) when the argument is outside the stock domain. The core returns -1 for every reject; the distinct error codes of the stock builder appear only in source comments. The JNI layer turns any negative return into an empty `byte[]` ([JNI_INTERFACE.md](JNI_INTERFACE.md)). No builder keeps state between calls: **Oracle** (`enc_stock.txt`, `STATE_repeat_*` and `STATE_inter_*` rows: repeated and interleaved calls give identical bytes), **Static** (the file has no mutable static data).

### Fixed getters (no argument, constant frame)

All rows: **Oracle** (`enc_stock.txt`, one vector each).

| Java method | Core function | Frame (hex) | Length |
|---|---|---|---|
| `getMaxPayloadSize` | `ctp_getMaxPayloadSize` | `5a 03 00` | 3 |
| `getGeneralInfo` | `ctp_getGeneralInfo` | `5a 07 01 00` | 4 |
| `getDeviceFwString` | `ctp_getDeviceFwString` | `5a 07 01 02` | 4 |
| `releaseControl` | `ctp_releaseControl` | `5a 06 01 00` | 4 |
| `commitSettings` | `ctp_commitSettings` | `5a 08 00` | 3 |
| `getHwBtn` | `ctp_getHwBtn` | `5a 26 01 01` | 4 |
| `getHwBtnSupport` | `ctp_getHwBtnSupport` | `5a 26 01 02` | 4 |
| `getHwBtnStatusSupport` | `ctp_getHwBtnStatusSupport` | `5a 26 01 03` | 4 |
| `hwBtnEnabled` | `ctp_hwBtnEnabled` | `5a 26 01 04` | 4 |
| `getBatteryLevel` | `ctp_getBatteryLevel` | `5a 27 01 01` | 4 |
| `getBatteryLevelSupport` | `ctp_getBatteryLevelSupport` | `5a 27 01 02` | 4 |
| `getBatteryStatus` | `ctp_getBatteryStatus` | `5a 28 01 01` | 4 |
| `getBatteryStatusSupport` | `ctp_getBatteryStatusSupport` | `5a 28 01 02` | 4 |
| `getBtAutoConnect` | `ctp_getBtAutoConnect` | `5a 31 01 01` | 4 |
| `getVoicePromptCtrl` | `ctp_getVoicePromptCtrl` | `5a 99 01 01` | 4 |
| `resetFactoryDefault` | `ctp_resetFactoryDefault` | `5a 9b 01 01` | 4 |
| `cancelFileTransfer` | `ctp_cancelFileTransfer` | `5a 98 02 82 00` | 5 |
| `getProfileInfoRec` | `ctp_getProfileInfoRec` | `5a 19 01 01` | 4 |
| `getActiveProfileRec` | `ctp_getActiveProfileRec` | `5a 1a 03 01 01 00` | 6 |
| `getActiveProfileMega` | `ctp_getActiveProfileMega` | `5a 1a 03 01 02 00` | 6 |

### Builders with arguments

| Java method | Frame | Argument domain | Rejected when | Length | Basis |
|---|---|---|---|---|---|
| `getFwInfo(n)` | `5a 07 02 01 <n>` | `n` in 0..255 | `n` < 0 or > 255 | 5 | **Oracle** (`enc_stock.txt`: -1, 0, 1, 64, 254, 255, 256, 257) |
| `getAudioLvl(n)` | `5a 23 04 01 <n> 00 00` | `n` in 0..255 | outside 0..255 | 7 | **Oracle** (same sweep) |
| `setBtAutoConnect(v)` | `5a 31 02 00 <v>` | `v` in {0, 1} | any other value | 5 | **Oracle** (-1, 0, 1, 2) |
| `setVoicePromptCtrl(v)` | `5a 99 02 00 <v>` | `v` in {0, 1, 2} | any other value | 5 | **Oracle** (-1, 0, 1, 2, 3) |
| `setTime(t)` | `5a 3b 04 <t LE32>` | any int32 | never | 7 | **Oracle** (0, 1, 0x100, 0x12345678, 0x7fffffff, 0x80000000, 0xffffffff) |
| `setActiveProfileRec(n)` | `5a 1a 03 00 01 <n>` | `n` in 0..255 | outside 0..255 | 6 | **Oracle** (byte sweep) |
| `setActiveProfileMega(n)` | `5a 1a 03 00 02 <n>` | `n` in 0..255 | outside 0..255 | 6 | **Oracle** (byte sweep) |
| `setActiveProfileRecVoicePreview(n)` | `5a 1a 03 02 01 <n>` | `n` in 0..255 | outside 0..255 | 6 | **Oracle** (byte sweep) |
| `setActiveProfileMegaVoicePreview(n)` | `5a 1a 03 02 02 <n>` | `n` in 0..255 | outside 0..255 | 6 | **Oracle** (byte sweep) |
| `setHwBtn(id, val)` | `5a 26 03 00 <id> <val>` | `id` in 1..20, `val` in {0, 1} | `id` outside 1..20, or `val` not 0 or 1 | 6 | **Oracle** (`id` 0, 1, 2, 19, 20, 21 at `val` 1; `val` -1, 0, 1, 2 at `id` 1; (10, 0)) |
| `setFileSize(a, b)` | `5a 98 05 01 <b LE32>` | `a` must be 1; `b` any int32 | `a` != 1 | 8 | **Oracle** (`a` 0, 1, 2; `b` 0, 1, 0x100, 0x12345678, 0xffffffff) |
| `getFileDataBlk(data, len, flag)` | `5a 98 <len+2> <off> <len> <data[0..len)>` with `off` = `0x81` if `flag` else `0x80` | `len` in 1..253, `data` non-null with at least `len` bytes | `data` null, `len` < 1 or > 253, or fewer than `len` source bytes | `len` + 5 (6 to 258) | **Oracle** (`len` 0, 1, 2, 64, 252, 253, 254 at `flag` false; 64 and 1 at `flag` true). The source-underrun and null-pointer rejects have no vector ([gaps](#verification-gaps)). |
| `getFileTransferMaxDataSize()` | not a frame; returns the integer 253 | none | never | n/a | **Oracle** (`INT` row) |

Notes:

- The profile setters share one routine: `5a 1a 03 <mode> <selector> <n>`, mode 0 for set and 2 for voice preview, selector 1 for Rec and 2 for Mega. **Static**
- The maximum `getFileDataBlk` frame (253 data bytes) is exactly 258 bytes, the size of `CTP_CAP`. **Static**
- The `getFileDataBlk` offset check in the core (`off` in 0x80..0x82) cannot fail for the two values the flag produces; `0x82` is only ever emitted as the constant in `cancelFileTransfer`. **Static**

## setMalcolmParam

`ctp_setMalcolmParam(out, a, b, c, n, d, e0, e1)` builds a sequence of parameter-group frames.

| Argument | Meaning |
|---|---|
| `a[i]` | parameter group id |
| `b[i]` | sub-index within the group |
| `c[i]` | float value |
| `n` | parameter count; the three arrays have length `n` |
| `d` | group-size seed; never written to the wire |
| `e0`, `e1` | optional outputs (`[lastGroupBytes, groupCount]`) |

**Frame format.** Each group frame is `5a 12 <cnt*6+1> <cnt>` followed by `cnt` parameters of 6 bytes: `<a[i] & 0xff> <b[i] & 0xff> <c[i] as IEEE-754 float32, little-endian>`. A call emits `full` frames of `gs` parameters, then one frame of `rem` parameters when `rem` is not 0, where `gs` is derived from `d` and `full = n / gs`, `rem = n % gs`. **Oracle** (`enc_stock.txt`, `grp_*` rows; the float bytes are checked by `f95s1_*`, `gid_*` and `sub97_*` rows).

### Sizing and the e outputs

| Quantity | Value | Basis |
|---|---|---|
| Group size `gs` | `d` < 16: 2. Otherwise `(d - 1) / 6`, clamped to 42 when that quotient is 43 or more. | **Oracle** (`grp_*`: `d` = 0, 16, 43, 259; sizes 2, 2, 7, 42). Intermediate `d` values follow the formula and have no vector: **Static**. |
| Full-group bytes `gb` | `gs * 6 + 4` in every case (16 for `d` < 16, 256 for the clamp) | **Oracle** (`e0` values 16, 46 in `grp_*`); 256 is **Static**. |
| Output length | `full * gb + (rem ? rem * 6 + 4 : 0)` | **Oracle** (`grp_*`) |
| `e0` | `rem ? rem * 6 + 4 : gb` | **Oracle** (`grp_*`: 10, 16, 46) |
| `e1` | `full + (rem ? 1 : 0)` | **Oracle** (`grp_*`) |
| `n` = 0 | valid call: empty frame (length 0), `e0` = `gb`, `e1` = 0 | **Oracle** (`grp_n0`: `e=16,0`) |
| `n` < 0 | reject | **Static** (not reachable from Java: array lengths are not negative) |

`ctp_malcolm_size(n, d)` returns the output length above, or `CTP_REJECT` for `n` < 0. The caller sizes the output buffer from it because the output exceeds `CTP_CAP` for larger `n`. The length byte of one group frame (`cnt*6+1`, at most 253) always fits a byte. **Static**

`e0` and `e1` are written only when the call succeeds and the pointers are non-null. On rejection the Java `e[]` array is left as it was. **Oracle** (`enc_stock.txt`: reject rows print `e=0,0`, the harness's initial contents).

### Validation

Every parameter is validated before any byte is written; one invalid parameter rejects the whole call. **Oracle** (`mix_reject`). `ctp_malcolm_validate(group, sub, f)` returns 0 to accept, or a stock error code: `0x18` unknown group, `0x19` unknown sub-index for the group, `0x2f` float outside the (group, sub) domain. The group id and sub-index are compared as full `int` values, so `0x195` is rejected although its low byte is `0x95`. **Oracle** (`gid_0x195`).

The domain classes below are exact; constants that are not whole numbers are named by their decimal value, and their exact bit patterns are in the source. "Boolean" accepts only 0.0 and 1.0. "Any" accepts every float.

| Group | Sub-index: domain |
|---|---|
| `0x49` | 1: [1, 20]. Others: reject sub. |
| `0x8f` | 0: boolean. Others: reject sub. |
| `0x95` | 0x00 boolean; 0x01 [0, 11.66]; 0x02 [0, 256]; 0x03 and 0x04 boolean; 0x05 [0, 1]; 0x06 boolean; 0x07 [0.01, 0.25]; 0x08 [20, 180]; 0x09 [20, 60]; 0x0a boolean; 0x0b [200, 800]; 0x0c [800, 1800]; 0x0d [1600, 2750]; 0x0e [0.25, 4]; 0x0f [0.5, 2]; 0x10 [-1, 5]; 0x11 [0, 2]; 0x12 [0, 4]; 0x13 boolean; 0x14 to 0x1b [-24, 24]; 0x1c to 0x23 [20, 8000]; 0x24 to 0x2b [1, 4000]; 0x2c boolean; 0x2d [0, 1]; 0x2e boolean; 0x2f to 0x35 any; 0x36 boolean. Others: reject sub. |
| `0x96` | 0x00 boolean; 0x01 [0, 1.6666]; 0x02 boolean; 0x03, 0x05, 0x08 [0, 1]; 0x04 boolean; 0x06 {0, 1, 2}; 0x07 boolean; 0x09 boolean; 0x0a [-12, 12]; 0x0b to 0x14 [-24, 24]; 0x15 boolean; 0x16 and 0x17 [10, 1000]; 0x18 boolean; 0x19 [0, 1]; 0x1a to 0x1d boolean; 0x1e any; 0x1f and 0x20 boolean; 0x21 to 0x28 [-20, 20]; 0x29 to 0x30 boolean; 0x31 to 0x38 [0, 0.015]; 0x39 to 0x3d any; 0x3e boolean; 0x70 {0, 1, 2}; 0x71 and 0x72 {0, 1, 2, 3}. Others: reject sub. |
| `0x97` | 0x00, 0x01, 0x04 boolean; 0x02, 0x03, 0x05 to 0x08 any. Others: reject sub. |
| any other group | reject group |

Basis for the table: the group-id boundary (`0x48`, `0x4a`, `0x98`, `0x195` reject; `0x49`, `0x8f`, `0x95`, `0x96`, `0x97` accept), group `0x97` sub-indexes 0, 1, 2, 8 (accept) and 9 (reject), group `0x95` sub 1 at -0.01 and 11.67 (reject) and 0.0, 0.01, 5.0, 11.65, 11.66 (accept), group `0x95` sub 0 at -1.0, 0.5, 2.0 (reject) and 0.0, 1.0 (accept), `0x49` sub 1 at 10.0 (accept) and sub 0 (reject), `0x8f` sub 0 (accept) and sub 1 (reject), and `0x96` sub `0x1e` at 7.0 (accept) are **Oracle** (`enc_stock.txt`: `gid_*`, `sub97_*`, `f95s1_*`, `f95s0_*`). Every other (group, sub, float) entry in the table is **Static**: it was read from the stock decompilation and is reproduced in the source, and no vector exercises it.

Range comparisons use the form `f < lo || f > hi` (reject), so a NaN passes every range-checked field and fails every boolean field. Whether the stock builder behaves the same for NaN is not recorded: **Static**.

## Decoder

Source: [`ctprotocol_decode.h`](../../patches/arm64/native/ctprotocol/core/ctprotocol_decode.h), [`ctprotocol_decode.c`](../../patches/arm64/native/ctprotocol/core/ctprotocol_decode.c).

### Entry contract

`int ctp_decode(const uint8_t *frame, int len, ctp_emit_fn emit, void *user)` decodes exactly one frame and calls `emit` once per event, in dispatch order.

| Rule | Detail | Basis |
|---|---|---|
| Buffer | `frame` points to a zero-initialized buffer of at least `CTP_DECODE_MINBUF` (258) bytes. The first `len` bytes hold the frame; the rest are zero. A few families read bytes beyond the declared payload; the zero tail makes those reads deterministic and inside the allocation. | **Static** |
| Explicit length | Exactly `len` bytes from offset 0 are decoded. Bytes after `len` are ignored. There is no offset argument. | **Oracle** (`dec_entry.txt`: `5a03020000ff` with length 5 fires `maxPlsCallback`; `5a03020000` with length 4 and `5a03020000ff` with length 6 do not) |
| Framing check | Proceed only when `len >= 3`, `frame[0] == 0x5a` and `frame[2] == (uint8_t)(len - 3)`. | **Oracle** (`dec_reject.txt` groups 1 to 5 and 9, 11; `dec_entry.txt`) |
| Exact length | A buffer that is not exactly one frame is rejected whole: concatenated frames, a frame plus a partial next frame, trailing bytes, a non-`0x5a` prefix. | **Oracle** (`dec_stream.txt` scenarios 3, 4, 7, 8) |
| Events | Emitted through the callback; the event pointer is valid only during the call. | **Static** |

Status values and the Java boolean:

| Core status | Value | Java `decode(...)` result |
|---|---|---|
| `CTP_DECODE_OK` | `0x00` | `true` |
| `CTP_DECODE_UNRECOGNIZED` | `0x0b` | `false` |

The JNI wrapper returns `status != 0x0b`. **Static** (JNI source), **Oracle** (`ret=` field of every `.out.txt` line).

`CTP_DECODE_UNRECOGNIZED` is returned in exactly these cases, all after the framing check passed:

1. The opcode (`frame[1]`) is not one of the opcodes in the dispatch table or the silent list below. **Oracle** (`dec_reject.txt` group 7 and `dec_state.txt`: `5a7f020000` returns `ret=0`; this is the only `ret=0` in the recorded corpus).
2. Opcode `0x02` with an acknowledgement code (`frame[3]`) outside the known set, or with a known code and a length that matches none of the `0x02` forms. **Static (unrecorded)**.
3. Opcode `0x07` with a length other than 7, 9, 19 or 67. **Static (unrecorded)**.

Every other outcome returns `CTP_DECODE_OK`, including a framing failure, a recognized opcode whose sub-command or length is wrong, and a silent opcode. **Acceptance is signalled by event emission, never by the status.** **Oracle** (`dec_reject.txt`: every rejected frame returns `ret=1` except `5a7f020000`).

### Statelessness

The decoder holds no state between calls: it does not buffer partial frames, reassemble a frame across calls, resynchronize on `0x5a`, tolerate trailing bytes or de-duplicate repeats. Framing is the caller's job. **Oracle** (`dec_stream.txt`, 8 scenarios; `dec_state.txt`, 7 control groups: identical bytes give identical output before and after rejects, partial frames, concatenated buffers and interleaved families, and the output follows the payload byte `00`, `07`, `00`). **Static**: the decoder source contains no mutable static data. The statement is bounded by those corpora; there is no randomized or long-running state test.

### Dispatch table

Columns: opcode (`frame[1]`, written `b1`), selector, Java callback, argument mapping. `b3`..`bN` are frame bytes by absolute offset; `len` is the total frame length (`plen + 3`); LE16 and LE32 are little-endian unsigned reads (LE32 is delivered as a signed `int`). Arguments appear in the order the Java callback receives them, which is not always frame order. Where no accepted-frame condition below holds, the frame is silent and the status is `CTP_DECODE_OK` unless stated otherwise.

| Opcode | Selector | Callback (signature) | Arguments | Basis |
|---|---|---|---|---|
| `0x02` | `len` 5 and `(b4 & 0x7f) < 2` | `obsoleteAckCallback` `(II)V` | `b3`, `b4` | **Oracle** (`dec_valid.txt`, `b4` = 0); high-bit forms **Static (unrecorded)** |
| `0x02` | `len` 7 and `b4 == 1` | `pendingAckCallback` `(III)V` | `b3`, 1, `LE16(b5)` clamped to [2, 600] | **Oracle** (`dec_valid.txt`: payload 0 yields 2); upper clamp **Static (unrecorded)** |
| `0x02` | `len` 6 and `b4 == 1` and `b5 < 4` | `fileAckCallback` `(III)V` | `b3`, `b5`, 1 | **Oracle** (`dec_valid.txt`, `b5` = 0) |
| `0x02` | `len` 13, `b3 != 0x3a`, `b4` in {0, 0x80, 0x81} | `dataAckCallback` `(II[B)V` | `b3`, `b4`, `byte[8]` = `b5`..`b12` | **Oracle** (`dec_valid.txt`, `b4` = 0, bytes `11 22 .. 88` copied in order); `b4` high-bit forms **Static** |
| `0x02` | `len` 13, `b3 == 0x3a` | none (internal) | n/a | **Static (unrecorded)** |
| `0x03` | `len` 5 | `maxPlsCallback` `(I)V` | `LE16(b3)` | **Oracle** (`dec_valid.txt`, `dec_state.txt`: payload `00` gives 0, `07` gives 7) |
| `0x06` | `len` 4 | `requestControlCallback` `(Z)V` | `b3 == 1` | **Oracle** (`dec_valid.txt`, `b3` = 0); `b3` = 1 **Static** |
| `0x07` | `len` 7 or 19 | `deviceInfoCallback` `(II)V` | `LE16(b3)`, `b6` | **Oracle** (`dec_valid.txt`, `len` 7, zero payload); `len` 19 **Static (unrecorded)** |
| `0x07` | `len` 9 | `fwInfoCallback` `(IIIII)V` | `b3`, `b4`, `b5`, `LE16(b6)`, `b8` | **Oracle** (zero payload) |
| `0x07` | `len` 67 | `devicefwStringCallback` `([I)V` | `int[64]` = `b3`..`b66`, each 0..255 | **Oracle** (zero payload, array length 64) |
| `0x19` | `len` > 4, `(b3 & 0x7f) == 0`, `b4 == 1`, `count = b6`, `plen == count*3 + 4`, all records valid | `profileInfoRecFirstCallback` `(IIIZIZZIZ)V`, once per record | `b5`, record index, `type`, `b0_hi`, `b1_lo`, `b1_b6`, `b1_hi_n`, `b2_lo`, `b2_hi_n` (record fields below; records start at `b7`, 3 bytes each) | **Oracle** (`dec_valid.txt`: 1, 2 and 3 records; indexes 0, 1, 2) |
| `0x19` | `len` > 4, `(b3 & 0x7f) != 0`, `count = b4`, `plen == (count+1)*3`, all records valid | `profileInfoRestCallback` `(IIZIZZIZ)V`, once per record | `b5` + record index, `type`, `b0_hi`, `b1_lo`, `b1_b6`, `b1_hi_n`, `b2_lo`, `b2_hi_n` (records start at `b6`) | **Oracle** (`dec_valid.txt`, one record, zero payload); `b5` + index folding **Static (unrecorded)** |
| `0x1a` | `len` 5, `b3` = 1 | `activeProfileRecCallback` `(IZ)V` | `b4 & 0x7f`, `b4 >> 7` | **Oracle** (zero payload) |
| `0x1a` | `len` 5, `b3` = 2 | `activeProfileMegaCallback` `(IZ)V` | `b4 & 0x7f`, `b4 >> 7` | **Oracle** (zero payload) |
| `0x22` | `count = b3`, `plen == count*7 + 2` | `audioLvlRangeCallback` `(IFFFIII)V`, once per 7-byte record starting at `b5` | `r[0]`, 0.0f, 0.0f, 0.0f, `LE16(r+1)`, `LE16(r+3)`, `LE16(r+5)` | **Oracle** (`dec_valid.txt`, one zero record, float bits 0); non-zero mapping **Static (unrecorded)** |
| `0x23` | `plen` < 5 | `audioLvlCallback` `(IFI)V` | `b3`, 0.0f, `LE16(b4)` | **Oracle** (`plen` 4, zero payload); `plen` 0..3 **Static** |
| `0x26` | `plen` 5, `b3` = 1 | `hwBtnCallback` `(IZZZZZZZ)V` | `LE32(b4)` plus 7 booleans | **Oracle** (`dec_valid.txt`, zero payload) |
| `0x26` | `plen` 5, `b3` = 2 | `hwBtnSupportCallback` `(IZZZZZZZ)V` | as above | **Oracle** (zero payload) |
| `0x26` | `plen` 5, `b3` = 3 | `hwBtnStatusSupportCallback` `(IZZZZZZZ)V` | as above, with inverted booleans | **Oracle** (zero payload gives `1100111`) |
| `0x26` | `plen` 5, `b3` = 4 | `hwBtnEnabledCallback` `(IZZZZZZZ)V` | as above | **Oracle** (zero payload) |
| `0x27` | `b3` = 1, `len` 5 | `batteryLevelCallback` `(I)V` | `b4` | **Oracle** (zero payload) |
| `0x27` | `b3` = 2, `len` 7 | `batteryLevelSupportCallback` `(III)V` | `b4`, `b5`, `b6` | **Oracle** (zero payload) |
| `0x28` | `len` 8, `b3` = 1 | `batteryStatusCallback` `(ZZ)V` | `b4 & 1`, `(b4 >> 1) & 1` | **Oracle** (zero payload) |
| `0x28` | `len` 8, `b3` = 2 | `batteryStatusSupportCallback` `(ZZ)V` | `b4 & 1`, `(b4 >> 1) & 1` | **Oracle** (zero payload) |
| `0x31` | `len` 4, `b3` < 2 | `btAutoConnectCallback` `(I)V` | `b3` | **Oracle** (`b3` = 0) |
| `0x99` | `len` 4, `b3` < 3 | `voicePromptCtrlCallback` `(I)V` | `b3` | **Oracle** (`b3` = 0) |

Opcode `0x02` families, in the order the core tests them: the acknowledgement code `b3` must be in the known set (1 to 3, 5 to 8, 0x10 to 0x16, 0x19, 0x1a, 0x1c, 0x1e, 0x20 to 0x26, 0x30 to 0x3b, 0x41 to 0x4f, 0x98, 0x99, 0x9b), otherwise the frame is unrecognized. Then, by `len`: 5, 7 and 13 always return `CTP_DECODE_OK` (emitting only when their inner condition holds); 6 returns `CTP_DECODE_OK` only when `b4 == 1`; any other `len`, and `len` 6 with `b4 != 1`, is unrecognized. **Static (unrecorded)** for the code set and the length handling; the vectors contain only the accepted forms above.

Opcode `0x19` record fields (`r0`, `r1`, `r2` are the three record bytes):

| Field | Value | Note |
|---|---|---|
| `type` | `r0 & 0x7f` | |
| `b0_hi` | `r0 >> 7` | boolean |
| `b1_lo` | `r1 & 0x3f` | |
| `b1_b6` | `(r1 >> 6) & 1` | boolean |
| `b1_hi_n` | `((r1 >> 7) & 1) ^ 1` | boolean, inverted bit |
| `b2_lo` | `r2 & 0x7f` | |
| `b2_hi_n` | `((r2 >> 7) & 1) ^ 1` | boolean, inverted bit |

A record is valid when `type` is 0 and `r1 & 0x3f` <= 0x0c; or `type` is 1, 2, 3 or 0x41 and `r1 & 0x3f` <= 4; or `type` is 0x40 (any field). Any other `type` is invalid. All records are validated before any event is emitted; one invalid record silences the whole frame. Records are emitted in record order. **Oracle** (`dec_valid.txt`: zero records give `type 0`, `b1_hi_n` 1, `b2_hi_n` 1; the 2- and 3-record frames emit indexes 0, 1, 2 in order). The validation ranges and the single-record bit extraction for non-zero bytes are **Static (unrecorded)**.

Opcode `0x26` booleans, by position (`f4` = `b4`, `f6` = `b6`):

| Position | 0 | 1 | 2 | 3 | 4 | 5 | 6 |
|---|---|---|---|---|---|---|---|
| Source bit | `f4` bit 0 | `f4` bit 3 | `f6` bit 2 | `f6` bit 3 | `f6` bit 1 | `f4` bit 4 | `f4` bit 7 |
| Inverted for sub 3 | yes | yes | no | no | yes | yes | yes |

The integer argument is `LE32(b4)` for all four subs. **Oracle** pins the inversion set on zero input (`dec_valid.txt`: sub 3 gives `1100111`, subs 1, 2 and 4 give `0000000`). The source-bit assignment is **Static (unrecorded)**.

### What the decode vectors pin

- Every one of the 25 reachable callbacks fires from at least one frame, with the Java signature and argument count shown above. **Oracle** (`dec_valid.txt`, 27 frames).
- Boolean arguments are JNI booleans; floats carry raw IEEE bits; arrays are distinguishable from null (the harness prints `[len=N]`). **Oracle** (`dec_valid.out.txt`).
- Non-zero payload values observed: `maxPls` 0 and 7, `dataAck` bytes `11 22 33 44 55 66 77 88`, the pending-ack lower clamp, the `0x19` record index sequence and the status-support inversion. Everything else about field mapping at non-zero values depends on probe sweeps recorded only as a summary (seven sweeps, 147 frames) in [DECODE_DIFFERENTIAL.md](../research/decoder/DECODE_DIFFERENTIAL.md). The sweep inputs and outputs are not stored in this repository.

### Recognized opcodes that emit nothing

Frames with these opcodes pass the framing check and return `CTP_DECODE_OK` with no event, whatever their length or payload: `0x01 0x05 0x10 0x11 0x13 0x14 0x15 0x16 0x1e 0x20 0x21 0x24 0x25 0x30 0x32 0x33 0x34 0x35 0x36 0x38 0x39 0x3a`. In the stock library these reach internal listener slots or record-store forms with no Java callback. **Static (unrecorded)**; the recorded vectors contain none of them.

### Callbacks with no dispatch path

`JNI_OnLoad` caches 28 callbacks; the core has event kinds for 25. `audioCtrlCallback`, `sbxProfileInfoCallback` and `sbxProfileDataCallback` have no event kind: no stock dispatcher path reaches them, so the core never emits them. **Static (unrecorded)**: the finding comes from the stock dispatcher and listener table; the evidence is described in [DECODE_CALLBACK_MATRIX.md](../research/decoder/DECODE_CALLBACK_MATRIX.md) and is not stored. No vector produces any of the three, which is consistent with, but does not prove, unreachability.

## Preserved stock quirks

Each item below looks like a defect and is kept because the stock library behaves this way. Do not correct them.

**Encoder**

| Behavior | Basis |
|---|---|
| A rejected argument yields an empty frame, not an exception or a null. Java cannot tell a reject from a valid zero-length result; `setMalcolmParam` with `n` = 0 is also an empty array. | **Oracle** (`enc_stock.txt` empty rows, `grp_n0`) |
| `setTime` accepts every int32, including negative values. | **Oracle** (`0x80000000`, `0xffffffff`) |
| `getAudioLvl` appends two zero bytes after the argument. | **Oracle** |
| `setFileSize`'s first argument is a command type that must be 1, not a size. | **Oracle** (`a` = 0 and 2 reject) |
| `getFileDataBlk` accepts `len` up to 253 and rejects 0 and 254. | **Oracle** |
| `setMalcolmParam` compares group id and sub-index as full ints but writes only their low bytes. | **Oracle** (`gid_0x195`) |
| `setMalcolmParam` is all or nothing: one invalid parameter rejects the call and leaves `e[]` untouched. | **Oracle** (`mix_reject`) |
| The group-size seed `d` below 16 selects 2 parameters per frame; at 259 and above it clamps to 42. | **Oracle** (`grp_*`) |
| Several (group, sub) pairs accept any float, and several float bounds are inclusive IEEE constants such as 11.66 and 0.01. | **Oracle** for the 11.66 bound and group `0x97` sub 2; the rest **Static** |
| The stock `checksum` function exists but no frame uses it; the core has none. | **Static (unrecorded)** |

**Decoder**

| Behavior | Basis |
|---|---|
| `decode` returns `true` for rejected frames of recognized opcodes. | **Oracle** (`dec_reject.txt`) |
| `decode` returns `false` only for unknown opcodes, unknown `0x02` codes or forms, and unknown `0x07` lengths. | **Oracle** for the unknown opcode; the `0x02` and `0x07` cases **Static (unrecorded)** |
| `pendingAckCallback` always receives 1 as its second argument and a value clamped to [2, 600]. | **Oracle** (lower clamp); upper bound **Static (unrecorded)** |
| `obsoleteAckCallback` and `dataAckCallback` pass the raw `b4` byte, so the high-bit values 0x80 and 0x81 reach Java as 128 and 129. | **Static** |
| `0x02` frames of `len` 13 with code `0x3a` are silent. | **Static (unrecorded)** |
| `requestControlCallback` fires for every `len` 4 frame; the boolean is `b3 == 1`. | **Static** |
| `deviceInfoCallback` skips `b5`; `len` 7 and 19 use the same extraction. | **Static (unrecorded)** |
| `audioLvlCallback` fires for any `plen` below 5, reading bytes beyond a short payload as zero, and its float is always 0.0. | **Static** (code), **Oracle** for `plen` 4 |
| `audioLvlRangeCallback` floats are always 0.0 and header byte `b4` is ignored. | **Oracle** (zero floats), **Static** (`b4`) |
| The `hwBtn` family reads its booleans from `b4` and `b6` only while the integer is `LE32(b4)`; sub 3 inverts positions 0, 1, 4, 5, 6. | **Oracle** (inversion at zero), **Static (unrecorded)** (bit sources) |
| The `0x19` callbacks differ in argument shape: the first-record callback gets `b5` and the index separately, the rest callback gets `b5 + index`. The `_hi_n` booleans are inverted bits. | **Oracle** (index), **Static (unrecorded)** (folding, inversion at non-zero) |
| `0x19` events are emitted only after all records validate; `b4` other than 1 silences the first-record form. | **Static (unrecorded)** |
| `btAutoConnectCallback` and `voicePromptCtrlCallback` silently drop out-of-range values. | **Static** |
| No stream handling, no de-duplication, no resynchronization. | **Oracle** (`dec_stream.txt`) |
| 22 opcodes are recognized and silent; 3 cached callbacks are never emitted. | **Static (unrecorded)** |

## Verification gaps

- No vector reaches the `0x02` unknown-length reject branch (`len` not 5, 6 with `b4 == 1`, 7 or 13) in `ctprotocol_decode.c`. No vector reaches the unknown-code reject of `0x02` or the unknown-length reject of `0x07` either. Only the unknown-opcode reject (`5a7f020000`) is recorded.
- No vector exercises the silent opcode list, the `0x02` high-bit `b4` values, `len` 19 of `0x07`, or the pending-ack upper clamp.
- No vector covers `setMalcolmParam` for NaN, for the (group, sub) pairs not listed under **Oracle**, for `n` of 42 or more, or for `d` between 17 and 258 other than the listed values. The same holds for `getFileDataBlk` with a source array shorter than `len`.
- No encode or decode vector has been run on arm64 or against a physical device. The Device evidence is limited to load, bind, connect and live operation ([ARM64_RUNTIME.md](../research/arm64/ARM64_RUNTIME.md)); a swallowed `ArrayIndexOutOfBoundsException` in the stock Java `CtProtocolMgr` occurs on certain live frames and is outside the native code ([ARM64_VERDICT.md](../research/arm64/ARM64_VERDICT.md)).

## Where the research records are superseded

| Record statement | Current behavior (code) |
|---|---|
| Decode returns `false` only for an unknown opcode ([DECODE_ENTRY.md](../research/decoder/DECODE_ENTRY.md), [DECODE_REJECTION_MATRIX.md](../research/decoder/DECODE_REJECTION_MATRIX.md), [PHASE2_VERDICT.md](../research/decoder/PHASE2_VERDICT.md)) | Three cases, per [DECODE_IMPLEMENTATION.md](../research/decoder/DECODE_IMPLEMENTATION.md) and the code, plus `0x02` `len` 6 with `b4 != 1` |
| `dataAck` requires `b4 == 0` ([DECODE_IMPLEMENTATION.md](../research/decoder/DECODE_IMPLEMENTATION.md)) | The code accepts `b4` in {0, 0x80, 0x81} |
| `audioLvl` and the zero-tail read apply to `plen` below 3 (decoder header comment, [DECODE_IMPLEMENTATION.md](../research/decoder/DECODE_IMPLEMENTATION.md)) | `audioLvl` fires for `plen` below 5; bytes beyond the declared payload are read for `plen` 0 to 2 (up to three bytes) |
| One callback per recognized frame ([DECODE_ENTRY.md](../research/decoder/DECODE_ENTRY.md)) | `0x19` and `0x22` emit one event per record |
| Reject error magnitudes mirror the stock builder (encoder header comment) | The core returns -1 for every reject |
| `enc_stock.txt` holds 97 vectors ([CHECKPOINT.md](../research/arm64/CHECKPOINT.md)) | The file holds 164 `ENC` rows, 1 `INT` row and a `DONE` marker (166 lines) |
| `dec_valid.txt` comments describe `hwBtn` callbacks as `(i,byte[])` | The signature is `(IZZZZZZZ)V` |

## Sources

- [`patches/arm64/native/ctprotocol/core/ctprotocol_encode.h`](../../patches/arm64/native/ctprotocol/core/ctprotocol_encode.h) and [`.c`](../../patches/arm64/native/ctprotocol/core/ctprotocol_encode.c)
- [`patches/arm64/native/ctprotocol/core/ctprotocol_decode.h`](../../patches/arm64/native/ctprotocol/core/ctprotocol_decode.h) and [`.c`](../../patches/arm64/native/ctprotocol/core/ctprotocol_decode.c)
- [`oracle/vectors/`](../../oracle/vectors/): `enc_stock.txt`, `dec_entry`, `dec_valid`, `dec_reject`, `dec_state`, `dec_stream` (`.txt` and `.out.txt`); [`oracle/README.md`](../../oracle/README.md)
- [`tests/ctprotocol/`](../../tests/ctprotocol/): `ctp_regress.c`, `CMakeLists.txt`, `compare.cmake`
- Research records: [ENCODE_SPEC.md](../research/encoder/ENCODE_SPEC.md), [ENCODE_VECTORS.md](../research/encoder/ENCODE_VECTORS.md), [ENCODE_DIFFERENTIAL.md](../research/encoder/ENCODE_DIFFERENTIAL.md), [DECODE_IMPLEMENTATION.md](../research/decoder/DECODE_IMPLEMENTATION.md), [DECODE_CALLBACK_MATRIX.md](../research/decoder/DECODE_CALLBACK_MATRIX.md), [DECODE_ENTRY.md](../research/decoder/DECODE_ENTRY.md), [DECODE_STREAM_BEHAVIOR.md](../research/decoder/DECODE_STREAM_BEHAVIOR.md), [DECODE_REJECTION_MATRIX.md](../research/decoder/DECODE_REJECTION_MATRIX.md), [DECODE_DIFFERENTIAL.md](../research/decoder/DECODE_DIFFERENTIAL.md), [FREEZE.md](../research/arm64/FREEZE.md), [RE.md](../research/arm64/RE.md), [ARM64_RUNTIME.md](../research/arm64/ARM64_RUNTIME.md), [ARM64_VERDICT.md](../research/arm64/ARM64_VERDICT.md)
