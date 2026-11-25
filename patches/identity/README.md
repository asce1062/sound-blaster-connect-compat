# identity patch

Gives the distributable `compat` variant its own application ID, label and
version. The `compat` variant applies `modernize`, then `arm64`, then this
patch. The other variants do not apply it and keep the stock identity.

## What it changes

- Manifest `package`: `com.creative.apps.sbconnect` ->
  `io.github.asce1062.sbconnect.compat`.
- The authority of the `google_measurement_service` provider, which must be
  unique per device.
- The labels of the application, `MainActivity` and the notification-listener
  service: `SB Connect Compat`.
- The two comparisons in `SbxDeviceManager.smali` of `getPackageName()` with
  the stock package, so the app keeps the stock host behavior under the new
  ID.
- `versionCode` and `versionName` in `apktool.yml`.

Class names, JNI class names, intent action strings, resource names and
SharedPreferences names are not changed. The audit behind this list, and why
each other package-dependent site keeps working, is in
[APPLICATION_IDENTITY.md](../../docs/technical/APPLICATION_IDENTITY.md).

## Inputs

`patch.cmake` runs with `${TREE}` set and reads its values as variables passed
through `sbc_add_variant(... DEFINES ...)` in the root `CMakeLists.txt`. They
come from [`cmake/sbc_version.cmake`](../../cmake/sbc_version.cmake):
`SBC_APP_ID`, `SBC_APP_LABEL`, `SBC_VERSION_NAME`, `SBC_VERSION_CODE`, and the
stock `SBC_UPSTREAM_VERSION` and `SBC_UPSTREAM_VERSION_CODE`, which serve as
anchors. A missing value stops the build.

Every edit asserts the number of times its stock anchor occurs, so a tree
that differs from 1.04.02 fails the build instead of producing a partly
renamed APK.
