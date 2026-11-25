# Phase 2 verdict - decoder oracle

> **Historical record.** Kept as evidence of how behavior was established; not updated for later changes. Status, corrections and the maintained references: [research index](../README.md).

Single verdict for the decoder-oracle phase. The stock x86 CtProtocol library was
used as the behavioral oracle to recover the observable inbound contract; no
decoder code was implemented in this phase. Oracle `.so` 99672 bytes, SHA-256
`215a0bd15ef6f2dd9a5dca0a3c867824d9a61313b7a23cab8f6622779bee7f0e`.

## Verdict

**GO_DECODER_IMPLEMENTATION**

Grade advanced: decode surface **ORACLE-MISSING -> ORACLE-CAPTURED / DECODE**. The
encode surface remains DIFFERENTIAL-PASS / ENCODE; the two lanes are independent.

## Gate results

| gate | result | document |
|---|---|---|
| D0 entry contract | Frozen: `decode([BI)Z` static; explicit `len` from offset 0; fresh per-call `Decode`+`Context`, no persistent instance, no lifecycle method; one callback per frame via the `MyListener` vtable; all 28 IDs resolve; `ret` is not the accept signal. | [DECODE_ENTRY.md](DECODE_ENTRY.md) |
| D1 valid-frame corpus | 25 reachable families, each ORACLE-CAPTURED by a minimal accepted frame; 27-frame frozen corpus. | [DECODE_VECTORS.md](DECODE_VECTORS.md) |
| D2 stream / framing | Single-frame, exact-length, stateless validator. No reassembly, no multi-frame consume, no resync, no trailing tolerance, no de-dup. Framing is the caller's responsibility. | [DECODE_STREAM_BEHAVIOR.md](DECODE_STREAM_BEHAVIOR.md) |
| D3 rejection matrix | 11 deterministic vectors, all rejected (callback absence); each paired control fired; `ret=0` only for an unknown opcode; per-family payload-length and sub-command ranges enforced. | [DECODE_REJECTION_MATRIX.md](DECODE_REJECTION_MATRIX.md) |
| D4 statefulness | No hidden decoder state: identical bytes yield identical output regardless of history; rejects/partials/concatenation leave no residue. | [DECODE_REJECTION_MATRIX.md](DECODE_REJECTION_MATRIX.md#d4---statefulness-controls) |
| D5 callback fidelity | Floats as raw IEEE-754 bits, booleans as native type, arrays as null/empty/len-distinguished, callback ordering captured (op19 -> N records in order). | [DECODE_CALLBACK_MATRIX.md](DECODE_CALLBACK_MATRIX.md#fidelity-d5) |

## Why GO, not a NO_GO

- **Stream model resolved** (not NO_GO_STREAM_MODEL_UNRESOLVED): the oracle answered
  every framing question directly (D2), giving a closed, exact-length single-frame
  contract with no buffering.
- **Callback surface complete** (not NO_GO_CALLBACK_SURFACE_INCOMPLETE): all 25
  reachable families are ORACLE-CAPTURED with typed arguments; none is
  ORACLE-MISSING. The 3 remaining cached callbacks (audioCtrl, sbxProfileInfo,
  sbxProfileData) are UNREACHABLE-FROM-KNOWN-DISPATCH, established from the
  dispatcher and vtable (the stock binary itself never emits them), not an
  uncaptured gap. An exact-parity decoder reproduces the dispatcher, including not
  emitting these.
- **No hidden state** (not NO_GO_HIDDEN_STATE): D4 found the decoder fully stateless
  per call; no STOP-and-characterize condition arose.
- Therefore not NO_GO_MULTIPLE_BLOCKERS.

## What the implementation phase inherits

The portable `ctprotocol-core` decoder must:

1. Accept only `len >= 3 && buf[0] == 0x5a && buf[2] == len - 3`; read exactly
   `len` bytes from offset 0.
2. Dispatch on `buf[1]`, with the sub-command (`buf[3]`) and `plen` discriminants
   in [DECODE_CALLBACK_MATRIX.md](DECODE_CALLBACK_MATRIX.md), to at most one of the
   25 reachable callbacks.
3. Validate each family's own payload length internally (entry gate is necessary,
   not sufficient) and reject out-of-range sub-commands.
4. Hold no state between calls; buffer nothing; de-duplicate nothing.
5. Emit `profileInfoRecFirstCallback` once per record, in record order, for op19
   multi-record frames.
6. Signal rejection by not emitting a callback; return `1` always except `0` for an
   unknown top-level opcode.
7. Not implement audioCtrl / sbxProfileInfo / sbxProfileData dispatch paths.

The JNI shim then maps decode events onto the 28 cached Java callbacks (28 declared
for ABI parity with `JNI_OnLoad`; only 25 ever fire). DIFFERENTIAL-PASS for the
decoder means byte-for-byte identical `DEC`/`CB` output against
`vectors/dec_valid.*` and the D2/D3/D4 captures.

## Scope boundary

No portable decoder implementation was begun in this phase, per directive.
