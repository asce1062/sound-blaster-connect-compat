# HARDWARE_VALIDATION

> **Historical record.** Kept as evidence of how behavior was established; not updated for later changes. Status, corrections and the maintained references: [research index](../README.md).

Device run of the `compat` candidate on a Galaxy S24 Ultra with a Sound
BlasterX Katana, next to an existing install of the stock-identity `arm64`
build, on 2026-11-25. It covers coexistence, identity, the permission flow,
the arm64 native runtime, Katana reads and writes, component exports, boot
delivery, the Play Protect install route and the effect on the existing app.
Protocol behavior was not changed for this run.

## Candidate

| Field | Value |
|---|---|
| Source | integration candidate `3b6d70b` (identity and page-size changes), clean tree |
| APK | `sbc_compat-aligned-debugSigned.apk`, 47488966 bytes |
| SHA-256 | `e6f4b7a957a1b65f12c775b3e137aeeab6c5977d299e5a949653f9bf5aa4811d` |
| Package | `io.github.asce1062.sbconnect.compat`, versionCode 1000, versionName `1.04.02-compat.0.1.0`, targetSdk 34 |
| Label | `SB Connect Compat` |
| Signer | v1, v2, v3; one signer, `CN=Android Debug`, SHA-256 `665d62c0db7db08aa52b50825e2a45992aaa0056d82a80a6d1bc491ce2c54202` |
| Alignment | `zipalign -c -P 16 4` passes |
| `lib/arm64-v8a/libsbxapplogic_ctprotocol_jni.so` | `970d1744d765e80a3e4b82854add4dd1d96402f0841b0a78070f9d80432d7836`, LOAD alignment `0x4000` |
| `lib/arm64-v8a/libserialport_jni.so` | `ca380c7c549c197777d8b76a1c763806030992da4fe0af74e6cf47f8d9eff232`, LOAD alignment `0x4000` |
| Measurement provider authority | `io.github.asce1062.sbconnect.compat.google_measurement_service` |
| `MainReceiver`, `MainService`, `MediaButtonReceiver` | `exported=false` |

## Device and existing install

| Field | Value |
|---|---|
| Device | Galaxy S24 Ultra (SM-S928U1), Android 17, API 37, security patch 2026-10-05 |
| ABIs | `arm64-v8a` only; no 32-bit ABI |
| Page size | 4096 bytes |
| Connection | wireless ADB |
| Existing app | `com.creative.apps.sbconnect` 10402 / `1.04.02`, targetSdk 34: the project's `arm64` build, signed with the same debug certificate `665d62c0...`, installed through the system package installer on 2026-10-15 |
| Play Protect | "Scan apps with Play Protect" on, "Improve harmful app detection" on; `package_verifier_user_consent=1`, `upload_apk_enable=1`; not changed during the run |

Below, **A** is the existing app and **B** the candidate. The existing app
was not uninstalled, cleared or overwritten.

## Results by gate

| Gate | Result |
|---|---|
| APPLICATION_COEXISTENCE | **Pass** |
| APPLICATION_IDENTITY | **Pass** |
| PERMISSION_FLOW | **Pass with findings** F1 to F4, and D1's silent connect failure |
| ARM64_NATIVE_RUNTIME | **Pass** on a 4 KiB-page kernel |
| KATANA_READ | **Pass** |
| KATANA_WRITE | **Pass** for master volume |
| COMPONENT_HARDENING | **Pass** |
| BOOT_DELIVERY | **Pass** |
| PLAY_PROTECT_INSTALLATION | **Fail** on the user route |
| BASELINE_REGRESSION | **Pass** |

### Play Protect installation

User route: the candidate APK was opened from the device file manager and
handed to the system package installer
(`com.google.android.packageinstaller`). Play Protect blocked it with "App
blocked to protect your device", naming SB Connect Compat and the reason
"This app can request access to sensitive data. This can increase the risk of
identity theft or financial fraud." The only choice was "Got it"; there was
no install-anyway option. The installer then showed "App not installed".
After dismissal B was absent and A was unchanged. Logcat names no rule.

The block is recorded as observed. The rule that produced it is not
identified. A, with the same debug certificate and the same declared
permissions under the stock package name, was installed through the same
installer on 2026-10-15, on an earlier Android release.

ADB route: `adb install` succeeds (installer `null`, initiating package
`com.android.shell`, APK signature scheme v3, `primaryCpuAbi=arm64-v8a`). An
ADB install does not show that the user route passes Play Protect, so every
result below is for an ADB-installed B.

### Coexistence and identity

