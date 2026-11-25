# Permissions and security model

This document describes the security model of the built Sound Blaster Connect APK (package `com.creative.apps.sbconnect`, targetSdk 34 in the `modernize` and `arm64` variants, targetSdk 26 in `resign`): every declared permission with its origin, protection level, runtime request path and feature; the final export value of every manifest component and the reason for it; the exposure of runtime-registered receivers; and the signing identity with its consequences, including observed Play Protect behavior. The `resign` variant carries the stock manifest unchanged; everything marked "added", "removed" or "capped" below applies to `modernize` and `arm64`. The `compat` variant has the `arm64` manifest under the package `io.github.asce1062.sbconnect.compat`, with the provider authority renamed to match; its permissions and component exports are those of `arm64` ([APPLICATION_IDENTITY.md](APPLICATION_IDENTITY.md)). The behavior changes themselves are described in [ANDROID_COMPATIBILITY.md](ANDROID_COMPATIBILITY.md); the inventory and decisions behind the permission lifecycle are in [PERMISSION_LIFECYCLE.md](../research/android/PERMISSION_LIFECYCLE.md).

## Verification basis

| Tag | Meaning |
|---|---|
| **Build** | Enforced by the build: an anchor asserted to occur a fixed number of times in [patch.cmake](../../patches/modernize/patch.cmake). |
| **Device** | Observed on hardware: Pixel 7a (Android 13), Galaxy S24 Ultra (Android 16 and Android 17, API 37), Pixel 8 (Android 17, API 37), one Sound BlasterX Katana. Raw logs stay outside the repository; only excerpts in [runtime/](../research/arm64/runtime/) and the validation records exist. |
| **Emulator** | Observed on an Android emulator (API 30 x86, API 34 x86_64 with arm64 translation). |
| **Static** | Read from code or the built manifest, not executed. Statements that a permission is "dormant" or "inert" carry this tag unless a trace exists. |
| **Expected** | Platform documentation or inference, not observed in this project. |

No 32-bit device was tested; anything about the variants on 32-bit hardware is **Expected**. The full permission list was read from the built manifest ([PERMISSION_AUDIT.md](../research/android/PERMISSION_AUDIT.md) for the stock set); `patch.cmake` edits only the entries marked "added", "removed" or "capped".

## Declared permissions

