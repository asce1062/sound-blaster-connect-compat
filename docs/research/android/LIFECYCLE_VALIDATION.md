# LIFECYCLE_VALIDATION

> **Historical record.** Kept as evidence of how behavior was established; not updated for later changes. Status, corrections and the maintained references: [research index](../README.md).

Runs of the permission lifecycle of `compat` ([PERMISSION_LIFECYCLE.md](PERMISSION_LIFECYCLE.md))
on a Pixel 8 and on emulators, 2026-11-25 and 2026-11-26. The Galaxy S24
Ultra of [HARDWARE_VALIDATION.md](HARDWARE_VALIDATION.md) kept its earlier
build and its Katana pairing as the positive control and was not used. No
pairing was created or removed, no speaker setting was written, and
CtProtocol behavior was not changed.

## Candidate

| Field | Value |
|---|---|
| Source | branch `phase-d/permission-lifecycle`, working tree before the commit that adds this record |
| APK (Pixel 8) | `sbc_compat-aligned-debugSigned.apk`, 47497158 bytes, SHA-256 `f6912a84282b79273d4fa146380f4516d5c571cfccf5cba2a2541b60a6e2a4ae`, debug-signed |
| Package | `io.github.asce1062.sbconnect.compat`, versionCode 1000, targetSdk 34 |
| Manifest | `BLUETOOTH_SCAN` with `neverForLocation`; `MainService` type `connectedDevice`; no notification listener; `MEDIA_CONTENT_CONTROL`, `SYSTEM_ALERT_WINDOW`, GCM receive and `WRITE_EXTERNAL_STORAGE` removed |

The emulator runs used builds of the same branch at earlier points; the
difference is noted per run.

## Devices

| Device | Detail |
|---|---|
| Pixel 8 | Android 17, API 37, security patch 2026-10-05, `arm64-v8a` only, 4 KiB pages, wireless ADB, no bonded Bluetooth devices. Install by `adb install` (installer `null`) |
| Speaker | Sound BlasterX Katana, powered, bonded to the S24 Ultra only |
| Emulator API 34 | x86_64 Google Play image, headless |
| Emulator API 30 | x86 Google APIs image, headless |

## Pixel 8 results

| Step | Result |
|---|---|
| Fresh install, first launch | Two system dialogs in order: Nearby devices, then notifications. No location, microphone, camera or storage dialog. Both declined. The app shows its offline screen. No `SecurityException`, `FATAL EXCEPTION` or ANR from the app |
| Relaunch | No permission dialog. No `SecurityException` |
| Connect to Device, Nearby devices declined once | The app's explanation dialog with **Allow** and **Not now** |
| **Not now**, leave and return to the screen instance | No further dialog. No Wi-Fi `startScan` permission violation |
| **Allow**, then the system **Allow** | One activity recreate. `startDiscovery` from the app with location denied. The unpaired Katana appears in the device list, with no bonded devices on the phone |
| `pm revoke` of Nearby devices, relaunch | No permission dialog at launch, no `SecurityException`. `MainService` restarts and stays a background service |
| Second denial (`USER_FIXED`) | The explanation offers **Open settings**, which opens the app's page in system settings; Back returns to the app |
| Final permission state | `BLUETOOTH_CONNECT`, `BLUETOOTH_SCAN`: denied, `USER_FIXED`. `POST_NOTIFICATIONS`: denied, `USER_SET`. Location and `RECORD_AUDIO`: denied without `USER_SET`, so never requested |
| `MainService` | Running, not foreground (no speaker connection) |

## Emulator results

| Run | Result |
|---|---|
| API 34, fresh install | Two dialogs (Nearby devices, notifications), none on relaunch, no app `SecurityException`. An ANR during the run belongs to `com.google.android.gms` on the cold image |
| API 34, connect screen without location, build before the Wi-Fi gate | `WifiService` logs "Permission violation - startScan not allowed" for the app. The build that followed runs `SbxConnectionManager.c()` only with precise location |
| API 30, fresh install, earlier build | One location dialog at launch, none on relaunch, no app `SecurityException` |
| API 30, final build (`sbc_compat-aligned-debugSigned.apk`, SHA-256 `689ce68d7d7e92eeed9272fd0d91c06542cc8775879db53c54a84a897b827c81`; arm64 libraries `970d1744...` and `ca380c7c...` unchanged) | Fresh install: one location dialog, denied; offline dashboard. Connect to Device: the app's location explanation ("finding Bluetooth devices that are not yet paired needs location access") with **Not now** and **Allow**. **Not now**: no further dialog. **Allow**: the system dialog; **Deny** shows the app's toast and leaves location `USER_FIXED`. Resume on the same screen: no dialog. Reopening the screen: the explanation with **Open settings**, which opens the app's App info page. Cold relaunch: no dialog. Two system permission requests in the whole run; no app `SecurityException`, `FATAL EXCEPTION`, ANR or `startScan` violation. `RECORD_AUDIO` never requested |

## Not covered

- Connection to a speaker with the current build: `connectedDevice` foreground
  start, revocation after connection, Katana reads and reversible writes.
- Boot delivery with the current build.
- Room calibration (microphone) and Wi-Fi speaker setup (location): the
  screens were not reached.
- The user install route through Play Protect with the current build.
- API 31 to 33 and 35 to 36 hardware.

## Verdicts

| Verdict | State |
|---|---|
| PERMISSION_LIFECYCLE | **Blocker: hardware regression incomplete.** Launch, denial, retry, permanent denial, revocation without a connection and unpaired discovery pass on the Pixel 8; the connection, revocation after connection, reads and writes and boot steps have not run |
| APPLICATION_SECURITY_REVIEW | **Blocker: boot and connection not re-verified.** The manifest review is complete (**Static**); the `connectedDevice` service type and the boot path have not run on hardware with this build |
| PLAY_PROTECT_INSTALLATION | **BLOCKED.** The last user-route result (stock permission set) is a block; the current build has not been through the user route. No appeal submitted |

## Evidence

Raw logcat captures and UI dumps stay outside the repository; they contain
device identifiers and Bluetooth addresses.
