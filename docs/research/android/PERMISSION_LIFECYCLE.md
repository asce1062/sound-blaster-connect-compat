# PERMISSION_LIFECYCLE

> **Historical record.** Kept as evidence of how behavior was established; not updated for later changes. Status, corrections and the maintained references: [research index](../README.md).

Inventory and design of the runtime-permission lifecycle of the modernized app
(`modernize`, and with it `arm64` and `compat`), from the findings in
[PERMISSION_FINDINGS.md](PERMISSION_FINDINGS.md) (PF1 to PF8). Static reading
of stock Sound Blaster Connect 1.04.02 as decoded by apktool 3.0.3; method
names are the obfuscated stock names. The change it describes is in
[patch.cmake](../../../patches/modernize/patch.cmake) and
[PermissionLifecycle.java](../../../patches/modernize/java/com/creative/apps/sbconnect/PermissionLifecycle.java).

## Request paths before the change

| Path | Requests | When |
|---|---|---|
| `MainActivity.D()`, called only from `onCreate` | `CAMERA`, `WRITE_EXTERNAL_STORAGE`, `RECORD_AUDIO`, `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`, code 0x457, no granted check | Every activity creation on API 23+, including the `recreate()` of the chain below |
| `BtPermCompat` (modernize overlay) | Nearby devices (0x42c) after the 0x457 result, then notifications (0x42d), then `recreate()` when `BLUETOOTH_CONNECT` is held | Every launch, chained off 0x457 |
| `MainActivity.w()` | Notification-listener access (system settings) | Removed by the patch before this change |

`CAMERA` is not declared in the manifest, so the platform denies it without a
dialog. `D()` running on every creation explains PF2: the `recreate()` at the
end of the chain creates the activity again and repeats the batch for every
member still denied.

## Bluetooth entry points

Calls that need `BLUETOOTH_CONNECT` or `BLUETOOTH_SCAN` on API 31+, grouped by
the code that reaches them first.

| Entry | Reached from | Before the change | After |
|---|---|---|---|
| `BluetoothUtils` getters: `a(String)` (bonded lookup), `b(Context)` (A2DP connected device), `c(Context)` (headset connected device), `g(device)` (bond and connection state) | `MainActivity.onCreate`, `onResume`, `C()`; `ConnectionFragment.g()`; `SbxDeviceManager`; `PreferencesUtils`; `MainService.onCreate` on boot | Ungated; `SecurityException` caught inside each method (PF1) | Gated on `btOk()`; return null or false, the stock "no device" value |
| `BluetoothUtils` actions: `b(device)` (createBond), `c(device)` / `d(device)` (A2DP connect, disconnect), `f(device)` (headset disconnect) | `SbxConnectionManager.b(device)`, `c(device)` | Ungated | Gated on `btOk()` |
| `BluetoothUtils.e(device)`, `BluetoothHeadset.connect` by reflection | `SbxConnectionManager.b(device)` on connect | Throws for `MODIFY_PHONE_STATE` on every connect (PF7) | Runs only with `MODIFY_PHONE_STATE` on API 31+ (see "Stock hidden-API calls") |
| `BluetoothUtils.a(device)`, device name | `SbxConnectionManager.f()`, list refresh | `getAliasName` by reflection, `NoSuchMethodException` (PF7), then fallbacks | Gated; API 30+ uses the public `getAlias()`, then `getName()` |
| `SbxConnectionManager.a()` (startDiscovery), `b()` (cancelDiscovery) | Connect screen, connect path | `a()` gated on `BLUETOOTH_CONNECT` only; `b()` ungated | Both gated on `scanOk()` (both Nearby permissions) |
| `SbxConnectionManager.f()` (bonded enumeration), `a(device)`, `b(device)` (connect), `c(device)` | Connect screen, `ConnectionFragment.onItemClick` | `f()` gated; others ungated (PF3) | All gated on `btOk()` |
| `ConnectionFragment.onItemClick`, Bluetooth partition | User tap | Reached the ungated calls, silent failure (PF3) | `requireBluetooth()`: explanation, request or settings, then stop |
| `ConnectionFragment.onResume` | Opening the connect screen | No prompt; with Nearby devices denied the device list is empty, so no tap reaches the check above | `requireBluetoothScreen()`, once per screen instance: the Nearby devices explanation on API 31+; on API 23 to 30, where discovery of unpaired devices needs location, the location explanation when precise location is not held |
| `AddBluetoothSpeakerFragment$3.onClick`: `BluetoothAdapter.enable()` | User tap on Add speaker | Ungated, outside `BluetoothUtils`; inside the method's catch | `enableAdapter()`: runs only with the grant and below API 33 (the platform ignores `enable()` from apps targeting 33+); the button still opens system Bluetooth settings |
| `BLEManager.e()`, BLE `startScan` | BLE device path | Ungated | Gated on `scanOk()` |
| `SbxConnectionManager.c()`, `WifiManager.startScan` for speakers in setup mode | Connect screen | Ungated; without location the platform refuses the scan and logs a permission violation | Gated on `wifiScanOk()` (precise location) |
| Profile proxy setup `BluetoothUtils.a(Context)`, `BluetoothAdapter.isEnabled` | Application and service start | No runtime permission required | Unchanged |
| Manifest `MainReceiver` and runtime receivers for Bluetooth actions (`SbxDeviceManager$2`, `SbxConnectionManager$2`, `$3`, `ConnectionFragment$1`, `MainService$3`) | Platform broadcasts | Delivered only to holders of `BLUETOOTH_CONNECT` on API 31+ (platform rule) | Unchanged |
| `SbxSocketBluetooth` (RFCOMM socket) and the bundled `ibluz` library (`c.a` to `c.i`, `BluzDeviceFactory`) | After a connect request | Reached only through the connect path above | Unchanged; their callers are gated |

