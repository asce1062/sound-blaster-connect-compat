# PERMISSION_REGRESSION

> **Historical record.** Kept as evidence of how behavior was established; not updated for later changes. Status, corrections and the maintained references: [research index](../README.md).

Hardware regression of the permission lifecycle of `compat` with a speaker,
the boot path, and the Play Protect user install route, 2026-11-26. It
completes the runs of [LIFECYCLE_VALIDATION.md](LIFECYCLE_VALIDATION.md), whose
verdicts it replaces. CtProtocol behavior was not changed. The only speaker
setting written was master volume, one step down and restored.

## Candidates

| Build | Detail |
|---|---|
| b4 | `sbc_compat-aligned-debugSigned.apk`, 47497158 bytes, SHA-256 `689ce68d7d7e92eeed9272fd0d91c06542cc8775879db53c54a84a897b827c81`, debug-signed. Commit `b3c4743` |
| b5 | b4 plus the discovery-call wrappers (below). 47497158 bytes, SHA-256 `5f46c4a1d916945506baa050805afb9df6e750788e3d0a161670d3d14b54b1c1`, debug-signed. Built from the commit that adds this record |

Both: package `io.github.asce1062.sbconnect.compat`, versionCode 1000,
targetSdk 34, arm64 libraries `970d1744...` and `ca380c7c...`.

## Devices

| Device | Detail |
|---|---|
| Galaxy S24 Ultra | Android 17, API 37. The Katana is bonded to it. Also installed: `com.creative.apps.sbconnect`, the project's `arm64` build under the stock package (A), the positive control, not changed |
| Pixel 8 | Android 17, API 37, no bonded devices. Play Protect on (`package_verifier_user_consent=1`) |
| Speaker | Sound BlasterX Katana, source Optical 1 |

On the S24 Ultra, b4 was installed with `adb install -r` over an earlier
`compat` build (installer `null`), which kept its grants: Nearby devices,
notifications and location granted, microphone denied with `USER_FIXED`. The
earlier APK was kept so it can be restored.

## S24 Ultra, b4, with the Katana

| Step | Result |
|---|---|
| Launch after the update | No permission dialog. Offline dashboard; the Connect screen lists the bonded Katana as Disconnected and starts discovery |
| Connect | The app's tap calls `BluetoothA2dp.connect`; the speaker refused the first two link attempts (`HCI_ERR_HOST_REJECT_RESOURCES`). A second tap 80 seconds later connected: SPP socket, `maxpayloadSize 62`, `GET_FEATURE_CONTROL_SUPPORT`. No `BluetoothHeadset.connect` call (gated, row 13 of [ANDROID_COMPATIBILITY.md](../../technical/ANDROID_COMPATIBILITY.md)) |
| Foreground service | `MainService` `isForeground=true`, `types=0x00000010` (`connectedDevice`); "Background started FGS: Allowed ... uidState: TOP" |
| Reads | Device name, presets Neutral, Gaming, Concert; sources Bluetooth, Aux In, Optical; Now Playing source Optical 1 and the master volume slider |
| Microphone | Denied (`USER_FIXED`) throughout; connection, reads and the write need no microphone |
| `pm revoke` of `BLUETOOTH_CONNECT` while connected, app in front | "Killing ... permissions revoked". The activity restarts; because the update came from a build without this lifecycle, its one-time Nearby step had not run, so it runs once: one system request. The system grants `BLUETOOTH_CONNECT` without a dialog, since `BLUETOOTH_SCAN` of the same group is still granted |
| `pm revoke` of `BLUETOOTH_SCAN` next | Killed again and restarted. With `BLUETOOTH_CONNECT` held and `BLUETOOTH_SCAN` not, the auto-reconnect calls `BluetoothAdapter.isDiscovering()` from `c.d.e()` (Bluz socket connect, through `SbxSppCommandManager`), which throws a caught `SecurityException` (twice). Fixed in b5 |
| `pm revoke` of `BLUETOOTH_CONNECT` with the app in the background (both denied) | Killed; `MainService` restarts with no Bluetooth calls and no `SecurityException`. Relaunch: no dialog, offline dashboard |
| Connect with both denied | The app's explanation ("Nearby devices") with **Not now** and **Allow**. **Allow**, then the system **Allow**: both granted `USER_SET`; the activity recreates and the Katana reconnects; foreground `connectedDevice`. One system request in this sequence |
| `pm revoke` of `POST_NOTIFICATIONS` while connected | Killed; `MainService` restarts for its sticky start, reconnects and runs in the foreground (`connectedDevice`). `NotificationService`: "Suppressing notification from package ... by user request". No launch prompt on the recreated activity. Notifications then re-granted with `pm grant` |
| Errors over the session | No `FATAL EXCEPTION`, no ANR, no Permission Denial for the app's own operations; `SecurityException` only in the two lines above |

### Read and write (A/B/A)

Slider position is the thumb's x pixel at row 2985 of 1440-wide screenshots.

| Step | App | Slider | Action |
|---|---|---|---|
| 1 | `compat` | 483 | one step down (the volume-down button) |
| 2 | `compat` | 465 | process killed by the revocation; a new process reconnects and reads 465 |
| 3 | A | 465 | A, launched after `compat` was force-stopped, reads the value from the speaker |
| 4 | A | 483 | one step up: volume back to its value before the run |

### Boot

Before the reboot both packages were not stopped (`stopped=false`). The
operator rebooted and unlocked the phone and turned wireless debugging back
on; neither app was opened.

- `BOOT_COMPLETED` started A's process for `MainReceiver`, then `compat`'s
  0.4 s later.
