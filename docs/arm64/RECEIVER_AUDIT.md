# RECEIVER_AUDIT

Phase 5A audit of exported components in the modernized arm64 build, with the
focus on whether each first-party receiver and service needs
`android:exported="true"` or can be `NOT_EXPORTED` (`exported="false"`). Source
of truth: `build/arm64/tree/AndroidManifest.xml`; export edits in
`patches/modernize/patch.cmake`.

## Why every component now carries an explicit `exported`

At targetSdk 31+ a component with an `<intent-filter>` must declare
`android:exported` explicitly or the package fails to install. Before API 31 a
filtered component was *implicitly* exported. The modernize patch set an explicit
value on the five first-party filtered components, choosing `true` for four of
them to preserve the stock implicit-exported behavior for the launch milestone,
and `false` for the one library receiver fed only in-package. This audit revisits
those four `true` values against what each component actually needs.

Key distinction used throughout: a **protected system broadcast** (sent by the
platform) and a **framework-targeted delivery** (media button, listener bind)
reach a manifest component regardless of `exported`, because the sender is the
system, not another app. `exported="true"` only matters when a *different,
third-party app* must reach the component. So "driven by the system" is **not**
a reason to stay exported.

## First-party components

Export values below are the pre-hardening baseline this audit started from; the
applied result is in the acceptance matrix near the end.

| Component | Type | Pre-hardening | Needs export? | Verdict |
|---|---|---|---|---|
| `MainActivity` | activity | `true` | yes | Correct. Launcher entry; must be exported. |
| `MainReceiver` | receiver | `true` | no | Tighten to `false`. See finding R1. |
| `MainService` | service | `true` | no | Tighten to `false`. See finding R2. |
| `LocalMusicRemoteControllerService` | service | `true` (+ `BIND_NOTIFICATION_LISTENER_SERVICE`) | yes | Correct. The system binds it from outside the app; must be exported and is gated by the signature-level bind permission. |
| `MediaButtonReceiver` (androidx) | receiver | `true` | no | Tighten to `false`. See finding R3. |

Library components from Google Play Services are Google's own declarations and
are left unchanged: `AppMeasurementReceiver`/`AppMeasurementService`/
`AppMeasurementContentProvider` and `SignInHubActivity` are `exported="false"`;
`PreviewActivity` and `RevocationBoundService` are `exported="true"` by Google's
design (the latter gated by a Google permission). `AdActivity` and
`InAppPurchaseActivity` have no filter and default to not-exported. None is a
first-party surface and none is changed here.

## Findings

### R1 - MainReceiver should be NOT_EXPORTED

`MainReceiver` registers for 14 **protected system broadcasts** (Bluetooth
adapter `STATE_CHANGED`; device `BOND_STATE_CHANGED`, `NAME_CHANGED`,
`ALIAS_CHANGED`, `ACL_CONNECTED`, `ACL_DISCONNECT_REQUESTED`,
`ACL_DISCONNECTED`; A2DP and headset `CONNECTION_STATE_CHANGED`;
`CONNECTIVITY_CHANGE`; `BOOT_COMPLETED`; `SCREEN_ON`; `USER_PRESENT`;
`LOCALE_CHANGED`) plus one app-private action,
`com.creative.apps.sbconnect.action.START_SERVICE`.

- All 14 system actions are delivered by the platform and reach a manifest
  receiver whether or not it is exported.
- `START_SERVICE` is app-namespaced and sent in-package (the manifest's
  `MainService` filters the same action); same-UID delivery works with
  `exported="false"`.

So `exported="false"` preserves every required delivery and additionally closes
the one real exposure: today any installed app can broadcast
`com.creative.apps.sbconnect.action.START_SERVICE` to this receiver.

**Risk:** low. Residual risk only if an undocumented external integration
broadcasts `START_SERVICE` to the app, which is not a known path.
**Recommendation:** set `exported="false"`; verify the Katana still connects
(the ACL and profile `CONNECTION_STATE_CHANGED` broadcasts drive the in-use /
connection state that the earlier launch work depended on).

### R2 - MainService should be NOT_EXPORTED

