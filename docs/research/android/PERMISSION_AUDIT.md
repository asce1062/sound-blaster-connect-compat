# PERMISSION_AUDIT

> **Historical record.** Kept as evidence of how behavior was established; not updated for later changes. Status, corrections and the maintained references: [research index](../README.md).

Phase 5A permission audit for the modernized arm64 Sound Blaster Connect build.
Every `uses-permission` in the packaged `AndroidManifest.xml` is enumerated,
classified by Android protection level, justified against app function, and given
a verdict. Source of truth: `build/arm64/tree/AndroidManifest.xml` (the apktool
tree the APK is built from); the declaration edits live in
`patches/modernize/patch.cmake`.

Package `com.creative.apps.sbconnect`, versionCode 10402, minSdk 14,
targetSdk 34.

## Summary

| Verdict | Count | Permissions |
|---|---|---|
| Required, correct | 11 | BLUETOOTH, BLUETOOTH_ADMIN, BLUETOOTH_SCAN, BLUETOOTH_CONNECT, POST_NOTIFICATIONS, FOREGROUND_SERVICE, FOREGROUND_SERVICE_MEDIA_PLAYBACK, MODIFY_AUDIO_SETTINGS, WAKE_LOCK, ACCESS_NETWORK_STATE, INTERNET |
| Stock, benign | 8 | NFC, CHANGE_NETWORK_STATE, CHANGE_WIFI_STATE, ACCESS_WIFI_STATE, VIBRATE, RECEIVE_BOOT_COMPLETED, com.google.android.c2dm.permission.RECEIVE, ACCESS_COARSE_LOCATION (sdk-capped) |
| Inert on modern Android | 2 | WRITE_EXTERNAL_STORAGE, MEDIA_CONTENT_CONTROL |
| Sensitive, confirm feature | 2 | RECORD_AUDIO, SYSTEM_ALERT_WINDOW |
| Over-broad on API 31+ | 1 | ACCESS_FINE_LOCATION |

No permission was added for a modding or data-collection purpose. The six
modernization additions (BLUETOOTH_SCAN, BLUETOOTH_CONNECT, POST_NOTIFICATIONS,
FOREGROUND_SERVICE, FOREGROUND_SERVICE_MEDIA_PLAYBACK, and the two legacy caps)
are the minimum to keep the stock Bluetooth and foreground-service paths working
at targetSdk 34. No encoder, decoder, or native code is involved.

## Full table

| Permission | Protection | Granted to a sideloaded app? | Purpose | Verdict |
|---|---|---|---|---|
| BLUETOOTH (`maxSdkVersion=30`) | install-time (legacy) | yes, API <=30 | SPP/RFCOMM to the device pre-12 | Required. Capped at 30 by the patch; replaced by BLUETOOTH_CONNECT above. |
| BLUETOOTH_ADMIN (`maxSdkVersion=30`) | install-time (legacy) | yes, API <=30 | discovery/adapter control pre-12 | Required. Capped at 30; replaced by BLUETOOTH_SCAN. |
| BLUETOOTH_SCAN | runtime (API 31+) | yes, on grant | device discovery (`startDiscovery`) | Required. Requested at runtime by BtPermCompat. See note 1 on `neverForLocation`. |
| BLUETOOTH_CONNECT | runtime (API 31+) | yes, on grant | bonded enumeration + SPP connect | Required. Core function; without it every Bluetooth call throws SecurityException at targetSdk 31+. |
| POST_NOTIFICATIONS | runtime (API 33+) | yes, on grant | the foreground-service / media notification | Required. Added by the patch; requested at runtime. |
| FOREGROUND_SERVICE | install-time (normal) | yes | MainService runs as a foreground service | Required at API 28+. |
| FOREGROUND_SERVICE_MEDIA_PLAYBACK | install-time (normal) | yes | typed FGS matching `foregroundServiceType="mediaPlayback"` | Required at API 34+. Matches the service type exactly. |
| MODIFY_AUDIO_SETTINGS | install-time (normal) | yes | audio routing / device settings | Required. Core audio-device function. |
| WAKE_LOCK | install-time (normal) | yes | hold CPU awake during connect/playback | Required. |
| ACCESS_NETWORK_STATE | install-time (normal) | yes | connectivity checks; GMS | Stock, benign. |
| INTERNET | install-time (normal) | yes | GMS, ads/measurement library, any firmware fetch | Stock, benign. |
| NFC | install-time (normal) | yes | tap-to-pair on NFC-capable Creative hardware | Stock, benign. Dormant on the Katana (no NFC pairing path exercised). |
| CHANGE_NETWORK_STATE | install-time (normal) | yes | network routing for Wi-Fi-capable Creative devices | Stock, benign. Dormant for an SPP-only device. |
| CHANGE_WIFI_STATE | install-time (normal) | yes | Wi-Fi control for Wi-Fi-capable devices | Stock, benign. Dormant here. |
| ACCESS_WIFI_STATE | install-time (normal) | yes | read Wi-Fi state | Stock, benign. |
| VIBRATE | install-time (normal) | yes | haptic feedback | Stock, benign. |
| RECEIVE_BOOT_COMPLETED | install-time (normal) | yes | MainReceiver auto-start on BOOT_COMPLETED | Stock, benign. Auto-start is the stock behavior; see `RECEIVER_AUDIT.md`. |
| com.google.android.c2dm.permission.RECEIVE | signature (Google) | only with GMS | legacy C2DM/GCM push to the measurement/ads libraries | Stock, benign. Library-defined. |
| ACCESS_COARSE_LOCATION (`maxSdkVersion=22`) | runtime | yes, API <=22 | pre-23 location model for BT scan | Stock, correctly capped at 22. |
| WRITE_EXTERNAL_STORAGE | runtime (legacy) | ignored at API 30+ | local-music browse / SD access | Inert on modern Android (scoped storage). Not granted at targetSdk 34; harmless. See note 2. |
| MEDIA_CONTENT_CONTROL | **signature\|privileged** | **never** (not a system app) | drive the removed RemoteController media API | Inert. A sideloaded app can never hold this; tied to the now-suppressed notification-listener media feature. See note 3. |
| RECORD_AUDIO | runtime (dangerous) | yes, on grant | microphone setup prompt seen at first run | Sensitive. Stock; requested at runtime. See note 4. |
| SYSTEM_ALERT_WINDOW | special (AppOps) | only via explicit Settings grant | draw-over-other-apps overlay | Sensitive special permission. Stock; not auto-granted, requires a manual Settings toggle, and is dormant unless the overlay path runs. See note 5. |
| ACCESS_FINE_LOCATION | runtime (dangerous) | yes, on grant | BLE scan location requirement pre-31 | Over-broad on API 31+. See note 1. |
| `uses-permission-sdk-23` ACCESS_COARSE_LOCATION | runtime | yes, API 23+ | coarse-location companion to the BLE scan path | Stock, benign. |