- `compat` loaded `libsbxapplogic_ctprotocol_jni.so` from its own `lib/arm64`.
- Both `MainService`s were released by the activity manager about 15 s later
  ("Waited long enough for") and ran as background services; no connection
  was made from the boot path.
- No `SecurityException`, Permission Denial, foreground-service refusal,
  `FATAL EXCEPTION` or ANR from `compat`.

### Component hardening

| Probe from the shell (uid 2000) | Result |
|---|---|
| `am start-service` and `am start-foreground-service` of `MainService` | "Requires permission not exported from uid 10032" |
| `am broadcast -f 32` to `MainReceiver` and to `android.support.v4.media.session.MediaButtonReceiver`, `compat` force-stopped | Result 0; no process started: not delivered |
| Notification listener | none declared in the installed package |

## S24 Ultra, b5

b5 routes the 10 `startDiscovery`, `cancelDiscovery` and `isDiscovering`
calls of the stock code through `PermissionLifecycle`, which returns false
without calling the adapter when `BLUETOOTH_SCAN` is not held. Installed with
`adb install -r` over b4; all grants kept, microphone denied `USER_FIXED`.

| Step | Result |
|---|---|
| Launch and connect | No permission dialog. Connect screen, Katana: SPP socket, `maxpayloadSize 62`, `GET_FEATURE_CONTROL_SUPPORT`; `MainService` `isForeground=true`, `types=0x00000010` |
| `pm revoke` of `BLUETOOTH_SCAN` while connected, app in front (`BLUETOOTH_CONNECT` held) | "Killing ... permissions revoked". The new process reconnects 8 s later with `BLUETOOTH_CONNECT` alone: one socket connect, `maxpayloadSize 62`, foreground `connectedDevice`. No discovery call reaches the adapter, no `SecurityException`, no dialog. `BLUETOOTH_SCAN` then re-granted with `pm grant` |
| Location denied (`ACCESS_FINE_LOCATION` and `ACCESS_COARSE_LOCATION` revoked, app force-stopped), launch | No dialog. The app reconnects to the bonded Katana: SPP socket, `maxpayloadSize 62`, foreground `connectedDevice`. Dashboard reads: presets Neutral, Gaming, Concert; sources Bluetooth, Aux In, Optical. Location then re-granted with `pm grant` |
| Errors over the session | No `SecurityException`, `FATAL EXCEPTION`, ANR or Permission Denial from the app; no permission dialog; no `BluetoothHeadset.connect` call |

No speaker setting was written with b5.

## Pixel 8, Play Protect user route (b4)

The adb-installed copy was uninstalled and b4 copied to `Download` as
`sbconnect-compat-test.apk` (same SHA-256). The operator opened it from the
file manager (Solid Explorer) with Play Protect on.

1. Google Play Protect: "App scan recommended". The app is named; the text
   says Play Protect has not seen the app before and recommends sending it to
   Google for a security scan. Choices: **Scan app**, **Don't install app**,
   and the link **Install without scanning**.
2. The operator chose **Scan app**; the APK was sent to Google.
3. Google Play Protect: "This app looks safe", "You can continue to install
   it", with **Install** and **Don't install**.
4. **Install**: "App installed". `installerPackageName` and
   `initiatingPackageName` `com.google.android.packageinstaller`,
   `originatingPackageName` `pl.solidexplorer2`, signer `527b0ab7`.
5. First launch: the Nearby devices dialog, then the notifications dialog,
   both declined; the offline dashboard. Two system requests; no
   `SecurityException`, `FATAL EXCEPTION` or ANR.

The log also shows the developer-verification check before the dialog:
"Verification finished for io.github.asce1062.sbconnect.compat. Result:
Pass(reason=FORCED_BACKPORT, message=null)". What that reason means for an
app from an unregistered developer is not established here.

## Not covered

- Room calibration (microphone) and Wi-Fi speaker setup (location): the
  screens were not reached.
- Discovery of an unpaired device on b4 and b5: the Katana stayed bonded to
  the S24 Ultra. The unpaired case with location denied is recorded on the
  Pixel 8 with the earlier build
  ([LIFECYCLE_VALIDATION.md](LIFECYCLE_VALIDATION.md)); b5 changes only
  whether discovery runs without `BLUETOOTH_SCAN`.
- The Play Protect user route with b5. It differs from b4 only in the
  discovery wrappers; the permission set is the same.
- The user route on the S24 Ultra with the current build, and with a
  release-signed APK on any device.
- A foreground start from the boot path (no connection at boot).
- API 31 to 33 and 35 to 36 hardware.

## Verdicts

These replace the verdicts of [LIFECYCLE_VALIDATION.md](LIFECYCLE_VALIDATION.md).

| Verdict | State |
|---|---|
| PERMISSION_LIFECYCLE | **PASS** on b5: no Bluetooth operation without its grant, the offline dashboard and the in-app retry when Nearby devices is denied, no repeated prompts, the speaker connection and reads with microphone, notifications or location denied. The microphone and location request screens (room calibration, Wi-Fi setup) were not reached |
| APPLICATION_SECURITY_REVIEW | **PASS**: services refuse callers without the app's uid, the receivers take no broadcast from the shell, no notification listener, no privileged permission requested; boot starts both apps with no error |
| PLAY_PROTECT_INSTALLATION | **PASS** for b4, debug-signed, on the Pixel 8: installed through the file manager and the system installer after a Play Protect scan reported it safe. Not established for a release-signed APK, which does not exist yet; the release gate in [RELEASE.md](../../development/RELEASE.md) stays closed |

## Evidence

Raw logcat captures, UI dumps and screenshots stay outside the repository;
they contain device identifiers, Bluetooth addresses and unrelated file names.
