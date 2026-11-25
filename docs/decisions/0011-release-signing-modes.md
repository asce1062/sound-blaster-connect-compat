# 0011. Sign releases in a separate, fail-closed pipeline with externally supplied keys

Status: Accepted; the production key does not exist yet

## Context

Every variant is signed with uber-apk-signer's debug key, which is fine for
development and for the `resign` control but cannot sign a release: anyone
can sign with a debug key, and Android installs an update only when its
signer matches the installed app. A release key therefore has to stay
private and unchanged for the life of the application ID
([0008](0008-separate-distribution-identity.md)), and a build that silently
signs with the wrong key produces an APK that cannot update existing
installs. Signing credentials must not end up in the repository, the build
tree or logs.

## Decision

- Three signing modes: **debug** (every variant, unchanged), **test-release**
  (a disposable key, for rehearsals) and **release** (the production key).
  test-release and release are separate targets for `compat`, each with its
  own environment prefix (`SBC_TEST_RELEASE_`, `SBC_RELEASE_`).
- Credentials, the keystore path and the expected certificate SHA-256 come
  only from the environment of the build, read when the target runs.
  `apksigner` reads the passwords from the environment itself. Nothing is a
  CMake cache entry or a command-line argument.
- A missing credential, a wrong password or alias, or a certificate that
  differs from the expected SHA-256 fails the target. No mode falls back to
  another mode's key; release additionally refuses an Android debug
  certificate and a checkout with uncommitted changes.
- Signing starts from the unsigned APK as its own step, then runs as
  separate processes: align and sign with the pinned build-tools
  `zipalign` and `apksigner` (v1, v2, v3), an independent verify (signature,
  alignment, fingerprint, package metadata, native library inventory,
  payload against the unsigned APK), and publication with SHA-256 and JSON
  metadata. The APK is renamed into place after verification and never
  modified afterwards.

## Consequences

- A failed signing leaves no file under the release name.
- The same verify script checks any downloaded release against the published
  fingerprint.
- Release builds need the pinned build-tools (`37.0.0`) in addition to the
  debug pipeline's tools.
- The production key, its backup and its published fingerprint are operator
  steps; until they exist, `apk-compat-release` cannot succeed. CI signing
  is an interface without a workflow or secrets.
- Debug, test-release and release APKs have different signers; moving an
  install between them requires an uninstall.

Detail: [SIGNING.md](../development/SIGNING.md),
[RELEASE.md](../development/RELEASE.md).
