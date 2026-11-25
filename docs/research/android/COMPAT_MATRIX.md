# SBConnect compatibility matrix

> **Historical record.** Kept as evidence of how behavior was established; not updated for later changes. Status, corrections and the maintained references: [research index](../README.md).

Where each variant stands, and the per-change ledger for `modernize`. This
lane is limited to devices that can execute the original 32-bit native
libraries; **no arm64 support is claimed**. See `PIPELINE.md` for hashes,
signing, and the payload-identity evidence (`resign` is proven SHA-256
payload-identical to stock per entry).

## Device / OS matrix

Legend: **install** = package parses and installs via sideload (the Play Store
listing filter is bypassed by sideloading and is out of scope here);
**run** = process starts and loads its native libraries.

| Device class | Android | `resign` (targetSdk 26) | `modernize` (targetSdk 34) |
|---|---|---|---|
| 32-bit-capable (armeabi-v7a execution) | 8-11 (API 26-30) | install + run | install + run |
| 32-bit-capable | 12-12L (API 31-32) | install + run (legacy behaviors grandfathered by target 26) | install + run (via the applied 31 changes) |
| 32-bit-capable | 13 (API 33) | install + run (grandfathered) | install + run (via the applied 33 changes) |
| 32-bit-capable | 14 (API 34) | install + run (grandfathered; target 26 >= 23 so not blocked) | install + run (via the applied 34 changes) |
| 64-bit-only (no 32-bit execution, e.g. Pixel 7/8 / ARMv9) | any | **cannot run** (no 32-bit `.so`) | **cannot run** (no 32-bit `.so`) |

Notes:
- Both variants carry the same 32-bit-only ABI set, so the bottom row is a hard
  limit for this lane. Fixing it is the separate `arm64` lane.
- `resign` keeps working on 31-34 because an app that **targets** API 26 is
  exempt from the 31+ behavior changes (they key off targetSdk). `modernize`
  instead adopts the modern model explicitly, which is what makes it the base
  for the `arm64` lane and avoids relying on grandfathering that Google narrows
  over time.
- Android 14's "cannot install apps that target below API 23" rule does not hit
  either variant (resign targets 26, modernize 34).
- **Verification is structural** (aapt2 / apksigner; per-entry SHA-256 for
  `resign`). No 32-bit Android 13/14 device was attached, so "install + run"
  above is the Android-defined expectation, not a hardware-observed result.

## modernize ledger

One row per change class. **"Failure without"** is the Android-specified
failure mode for an app that *targets* the given API without the change; it was
not reproduced on hardware in this lane (no device). **"Test result"** states
what was actually verified here.

| # | Change | Android requirement | Failure without (target >= API) | Expected behavior with change | Test result |
|---|---|---|---|---|---|
| 1 | Explicit `android:exported` on the 5 filtered components (`MainActivity`, `MainReceiver`, `LocalMusicRemoteControllerService`, `MediaButtonReceiver` = true; `AppMeasurementReceiver` = false) | API 31: a component with an `<intent-filter>` must declare `android:exported` | Install fails: `INSTALL_PARSE_FAILED_MANIFEST_MALFORMED` ("requires an explicit value for android:exported") | Package parses and installs; system-driven components remain reachable | Structural: all 5 attributes present with the intended values in the built manifest (aapt2 dump xmltree); package parses under aapt2 link |
| 2 | `PendingIntent` `FLAG_IMMUTABLE` OR'd into all 23 construction sites | API 31: `getActivity`/`getService`/`getBroadcast`/`getActivities` require `FLAG_IMMUTABLE` or `FLAG_MUTABLE` | Runtime `IllegalArgumentException` when the PendingIntent is created -> crash on that path (e.g. building the MainService notification) | PendingIntents construct; notification + media-control intents work | Structural: all 23 sites re-assembled by `apktool b` (both dex built); flag value verified by inspection. Runtime not exercised (no device) |
| 3 | Add `BLUETOOTH_SCAN` + `BLUETOOTH_CONNECT`; cap legacy `BLUETOOTH`/`BLUETOOTH_ADMIN` at `maxSdkVersion=30` | API 31: legacy Bluetooth permissions no longer grant scan/connect | Scan/connect calls return failure / `SecurityException`; device discovery and pairing break | The runtime BT permissions exist and can be granted | Structural: permissions present with correct `maxSdkVersion` (aapt2 badging). **Runtime request not wired** - see residuals |
| 4 | Add `POST_NOTIFICATIONS` | API 33: notifications require runtime `POST_NOTIFICATIONS` | Notifications silently dropped; the foreground-service notification does not appear | The permission exists and can be granted | Structural: permission present (aapt2 badging). Not runtime-tested; request not wired - see residuals |
| 5 | Add `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_MEDIA_PLAYBACK`; set `MainService android:foregroundServiceType="mediaPlayback"` | API 34: a foreground service must declare a type and hold the matching permission | `startForeground` throws `MissingForegroundServiceTypeException` -> service start crashes | `MainService` starts in the foreground; `mediaPlayback` has no dangerous-permission prerequisite, so it starts before the BT grants | Structural: `foregroundServiceType=mediaPlayback` + both permissions present (aapt2 xmltree); `MainService` uses 2-arg `startForeground`, so it adopts the manifest type |

targetSdk was raised to 34 as a **single manifest/yml change independent of
the ABI set** — no native library was added, removed, or replaced to achieve
any row above (see `PIPELINE.md`, native-library byte-identity). The targetSdk
bump and the (separate, not-done-here) arm64 ABI work are deliberately kept
apart.

## Residuals — device-gated

| Item | State | Why it needs a device |
|---|---|---|
| Runtime `requestPermissions()` for `BLUETOOTH_SCAN`/`BLUETOOTH_CONNECT`/`POST_NOTIFICATIONS` | **not wired** | The app targets 26 and never requested these. Until the request UI is added in smali, the user must grant Nearby-devices / Notifications in Settings on Android 12+. Adding and validating the request flow needs a device. |
| Install + launch confirmation | **not done** | No 32-bit-capable Android 13/14 phone was attached. |
| `android:usesPermissionFlags="neverForLocation"` on `BLUETOOTH_SCAN` | **omitted** | apktool's pinned api-23 framework rejects the API-31 attribute. The app already holds `ACCESS_FINE_LOCATION`, so scanning works with location granted. |

## Stop-condition log

No stop condition was triggered during this work: no unexplained Java crash,
native-loader error, Bluetooth permission failure, or package-signature problem
was encountered. Two build failures occurred and were explained and fixed, not
patched around:

1. A CMake `while(TRUE)` under the unset `CMP0012` policy evaluated as a
   string and skipped the anchor counter (returned 0) -> rewritten as a
   `FIND`-driven loop.
2. aapt2 rejected `android:usesPermissionFlags` because apktool's bundled
   framework predates API 31 -> the attribute was dropped (recorded above), not
   forced.

An earlier apktool-based `resign` re-encoded resources and dex (a semantic
control, not payload-preserving). That boundary was resolved, not worked
around: `resign` now copies the stock archive and re-signs it directly, and the
build proves per-entry SHA-256 payload identity to stock. See `PIPELINE.md`,
*resign — payload-preserving* and *Design note*.
