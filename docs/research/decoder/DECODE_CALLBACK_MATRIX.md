# Decode callback matrix (ORACLE-CAPTURED / UNREACHABLE)

> **Historical record.** Kept as evidence of how behavior was established; not updated for later changes. Status, corrections and the maintained references: [research index](../README.md).

Gates D1 (valid-frame coverage) and D5 (callback fidelity). Every inbound callback
the stock decoder can emit, keyed on the opcode and discriminant that reaches it,
with the exact typed arguments captured from the oracle. JNI signatures are the
frozen descriptors from
[FREEZE.md](../arm64/FREEZE.md#inbound-callbacks-28-cached-static-methods-name---jni-signature);
argument values are from [`vectors/dec_valid.out.txt`](../../../oracle/vectors/dec_valid.out.txt).
Discriminants are stated in observable terms (opcode byte `buf[1]`, payload length
`plen`, first payload byte `sub = buf[3]`).

A family is **ORACLE-CAPTURED** only where at least one accepted frame reached it.
Field *meaning* is not invented where the stock library does not expose it; where
a structural position has no name, the captured value stands on its own.

## 25 reachable callbacks (ORACLE-CAPTURED)

| callback | JNI sig | reached by | example frame | captured args |
|---|---|---|---|---|
| obsoleteAckCallback | (II)V | op02, plen=2 | `5a02020100` | `1 0` |
| pendingAckCallback | (III)V | op02, plen=4 | `5a020401010000` | `1 1 2` |
| fileAckCallback | (III)V | op02, plen=3 | `5a0203010100` | `1 0 1` |
| dataAckCallback | (II[B)V | op02, plen=0xa, code!=0x3a | `5a020a01001122334455667788` | `1 0 [len=8]1122334455667788` |
| maxPlsCallback | (I)V | op03, plen=2 | `5a03020000` | `0` |
| requestControlCallback | (Z)V | op06 | `5a060100` | `0` |
| deviceInfoCallback | (II)V | op07, plen=4 | `5a070400000000` | `0 0` |
| fwInfoCallback | (IIIII)V | op07, plen=6 | `5a0706000000000000` | `0 0 0 0 0` |
| devicefwStringCallback | ([I)V | op07, plen=0x40 | `5a0740`+64B | `[len=64]0,0,…` |
| activeProfileRecCallback | (IZ)V | op1a, sub=1 | `5a1a020100` | `0 0` |
| activeProfileMegaCallback | (IZ)V | op1a, sub=2 | `5a1a020200` | `0 0` |
| profileInfoRecFirstCallback | (IIIZIZZIZ)V | op19, mode=1 | `5a190700010001000000` | `0 0 0 0 0 0 1 0 1` |
| profileInfoRestCallback | (IIZIZZIZ)V | op19, sub&0x7f!=0, buf4=1 | `5a1906010100000000` | `0 0 0 0 0 1 0 1` |
| audioLvlRangeCallback | (IFFFIII)V | op22, plen=9 | `5a2209010000000000000000` | `0 0.0 0.0 0.0 0 0 0` |
| audioLvlCallback | (IFI)V | op23, plen=4 | `5a230400000000` | `0 0.0 0` |
| hwBtnCallback | (IZZZZZZZ)V | op26, sub=1 | `5a26050100000000` | `0` + 7 bool |
| hwBtnSupportCallback | (IZZZZZZZ)V | op26, sub=2 | `5a26050200000000` | `0` + 7 bool |
| hwBtnStatusSupportCallback | (IZZZZZZZ)V | op26, sub=3 | `5a26050300000000` | `0 1100111` |
| hwBtnEnabledCallback | (IZZZZZZZ)V | op26, sub=4 | `5a26050400000000` | `0` + 7 bool |
| batteryLevelCallback | (I)V | op27, sub=1 | `5a27020100` | `0` |
| batteryLevelSupportCallback | (III)V | op27, sub=2 | `5a270402000000` | `0 0 0` |
| batteryStatusCallback | (ZZ)V | op28, sub=1 | `5a28050100000000` | `0 0` |
| batteryStatusSupportCallback | (ZZ)V | op28, sub=2 | `5a28050200000000` | `0 0` |
| btAutoConnectCallback | (I)V | op31 | `5a310100` | `0` |
| voicePromptCtrlCallback | (I)V | op99 | `5a990100` | `0` |

## 3 unreachable callbacks (UNREACHABLE-FROM-KNOWN-DISPATCH)

These method IDs are cached by `JNI_OnLoad` (part of the all-or-nothing 28) but no
accepted frame reaches them, established from the dispatcher and the `MyListener`
vtable, not from failure to guess an input:

| callback | JNI sig | why unreachable |
|---|---|---|
| audioCtrlCallback | (IZ)V | No native `listen()` bridge references its method ID. No vtable slot upcalls it, so no opcode can dispatch it. |
| sbxProfileInfoCallback | (II)V | Bridge exists at vtable `+0xe8` (real `0xdc80`), but `Decode::decode` never dispatches offset `+0xe8`. |
| sbxProfileDataCallback | (I)V | Bridge exists at vtable `+0xec` (real `0xdbf0`), but `Decode::decode` never dispatches offset `+0xec`. |

Supporting evidence: `Decode::decode` (`@0001a520`) dispatches through 54 distinct
vtable offsets spanning `+0x0c..+0xf0` and skips exactly `{+0x64, +0xc8, +0xe8,
+0xec}`. `+0x64` and `+0xc8` are listener-management slots, not callbacks; `+0xe8`
and `+0xec` are the sbxProfile bridges. The 24 offsets that carry the 25 captured
families are all within the dispatched set; none fall in the skipped set. Vtable at
real vaddr `0x18dc8` (`vectors`-adjacent dump retained in the RE workspace).

## Fidelity (D5)

The capture distinguishes the typed surface unambiguously:

- **Floats** (`audioLvl`, `audioLvlRange`) are printed with their raw IEEE-754 bits
  (`Float.floatToRawIntBits`), so width and bit pattern are exact, not a decimal
  rendering.
- **Booleans** (`hwBtn` family `(IZZZZZZZ)V`, `requestControl` `(Z)V`, battery
  status `(ZZ)V`, `activeProfile*` `(IZ)V`) are the real JNI argument type; the
  7-digit groups in the capture are seven distinct boolean arguments.
- **Byte arrays** (`dataAck` `[B`) and **int arrays** (`devicefwString` `[I`) are
  printed as `null` vs `[len=N]<elements>`, so null, empty, and length are
  distinguishable.
- **Callback ordering**: a single op19 frame with record count N emits
  `profileInfoRecFirstCallback` N times in record order (count=2 -> records 0,1;
  count=3 -> records 0,1,2), captured in
  [`vectors/dec_valid.out.txt`](../../../oracle/vectors/dec_valid.out.txt). No other
  reachable opcode emits more than one callback per frame.

## Count reconciliation

28 cached callbacks = 25 ORACLE-CAPTURED + 3 UNREACHABLE-FROM-KNOWN-DISPATCH. No
family is STATIC-MAPPED-only (every reachable family was actually triggered) and
none is ORACLE-MISSING.