| Permission | Origin | Protection level | Runtime request | Feature | Basis |
|---|---|---|---|---|---|
| `BLUETOOTH` | Stock, capped `maxSdkVersion="30"` | Normal (install-time) | none | SPP/RFCOMM link to the device on API 30 and below | **Build** (cap); **Static** (use) |
| `BLUETOOTH_ADMIN` | Stock, capped `maxSdkVersion="30"` | Normal (install-time) | none | Discovery and adapter control on API 30 and below | **Build**; **Static** |
| `BLUETOOTH_SCAN` | Added, `usesPermissionFlags="neverForLocation"` | Dangerous, runtime (API 31+, "Nearby devices") | `PermissionLifecycle`, request code 0x42c: once per install at launch; afterwards from the connect screen or a device tap, after an explanation | Classic discovery (`startDiscovery`) and BLE scan start | **Build**; **Device** (Pixel 8, API 37: an unpaired Katana discovered with location denied) |
| `BLUETOOTH_CONNECT` | Added | Dangerous, runtime (API 31+, "Nearby devices") | Same request as `BLUETOOTH_SCAN` | Every Bluetooth path: bonded and connected device lookup, bonding, profile connect and disconnect, the SPP connection. 18 entry gates skip these calls without the grant | **Build**; **Device** |
| `POST_NOTIFICATIONS` | Added | Dangerous, runtime (API 33+) | `PermissionLifecycle`, request code 0x42d, once per install at launch, after the Nearby step and independent of its result | The app's own foreground-service and media notifications; it guards nothing else | **Build**; **Device** (Pixel 8: prompted after Nearby was denied); **Emulator** (API 34) |
| `FOREGROUND_SERVICE` | Added | Normal | none | `MainService` runs as a foreground service | **Build**; **Device** |
| `FOREGROUND_SERVICE_CONNECTED_DEVICE` | Added; replaces `FOREGROUND_SERVICE_MEDIA_PLAYBACK` | Normal, with a prerequisite met by `CHANGE_NETWORK_STATE` and `NFC` | none | Matches `foregroundServiceType="connectedDevice"` on `MainService` (API 34+) | **Build**; foreground start with a connected speaker is pending on hardware |
| `MODIFY_AUDIO_SETTINGS` | Stock | Normal | none | Audio routing and device settings | **Static** |
| `WAKE_LOCK` | Stock | Normal | none | Keeps the CPU awake during connect and playback | **Static** |
| `ACCESS_NETWORK_STATE` | Stock | Normal | none | Connectivity checks; bundled Google Play services libraries | **Static** |
| `INTERNET` | Stock | Normal | none | Bundled Google Play services, ads and measurement libraries; `JSONParser` HTTP fetch | **Static** |
| `NFC` | Stock | Normal | none | Tap-to-pair on NFC-capable hardware; dormant with the Katana. Also a prerequisite of the `connectedDevice` service type | **Static** |
| `CHANGE_NETWORK_STATE` | Stock | Normal | none | Network routing for Wi-Fi-capable devices; dormant for an SPP-only device. Also a prerequisite of the `connectedDevice` service type | **Static** |
| `CHANGE_WIFI_STATE` | Stock | Normal | none | Wi-Fi control for Wi-Fi-capable devices; dormant here | **Static** |
| `ACCESS_WIFI_STATE` | Stock | Normal | none | Reads Wi-Fi state | **Static** |
| `VIBRATE` | Stock | Normal | none | Haptic feedback | **Static** |
| `RECEIVE_BOOT_COMPLETED` | Stock | Normal | none | `MainReceiver` start on `BOOT_COMPLETED` | **Static**; **Device** (broadcast delivered after reboot, S24 Ultra, before the lifecycle change) |
| `ACCESS_COARSE_LOCATION` | Stock, capped `maxSdkVersion="22"` | Dangerous | none | Pre-API-23 location model for Bluetooth scanning | **Static** |
| `ACCESS_COARSE_LOCATION` (`uses-permission-sdk-23`), `ACCESS_FINE_LOCATION` | Stock | Dangerous | `PermissionLifecycle`, request code 0x42f. API 23 to 30: once per install at launch, and from the connect screen after an explanation. API 31+: only when Wi-Fi speaker setup opens | Wi-Fi speaker setup (scan results, current network) on every level; discovery of unpaired Bluetooth devices on API 23 to 30. No positioning code | **Static** (use); **Emulator** (API 30: one launch prompt, none on relaunch); **Device** (S24 Ultra, API 37: paired connection with location declined) |
| `RECORD_AUDIO` | Stock | Dangerous | `PermissionLifecycle`, request code 0x42e, only when room calibration opens | Room calibration (`CalibrationEngine`, `CalibrationManager`) | **Static**; **Device** (Pixel 8: not requested at launch). The calibration prompt itself needs a speaker that offers calibration and is not exercised |

Removed from the stock manifest:

| Permission | Protection level | Reason | Basis |
|---|---|---|---|
| `MEDIA_CONTENT_CONTROL` | Signature or privileged | Never granted to this app; it served only the notification-listener feature, which is removed | **Build**; **Static** |
| `SYSTEM_ALERT_WINDOW` | Special (AppOps) | No overlay window in the code | **Build**; **Static** |
| `com.google.android.c2dm.permission.RECEIVE` | Signature (Google-defined) | No first-party push registration and no push receiver declared | **Build**; **Static** |
| `WRITE_EXTERNAL_STORAGE` | Dangerous (legacy) | No first-party shared-storage write; no effect on a target-34 app | **Build**; **Static** |

