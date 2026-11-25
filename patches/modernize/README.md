# modernize patch

Raises the app's target API level from 26 to 34 and applies the changes that
Android 12, 13 and 14 require of an app that targets them. The `modernize`
variant is the stock app plus this patch; the `arm64` variant applies this
patch and then `arm64`.

## What it changes

- `targetSdkVersion` 26 -> 34 in `apktool.yml`.
- Explicit `android:exported` on every component with an intent filter, and
  `MainReceiver`, `MainService` and `MediaButtonReceiver` set to not exported.
- `FLAG_IMMUTABLE` added at all 23 `PendingIntent` construction sites.
- Bluetooth permissions for API 31 (`BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`;
  legacy `BLUETOOTH` and `BLUETOOTH_ADMIN` capped at API 30),
  `POST_NOTIFICATIONS`, and the foreground-service type and permissions for
  API 34.
- `org.apache.http.legacy` and `android.test.base` declared as optional
  libraries.
- Three shim classes in `overlay/`: `FgChannelCompat` (notification channel
  for the foreground service), `RcvCompat` (receiver registration flags on
  API 34 and later, 96 call sites) and `BtPermCompat` (runtime permission
  requests for Bluetooth and notifications).
- The notification-listener access prompt for a feature built on a removed
  platform API is no longer shown.

Each change, the platform rule behind it and how it was verified are in
[ANDROID_COMPATIBILITY.md](../../docs/technical/ANDROID_COMPATIBILITY.md); the
permission and export model in
[PERMISSIONS.md](../../docs/technical/PERMISSIONS.md).

## Layout

- `patch.cmake`: in-place edits of the staged tree, run with `${TREE}` set.
  Every edit asserts the number of times its anchor occurs, so a stock tree
  that differs from 1.04.02 fails the build instead of producing a partly
  patched APK. Method and field names in the anchors are the obfuscated names
  of the stock release.
- `overlay/`: files copied onto the staged tree before `patch.cmake` runs
  (the three shim classes under `smali/com/creative/apps/sbconnect/`).

`android:usesPermissionFlags="neverForLocation"` is not set on
`BLUETOOTH_SCAN`: the framework bundled with apktool 3.0.3 predates that
attribute and aapt2 rejects it. The app keeps `ACCESS_FINE_LOCATION`, so
scanning works with location granted.
