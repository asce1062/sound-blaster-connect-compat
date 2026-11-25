# 0009. Derive all version metadata from the CMake project version

Status: Accepted

## Context

A release needs an Android versionName and versionCode, a Git tag and an
artifact name. Kept separately, they drift. Android also requires each update
to carry a larger versionCode than the installed one, and the stock app's
version (1.04.02, code 10402) has to stay visible, because it fixes which
release the patches apply to.

## Decision

- `project(VERSION MAJOR.MINOR.PATCH)` in `CMakeLists.txt` is the only version
  source. `cmake/sbc_version.cmake` derives the rest.
- versionName is `<upstream>-compat.<project>`, for example
  `1.04.02-compat.0.1.0`.
- versionCode is `MAJOR * 1000000 + MINOR * 1000 + PATCH`, each component
  0 to 999; configure fails outside that range.
- The tag is `v<project>` and the release APK is
  `sbconnect-compat-<tag>.apk`. Configure writes all values to
  `build/release.env` for release tooling.

## Consequences

- versionCode order matches project version order, so updates are always
  accepted in sequence. 0.1.0 has code 1000.
- The code is unrelated to the stock 10402. The packages differ, so the
  system never compares the two.
- A component above 999, or a fourth component, needs a new scheme and a new
  record.

Detail: [APPLICATION_IDENTITY.md](../technical/APPLICATION_IDENTITY.md#versions).
