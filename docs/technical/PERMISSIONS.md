# Permissions and security model

This document describes the security model of the built Sound Blaster Connect APK (package `com.creative.apps.sbconnect`, targetSdk 34 in the `modernize` and `arm64` variants, targetSdk 26 in `resign`): every declared permission with its origin, protection level, runtime request path and feature; the final export value of every manifest component and the reason for it; the exposure of runtime-registered receivers; and the signing identity with its consequences, including observed Play Protect behavior. The `resign` variant carries the stock manifest unchanged; everything marked "added" or "capped" below applies to `modernize` and `arm64`. The `compat` variant has the `arm64` manifest under the package `io.github.asce1062.sbconnect.compat`, with the provider authority renamed to match; its permissions and component exports are those of `arm64` ([APPLICATION_IDENTITY.md](APPLICATION_IDENTITY.md)). The behavior changes themselves are described in [ANDROID_COMPATIBILITY.md](ANDROID_COMPATIBILITY.md).

## Verification basis

| Tag | Meaning |
|---|---|
| **Build** | Enforced by the build: an anchor asserted to occur a fixed number of times in [patch.cmake](../../patches/modernize/patch.cmake). |
| **Device** | Observed on hardware (Pixel 7a, Android 13; Galaxy S24 Ultra, Android 16; one Sound BlasterX Katana). Raw runtime logs were not preserved; only excerpts in [runtime/](../research/arm64/runtime/) exist. |
| **Static** | Read from code or the built manifest, not executed. Statements that a permission is "dormant" or "inert" carry this tag unless a trace exists. |
| **Expected** | Platform documentation or inference, not observed in this project. |

No 32-bit device was tested; anything about the variants on 32-bit hardware is **Expected**. The full permission list below was read from the built manifest by the permission audit ([PERMISSION_AUDIT.md](../research/android/PERMISSION_AUDIT.md)); `patch.cmake` itself edits only the entries marked "added" or "capped".

## Declared permissions

| Permission | Origin | Protection level | Runtime request | Feature | Basis |
|---|---|---|---|---|---|
| `BLUETOOTH` | Stock, capped `maxSdkVersion="30"` | Normal (install-time) | none | SPP/RFCOMM link to the device on API 30 and below | **Build** (cap); **Static** (use) |
| `BLUETOOTH_ADMIN` | Stock, capped `maxSdkVersion="30"` | Normal (install-time) | none | Discovery and adapter control on API 30 and below | **Build**; **Static** |
| `BLUETOOTH_SCAN` | Added | Dangerous, runtime (API 31+, "Nearby devices") | `BtPermCompat.ensure()`, request code 0x42c, after the stock batch | Device discovery (`startDiscovery`) | **Build** (declared); **Device** (S24 Ultra: prompted and granted) |
| `BLUETOOTH_CONNECT` | Added | Dangerous, runtime (API 31+, "Nearby devices") | `BtPermCompat.ensure()`, request code 0x42c, same request as `BLUETOOTH_SCAN` | Bonded-device enumeration (`getBondedDevices`) and the SPP connection; `BtPermCompat.ok()` guards both entry points on this permission | **Build**; **Device** |
| `POST_NOTIFICATIONS` | Added | Dangerous, runtime (API 33+) | `BtPermCompat.askNotif()`, request code 0x42d, after the Bluetooth result | The app's own foreground-service and media notifications; it guards nothing else | **Build**; **Device** |
| `FOREGROUND_SERVICE` | Added | Normal | none | `MainService` runs as a foreground service | **Build**; **Device** (service foreground on S24 Ultra) |
| `FOREGROUND_SERVICE_MEDIA_PLAYBACK` | Added | Normal | none | Matches `foregroundServiceType="mediaPlayback"` on `MainService` (API 34+) | **Build**; **Device** |
| `MODIFY_AUDIO_SETTINGS` | Stock | Normal | none | Audio routing and device settings | **Static** |
| `WAKE_LOCK` | Stock | Normal | none | Keeps the CPU awake during connect and playback | **Static** |
| `ACCESS_NETWORK_STATE` | Stock | Normal | none | Connectivity checks; bundled Google Play services libraries | **Static** |
| `INTERNET` | Stock | Normal | none | Bundled Google Play services, ads and measurement libraries; `JSONParser` HTTP fetch | **Static** |
| `NFC` | Stock | Normal | none | Tap-to-pair on NFC-capable hardware; dormant with the Katana | **Static** |
| `CHANGE_NETWORK_STATE` | Stock | Normal | none | Network routing for Wi-Fi-capable devices; dormant for an SPP-only device | **Static** |
| `CHANGE_WIFI_STATE` | Stock | Normal | none | Wi-Fi control for Wi-Fi-capable devices; dormant here | **Static** |
| `ACCESS_WIFI_STATE` | Stock | Normal | none | Reads Wi-Fi state | **Static** |
| `VIBRATE` | Stock | Normal | none | Haptic feedback | **Static** |
| `RECEIVE_BOOT_COMPLETED` | Stock | Normal | none | `MainReceiver` start on `BOOT_COMPLETED` | **Static**; **Device** (broadcast delivered after reboot, S24 Ultra) |
| `com.google.android.c2dm.permission.RECEIVE` | Stock | Signature (Google-defined) | none | Legacy push for the bundled Google libraries | **Static** |
| `ACCESS_COARSE_LOCATION` | Stock, capped `maxSdkVersion="22"` | Dangerous | none | Pre-API-23 location model for Bluetooth scanning | **Static** |
| `ACCESS_COARSE_LOCATION` (`uses-permission-sdk-23`) | Stock | Dangerous | stock batch | Coarse-location companion to the scan path on API 23+ | **Static** |
| `ACCESS_FINE_LOCATION` | Stock, uncapped | Dangerous | stock batch (request code 0x457) | Location requirement of Bluetooth scanning before API 31. Declining it on API 37 leaves the connection to an already-paired speaker working; discovery of an unpaired device with location declined is untested | **Device** (location dialog during setup on S24 Ultra; declined path, `compat`, API 37); **Static** (use) |
| `RECORD_AUDIO` | Stock | Dangerous | stock batch (0x457) | Microphone prompt at first run; belongs to the audio-tuning or input-monitoring feature. Declining it leaves the Bluetooth connection, reads and volume writes working | **Static**; **Device** (`compat`, S24 Ultra, API 37) |
| `WRITE_EXTERNAL_STORAGE` | Stock, uncapped | Dangerous (legacy) | none | Local-music browsing | **Static**; no effect on a target-34 app is **Expected** (scoped storage) |
| `MEDIA_CONTENT_CONTROL` | Stock | Signature or privileged | none | Drives the removed `RemoteController` media API behind `LocalMusicRemoteControllerService` | **Static**; never granted to a debug-signed sideload is **Expected** |
| `SYSTEM_ALERT_WINDOW` | Stock | Special (AppOps; user toggle in Settings) | none | Draw-over-apps overlay; dormant unless that code path runs | **Static** |