## Notes

1. **ACCESS_FINE_LOCATION / `neverForLocation`.** Before API 31 a Bluetooth LE
   scan required a location grant, so the stock app declares
   ACCESS_FINE_LOCATION (uncapped) and prompts for it at first run (the location
   dialog seen during setup). At API 31+ a scan can instead declare
   `android:usesPermissionFlags="neverForLocation"` on BLUETOOTH_SCAN and drop
   the location requirement. That attribute is **not** applied here: apktool's
   pinned framework (API 23 attribute table) predates it and aapt2 rejects it
   (recorded in `patch.cmake`). Consequence: on a modern device the app still
   asks for location it does not use for positioning. This is a known toolchain
   tradeoff, not a data-collection path, the app holds no GPS code path. A future
   toolchain that can emit the API-31 attribute should add `neverForLocation` to
   BLUETOOTH_SCAN and cap ACCESS_FINE_LOCATION at `maxSdkVersion="30"`, removing
   the location prompt. Recommended, not blocking.

2. **WRITE_EXTERNAL_STORAGE.** Uncapped in the manifest, but at targetSdk 30+ it
   is not granted (scoped storage supersedes it). It is a no-op on the Katana
   runtime. Capping at `maxSdkVersion="18"` would make the manifest honest;
   cosmetic only.

3. **MEDIA_CONTENT_CONTROL.** Protection level `signature|privileged`: the
   platform grants it only to apps signed with the platform key or installed as
   a privileged system app. A debug-signed sideload never receives it. It exists
   to feed the `android.media.RemoteController` path behind
   `LocalMusicRemoteControllerService`, which is removed on modern Android; the
   prompt for that feature is suppressed in this build. Inert and ungrantable;
   left in place because it changes nothing.

4. **RECORD_AUDIO.** A dangerous runtime permission, surfaced as the microphone
   prompt at first run. It is stock and belongs to the device's audio-tuning /
   input-monitoring feature. The bringup does not add or widen it. It is called
   out here only because it is sensitive: if the microphone feature is not used
   with the Katana, the grant can be declined at runtime with no effect on the
   connection.

5. **SYSTEM_ALERT_WINDOW.** A special permission that is never auto-granted; the
   user must enable "Display over other apps" in Settings. Stock. Dormant unless
   the overlay code path runs. No change by the bringup.

## Cross-references

- Modernization permission edits: `patches/modernize/patch.cmake` (manifest block).
- Component exposure (exported receivers/services): `RECEIVER_AUDIT.md`.
- Signing identity that gates `signature`/`privileged` permissions: `APP_IDENTITY.md`.