`CAMERA` was requested by the stock launch batch without being declared, so the platform denied it silently; it is no longer requested (**Static**).

Notes:

- One owner, `PermissionLifecycle` ([source](../../patches/modernize/java/com/creative/apps/sbconnect/PermissionLifecycle.java)), makes every runtime request; the stock launch batch (`MainActivity.D()`, request code 0x457) and the earlier `BtPermCompat` overlay are gone (**Build**).
- Launch sequence, once per install and never on a recreated activity: Nearby devices on API 31+, or location on API 23 to 30; then notifications on API 33+. Each step waits for the previous result because the platform drops a second request while one is on screen. A relaunch makes no request (**Device**, Pixel 8: two requests at first launch, none after a force-stop and relaunch; **Emulator**, API 30 and 34).
- When Nearby devices arrives after the activity was created, the activity is recreated once so the stock initialization runs with it (**Device**, Pixel 8: one recreate, then discovery started).
- With Nearby devices denied, no Bluetooth call that needs it runs: no `SecurityException` is logged for the package at launch, on the connect screen, or after an external revoke (**Device**, Pixel 8, API 37; **Emulator**, API 34). The offline dashboard stays.
- The connect screen explains a denial once per visit. Its button requests the permission while the system can still show its dialog, and opens the app's settings page after a permanent denial (`USER_FIXED`) (**Device**, Pixel 8: "Allow" after one denial, "Open settings" after two; the settings button opened the app's App info page). A resume after the dialog does not prompt again (**Device**).
- Wi-Fi discovery of speakers in setup mode runs only with precise location, so the connect screen no longer triggers a refused Wi-Fi scan (**Device**, Pixel 8; **Emulator**, API 34 logged the platform's "Permission violation - startScan" before the gate).
- During a connection the stock code calls `BluetoothHeadset.connect` by reflection, which needs `MODIFY_PHONE_STATE` (`signature|privileged`). On API 31+ the call now runs only when that permission is held, which for this app means never; the SPP session never depended on it (**Build**; **Device** before the change: the exception was caught and SPP was unaffected).
- The stock device-name lookup tries the hidden `getAliasName`; on API 30+ the public `getAlias()` replaces it (**Build**).
- Denying Nearby devices in system settings shows the permission controller's "designed for an older version of Android" warning, although the package targets API 34 (**Device**, S24 Ultra; the AOSP conditions for it do not hold, and the cause is not identified). The target API level is not changed for it ([PERMISSION_LIFECYCLE.md](../research/android/PERMISSION_LIFECYCLE.md)).
- No permission was added for a purpose other than keeping the stock Bluetooth and foreground-service paths working at targetSdk 34 (**Static**).

## Component export model

Before API 31 a component with an `<intent-filter>` was implicitly exported. At targetSdk 31 and above the manifest must say so explicitly (**Expected** platform rule, **Build** anchors). Protected system broadcasts and framework-targeted deliveries (media-button routing) reach a manifest component whether or not it is exported, because the sender is the system; `exported="true"` matters only when a third-party app must reach the component.

| Component | Type | Stock | Final | Reason | Basis |
|---|---|---|---|---|---|
| `MainActivity` | Activity | no `exported` | `true` | Launcher entry point | **Build**; **Device** |
| `MainReceiver` | Receiver | no `exported` | `false` | Receives 14 protected system broadcasts (Bluetooth adapter `STATE_CHANGED`; device `BOND_STATE_CHANGED`, `NAME_CHANGED`, `ALIAS_CHANGED`, `ACL_CONNECTED`, `ACL_DISCONNECT_REQUESTED`, `ACL_DISCONNECTED`; A2DP and headset `CONNECTION_STATE_CHANGED`; `CONNECTIVITY_CHANGE`; `BOOT_COMPLETED`; `SCREEN_ON`; `USER_PRESENT`; `LOCALE_CHANGED`) and one app-namespaced action, `com.creative.apps.sbconnect.action.START_SERVICE`, sent inside the package. `false` closes the one third-party exposure: any installed app could otherwise broadcast `START_SERVICE` to it | **Build**; **Device**: `BOOT_COMPLETED` delivered after reboot (S24 Ultra). The Bluetooth broadcasts reach it only while `BLUETOOTH_CONNECT` is held (**Expected** platform rule) |
| `MainService` | Service | `exported="true"` | `false` | `connectedDevice` foreground service (the speaker link and its media session; it plays no audio) filtering `START_SERVICE` and `PLAY_PAUSE`, both started in-package | **Build**; **Device**: started from a same-app caller and from the boot receiver (S24 Ultra, as `mediaPlayback` before the type change) |
| `LocalMusicRemoteControllerService` | Service | no `exported`, notification-listener filter and permission | `false`; listener filter and `BIND_NOTIFICATION_LISTENER_SERVICE` removed; the app's own `BIND_RC_CONTROL_SERVICE` action kept | Its listener callback is empty and the feature it fed (other players' Now Playing metadata through the deprecated `RemoteController`) was already unreachable after its access prompt was removed. The app binds it with an explicit intent from inside the package | **Build**; **Static** |
| `MediaButtonReceiver` (support library) | Receiver | no `exported` | `false` | Filters `MEDIA_BUTTON`; the `MediaSession` framework delivers media-button events to the session owner's registered component as a targeted system delivery | **Build**. Runtime **not exercised** |
| `AppMeasurementReceiver` (Google) | Receiver | no `exported` | `false` | Fed only by in-package broadcasts | **Build** |
| `AppMeasurementService`, `AppMeasurementContentProvider`, `SignInHubActivity` (Google) | Service, provider, activity | `false` | `false` (unchanged) | Google's own declaration | **Static** |
| `PreviewActivity` (Google app invites) | Activity | `true` | `false` | No first-party app-invite use | **Build**; **Static** |
| `RevocationBoundService` (Google) | Service | `true` | `true` (unchanged) | Google's design; protected by a Google permission | **Static** |
| `AdActivity`, `InAppPurchaseActivity` (Google) | Activities | no filter | default (not exported) | No intent filter | **Static** |