- After the install, `pm list packages` lists `com.creative.apps.sbconnect`
  and `io.github.asce1062.sbconnect.compat`.
- Both packages resolve a launcher activity (`cmd package query-activities`):
  A's `MainActivity` is labeled by its `launcher_name` resource, and B's by the
  literal `SB Connect Compat`. Play Protect, the package installer and the
  permission controller show B as SB Connect Compat.
- B installs while A holds its own measurement provider authority, with no
  `INSTALL_FAILED_CONFLICTING_PROVIDER`.
- A's versionCode, versionName, first install time and last update time
  (2026-10-15 19:32:16) are unchanged after B's install and after the whole run.
- A keeps its own presets (Cinema, Chillout., Night in addition to the built-in
  ones) and Recent Music. B starts with the built-in presets only (Neutral,
  Gaming, Concert). Data is per package; the Bluetooth pairing is shared.

### Permission flow

On a fresh install every runtime permission of B starts ungranted, and no
`pm grant` was used. The first launch requests, in order:

1. Location: allowed "While using the app".
2. Microphone: denied.
3. Nearby devices (`BLUETOOTH_CONNECT`, `BLUETOOTH_SCAN`): allowed.
4. Notifications: allowed.
5. Microphone again, after the activity recreates itself: denied.

Bluetooth discovery and the SPP connection start only after Nearby devices is
granted.

- **F1.** Before the grant, `SbxDeviceManager` calls
  `BluetoothA2dp.getConnectedDevices` through `BluetoothUtils`, which throws
  `SecurityException: Need android.permission.BLUETOOTH_CONNECT`. The app
  catches it and the call is not fatal. This path is not covered by the
  `BtPermCompat` request.
- **F2.** The microphone request repeats after the activity's `recreate()`,
  inside the same first-launch sequence. The stock batch runs on every
  activity creation ([PERMISSIONS.md](../../technical/PERMISSIONS.md)) and asks
  again for any permission in it that is still denied.
- **F3.** The stock permission batch requests location. The package
  declares `BLUETOOTH_SCAN` without `neverForLocation`, so the platform can
  require location for discovery results
  ([ANDROID_COMPATIBILITY.md](../../technical/ANDROID_COMPATIBILITY.md)). In
  the operator's use, the connection fails without Nearby devices. With
  location declined and Nearby devices allowed, the paired Katana connects
  (D2 below). Discovery of an unpaired device with location declined was not
  run.
- **F4.** Denying Nearby devices in system settings shows "This app was
  designed for an older version of Android. Denying permission may cause it to
  no longer function as intended." This happens although the package targets
  API 34, caps `BLUETOOTH` and `BLUETOOTH_ADMIN` at `maxSdkVersion 30`, and the
  two Nearby permissions carry only `USER_SET` and `USER_SENSITIVE_*` flags.
  The denial was cancelled; the deny paths were run from the in-app dialogs
  instead (D1, D2).

No fatal exception occurs in the permission flow.

#### Declined paths

Each case was set up with `pm revoke` and `pm clear-permission-flags` so the
dialog appears again on launch, with A force-stopped so it did not hold the
speaker. The decline itself was the operator's or a tap on the system dialog.

- **D1, Nearby devices declined.** Launch shows the Nearby devices dialog;
  "Don't allow" sets it `USER_FIXED`. B stays running and shows the offline
  Now Playing screen with "Touch to connect to an Audio Device". The Connect
  screen lists the Katana as Disconnected. Tapping it gives no visible
  response, no message and no new request. The log shows a caught
  `SecurityException: Need android.permission.BLUETOOTH_CONNECT` from
  `ConnectionFragment.onItemClick` through `SbxConnectionManager` and
  `BluetoothUtils` to `BluetoothA2dp.getConnectedDevices`, a second path that
  `BtPermCompat` does not guard. No fatal exception or ANR.
- **D2, location declined, Nearby devices allowed.** Launch shows the location
  dialog; "Don't allow" sets it `USER_FIXED`, and no further dialog follows.
  B does not connect on launch. From the Connect screen, tapping the Katana
  starts discovery, then SPP connects, CtProtocol starts (`maxpayloadSize 62`,
  `GET_FEATURE_CONTROL_SUPPORT`) and `MainService` is promoted to the
  foreground. The screen shows the Katana as Connected. Location is not
  required to connect to an already-paired speaker.

In D2 the stock code also calls `BluetoothHeadset.connect`, which throws a
caught `SecurityException` for `MODIFY_PHONE_STATE`. A's baseline connection
log contains the same exception, so it is stock behavior. No write was made in
D1 or D2. Afterwards B's location grant was restored and A was relaunched; A
reconnected with its own presets.

