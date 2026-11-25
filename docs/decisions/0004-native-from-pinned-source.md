# 0004. Build native libraries from source with a pinned NDK

Status: Accepted

## Context

Shipping prebuilt `.so` files in the repository would make the published
binaries unverifiable: a reader could not tell whether they match the source.
Different NDK releases also produce different machine code from the same
source, so "built from this source" is not reproducible without naming the
toolchain.

## Decision

No native binary is tracked. `cmake/sbc_native.cmake` builds
`patches/arm64/native/` during the main build with NDK `25.1.8937393`
exactly, rejecting any other revision. The libraries are built with
`-ffile-prefix-map`, a SHA-1 build ID and stripping, so their bytes do not
depend on the build machine's paths.

## Consequences

- Every arm64 APK carries libraries built from the tracked source.
- The same NDK revision produces byte-identical libraries from any checkout
  location, so independent builds can be compared by hash.
- Building the `arm64` variant requires that NDK revision. Without it the
  variant is skipped, not built with a different toolchain.
- Moving to another NDK is a deliberate change that needs a new comparison
  of the outputs and a new device run.

See [NATIVE_LIBRARIES.md](../technical/NATIVE_LIBRARIES.md).
