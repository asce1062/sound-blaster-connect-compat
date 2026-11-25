# Decode rejection matrix and statefulness controls (ORACLE-CAPTURED)

> **Historical record.** Kept as evidence of how behavior was established; not updated for later changes. Status, corrections and the maintained references: [research index](../README.md).

Gates D3 (bounded, deterministic rejection vectors) and D4 (statefulness
controls). Not a broad fuzz: a fixed set of single-mutation vectors, each paired
with a known-good control fed through the same observation window so that
non-poisoning is proven, not assumed.

- D3 corpus [`vectors/dec_reject.txt`](../../../oracle/vectors/dec_reject.txt),
  capture [`vectors/dec_reject.out.txt`](../../../oracle/vectors/dec_reject.out.txt).
- D4 corpus [`vectors/dec_state.txt`](../../../oracle/vectors/dec_state.txt),
  capture [`vectors/dec_state.out.txt`](../../../oracle/vectors/dec_state.out.txt).

Control frame = `5a03020000` (`maxPlsCallback 0`). Both run in `seq` mode.

## D3 - rejection matrix

Each group is `[mutant, control]`. Every mutant produced no callback; every
control fired `maxPls 0`.

| # | mutation | input | ret | callback |
|---|---|---|---|---|
| 1 | truncate by one byte | `5a030200` | 1 | none |
| 2 | truncate to header only | `5a03` | 1 | none |
| 3 | declared length too large | `5a03030000` (plen=3, 2 present) | 1 | none |
| 4 | declared length too small | `5a03010000` (plen=1, 2 present) | 1 | none |
| 5 | magic-byte mutation | `5b03020000` | 1 | none |
| 6 | unknown sub-command | `5a26050900000000` (op26 sub=9) | 1 | none |
| 7 | unknown command | `5a7f020000` (op=0x7f) | **0** | none |
| 8 | unknown sub-command | `5a27020300` (op27 sub=3) | 1 | none |
| 9 | min payload | `5a0300` (op03 plen=0) | 1 | none |
| 10 | starved sub payload | `5a260101` (op26 plen=1) | 1 | none |
| 11 | max payload | `5a03ff` + 255 bytes (op03 plen=0xff) | 1 | none |

Findings:

- **Rejection is callback absence.** `ret` stays `1` for every rejected frame
  except the unknown top-level opcode (D3-7), which is the only case that returns
  `0`. A reimplementation keys accept/reject on callback emission and reproduces
  `ret=0` only for an unrecognised opcode.
- **Exact framing** (D3-1..5): `len >= 3`, `buf[0]==0x5a`, `buf[2]==len-3`. Any
  deviation, in either direction, rejects.
- **Per-family payload length** (D3-9, D3-11): a correctly framed op03 whose
  payload length is not what `maxPls` expects (plen 0 or 0xff instead of 2) is
  dispatched to the op03 handler but emits no callback. Each family validates its
  own payload length internally; passing the entry gate is necessary, not
  sufficient.
- **Sub-command ranges** (D3-6, D3-8, D3-10): op26 accepts sub 1..4, op27 accepts
  sub 1..2; an out-of-range or payload-starved sub-command is dropped with no
  callback.
- **No poisoning**: every control fired normally after its mutant.

## D4 - statefulness controls

The decisive test (directive D4): identical bytes at different points in a run
must produce identical output; any difference would be hidden decoder state and a
STOP condition. No such difference occurred.

| # | control | observation |
|---|---|---|
| 1 | fresh baseline | `maxPls 0` |
| 2 | identical frame x3 | `maxPls 0` x3 (no de-dup, no accumulation) |
| 3 | interleaved families | `maxPls 0` at calls 1,3,5 is invariant across intervening `batteryLevel`/`requestControl` |
| 4 | after rejected frames | reject (op 0x7f, ret=0), then `maxPls 0`; reject (bad length, ret=1), then `maxPls 0` |
| 5 | after a partial frame | `5a0302` -> nothing, then `maxPls 0` |
| 6 | after a concatenated buffer | reject, then `maxPls 0` |
| 7 | value tracking | payload `00` -> `maxPls 0`, `07` -> `maxPls 7`, `00` -> `maxPls 0` |

Finding: **no hidden decoder state.** Output depends only on the current call's
bytes. Repeats, interleaving, a preceding reject, a partial, or a concatenated
buffer leave no residue; reverting the input bytes reverts the output exactly
(D4-7). This reconfirms the per-call lifetime from
[DECODE_ENTRY.md](DECODE_ENTRY.md) behaviorally.
