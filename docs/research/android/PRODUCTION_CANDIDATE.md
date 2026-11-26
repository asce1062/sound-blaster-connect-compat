# PRODUCTION_CANDIDATE

> **Historical record.** Kept as evidence of how behavior was established; not updated for later changes. Status, corrections and the maintained references: [research index](../README.md).

Qualification of the first production-signed `compat` build against the
[release gates](../../development/RELEASE.md#release-gates). Started
2026-11-26.

## Candidate

| Item | Value |
|---|---|
| File | `sbconnect-compat-v0.1.0.apk`, 47521734 bytes |
| SHA-256 | `63dcd8892ef612191dfd253f5bfd5c45fc0d8a85c42c261b40f152bf922a1543` |
| Source | `596f3bb`, no uncommitted changes |
| Package | `com.creative.apps.sbconnect.compat`, versionCode 1000, versionName `1.04.02-compat.0.1.0`, label SB Connect Compat |
| Signer | `CN=SB Connect Compat`, RSA 4096, certificate SHA-256 `3c726afab7e94ca20c5d44f854eb357e684323a0bc4ae5d747d3281439e82b57` (the committed fingerprint) |
| Unsigned input | `ee302140895372b4c1bb56da1fdb9750b8b93adb5c171345551200ae8ea87a6e` |
| arm64 libraries | `970d1744...`, `ca380c7c...` (the accepted digests) |

The operator signed it on their machine through `apk-compat-release`. An
earlier production-signed build, `81b32401...` from `25b7f61`, carried the
first application ID and was never installed.

## Signing gate

The build's own verification passed (apksigner v1, v2, v3 with one signer;
`zipalign -c -P 16 4`; certificate equal to the committed fingerprint;
package and versions; ABIs `arm64-v8a armeabi armeabi-v7a x86` with the
arm64 libraries matching the build; 4309 non-signature entries identical to
the unsigned APK). Separately: `sha256sum -c` of the `.sha256` file,
`verify_release.py --mode release` against `release.env` and tag `v0.1.0`,
an independent `apksigner verify --print-certs`, `zipalign -c`, `aapt2 dump
badging`, and `compare_apks.py --ignore-signatures` against the unsigned
APK (equivalent) all pass.

## User install route (Pixel 8, Android 17, API 37)

No `compat` package was installed beforehand: the debug-signed b4 build had
been removed with `adb uninstall`. The APK was copied to `Download/` with
`adb push`; its on-device SHA-256 matched the candidate. Play Protect was on
and was not changed.

| Step | Observation |
|---|---|
| 1 | The operator opened the APK in the file manager. Play Protect: "App scan recommended", "Play Protect hasn't seen this app before", with **Scan app** and **Don't install app** |
| 2 | The operator chose **Scan app**. Play Protect: "This app looks safe", "You can continue to install it", with **Install** and **Don't install** |
| 3 | The operator chose **Install**. The package installed |

Installed state, read with `pm` and `dumpsys package` before the first
launch:

| Field | Value |
|---|---|
| Package | `com.creative.apps.sbconnect.compat`, versionCode 1000, versionName `1.04.02-compat.0.1.0`, targetSdk 34 |
| `base.apk` SHA-256 | `63dcd889...`, equal to the candidate |
| Signer of the installed APK | `CN=SB Connect Compat`, `3c726afa...` |
| Installer | `installerPackageName` and `initiatingPackageName` `com.google.android.packageinstaller`; `originatingPackageName` the file manager; `packageSource` 3 (downloaded file) |
| ABI | `primaryCpuAbi` `arm64-v8a` |
| Runtime permissions | `POST_NOTIFICATIONS` and `ACCESS_FINE_LOCATION` not granted. `ACCESS_LOCAL_NETWORK` granted by the platform with `REVOKE_WHEN_REQUESTED` |
| Process | not running |

**Verdict: PRODUCTION_PLAY_PROTECT_PASS** for this APK and certificate on
this device. It says nothing about other builds, other signers or other
devices.

Screenshots: `pp-1-scan-recommended.png`, `pp-2-after-scan.png`,
`pp-3-installed.png` in the operator's evidence folder
`production-candidate-v0.1.0-596f3bb-2026-11-26`.

## Hardware (Pixel 8, Sound BlasterX Katana)

The same install, continuing from the user install route. The Pixel 8 is
bonded to the Katana only. The operator drove the app; `logcat -v
threadtime` ran throughout. The run wrote master volume only.

