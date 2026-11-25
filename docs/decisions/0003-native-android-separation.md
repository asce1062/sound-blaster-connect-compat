# 0003. Separate native-library work from Android packaging work

Status: Accepted

## Context

Two independent problems keep the stock app off current phones: its Android
manifest and code predate the rules of Android 12 to 14, and its native
libraries exist only for 32-bit processors. Fixing them together would make
every failure ambiguous: a crash could come from a manifest change, a smali
patch or a native library.

## Decision

Android compatibility changes live in the `modernize` patch and touch only
the manifest, smali and resources. Native libraries live in the `arm64`
patch and its `native/` source and touch only `lib/arm64-v8a/`. The `arm64`
variant is `modernize` followed by `arm64`. Protocol semantics are never
changed by either.

## Consequences

- `modernize` can be built and tested without an NDK, and its effect is
  visible on any phone that still runs 32-bit code.
- A native change cannot alter Android behavior and an Android change cannot
  alter protocol behavior, so each kind of regression has one place to look.
- The `resign` variant changes neither and serves as the control for signing
  alone ([0006](0006-resign-bypasses-apktool.md)).
