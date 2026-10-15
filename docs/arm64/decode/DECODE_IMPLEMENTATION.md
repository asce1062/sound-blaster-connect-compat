# Decode implementation

The portable `ctprotocol-core` inbound decoder. One JNI-free parser
([`core/ctprotocol_decode.c`](../../../patches/arm64/native/ctprotocol/core/ctprotocol_decode.c),
[`.h`](../../../patches/arm64/native/ctprotocol/core/ctprotocol_decode.h)) plus a
thin JNI adapter
([`jni/ctprotocol_jni_decode.c`](../../../patches/arm64/native/ctprotocol/jni/ctprotocol_jni_decode.c))
that maps typed events onto the stock `SbxSppCommandManager` static callbacks.
The same sources compile for x86 (differential) and arm64-v8a (device).

## Shape

`int ctp_decode(const uint8_t *frame, int len, ctp_emit_fn emit, void *user)`
parses exactly one frame and calls `emit` once per event, in dispatch order. The
core knows nothing about JNI, Java, Android, Bluetooth or callbacks: it reads
bytes and emits typed events. The adapter owns everything Java. No state crosses
calls: the decoder buffers nothing, concatenates nothing, resyncs nothing, and
tolerates no trailing bytes. This is the behaviour the Phase 2 stream and state
oracles froze ([`DECODE_STREAM_BEHAVIOR.md`](DECODE_STREAM_BEHAVIOR.md)).

## Frame grammar and entry gate

Inbound frame: `5A <op> <plen> <payload[plen]>`, total length `plen + 3`,
little-endian scalars. The entry gate is

```
len >= 3  &&  frame[0] == 0x5A  &&  frame[2] == (uint8_t)(len - 3)
```

Any gate failure returns `CTP_DECODE_OK` and emits nothing (Java `true`, no
callback). Dispatch is on `frame[1]`, then on a subcommand byte (`frame[3]`) or
on the total length, per opcode.

## Return model

The stock wrapper hands Java `decode(...) != 0x0b`. The core returns
`CTP_DECODE_UNRECOGNIZED` (`0x0b`, Java `false`) in exactly three cases, all
confirmed against the stock x86 library:

1. Unknown top-level opcode (dispatcher default).
2. `op02` whose code is outside the acknowledgement membership set, or whose
   gate-passing length matches no known `op02` form (`len` not in
   `{5, 6, 7, 13}`).
3. `op07` whose gate-passing length matches no known form (`len` not in
   `{7, 9, 19, 67}`).

Every other outcome returns `CTP_DECODE_OK` (Java `true`): a successful decode,
an entry-gate failure, and any per-family subcommand or length rejection.
**Acceptance is signalled by event emission, never by the return value** - a
recognized frame that fails a family-internal check returns `true` and emits
nothing, exactly like stock. (The Phase 2 prose in
[`PHASE2_VERDICT.md`](PHASE2_VERDICT.md) that read "ret=0 only for unknown
opcode" understates cases 2 and 3; the stock library returns `false` for all
three, verified live.)

## Dispatch table

| op | Subcommand / length | Family | Notes |
|---|---|---|---|
| 0x02 | code known, len 5 | obsoleteAck | `code`, `b4` (b4&0x7f < 2) |
| 0x02 | code known, len 7, b4==1 | pendingAck | `code`, `1`, LE16(b5) clamped [2,600] |
| 0x02 | code known, len 6, b4==1 | fileAck | `code`, `b5` (<4), `1` |
| 0x02 | code known, len 13, b4==0 | dataAck | `code`, `b4`, `b[5..12]`; code 0x3a is an internal bridge (no callback) |
| 0x03 | len 5 | maxPls | LE16(b3) |
| 0x06 | len 4 | requestControl | `b3 == 1` |
| 0x07 | len 7 or 19 | deviceInfo | LE16(b3), `b6` |
| 0x07 | len 9 | fwInfo | `b3`, `b4`, `b5`, LE16(b6), `b8` |
| 0x07 | len 67 | devicefwString | `int[64]` = `b[3..66]` |
| 0x19 | sub&0x7f==0, mode(b4)==1 | profileInfoRecFirst | per-record; `plen == count*3 + 4`, `count=b6` |
| 0x19 | sub&0x7f!=0 | profileInfoRest | per-record; `plen == (count+1)*3`, `count=b4` |
| 0x1a | len 5, sub(b3) 1/2 | activeProfileRec / activeProfileMega | `b4&0x7f`, `b4>>7` |
| 0x22 | `plen == count*7 + 2`, `count=b3` | audioLvlRange | per-record, 7 bytes each |
| 0x23 | plen < 5 | audioLvl | `b3`, reserved float `0.0`, LE16(b4) |
| 0x26 | plen 5, sub(b3) 1/2/3/4 | hwBtn / hwBtnSupport / hwBtnStatusSupport / hwBtnEnabled | LE32(b4) + 7 bools |
| 0x27 | sub 1 len 5 / sub 2 len 7 | batteryLevel / batteryLevelSupport | `b4` / `b4`,`b5`,`b6` |
| 0x28 | len 8, sub 1/2 | batteryStatus / batteryStatusSupport | `b4&1`, `(b4>>1)&1` |
| 0x31 | len 4, b3<2 | btAutoConnect | `b3` |
| 0x99 | len 4, b3<3 | voicePromptCtrl | `b3` |