The residual risk of `MainReceiver` and `MainService` being `false` is an undocumented external integration that broadcasts to them; none is known (**Static**).

## Runtime-registered receivers

The stock app and its bundled libraries register receivers at runtime through the two-argument `Context.registerReceiver`. The patch redirects all 96 such invocations (asserted by the build, every dex and package, including the bundled `ibluz` library) to `RcvCompat.register` (**Build**).

| API level | Call made | Exposure |
|---|---|---|
| 34 and above | `registerReceiver(receiver, filter, RECEIVER_EXPORTED)` | Receivable from other apps for non-protected actions |
| Below 34 | Original two-argument call, unchanged | Platform default for that release, as in stock |

Rationale: before Android 13 every dynamically registered receiver was implicitly exported, so `RECEIVER_EXPORTED` reproduces the stock exposure exactly and cannot silently stop a receiver that depends on broadcasts from other apps, such as media or music metadata and system state. The two-argument form carries no broadcast-permission argument, so no site is permission-protected. Consequences:

- Protected system broadcasts reach these receivers regardless of the flag (**Expected**).
- Any app on the device can send a matching non-protected action to a runtime-registered receiver on API 34+, as it could on the stock app (**Expected**).
- The build does not classify sites. `RECEIVER_NOT_EXPORTED` was not evaluated per site, so some of the 96 may not need export (**Static** limit).
- Behavior on API 36 with `RECEIVER_EXPORTED`: launch without a crash and Dashboard reached (**Device**, S24 Ultra). `runtime/s24_launch.txt` states 78 sites; that figure is superseded by the 96 asserted in `patch.cmake`.

## Signing identity

