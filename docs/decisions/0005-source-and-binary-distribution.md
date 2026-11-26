# 0005. Offer source builds and signed binaries as first-class outputs

Status: Accepted; both routes implemented, the first signed release is an unpublished draft

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
  published with its checksums as a GitHub release of this repository. The
  application identity is [0008](0008-separate-distribution-identity.md),
  the signing pipeline and key [0011](0011-release-signing-modes.md), and
  the release automation [0012](0012-trusted-builds-in-private-repository.md).

## Consequences

- The source route remains complete on its own; nothing in it may depend on
  release infrastructure.
- The two routes produce differently signed APKs, which Android treats as
  different signers. Switching between them requires an uninstall.
- A signed binary contains the stock app's code in modified form. Publishing
  one is the project owner's decision; the release route ends at a draft
  release, and this record does not make that decision.
