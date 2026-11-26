# 0012. Run APK builds and releases from the private build-input repository

Status: Accepted

## Context

The APK workflows need the stock APK, and the release workflow needs
signing secrets. Their outputs (unsigned, debug-signed and rehearsal APKs,
release inputs) contain the stock app's code. In a public repository,
anyone can download its workflow artifacts and read its logs, and a pull
request from a fork runs with the base branch's caches. A public compat
repository can therefore hold none of these, and its pull requests must not
reach a credential.

## Decision

- The compat repository runs source CI only (`.github/workflows/ci.yml`):
  host suites, native libraries, pins, links and hygiene. It has no secret,
  environment, variable or deploy key, and uploads no artifact and uses no
  cache.
- The APK build, release and verification workflows live in `ci/trusted/`
  of the compat repository and run from `.github/workflows/` of the private
  build-input repository, which also holds the stock APK. They run only on
  dispatch, check out the compat source at a full commit SHA, and refuse to
  run in a public repository, for a commit on no branch of the source
  repository (a fork's pull-request commit), or when their own files differ
  from `ci/trusted/` at that commit.
- Every artifact upload in a trusted workflow is conditional on the running
  repository being private. Artifacts stay in the build-input repository.
- `scripts/ci/check_workflows.py`, run by source CI, fails a public
  workflow that reads a secret, names an environment, uploads, caches, has
  a privileged trigger or grants a write permission, and a trusted workflow
  without these guards.
- A release is prepared and verified as a draft in the build-input
  repository; its unchanged assets and notes are then copied to a draft
  release of the compat repository, the published distribution route
  ([0005](0005-source-and-binary-distribution.md)).

## Consequences

- Making the compat repository public exposes source, source CI logs and
  release assets, and nothing from the APK pipeline.
- A change to `ci/trusted/` takes effect only after it is copied to the
  build-input repository; until then the trusted workflows refuse the new
  commit.
- While the compat repository is private, the build-input repository's
  token cannot read it; the commit to build is mirrored to the build-input
  repository and `SBC_SOURCE_REPOSITORY` names that repository.

Detail: [CI.md](../development/CI.md),
[RELEASE.md](../development/RELEASE.md#each-release).