### arm64 native runtime

- B runs as a child of `zygote64`, with `primaryCpuAbi=arm64-v8a` and no secondary ABI.
- `nativeloader` loads
  `.../io.github.asce1062.sbconnect.compat-.../lib/arm64/libsbxapplogic_ctprotocol_jni.so`.
- The CtProtocol session starts after SPP connects: `maxpayloadSize 62`,
  then `GET_FEATURE_CONTROL_SUPPORT`.
- `libserialport_jni.so` is not loaded in any B session; the app does not need
  it for the Bluetooth path.

The device kernel uses 4 KiB pages. This run does not show that the libraries
execute on a 16 KiB-page runtime. Their 16 KiB alignment is a build property
(table above).

### Katana read and write

- **Reads.** B's Dashboard shows the device name Sound BlasterX Katana, the
  presets and the sources Bluetooth, Aux In (unavailable) and Optical. Now
  Playing shows source Optical 1 and the master volume slider.
- **Write and readback** (A/B/A). Slider position is measured as the knob's
  x pixel at a fixed row of 1440-wide screenshots.

| Step | App | Slider | Action |
|---|---|---|---|
| 1 | B | 447 | one step down |
| 2 | B | 428 | the operator heard the volume drop on the speaker; B force-stopped |
| 3 | A | 428 | A reads the value B wrote, from the speaker |
| 4 | A | 447 | one step up: volume restored to its value before B |

The readback in step 3 comes from the speaker through A's own session. It is
not a UI value carried over by B. The run wrote master volume only.

### Component hardening

| Probe from the shell (uid 2000) | Result |
|---|---|
| `am broadcast -f 32 -n <B>/com.creative.apps.sbconnect.MainReceiver` | Enqueued, result 0, B's process not started: not delivered |
| `am broadcast -f 32 -n <B>/android.support.v4.media.session.MediaButtonReceiver` | Enqueued, result 0, B's process not started: not delivered |
| `am start-service` and `am start-foreground-service` of `<B>/com.creative.apps.sbconnect.MainService` | `Permission Denial: Accessing service ... that is not exported` |

The legitimate path works. Right after SPP connects, B starts its own
`MainService` as a foreground service from the top state:
`Background started FGS: Allowed [callingPackage: io.github.asce1062.sbconnect.compat; uidState: TOP ... code:PROC_STATE_TOP]`,
notification channel `sbconnect_fg`. No ANR, fatal exception or Permission
Denial for B's own operations occurred.

### Boot delivery

Before the reboot both packages were in the not-stopped state. B was started
once from a launcher intent after the hardening probes had force-stopped it.
After the reboot the operator unlocked the device and turned wireless
debugging back on. Neither app was opened.

- `BOOT_COMPLETED` (required permission `RECEIVE_BOOT_COMPLETED`) was
  delivered through the manifest to both receivers. A's
  `MainReceiver` came first, then B's, a third of a second later. Both receivers
  list `exported=false`.
- Each process was started for that broadcast: `Start proc ... for broadcast
  {<package>/com.creative.apps.sbconnect.MainReceiver}`.
- In each process the arm64 CtProtocol library loads from its own `lib/arm64`.
- Each `MainService` is started by its receiver and runs as a background
  service. The activity manager releases both delayed starts about 15 seconds
  later ("Waited long enough for: ServiceRecord{... MainService ...}"). The
  foreground promotion happens on SPP connect, and neither app connected during
  the capture.
- No ANR, fatal exception, SecurityException or Permission Denial occurred in
  either process. Both log the same measurement-library initialization errors
  (no `google_app_id`).

### Baseline regression

Before B was installed, A connected over SPP and read its presets and
sources, and its volume write was confirmed with a readback. After B's
session A launched, reconnected without help, read the value B had written,
wrote the restore, and kept its data and metadata. After the reboot, A's boot
receiver and service ran alongside B's.

## Evidence

Raw screenshots, UI dumps and logcat captures were kept off the repository.
They contain device identifiers, network addresses and unrelated personal
data. This record quotes them with identifiers removed. The screenshot of the
Play Protect block includes an unrelated file list and is not published.

## Not covered

- Installing the release-signed build and a user-route install with a project
  certificate. Every install here used the debug certificate.
- Discovery of an unpaired device with location declined, and declining a
  permission from system settings.
- Writes other than master volume: preset selection, source selection and EQ.
- A 16 KiB-page device.