`MainService` is a `mediaPlayback` foreground service filtering two app-private
actions, `...action.START_SERVICE` and `...action.PLAY_PAUSE`. Both are started
in-package (directly, or from a media-notification action whose PendingIntent
runs under the app's own identity). A same-UID start works with
`exported="false"`.

**Risk:** low-to-medium, bounded by confirming no external caller starts the
service by action. **Recommendation:** set `exported="false"`; verify the
foreground-service notification still appears and playback controls still
function after connect.

### R3 - MediaButtonReceiver should be NOT_EXPORTED

The androidx `MediaButtonReceiver` filters `android.intent.action.MEDIA_BUTTON`.
Media-button events are routed by the `MediaSession` framework to the registered
component as a targeted system delivery, which does not depend on the receiver
being exported to a third party. On modern Android this receiver is commonly
declared not-exported; the on-device step below confirms it for this build.

**Risk:** low; the media path here is largely inert (the RemoteController
feature behind it is dead on modern Android). **Recommendation:** set
`exported="false"`.

## Change applied and verified

The three `exported="true"` values were flipped to `"false"` in the
`patch.cmake` manifest block (`MainReceiver`, `MainService`, `MediaButtonReceiver`),
leaving `MainActivity` and `LocalMusicRemoteControllerService` exported. Only
manifest export flags changed; the CtProtocol encoder/decoder, the JNI, the
native `.so` libraries, the permission flow, the package identity and signing,
and the 96-site dynamic `registerReceiver` compatibility shim are untouched. The
arm64 APK was the only rebuild target.

### Acceptance matrix

Device: Galaxy S24 Ultra (SM-S928U1), Android 16, arm64. Fresh clean install,
Play Protect left enabled.

| Component | Before | After | External caller needed? | Runtime result |
|---|---|---|---|---|
| `MainReceiver` | `exported=true` | `exported=false` | No | **PASS.** `BOOT_COMPLETED` delivered to `MainReceiver` after reboot with the receiver `exported=false` (broadcast record state `DELIVERED`, `requiredPermissions=[RECEIVE_BOOT_COMPLETED]`, terminal +141ms). AMS started the process `for broadcast {.../MainReceiver}` with no manual launch. Implicit `CONNECTIVITY_CHANGE` to the same receiver is skipped by targetSdk policy (`[0,23]` only), independent of the export flag. |
| `MainService` | `exported=true` | `exported=false` | No | **PASS.** Started as a foreground service from the same-app caller (`ActivityManager: Background started FGS: Allowed ... cmp=.../.MainService`), `isForeground=true`, type `mediaPlayback`, channel `sbconnect_fg`. Also auto-created from the boot receiver (`createdFromFg=false`) while `MainActivity` never resumed. |
| `MediaButtonReceiver` | `exported=true` | `exported=false` | No | **STATICALLY_JUSTIFIED / RUNTIME_UNTESTED.** `MEDIA_BUTTON` is routed by the `MediaSession` framework to the session owner's registered component; the device reported 0 active media sessions, so no caller path exists to exercise or to break. `exported="false"` matches androidx's own modern default for this receiver. |

### Eight-point connection regression (all PASS)

1. App starts (process alive, no `FATAL`/ANR). 2. Nearby Devices flow works
(`BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`, plus location and notifications granted).
3. Katana appears (Dashboard header "Sound BlasterX Katana"). 4. SPP control
connection opens (MainService foreground + live device data). 5. Connected device
UI renders. 6. Presets and per-source availability read from the speaker. 7. No
new `SecurityException` attributable to the change (the only `System.err`
exceptions are the stock `SbxDeviceManager` A2DP/Headset `BLUETOOTH_CONNECT`
profile probes, independent of export flags). 8. Zero `Permission Denial` against
the three components.

### Verdict: HARDENING_PASS

The connection path and the boot auto-start both remain intact with all three
components `NOT_EXPORTED`, so no component reverts. The one component that could
not be exercised at runtime (`MediaButtonReceiver`) is held `exported="false"` on
the static justification above; if a local-playback MediaSession path is ever
added and a media-button regression appears, re-grade it here.

## Cross-references

- Export edits and rationale: `patches/modernize/patch.cmake` (manifest block).
- Permissions that gate the exported listener service: `PERMISSION_AUDIT.md`
  (`MEDIA_CONTENT_CONTROL`, `BIND_NOTIFICATION_LISTENER_SERVICE`).
