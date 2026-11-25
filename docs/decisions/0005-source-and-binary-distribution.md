# 0005. Offer source builds and signed binaries as first-class outputs

Status: Accepted, not yet implemented

## Context

Most users want an APK they can install. Others want to build from their own
copy of the stock app and verify every step. Forcing one route either
excludes users who cannot run the toolchain or asks users to trust a binary
they cannot check.

## Decision

Both routes are supported as equal outputs:

- **Source build:** the pipeline in this repository, run on the user's own
  copy of the stock APK, as documented in
  [BUILDING.md](../development/BUILDING.md). This route works today.
- **Signed binary:** a release APK signed with the project's release key and
  published with its checksums. The release key, application identity and
  release workflow do not exist yet; they will be recorded in separate
  decisions when they are established.

## Consequences

- The source route remains complete on its own; nothing in it may depend on
  release infrastructure.
- The two routes produce differently signed APKs, which Android treats as
  different signers. Switching between them requires an uninstall.
- Whether and how a binary containing the stock app's code may be published
  is an open question for the project owner. This record does not settle it.
