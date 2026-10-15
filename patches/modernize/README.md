# modernize patch

Raises the app's target API level and applies the behavior changes newer
Android enforces. Layered on top of the `resign` repackage (the `modernize`
variant = this patch; the `arm64` variant = this patch + `arm64`).

This patch is **owned by the 32-bit-capable pipeline track**. `patch.cmake`
raises `targetSdkVersion` to **34** and applies every manifest/smali change
the 31/33/34 behavior gates force (see "What this patch does"). It builds and
signs clean; the ABIs are unchanged (`armeabi armeabi-v7a utility x86`). What
remains is the runtime permission-request UI, which needs a device (see
"Remaining — device-gated").

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

## What this patch does

All edits are in-place in `patch.cmake`; the patch ships no `overlay/`.

- **targetSdkVersion 26 -> 34** in `apktool.yml` (apktool writes it into the
  built manifest).
- **`android:exported` (>=31)** added to the 5 filtered components that
  lacked it: `MainActivity`, `MainReceiver`, `LocalMusicRemoteControllerService`
  and `MediaButtonReceiver` stay exported (system-driven); `AppMeasurementReceiver`
  is set `false` (fed only by in-package broadcasts). `MainService` already
  declared `exported="true"`.
- **`PendingIntent` `FLAG_IMMUTABLE` (>=31)** OR'd into all **23** construction
  sites (`getActivity`/`getService`/`getBroadcast`/`getActivities`) across the
  app's own code and the bundled support/androidx/GMS libraries. Without a
  mutability flag these throw `IllegalArgumentException` at runtime on 31+.
  The combined value preserves any stock flag (`UPDATE_CURRENT`,
  `CANCEL_CURRENT`, `ONE_SHOT`).
- **Bluetooth permissions (>=31):** legacy `BLUETOOTH` / `BLUETOOTH_ADMIN`
  capped at `maxSdkVersion="30"`; `BLUETOOTH_SCAN` + `BLUETOOTH_CONNECT` added.
- **`POST_NOTIFICATIONS` (>=33)** added.
- **Foreground service (>=34):** `FOREGROUND_SERVICE` +
  `FOREGROUND_SERVICE_MEDIA_PLAYBACK` added; `MainService` gets
  `foregroundServiceType="mediaPlayback"`. `MainService` uses the 2-arg
  `startForeground`, so it adopts the manifest type. `mediaPlayback` has no
  dangerous-permission prerequisite, so the service still starts before the
  BT runtime permissions are granted.

`android:usesPermissionFlags="neverForLocation"` on `BLUETOOTH_SCAN` is
deliberately omitted: apktool's pinned framework (api-23 attr table) predates
that API-31 attribute and aapt2 rejects it. The app already declares
`ACCESS_FINE_LOCATION`, so scanning works with location granted.

## Remaining — device-gated

Declaring a runtime permission is not the same as requesting it. The app
targets 26 and never calls `requestPermissions()` for `BLUETOOTH_SCAN` /
`BLUETOOTH_CONNECT` / `POST_NOTIFICATIONS`. Until that request UI is wired
into the app's flow, the user must grant Nearby-devices and Notifications
manually in Settings on Android 12+. Wiring the request is smali work that
needs a device to validate, and is the next step for this track.

## Layout

- `patch.cmake` — in-place edits (bump `apktool.yml` targetSdk, inject manifest
  attributes, prepend `const` to PendingIntent flag registers). Runs with
  `${TREE}` set to the staged tree. Each edit asserts its anchor occurs the
  expected number of times, so a stock-text drift fails the build loudly.
- `overlay/` — not used by this patch (whole-file replacements would go here,
  mirroring the decoded tree).
