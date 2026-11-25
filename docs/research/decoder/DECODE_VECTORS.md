# Decode valid-frame vectors (ORACLE-CAPTURED)

> **Historical record.** Kept as evidence of how behavior was established; not updated for later changes. Status, corrections and the maintained references: [research index](../README.md).

Gate D1. The frozen valid-frame corpus and its oracle capture: every
response/callback family constructible from the static dispatcher, each reached by
at least one accepted frame. Corpus
[`vectors/dec_valid.txt`](../../../oracle/vectors/dec_valid.txt), capture
[`vectors/dec_valid.out.txt`](../../../oracle/vectors/dec_valid.out.txt), run with
`oracle/run.sh <so> dec vectors/dec_valid.txt`. Per-family argument detail and the
3 unreachable families are in
[DECODE_CALLBACK_MATRIX.md](DECODE_CALLBACK_MATRIX.md).

## Frame format (inbound)

```
5a <op> <plen> <payload[plen]>        total length = plen + 3
```

Entry gate: `len >= 3`, `buf[0] == 0x5a`, `buf[2] == len - 3`; dispatch on
`buf[1]`. Several opcodes discriminate further on the first payload byte
(`sub = buf[3]`) or on `plen`. Multi-byte scalars in payloads are little-endian.

## Corpus shape

27 accepted frames: 25 that each fire exactly one distinct callback family (one per
reachable family), plus 2 ordering demonstrators (op19 with record count 2 and 3)
that fire `profileInfoRecFirstCallback` once per record. Every frame is
oracle-verified to fire its named family; the run produces 25 distinct callbacks
with no frame failing to fire.

The frames were derived by sweeping each gated opcode's discriminant until the
accept path was found, then reducing to one minimal accepted frame per family. The
sweeps that located the record and ack discriminants (op02 `plen`/code, op19
mode/count, op1a sub, op26/op27/op28 sub ranges) are retained in the RE workspace;
the reduced corpus here is the frozen artifact.

## Coverage

| opcode | families reached |
|---|---|
| op02 | obsoleteAck, pendingAck, fileAck, dataAck (by plen / code) |
| op03 | maxPls |
| op06 | requestControl |
| op07 | deviceInfo, fwInfo, devicefwString (by plen) |
| op19 | profileInfoRecFirst, profileInfoRest |
| op1a | activeProfileRec, activeProfileMega (by sub) |
| op22 | audioLvlRange |
| op23 | audioLvl |
| op26 | hwBtn, hwBtnSupport, hwBtnStatusSupport, hwBtnEnabled (sub 1..4) |
| op27 | batteryLevel, batteryLevelSupport (sub 1..2) |
| op28 | batteryStatus, batteryStatusSupport (sub 1..2) |
| op31 | btAutoConnect |
| op99 | voicePromptCtrl |

25 families, all ORACLE-CAPTURED. Opcodes present in the dispatcher but carrying no
callback (record-store forms op11/op13/op14/op15/op16/op21 and the set/ack-only
opcodes) accept their frames without emitting a callback; they are not a callback
family and are out of scope for this matrix.

## Reproduce

```bash
cd oracle && ./run.sh ../decompiled/lib/x86/libsbxapplogic_ctprotocol_jni.so dec vectors/dec_valid.txt
```

Output is deterministic and matches `vectors/dec_valid.out.txt` line for line.