| | Stock | `resign`, `modernize`, `arm64` outputs |
|---|---|---|
| Certificate subject | `CN=Creative Technology Ltd.`, same OU and O, `L=Singapore`, `ST=Singapore`, `C=SG` | `C=US, O=Android, CN=Android Debug` |
| Certificate SHA-256 | `549a10ca103aa35a6f120c00f081c9a8e33911715a302f2251ccd74f407052e4` | `665d62c0db7db08aa52b50825e2a45992aaa0056d82a80a6d1bc491ce2c54202` |
| Certificate SHA-1 | `a0717041a23267c32658960ffa342af171de4604` | `112a61fa35193e9b5cc48bce63e8bbf0cebbae76` |
| Key | RSA 2048 | RSA 2048, Android debug key applied by uber-apk-signer 1.3.0 |
| Schemes | v1 only | v1, v2, v3 (apksigner verification passed for `resign` and `modernize`; uber-apk-signer verified all three for each variant) |

The signer is **Build** (signing runs in the variant build); the certificate values and scheme list are **Static** records. The stock APK carries `META-INF/CERT.RSA`/`CERT.SF`; outputs carry `META-INF/ANDROIDD.RSA`/`ANDROIDD.SF`. Package name, versionName 1.04.02, versionCode 10402 and minSdk 14 are unchanged, so the system treats an output as the same app identity signed by a different author (**Static**).

The records differ on one point: `PIPELINE.md` describes the debug key as the per-machine `~/.android/debug.keystore`, while `APP_IDENTITY.md` calls it the uber-apk-signer default. The certificate fingerprint above is recorded identically for all variants. This document does not determine which keystore signs a given build, and makes no claim that the key is secret.

Consequences:

1. **Signature conflict with stock.** A different certificate means an output cannot be installed as an update over a Creative-signed install; the stock app must be uninstalled first, which removes its data (**Expected**: `INSTALL_FAILED_UPDATE_INCOMPATIBLE`; not observed, since the 64-bit-only test devices cannot install stock at all). Output variants share one debug certificate and one versionCode; repeated `adb install -r` of successive `arm64` builds worked during testing (**Device**). The `compat` variant is a different package, so it does not conflict with a stock install; it conflicts only with another `compat` build signed by a different key (**Emulator**, API 30: `INSTALL_FAILED_UPDATE_INCOMPATIBLE` over a test-release install).
2. **No origin attestation.** The debug certificate does not bind a build to Creative or to this project. Anyone holding a debug key with the same fingerprint can produce an APK the system accepts as an update to an installed output (**Expected**).
3. **Signature-level permissions are never granted.** Any `signature` or `signature|privileged` permission stays ungranted to a debug-signed sideload (**Expected**); the build no longer declares or requests one.
4. **v2 or later is required at target 30 and above.** The stock app's v1-only signature suffices at its own target 26; the re-targeted outputs carry v2 and v3 (**Expected** platform rule). The device reported `apkSigningVersion=4` for the arm64 build (**Device**, recorded value).
5. **Outputs are sideload-only.** The Creative private key is unavailable.
6. **Release signing.** `compat` has test-release and release targets that sign with an externally supplied key, v1, v2 and v3, and check the certificate against an expected SHA-256 ([SIGNING.md](../development/SIGNING.md)). A test-release build updated an earlier build signed with the same key and kept its data, and a build signed with another key was refused as an update (**Emulator**, API 30; [RELEASE_SIGNING.md](../research/android/RELEASE_SIGNING.md)). The production key, which would give every release one signer, does not exist yet.

## Play Protect

Play Protect is not disabled, bypassed, patched or excluded by this project. The records describe what was seen. An `adb install` is a development route and is not evidence that the user route passes.

