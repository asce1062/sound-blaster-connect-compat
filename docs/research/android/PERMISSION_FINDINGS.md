# PERMISSION_FINDINGS

> **Historical record.** Kept as evidence of how behavior was established; not updated for later changes. Status, corrections and the maintained references: [research index](../README.md).

Baseline of the permission and platform-API findings from the device run of
the `compat` candidate `3b6d70b` on a Galaxy S24 Ultra (Android 17, API 37)
with a Sound BlasterX Katana, on 2026-11-25
([HARDWARE_VALIDATION.md](HARDWARE_VALIDATION.md)). It fixes what was
observed before any change to the permission lifecycle, and keeps the
observations apart from the explanations proposed for them.

Two kinds of statement are used:

- **Observed**: seen on the device, in its logs or in the installed package
  state. The source is named.
- **Hypothesis**: a proposed cause or consequence that the observations do not
  establish. Each names what would settle it.

## Findings

### PF1. Bluetooth calls before the Nearby devices grant

Observed: on the first launch, before Nearby devices (`BLUETOOTH_CONNECT`,
`BLUETOOTH_SCAN`) is granted, `SbxDeviceManager` reaches
`BluetoothA2dp.getConnectedDevices` through `BluetoothUtils`, which throws
`SecurityException: Need android.permission.BLUETOOTH_CONNECT`. The app
catches it; the process continues.

Hypothesis: the existing gate (`BtPermCompat.ok()` on discovery and bonded
enumeration) covers two entry points of the connection manager and no other
Bluetooth call. Settled by an inventory of Bluetooth call sites and their
callers.

### PF2. Repeated microphone request

Observed: with the microphone declined, the first-launch sequence asks for it
a second time after the activity's `recreate()`.

Hypothesis: the stock request batch runs on every activity creation and asks
again for any member still denied, so every later launch with a declined
microphone also prompts until the system stops showing the dialog. Settled by
reading the batch's caller and by relaunching with the microphone declined.

### PF3. Silent failure with Nearby devices declined

Observed: with Nearby devices declined in the dialog (`USER_FIXED`), the app
stays alive on its offline Now Playing screen ("Touch to connect to an Audio
Device"). The Connect screen lists the paired Katana as Disconnected. Tapping
it shows nothing: no message, no new request. The log shows a caught
`SecurityException: Need android.permission.BLUETOOTH_CONNECT` from
`ConnectionFragment.onItemClick` through `SbxConnectionManager.a` and
`BluetoothUtils.b` to `BluetoothA2dp.getConnectedDevices`. No fatal exception
or ANR.

### PF4. Paired connection with location declined

Observed: with location declined (`USER_FIXED`) and Nearby devices allowed,
tapping the paired Katana on the Connect screen starts discovery, connects
SPP, starts the CtProtocol session (`maxpayloadSize 62`,
`GET_FEATURE_CONTROL_SUPPORT`) and promotes `MainService` to the foreground.
The app does not connect by itself on launch in that state.

### PF5. Discovery of an unpaired device without location

Not observed. No unpaired device was discovered in any run, with or without
location.

Hypothesis: on API 31 and later, because `BLUETOOTH_SCAN` is declared without
`neverForLocation`, discovery results for a new device are withheld unless
location is granted. Settled by a controlled discovery of an unpaired device
with location declined.

### PF6. "Designed for an older version of Android" warning

Observed: denying Nearby devices from the app's page in system settings shows
the permission controller's warning that the app was designed for an older
version of Android and that denying may stop it working as intended. The
package targets API 34. `BLUETOOTH` and `BLUETOOTH_ADMIN` are capped at
`maxSdkVersion 30`. The two Nearby permissions carry `USER_SET` and
`USER_SENSITIVE_*` flags only. The denial was cancelled.

Hypothesis: none established. Candidates include the permission controller's
handling of a permission group that holds a permission with a legacy
`maxSdkVersion`, and its treatment of `uses-permission-sdk-23`. Settled by
reading the permission controller's condition for that message.

### PF7. `MODIFY_PHONE_STATE` exception on connect

Observed: on connecting, `ConnectionFragment.onItemClick` calls
`SbxConnectionManager.b`, which calls `BluetoothUtils.e`, which invokes
`BluetoothHeadset.connect` by reflection. The call throws
`SecurityException: Neither user ... nor current process has
android.permission.MODIFY_PHONE_STATE`, wrapped in an
`InvocationTargetException`, and the app catches it. The SPP session is
unaffected. The stock-identity `arm64` build logs the same exception in its
baseline session.

A related caught failure: `BluetoothUtils.a`, reached from
`SbxConnectionManager.f` during the device list refresh, throws
`NoSuchMethodException: android.bluetooth.BluetoothDevice.getAliasName`.

Hypothesis: both are stock calls to hidden platform methods that no longer
exist or are not available to third-party apps. Settled by reading
`BluetoothUtils` and its callers.

### PF8. Play Protect block on the user install route

Observed: opening the debug-signed candidate APK from the device file manager
and handing it to the system package installer produces "App blocked to
protect your device" with the reason that the app can request access to
sensitive data, and only a "Got it" choice. The installer then reports "App
not installed". Logcat names no rule. The same package installs through
`adb install`, which does not show that the user route passes Play Protect.

Hypothesis: the block responds to the declared capabilities (sensitive
permissions, the notification-listener service) together with an unknown
signer. Not settled by the device run; Google does not publish the rule.

## Not part of this baseline

- CtProtocol behavior. No protocol change is related to any finding.
- The 16 KiB-page runtime. The device uses 4 KiB pages.