Opcodes `0x01 0x05 0x10 0x11 0x13 0x14 0x15 0x16 0x1e 0x20 0x21 0x24 0x25 0x30
0x32 0x33 0x34 0x35 0x36 0x38 0x39 0x3a` are recognized (return `true`) but reach
no Java callback: internal listener slots or record-store forms with no bridge.

## Field extraction notes

- **Java argument order is not frame order.** Each event struct is laid out in
  the Java callback argument order, pinned empirically against the stock oracle
  with distinct-value probes, because the stock bridges reorder fields.
- **`deviceInfo`** passes LE16(b3) and `b6`; `b5` is skipped by the `(II)` bridge.
- **`hwBtn` bit map** (per the 7 booleans): positions pull from `b4` bits
  `{0,3,-,-,-,4,7}` and `b6` bits `{-,-,2,3,1,-,-}`. The status-support family
  (`sub==3`) inverts positions 0,1,4,5,6 and leaves 2,3 direct, so an all-zero
  payload yields `1100111`.
- **`profileInfoRecFirst`** args are `(X, record_index, type, ...)`: `X` is
  payload byte `b5`, `record_index` is the 0-based ordinal of the record within
  the frame. **`profileInfoRest`** args are `(X + record_index, type, ...)`:
  stock folds the header byte and the ordinal into one running arg and drops the
  separate index. Both were pinned with distinct multi-record frames (a
  single-record frame cannot tell `X`, `index` and `type` apart when all three
  are zero).
- **`audioLvl` / `audioLvlRange` floats are always `0.0f`** in the decode path,
  regardless of payload (confirmed by a per-byte sweep); they are reserved in
  inbound frames.
- **`op19` record validation is two-pass.** Every record is validated first
  (`type` in `{0,1,2,3,0x40,0x41}`; `type 0` field <= 0x0c, `type 0x40` any,
  others field <= 4); if any record is invalid the whole frame emits nothing and
  returns `true`. Only when all records pass are events emitted, in record order.
- **`op19` mode gate.** `profileInfoRecFirst` emits only when `mode (b4) == 1`;
  modes 0/2/3 reach bridges with no Java callback. The decompiled structure
  admits mode 0, but the stock bridge filters it, so the core gates on `mode==1`.

## Buffer contract

`ctp_decode` reads the frame in place. A few degenerate short frames (`op23`
with `plen < 3`) make the stock dispatcher read up to two bytes past the declared
payload out of its zeroed work buffer; the caller passes the frame in a
zero-initialized buffer of at least `CTP_DECODE_MINBUF` (258) bytes so those
reads see zero rather than running past the allocation. Real device frames carry
an 8-bit `plen` and never exceed this. The adapter copies the first `len` bytes
of the Java `byte[]` into a zeroed 258-byte buffer and clamps `len` to it.

## JNI adapter

`decode([BI)Z` copies the frame, runs `ctp_decode`, and returns
`ret != CTP_DECODE_UNRECOGNIZED`. `JNI_OnLoad` caches the 28 inbound callback
method IDs all-or-nothing (any `GetStaticMethodID` failure fails the load with
`-1`), mirroring the stock loader. Three of the 28 (`audioCtrl`,
`sbxProfileInfo`, `sbxProfileData`) are cached but never invoked: no dispatcher
path reaches them, in stock or here. Each emitted event maps to one
`CallStaticVoidMethod` with the cached method ID and the args in Java order.
