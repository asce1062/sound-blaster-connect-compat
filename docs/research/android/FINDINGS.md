# SBConnect bring-up — findings

Compatibility analysis of the stock `SBConnect_v1.04.02.apk` and what making
it run on current Android requires. This is the reference the pipeline and
both tracks build against.

## The app

| | |
|---|---|
| Package | `com.creative.apps.sbconnect` |
| Version | 1.04.02 (versionCode 10402) |
| minSdk | 14 (Android 4.0) |
| targetSdk | **26** (Android 8.0) |
| Last updated | Jan 2019 (Play listing); build constants say 2016 |
| Transport | **Bluetooth** (`BLUETOOTH`, `BLUETOOTH_ADMIN` + location). No USB `device_filter`. |
| dex | 2 (`classes.dex`, `classes2.dex`) |

## Why Play says "not compatible" — two separate problems

The single "not available for your devices" label hides two unrelated causes.

### 1. Play Store listing filter (soft, bypassable)

Play refuses to *offer* the app because of the low targetSdk, the missing
ABIs, and implied hardware features. **Sideloading a re-signed APK bypasses
this entirely** on any device that can actually run the app. This is what the
`resign` pipeline variant delivers.

### 2. 64-bit-only devices cannot load the native libs (hard, not bypassable)

The APK ships native code for **32-bit ABIs only**:

```
lib/armeabi/       lib/armeabi-v7a/       lib/x86/       lib/utility/
```

No `arm64-v8a`, no `x86_64`. Modern flagships (Pixel 7/8 on Tensor G2/G3, and
other ARMv9 parts) **dropped the 32-bit execution state**: they physically
cannot load a 32-bit `.so`. An app with only 32-bit native libraries will not
run on them, and no repackaging changes that. Fixing it needs `arm64-v8a`
builds of the two libraries, which requires reverse engineering them (no
source shipped). That is the `arm64` track.

Phones that still carry 32-bit support (many Snapdragon/MediaTek devices on
Android 13/14) can run the re-signed app today.

## Native libraries

Two `.so`, both stripped 32-bit ARM ELF:

| Library | Role |
|---|---|
| `libsbxapplogic_ctprotocol_jni.so` | **CtProtocol** JNI — the Sound Blaster command protocol. The own-app effort needs exactly this. |
| `libserialport_jni.so` | Serial-port JNI (device transport helper). |

Sizes (armeabi-v7a): ctprotocol 67 KB, serialport 14 KB.

## Component inventory (for the modernize track)

App components (non-GMS):

| Component | Type | Notes |
|---|---|---|
| `MainActivity` | activity | launcher, `singleTask` |
| `MainReceiver` | receiver | |
| `MainService` | service | `exported="true"` — must be reviewed at targetSdk 31+ |
| `LocalMusicRemoteControllerService` | service | `BIND_NOTIFICATION_LISTENER_SERVICE` |

The rest are Google Play services / ads / measurement components.

Only 6 `android:exported` attributes are present across the whole manifest.
At **targetSdk ≥ 31** every component with an `<intent-filter>` must declare
`exported` explicitly or the package will not install.

## Target-SDK bump requirements

Raising `targetSdkVersion` from 26 opts into stricter runtime behavior:

- **≤ 30 (Android 11):** installable with no manifest/smali changes. The
  `modernize` starter stops here.
- **≥ 31 (Android 12):** explicit `android:exported` on filtered components;
  `PendingIntent` needs `FLAG_IMMUTABLE`/`FLAG_MUTABLE`; legacy Bluetooth
  permissions stop granting scan/connect — needs runtime `BLUETOOTH_SCAN` /
  `BLUETOOTH_CONNECT`.
- **≥ 33 (Android 13):** `POST_NOTIFICATIONS` runtime permission for the
  service notification.
- **≥ 34 (Android 14):** `foregroundServiceType` + matching
  `FOREGROUND_SERVICE_*` permission for any foreground service.

## Signing

Rebuilt APKs are signed with uber-apk-signer's debug key (sideload only).
A release identity is a later decision; nothing here needs the original
Creative key, which is not available.

## Tracks

| Track | Variant | Runs on | Owner |
|---|---|---|---|
| Re-sign | `resign` | 32-bit-capable Android 13/14 phones (sideload) | 32-bit pipeline session |
| Modernize | `modernize` | same, higher targetSdk | 32-bit pipeline session |
| Native 64-bit | `arm64` | 64-bit-only devices (Pixel 7/8) — once libs exist | this session + own-app work |

## Modernize status

`patches/modernize/` is implemented and raises `targetSdkVersion` to **34**.
Both deliverables build and sign clean (debug key, v1+v2+v3); the stock ABIs
(`armeabi armeabi-v7a utility x86`) are unchanged in both, so each still runs
only on 32-bit-capable devices.

Applied for the 31/33/34 gates: explicit `android:exported` on the 5 filtered
components that lacked it; `PendingIntent` `FLAG_IMMUTABLE` on all 23
construction sites (app + bundled support/androidx/GMS); `BLUETOOTH_SCAN` /
`BLUETOOTH_CONNECT` added with legacy `BLUETOOTH` / `BLUETOOTH_ADMIN` capped at
`maxSdkVersion 30`; `POST_NOTIFICATIONS`; `FOREGROUND_SERVICE` +
`FOREGROUND_SERVICE_MEDIA_PLAYBACK` with `MainService foregroundServiceType=
mediaPlayback` (no dangerous-permission prerequisite, so the FGS starts before
the BT runtime grants).

Verified structurally only — no 32-bit Android 13/14 device was attached for
this work, so install + launch were not confirmed on hardware. Still device-
gated: the runtime `requestPermissions()` UI for `BLUETOOTH_SCAN/CONNECT` and
`POST_NOTIFICATIONS` is not wired in (the app targets 26 and never requested
them), so on Android 12+ those must be granted in Settings until that smali is
added. `patches/modernize/README.md` has the full change list and rationale
(including why `usesPermissionFlags="neverForLocation"` is omitted).