## Runtime permissions and their consumers

| Permission | First-party consumer | Decision |
|---|---|---|
| `BLUETOOTH_CONNECT`, `BLUETOOTH_SCAN` | Every Bluetooth path above | Launch request once per install on API 31+; afterwards only from a device tap, with explanation |
| `POST_NOTIFICATIONS` | `MainService` foreground and media notifications | Launch request once per install on API 33+, independent of the Bluetooth result. Denied: the service runs without a visible notification |
| `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION` | Wi-Fi speaker setup: Wi-Fi scan results and the current network (`WifiSetupFragment`, `SbxWifiSetupManager`, which sends the chosen SSID to the speaker's own access point at 192.168.43.1); Wi-Fi scans in `SbxConnectionManager`; Bluetooth and BLE discovery on API 23 to 30. No positioning code | API 23 to 30: launch request once (discovery needs it there). API 31+: requested when Wi-Fi speaker setup opens |
| `RECORD_AUDIO` | Room calibration only (`CalibrationEngine`, `CalibrationManager`) | Requested when room calibration opens. Not needed for speaker control |
| `CAMERA` | None; not declared | No longer requested |
| `WRITE_EXTERNAL_STORAGE` | None in first-party code | No longer requested; declaration removed |

Location from Bluetooth scans: the scan results fill the device list and the
connection. The only Bluetooth-derived value found leaving the device is the
connected model name (`SbxDevice.b`) as the label of an analytics event
(`AnalyticsUtils`, from `MainActivity$2`, Google Analytics property
`UA-73800400-3`). No code derives a position from scan results. On that basis
`BLUETOOTH_SCAN` is declared with `neverForLocation`, so discovery on API 31+
needs no location grant; the platform then withholds some BLE beacon results.

## Stock hidden-API calls

| Call | Observed | Platform | Decision |
|---|---|---|---|
| `BluetoothHeadset.connect`, reflection, `BluetoothUtils.e` | `SecurityException` for `MODIFY_PHONE_STATE` on every connect, caught; the SPP session is unaffected (PF7). `BluetoothA2dp.connect` by reflection (`BluetoothUtils.c`) logged no exception in the same session | `MODIFY_PHONE_STATE` has protection level `signature|privileged`; an ordinary app cannot hold it | Not requested. On API 31+ the call runs only when the permission is held, which for this app means never |
| `BluetoothDevice.getAliasName`, reflection, `BluetoothUtils.a` | `NoSuchMethodException` on every list refresh, caught; the stock code falls back | `getAlias()` is public from API 30 | API 30+ uses `getAlias()`, then `getName()`; below 30 the stock lookup runs |

## Older-Android warning (PF6)

The permission controller's `AppPermissionViewModel` shows the warning when a
granted permission is revoked and one of these holds for the group:

- the permission was granted by default;
- the app does not support runtime permissions (targetSdk below 23);
- an install-time-to-runtime split applies: a split permission with a split
  targetSdk above the app's, a normal source permission, and a dangerous new
  permission the app requests.

On the S24 the package targets 34; the Nearby permissions carry `USER_SET` and
`USER_SENSITIVE_*` only; the `BLUETOOTH` and `BLUETOOTH_ADMIN` splits name
targetSdk 31, below the app's target. None of the three holds in the AOSP
code. The device runs Google's permission-controller module
(`aml_372527060`), whose source for that build is not published. The cause is
not identified, and the target API level is not changed for it.

## Manifest and capability review

| Item | Before | After | Reason |
|---|---|---|---|
| `LocalMusicRemoteControllerService` | Exported notification listener (`BIND_NOTIFICATION_LISTENER_SERVICE`, listener action) | Not exported; listener action and permission removed; the app's own `BIND_RC_CONTROL_SERVICE` action kept | `onNotificationPosted` is empty; the access fed only other players' Now Playing metadata through the deprecated `RemoteController`, and its prompt was already removed. `LocalMusicManager.i()` binds the service with an explicit-package intent, which an unexported service accepts. Consequence: no Now Playing metadata from other players, a feature already unreachable |
| `MEDIA_CONTENT_CONTROL` | Declared | Removed | `signature|privileged`; never granted |
| `SYSTEM_ALERT_WINDOW` | Declared | Removed | No overlay window in the code |
| `com.google.android.c2dm.permission.RECEIVE` | Declared | Removed | No first-party GCM registration; no GCM receiver declared |
| `WRITE_EXTERNAL_STORAGE` | Declared | Removed | No first-party shared-storage writes |
| `com.google.android.gms.appinvite.PreviewActivity` | Exported with a filter | Not exported | No first-party app-invite use |
| `MainService` type | `mediaPlayback` | `connectedDevice` with `FOREGROUND_SERVICE_CONNECTED_DEVICE` | The service holds the speaker link and a media session and plays no audio. The prerequisite is met by the declared normal permissions `CHANGE_NETWORK_STATE` and `NFC`, so the service may start before the Nearby grant and from `BOOT_COMPLETED` on API 35+, where `mediaPlayback` may not |
| `RevocationBoundService` (Google) | Exported, protected by a Google permission | Unchanged | Google's declaration |

Normal permissions (`NFC`, `CHANGE_NETWORK_STATE`, `CHANGE_WIFI_STATE`,
`ACCESS_*_STATE`, `INTERNET`, `VIBRATE`, `WAKE_LOCK`,
`MODIFY_AUDIO_SETTINGS`, `RECEIVE_BOOT_COMPLETED`) are unchanged.

## Lifecycle after the change

- **Launch** (`MainActivity.onCreate` to `PermissionLifecycle.onLaunch`):
  nothing on a recreated activity. Otherwise, each step once per install,
  recorded in the app's `sbc_permissions` preferences: Nearby devices on API
  31+, or location on API 23 to 30; then notifications on API 33+. The steps
  chain on each result because the platform drops a second request while one
  is on screen.
- **Grant after creation**: at the end of the launch sequence, after a
  feature request, or on returning from system settings (`onResume`), the
  activity is recreated once when Nearby devices is now held and was not at
  creation, so the stock initialization runs with the grant.
- **Feature prompts**: opening the connect screen or tapping a device (Nearby devices), opening room calibration
  (microphone) and opening Wi-Fi speaker setup (location). Each shows an
  explanation dialog. Its positive button requests the permission while the
  system can still show its dialog (never asked, or declined once), and opens
  the app's system settings page otherwise. A fragment resuming after the
  system dialog does not prompt again. A denial ends with a short message
  naming the unavailable feature.
- **Denied Nearby devices**: the offline UI stays; no Bluetooth call runs;
  tapping a device explains and offers the request or settings.

Features unavailable without each permission: Nearby devices, every device
connection and control; microphone, room calibration; location, Wi-Fi speaker
setup on all levels and Bluetooth discovery of new devices on API 23 to 30;
notifications, the visible foreground-service notification.

## Build changes that support it

- `patches/<p>/java/` is compiled at build time (`cmake/sbc_java.cmake`,
  `cmake/compile_java.cmake`): javac to Java 8 bytecode against the
  `android-34` platform jar, d8 from build-tools 37.0.0, then apktool decodes
  the dex to smali, which is copied onto the staged tree.
- apktool decode and build run with `-p build/apktool-framework`. Before,
  they used the per-user framework cache (`%LOCALAPPDATA%\apktool\framework\1.apk`),
  which on the build machine was a 2020 file without
  `attr/usesPermissionFlags`, so aapt2 rejected `neverForLocation`. The
  build-local directory takes the framework bundled in the pinned apktool jar,
  which defines it.
