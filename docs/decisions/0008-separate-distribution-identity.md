# 0008. Distribute under a separate application ID; keep stock-identity controls

Status: Accepted; application ID revised 2026-11-26, before any release

## Context

The stock-identity variants install as `com.creative.apps.sbconnect` with a
different signing key. Android refuses them as an update over a
Creative-signed install, so the user has to uninstall the stock app and lose
its data first, and two builds by different people collide under one package.
A distributed build also should not install as Creative's app.

The identifiers built into the APK describe what it is, a compatibility
build of Sound Blaster Connect, and carry no maintainer's namespace or name.
Maintainer credit belongs in the license and the repository, not in the app.

The stock code depends on its package name in one place that changes
behavior: `SbxDeviceManager` compares `getPackageName()` with the stock
package to select the SB Connect host path. The other uses of the package
name are self-relative.

## Decision

- Add a `compat` variant: `arm64` plus an `identity` patch that sets the
  application ID `com.creative.apps.sbconnect.compat` (the stock ID plus
  `.compat`), the label `SB Connect Compat` and the project version. The
  first ID, in the maintainer's `io.github` namespace, was replaced before
  any release; device records made with it are kept as they were.
- Change only identity sites: the manifest `package`, the provider authority,
  the three labels, the two `SbxDeviceManager` comparisons and the version
  fields. Java class names, JNI class names and action strings stay as in
  stock. No global namespace replacement.
- Keep `resign`, `modernize` and `arm64` on the stock identity as controls.

## Consequences

- `compat` installs next to the stock app, with its own data. Nothing
  migrates from a stock install.
- The JNI interface and the native libraries are the same as in `arm64`; the
  identity change does not touch protocol code.
- A regression that appears only in `compat` points at a package-dependent
  contract, since `arm64` differs from it only by the identity patch.
- A new package-dependent site in a future stock release would not be caught
  by the anchor counts; the audit would need repeating.

Audit and per-site detail:
[APPLICATION_IDENTITY.md](../technical/APPLICATION_IDENTITY.md).
