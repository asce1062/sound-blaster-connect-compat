# 0006. Build the `resign` control without apktool

Status: Accepted

## Context

Every variant changes the signer, and an apktool round trip re-encodes the
manifest, resources and dex even when no patch is applied. If a re-signed
app misbehaves, it must be possible to tell whether signing alone or the
re-encoding caused it.

## Decision

The `resign` variant does not decode or rebuild. It copies the stock archive,
aligns it only if it is not already aligned (no recompression), signs it with
the debug key, and then fails the build unless every non-signature entry is
SHA-256 identical to the stock entry.

## Consequences

- `resign` is the stock app with a different signature and nothing else,
  enforced by the build. It is the control for signing effects such as Play
  Protect behavior and signature conflicts.
- `resign` keeps targetSdk 26 and the 32-bit-only libraries, so it does not
  run on 64-bit-only phones.
- The other variants go through apktool and are not payload-identical; their
  differences are the documented patches plus apktool's re-encoding.

See the payload contract in
[ANDROID_COMPATIBILITY.md](../technical/ANDROID_COMPATIBILITY.md#resign-payload-preservation-contract).
