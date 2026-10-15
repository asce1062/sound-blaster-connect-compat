# modernize patch

Raises the app's target API level and applies the behavior changes newer
Android enforces. Layered on top of the `resign` repackage (the `modernize`
variant = this patch; the `arm64` variant = this patch + `arm64`).

This patch is **owned by the 32-bit-capable pipeline track** and is a
scaffold right now — `patch.cmake` bumps the target SDK and nothing else, so
the `modernize` variant currently builds the same bytes as `resign` plus the
manifest/yml SDK change. Fill in the rest on a device, one change at a time,
rebuilding and testing between each.

## What a target-SDK bump requires

The stock app is `minSdk 14 / targetSdk 26`. Raising `targetSdkVersion` opts
the app into stricter runtime behavior that must be handled in smali or it
crashes or silently loses function:

- **targetSdk ≥ 31 (Android 12):** every `<activity>/<service>/<receiver>`
  with an `<intent-filter>` must set `android:exported` explicitly, or the
  package fails to install. `PendingIntent`s must pass `FLAG_IMMUTABLE` or
  `FLAG_MUTABLE`.
- **targetSdk ≥ 31 + Bluetooth:** the legacy `BLUETOOTH` / `BLUETOOTH_ADMIN`
  permissions stop granting scan/connect. Needs `BLUETOOTH_SCAN`,
  `BLUETOOTH_CONNECT` (runtime-requested) and the `neverForLocation` flag or
  location, depending on whether scanning derives location.
- **targetSdk ≥ 33 (Android 13):** `POST_NOTIFICATIONS` is a runtime
  permission; the `MainService` notification needs it requested.
- **Foreground services:** `android:foregroundServiceType` is required, and
  from targetSdk 34 a matching `FOREGROUND_SERVICE_*` permission.

Decide how far to push (33 vs 34) on the device you are targeting; each step
adds surface. `docs/FINDINGS.md` has the component inventory and the exact
manifest entries.

## Layout

- `overlay/` — whole-file replacements, mirroring the decoded tree
  (`AndroidManifest.xml`, `res/...`, `smali/...`).
- `patch.cmake` — in-place edits (bump `apktool.yml` targetSdk, inject a
  manifest attribute, rewrite a smali line). Runs with `${TREE}` set to the
  staged tree.