Notes:

- The patch adds five permissions (`BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`, `POST_NOTIFICATIONS`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK`) and caps two (`BLUETOOTH`, `BLUETOOTH_ADMIN`). The permission audit summary calls these "six additions" and omits one from its count; this document follows the code.
- The stock request batch (code 0x457) is issued by `MainActivity.D()` on every launch; a comment in `BtPermCompat.smali` describes it as camera, microphone and location. The built-manifest list in the audit has no `CAMERA` entry, and this document does not resolve that difference.
- `android:usesPermissionFlags="neverForLocation"` is not set on `BLUETOOTH_SCAN` because apktool 3.0.3's pinned framework attribute table predates it and aapt2 rejects it (**Build** toolchain constraint, noted in `patch.cmake`). `ACCESS_FINE_LOCATION` therefore remains declared and requested although the app has no positioning feature (**Static**: the audit reports no GPS code path).
- Request order on API 33+ is location and microphone (stock batch), then Nearby devices, then notifications, then `Activity.recreate()` when `BLUETOOTH_CONNECT` is held. The requests are chained because Android drops a second `requestPermissions` call while a dialog sequence is pending (**Device**, S24 Ultra; rationale in code comments). Below API 31 `BtPermCompat` does nothing, and below API 33 `askNotif()` does nothing (**Static**).
- Because the stock batch runs on every launch, the `recreate()` at the end of the chain asks again for any batch permission still denied. A denied microphone is requested twice in the first-run sequence (**Device**, `compat`, S24 Ultra, API 37).
- Before Nearby devices is granted, `SbxDeviceManager` reaches `BluetoothA2dp.getConnectedDevices` through `BluetoothUtils`. `BtPermCompat` does not guard that path, so it throws `SecurityException: Need android.permission.BLUETOOTH_CONNECT`. The stock code catches the exception, and the call is not fatal (**Device**, same run).
- With Nearby devices declined in the dialog, the app stays on its offline Now Playing screen and lists the paired speaker as Disconnected. Tapping it reaches the same unguarded call from `ConnectionFragment.onItemClick` through `SbxConnectionManager` and `BluetoothUtils`. The `SecurityException` is caught, nothing connects, and the app shows no message and does not ask again. No fatal exception or ANR occurs (**Device**, `compat`, S24 Ultra, API 37).
- During a connection the stock code calls `BluetoothHeadset.connect`, which throws a caught `SecurityException` for `MODIFY_PHONE_STATE`. The stock-identity `arm64` build logs the same exception, and the SPP session is unaffected (**Device**).
- Denying Nearby devices in system settings shows the permission controller's "designed for an older version of Android" warning, although the package targets API 34 (**Device**, same run; cause not identified). Records: [HARDWARE_VALIDATION.md](../research/android/HARDWARE_VALIDATION.md).
- No permission was added for a purpose other than keeping the stock Bluetooth and foreground-service paths working at targetSdk 34 (**Static**).

## Component export model

Before API 31 a component with an `<intent-filter>` was implicitly exported. At targetSdk 31 and above the manifest must say so explicitly (**Expected** platform rule, **Build** anchors). The patch sets six explicit values (one anchor each). Protected system broadcasts and framework-targeted deliveries (media-button routing, notification-listener binding) reach a manifest component whether or not it is exported, because the sender is the system; `exported="true"` matters only when a third-party app must reach the component.

| Component | Type | Stock | Final | Reason | Basis |
|---|---|---|---|---|---|
| `MainActivity` | Activity | no `exported` | `true` | Launcher entry point | **Build**; **Device** |
| `MainReceiver` | Receiver | no `exported` | `false` | Receives 14 protected system broadcasts (Bluetooth adapter `STATE_CHANGED`; device `BOND_STATE_CHANGED`, `NAME_CHANGED`, `ALIAS_CHANGED`, `ACL_CONNECTED`, `ACL_DISCONNECT_REQUESTED`, `ACL_DISCONNECTED`; A2DP and headset `CONNECTION_STATE_CHANGED`; `CONNECTIVITY_CHANGE`; `BOOT_COMPLETED`; `SCREEN_ON`; `USER_PRESENT`; `LOCALE_CHANGED`) and one app-namespaced action, `com.creative.apps.sbconnect.action.START_SERVICE`, sent inside the package. `false` closes the one third-party exposure: any installed app could otherwise broadcast `START_SERVICE` to it | **Build**; **Device**: `BOOT_COMPLETED` delivered after reboot, the process started for the broadcast with no manual launch (S24 Ultra). `CONNECTIVITY_CHANGE` is skipped by the platform's target-SDK policy regardless of the flag |
| `MainService` | Service | `exported="true"` | `false` | `mediaPlayback` foreground service filtering `START_SERVICE` and `PLAY_PAUSE`, both started in-package: directly, or from the app's own notification `PendingIntent`s, which run under the app's identity | **Build** (flip anchored on the unique label); **Device**: started as a foreground service from a same-app caller, type `mediaPlayback`, channel `sbconnect_fg`; also created from the boot receiver |
| `LocalMusicRemoteControllerService` | Service (notification listener) | no `exported` | `true` | The system binds a notification listener from outside the app. Binding is restricted by `BIND_NOTIFICATION_LISTENER_SERVICE`, a signature-level permission that only the system can hold | **Build**; **Static**. The feature behind it is inert and its access prompt is suppressed (see [ANDROID_COMPATIBILITY.md](ANDROID_COMPATIBILITY.md), row 12) |
| `MediaButtonReceiver` (support library) | Receiver | no `exported` | `false` | Filters `MEDIA_BUTTON`; the `MediaSession` framework delivers media-button events to the session owner's registered component as a targeted system delivery. `false` is the library's own modern default | **Build**. Runtime **not exercised**: the test device had no active media session, so the value rests on static reasoning |
| `AppMeasurementReceiver` (Google) | Receiver | no `exported` | `false` | Fed only by in-package broadcasts | **Build** |
| `AppMeasurementService`, `AppMeasurementContentProvider`, `SignInHubActivity` (Google) | Service, provider, activity | `false` | `false` (unchanged) | Google's own declaration | **Static** |
| `PreviewActivity`, `RevocationBoundService` (Google) | Activity, service | `true` | `true` (unchanged) | Google's design; the service is protected by a Google permission | **Static** |
| `AdActivity`, `InAppPurchaseActivity` (Google) | Activities | no filter | default (not exported) | No intent filter | **Static** |

Observed regression result with the final values in place (**Device**, Galaxy S24 Ultra, clean install, Play Protect on): app starts without a fatal error or ANR, the Nearby devices flow completes, the Katana appears, the SPP control connection opens with `MainService` in the foreground, presets and per-source availability read from the speaker, and no `Permission Denial` was logged against the three components flipped to `false`. The only `System.err` entries were the stock `SbxDeviceManager` A2DP and headset profile probes that need `BLUETOOTH_CONNECT`, independent of export flags. The residual risk of `MainReceiver` and `MainService` being `false` is an undocumented external integration that broadcasts to them; none is known (**Static**).

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

1. **Signature conflict with stock.** A different certificate means an output cannot be installed as an update over a Creative-signed install; the stock app must be uninstalled first, which removes its data (**Expected**: `INSTALL_FAILED_UPDATE_INCOMPATIBLE`; not observed, since the 64-bit-only test devices cannot install stock at all). Output variants share one debug certificate and one versionCode; repeated `adb install -r` of successive `arm64` builds worked during testing (**Device**). The `compat` variant is a different package, so it does not conflict with a stock install; it conflicts only with another `compat` build signed by a different key.
2. **No origin attestation.** The debug certificate does not bind a build to Creative or to this project. Anyone holding a debug key with the same fingerprint can produce an APK the system accepts as an update to an installed output (**Expected**).
3. **Signature-level permissions are never granted.** `MEDIA_CONTENT_CONTROL` and any `signature` or `signature|privileged` permission stay ungranted to a debug-signed sideload (**Expected**).
4. **v2 or later is required at target 30 and above.** The stock app's v1-only signature suffices at its own target 26; the re-targeted outputs carry v2 and v3 (**Expected** platform rule). The device reported `apkSigningVersion=4` for the arm64 build (**Device**, recorded value).
5. **Outputs are sideload-only.** The Creative private key is unavailable.
6. **Release signing.** `compat` has test-release and release targets that sign with an externally supplied key, v1, v2 and v3, and check the certificate against an expected SHA-256 ([SIGNING.md](../development/SIGNING.md)). A test-release build updated an earlier build signed with the same key and kept its data, and a build signed with another key was refused as an update (**Emulator**, API 30; [RELEASE_SIGNING.md](../research/android/RELEASE_SIGNING.md)). The production key, which would give every release one signer, does not exist yet.

## Play Protect

Play Protect is not disabled, bypassed, patched or excluded by this project. The records describe what was seen.

| Item | Result | Basis |
|---|---|---|
| Verifier settings on the Galaxy S24 Ultra (Android 16), read only | `package_verifier_user_consent=1`; `package_verifier_enable` unset (platform default); `upload_apk_enable=1`; `com.google.android.gms` and `com.android.vending` present | **Device** |
| Install by `adb install -r`, installer attribution `null` (used for all hardware testing) | No install-time Play Protect prompt or block; the app installed and ran | **Device** |
| Post-install, across repeated reinstall and test cycles | No automatic removal or disable event; the one uninstall was user-initiated | **Device** |
| Background analysis | With `upload_apk_enable=1` an unknown APK may be sampled by Google; it did not block or alter the app | **Device** (setting), **Expected** (behavior) |
| User sideload through a file manager or browser and the package installer | An "allow from this source" step and a Play Protect scan; for an unrecognized debug-signed app, commonly a warning with an install-anyway choice | **Expected**. This path was not run. |
| Distribution through the Play Store | Not applicable; not distributed there | n/a |

The expected scrutiny follows from the signer profile (debug key, no known-good signer, no store installer record), not from the app's content (**Expected**). The Pixel 7a has no recorded Play Protect observation.

## Sources

- [patches/modernize/patch.cmake](../../patches/modernize/patch.cmake), authoritative for manifest edits and anchor counts
- [patches/modernize/overlay/smali/com/creative/apps/sbconnect/BtPermCompat.smali](../../patches/modernize/overlay/smali/com/creative/apps/sbconnect/BtPermCompat.smali)
- [patches/modernize/overlay/smali/com/creative/apps/sbconnect/RcvCompat.smali](../../patches/modernize/overlay/smali/com/creative/apps/sbconnect/RcvCompat.smali)
- [patches/modernize/overlay/smali/com/creative/apps/sbconnect/FgChannelCompat.smali](../../patches/modernize/overlay/smali/com/creative/apps/sbconnect/FgChannelCompat.smali)
- [patches/modernize/README.md](../../patches/modernize/README.md) (partly superseded; see ANDROID_COMPATIBILITY.md)
- [CMakeLists.txt](../../CMakeLists.txt), [cmake/sbc_patches.cmake](../../cmake/sbc_patches.cmake), [cmake/resign_control.cmake](../../cmake/resign_control.cmake)
- [docs/research/android/PERMISSION_AUDIT.md](../research/android/PERMISSION_AUDIT.md)
- [docs/research/android/RECEIVER_AUDIT.md](../research/android/RECEIVER_AUDIT.md)
- [docs/research/android/APP_IDENTITY.md](../research/android/APP_IDENTITY.md)
- [docs/research/android/PLAY_PROTECT_MATRIX.md](../research/android/PLAY_PROTECT_MATRIX.md)
- [docs/research/android/FINDINGS.md](../research/android/FINDINGS.md), [PIPELINE.md](../research/android/PIPELINE.md)
- [docs/research/arm64/ARM64_RUNTIME.md](../research/arm64/ARM64_RUNTIME.md)
- [docs/research/arm64/runtime/s24_launch.txt](../research/arm64/runtime/s24_launch.txt)
