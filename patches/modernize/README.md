# modernize patch

Raises the app's target API level from 26 to 34 and applies the changes that
Android 12, 13 and 14 require of an app that targets them. The `modernize`
variant is the stock app plus this patch; the `arm64` variant applies this
patch and then `arm64`.

## What it changes

- `targetSdkVersion` 26 -> 34 in `apktool.yml`.
- Explicit `android:exported` on every component with an intent filter;
  `MainReceiver`, `MainService`, `MediaButtonReceiver`, the former
  notification-listener service and `PreviewActivity` not exported.
- `FLAG_IMMUTABLE` added at all 23 `PendingIntent` construction sites.
- Bluetooth permissions for API 31 (`BLUETOOTH_SCAN` with `neverForLocation`,
  `BLUETOOTH_CONNECT`; legacy `BLUETOOTH` and `BLUETOOTH_ADMIN` capped at
  API 30), `POST_NOTIFICATIONS`, and the `connectedDevice` foreground-service
  type and permissions for API 34.
- `MEDIA_CONTENT_CONTROL`, `SYSTEM_ALERT_WINDOW`, the GCM receive permission
  and `WRITE_EXTERNAL_STORAGE` removed; the notification-listener declaration
  and its access prompt removed.
- `org.apache.http.legacy` and `android.test.base` declared as optional
  libraries.
- Two smali shim classes in `overlay/`: `FgChannelCompat` (notification
  channel for the foreground service) and `RcvCompat` (receiver registration
  flags on API 34 and later, 96 call sites).
- `PermissionLifecycle` in `java/`: every runtime permission request (a
  one-time launch sequence, then explanation dialogs at the features that
  need a permission, with Settings guidance after a permanent denial) and the
  18 Bluetooth entry gates that keep the app offline without the grant, plus
  wrappers for the 10 discovery calls that need `BLUETOOTH_SCAN`.

Each change, the platform rule behind it and how it was verified are in
[ANDROID_COMPATIBILITY.md](../../docs/technical/ANDROID_COMPATIBILITY.md); the
permission and export model in
[PERMISSIONS.md](../../docs/technical/PERMISSIONS.md); the request lifecycle
in
[PERMISSION_LIFECYCLE.md](../../docs/research/android/PERMISSION_LIFECYCLE.md).

## Layout

- `patch.cmake`: in-place edits of the staged tree, run with `${TREE}` set.
  Every edit asserts the number of times its anchor occurs, so a stock tree
  that differs from 1.04.02 fails the build instead of producing a partly
  patched APK. Method and field names in the anchors are the obfuscated names
  of the stock release.
- `overlay/`: files copied onto the staged tree before `patch.cmake` runs
  (the two shim classes under `smali/com/creative/apps/sbconnect/`).
- `java/`: Java sources compiled at build time (javac against the pinned SDK
  platform's `android.jar`, d8, then apktool to smali) and copied onto the
  staged tree with the overlay. See
  [cmake/sbc_java.cmake](../../cmake/sbc_java.cmake).