| Item | Result | Basis |
|---|---|---|
| Verifier settings on the Galaxy S24 Ultra (Android 16), read only | `package_verifier_user_consent=1`; `package_verifier_enable` unset (platform default); `upload_apk_enable=1`; `com.google.android.gms` and `com.android.vending` present | **Device** |
| Install by `adb install`, installer attribution `null` (used for all hardware testing) | No install-time Play Protect prompt or block; the app installed and ran (S24 Ultra; Pixel 8, API 37) | **Device** |
| Post-install, across repeated reinstall and test cycles | No automatic removal or disable event | **Device** |
| User route: file manager, then the system package installer, `compat` candidate before the lifecycle change | "App blocked to protect your device", reason that the app can request access to sensitive data, only "Got it"; the installer then reports "App not installed" | **Device** (S24 Ultra, API 37; [PERMISSION_FINDINGS.md](../research/android/PERMISSION_FINDINGS.md) PF8) |
| User route with the reduced permission set and no notification listener | Pending | |
| Distribution through the Play Store | Not applicable; not distributed there | n/a |

Google's developer guidance for Play Protect warnings describes "App blocked
to protect your device" as an automatic block of apps installed from
internet-sideloading sources (browsers, messaging apps, file managers) that
declare `RECEIVE_SMS`, `READ_SMS`, a notification listener or an
accessibility service. The stock manifest declares a notification listener
and none of the others; the `modernize` patch removes it, so the current build
declares none of the four (**Static**). Whether that clears the block on the
user route is **Expected** until the pending row above is run. An appeal goes
through Google's Play Protect appeals form, which asks for the package name and
the SHA-256 of the APK as submitted to VirusTotal; Google states that its
decisions are final and that it sends no reply. Separately, Google's Android
developer verification requires apps on certified devices to come from a
verified developer, in four countries from September 2026 and elsewhere from
2027 on its published schedule; ADB installs stay available (**Expected**).
Sources: [warning guidance](https://developers.google.com/android/play-protect/warning-dev-guidance),
[appeals form](https://support.google.com/googleplay/android-developer/contact/protectappeals),
[developer verification](https://support.google.com/android-developer-console/answer/16561738).

## Sources

- [patches/modernize/patch.cmake](../../patches/modernize/patch.cmake), authoritative for manifest edits and anchor counts
- [patches/modernize/java/com/creative/apps/sbconnect/PermissionLifecycle.java](../../patches/modernize/java/com/creative/apps/sbconnect/PermissionLifecycle.java)
- [patches/modernize/overlay/smali/com/creative/apps/sbconnect/RcvCompat.smali](../../patches/modernize/overlay/smali/com/creative/apps/sbconnect/RcvCompat.smali)
- [patches/modernize/overlay/smali/com/creative/apps/sbconnect/FgChannelCompat.smali](../../patches/modernize/overlay/smali/com/creative/apps/sbconnect/FgChannelCompat.smali)
- [patches/modernize/README.md](../../patches/modernize/README.md)
- [CMakeLists.txt](../../CMakeLists.txt), [cmake/sbc_patches.cmake](../../cmake/sbc_patches.cmake), [cmake/sbc_java.cmake](../../cmake/sbc_java.cmake), [cmake/resign_control.cmake](../../cmake/resign_control.cmake)
- [docs/research/android/PERMISSION_FINDINGS.md](../research/android/PERMISSION_FINDINGS.md), [PERMISSION_LIFECYCLE.md](../research/android/PERMISSION_LIFECYCLE.md)
- [docs/research/android/PERMISSION_AUDIT.md](../research/android/PERMISSION_AUDIT.md)
- [docs/research/android/RECEIVER_AUDIT.md](../research/android/RECEIVER_AUDIT.md)
- [docs/research/android/APP_IDENTITY.md](../research/android/APP_IDENTITY.md)
- [docs/research/android/PLAY_PROTECT_MATRIX.md](../research/android/PLAY_PROTECT_MATRIX.md)
- [docs/research/android/FINDINGS.md](../research/android/FINDINGS.md), [PIPELINE.md](../research/android/PIPELINE.md)
- [docs/research/arm64/ARM64_RUNTIME.md](../research/arm64/ARM64_RUNTIME.md)
- [docs/research/arm64/runtime/s24_launch.txt](../research/arm64/runtime/s24_launch.txt)