| Step | Observation |
|---|---|
| First launch | Two system requests: Nearby devices, then notifications; the operator allowed both. `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT` and `POST_NOTIFICATIONS` granted `USER_SET`. No location or microphone request; both stay not granted. `libsbxapplogic_ctprotocol_jni.so` loads from `lib/arm64` (`nativeloader` "ok"). Dashboard offline, "Touch to connect to an Audio Device" |
| Discovery and connection | Connect to Device lists the bonded Katana; the operator connected it. A2DP connect, then the SPP socket on port 2, `maxpayloadSize 62`, `GET_FEATURE_CONTROL_SUPPORT`. `MainService` runs in the foreground, type `connectedDevice`, with its ongoing notification. "Sound BlasterX Katana, Connected" |
| Live state and presets | Dashboard reads presets Neutral, Gaming, Concert and sources Bluetooth, Aux In (unavailable) and Optical (active). The operator switched presets and back; presets and saved profiles stayed in sync with the speaker. 22 commands sent, 46 frames received |
| Reversible write | Master volume one step down and back, from the app's buttons and from the speaker's buttons and remote. The app's slider and the speaker followed each other in both directions and each adjustment continued from the last value; no lost or conflicting step. Never above the starting level |
| `pm revoke` of `BLUETOOTH_SCAN` while connected, app in front | "Killing ... permissions revoked". The new process reconnects 5 s later with `BLUETOOTH_CONNECT` alone, `maxpayloadSize 62`, foreground `connectedDevice`. No dialog, no `SecurityException` |
| `pm revoke` of `POST_NOTIFICATIONS` while connected | Killed; the new process reconnects and `MainService` runs in the foreground. Notifications then re-granted with `pm grant` |
| `pm revoke` of `BLUETOOTH_CONNECT` with the app in the background (both Nearby permissions denied) | Killed; `MainService` restarts for its sticky start, makes no Bluetooth call and is not in the foreground. No `SecurityException` |
| Relaunch and recovery | No system dialog on launch; Connect to Device shows the Katana disconnected and the app's Nearby devices explanation with **Not now** and **Allow**. **Allow**, then the system **Allow** (one system request): both granted `USER_SET`, the Katana reconnects without a further tap, `maxpayloadSize 62`, foreground `connectedDevice` |

No `FATAL EXCEPTION`, ANR, `UnsatisfiedLinkError` or `SecurityException`
from the app in the whole run. The app logs, and catches, the
`ArrayIndexOutOfBoundsException` in `CtProtocolMgr.d()` already recorded in
[ARM64_VERDICT.md](../arm64/ARM64_VERDICT.md), `NullPointerException`s
from the firmware-update JSON parse after `checkFWVersion`, one
`[waitForReply] - Timed Out!!` during the connection setup with traffic
continuing after it, and the support library's denied `mListener`
reflection.

**Verdict: hardware gate PASS** for this APK on this device and speaker.

Screenshots `hw-1-after-prompts.png`, `hw-2-connected.png`,
`hw-3-presets.png`, `hw-5-notification.png` (the explanation dialog) and
`hw-6-recovered.png`, and the full log `hw-logcat.txt`, are in the same
evidence folder.

## Update (Pixel 8)

The [update qualification](../../development/RELEASE.md#update-qualification)
ran on the same install, after the hardware run, with the Katana connected
and the operator's synced presets and saved profiles in the app.

| Item | Value |
|---|---|
| Labelled build | `sbconnect-compat-v0.1.0-rehearsal.1.apk`, SHA-256 `095d397523cdcfc5ca0ea9164d9ccb3ca4e7b21ec734a36ff61cb0e23bf8d553`, from `0c925cf` (differs from `596f3bb` in documentation only), no uncommitted changes |
| Package | `com.creative.apps.sbconnect.compat`, versionCode 1000, versionName `1.04.02-compat.0.1.0-rehearsal.1` |
| Signer | the production key, certificate `3c726afa...`; signed by the operator through `apk-compat-release`, which passed its verification; `sha256sum -c`, `verify_release.py --mode release` and `apksigner verify --print-certs` pass |

| Step | Observation |
|---|---|
| `adb install -r` of the labelled build over the candidate | Success. `firstInstallTime` unchanged (16:56:55), `lastUpdateTime` 17:27:52, installed `base.apk` `095d3975...`. `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT` and `POST_NOTIFICATIONS` still granted `USER_SET` |
| After the update | The system stops the app for the update and restarts the activity that was in front. It reconnects to the remembered Katana without a tap or a dialog: SPP socket 1.6 s after the process start, `maxpayloadSize 62`, foreground `connectedDevice`. The operator found the presets, saved profiles and settings as before |
| `adb install -r` of the candidate over the labelled build | Success. `base.apk` `63dcd889...`, versionName `1.04.02-compat.0.1.0`, grants kept, reconnects without a tap, foreground `connectedDevice` |

**Verdict: update gate PASS** for the production key on this device.

`before-`, `after-` and `restored-dumpsys-package.txt` and
`up-1-after-update.png` are in the operator's evidence folder
`update-rehearsal-v0.1.0-2026-11-26`; the log is `hw-logcat.txt` above.

## Result

All four [release gates](../../development/RELEASE.md#release-gates)
pass for `63dcd889...`. The Pixel 8 is left with the candidate installed.
