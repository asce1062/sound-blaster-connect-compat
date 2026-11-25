# 0002. Accept the reimplementation only by differential testing

Status: Accepted

## Context

There is no specification of the speaker protocol. The stock library is the
only authority on what a command frame looks like and which response produces
which callback. A reimplementation written from a static reading of the
binary can misread field order, range checks or edge cases, and hardware
tests cannot reach most rejection paths.

## Decision

The stock x86 library is the behavioral oracle. A Java harness with the stock
class's exact name (`oracle/`) runs a library over fixed inputs and prints one
deterministic line per result. The stock library's output is captured once
and frozen in `oracle/vectors/`. The reimplementation is accepted only when
its output is byte-identical to the stock library's on every vector set, and
the frozen files are never edited afterwards.

## Consequences

- Behavior is defined by recorded observations, not by interpretation of the
  decompiled code. Odd stock behavior is reproduced rather than "fixed".
- Coverage is limited to what the vectors exercise. Known gaps are listed in
  [TESTING.md](../development/TESTING.md#known-coverage-gaps).
- The harness needs a 32-bit x86 emulator. `tests/ctprotocol/` replays the
  same files on a host compiler so every change can be checked without one.
- The arm64 build is not run against the oracle directly; it shares the
  source that passes on x86 and on 64-bit hosts.

See [TESTING.md](../development/TESTING.md) and
[the research index](../research/README.md).
