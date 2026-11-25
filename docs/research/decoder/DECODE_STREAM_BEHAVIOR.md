# Decode stream / framing behavior (ORACLE-CAPTURED)

> **Historical record.** Kept as evidence of how behavior was established; not updated for later changes. Status, corrections and the maintained references: [research index](../README.md).

Gate D2. How the stock decoder treats call boundaries, partial frames,
concatenation, and junk, captured against the oracle (not inferred from
decompilation). Corpus [`vectors/dec_stream.txt`](../../../oracle/vectors/dec_stream.txt),
capture [`vectors/dec_stream.out.txt`](../../../oracle/vectors/dec_stream.out.txt),
run under `seq` mode where a blank line opens a new observation window and each
line within a window is one `decode()` call (callbacks cleared only at window
start, so cross-call carryover is directly observable).

Building blocks: frame A = `5a03020000` (`maxPlsCallback 0`), frame B =
`5a060100` (`requestControlCallback 0`).

## The 8 scenarios

| # | scenario | input | result | behavior |
|---|---|---|---|---|
| 1 | full frame, one call | A | `maxPls 0` | accepted |
| 2 | split across calls | `5a0302`, then `0000`, then A | nothing, nothing, `maxPls 0` | no reassembly; control fires |
| 3 | two frames concatenated, one call | `5a030200005a060100` | nothing | whole buffer rejected |
| 4 | full + partial next, one call | `5a030200005a06` | nothing | whole buffer rejected |
| 5 | partial completed by next call | `5a06`, then `0100`, then B | nothing, nothing, `requestControl 0` | no reassembly; control fires |
| 6 | same frame twice | A, then A | `maxPls 0`, `maxPls 0` | both fire; no de-dup |
| 7 | non-frame prefix | `ff5a03020000` | nothing | rejected; no resync to `0x5a` |
| 8 | trailing junk byte | `5a03020000ff` | nothing | rejected; no trailing tolerance |

## Stream model

The decoder is a **single-frame, exact-length, stateless validator**. Each
`decode(buf, len)` call must contain exactly one complete frame and nothing else:

- `len >= 3`, `buf[0] == 0x5a`, `buf[2] == len - 3`. Any buffer that is not
  exactly one frame of the declared length is rejected whole (scenarios 3, 4, 8).
- It does **not** buffer or reassemble across calls (2, 5): a partial frame is
  dropped, and the following call starts clean. There is no inter-call state to
  hold a pending header.
- It does **not** consume multiple concatenated frames from one buffer (3): the
  length gate sees the whole buffer as one over-long frame and rejects it.
- It does **not** resync past a non-`0x5a` prefix (7): the magic-byte gate fails
  and the call is rejected; it does not scan forward for a frame start.
- It does **not** de-duplicate repeats (6): identical successive frames each fire.

## Consequence for the reimplementation

Framing and reassembly are the **caller's** responsibility, exactly as in the
stock app: `CtProtocolMgr` (pure Java, the `BluzSocket` transport layer) delivers
one complete frame per `decode()` call. The portable `ctprotocol-core` decoder
therefore needs no receive buffer and no stream state. It must:

1. reject unless `len >= 3 && buf[0] == 0x5a && buf[2] == len - 3`;
2. dispatch on `buf[1]` (and sub-discriminants) to at most one callback;
3. hold no state between calls.

Reproducing a cross-call buffer would be a behavioral divergence, not a
compatibility feature.
