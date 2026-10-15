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

| Component | Type | Current | Needs export? | Verdict |
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

## Proposed change (not yet applied)

Flip three `exported="true"` to `"false"` in the `patch.cmake` manifest block
(lines that set `MainReceiver`, `MainService`, `MediaButtonReceiver`), leaving
`MainActivity` and `LocalMusicRemoteControllerService` exported. This is a
hardening step, not a launch requirement, so it is gated on an on-device
re-verification rather than bundled blind:

Verification protocol (Galaxy S24 Ultra, Android 16, arm64):
1. Build `apk-arm64`, install, grant the runtime permissions.
2. Connect to the Katana over Bluetooth SPP; confirm the Dashboard reaches the
   connected state and the in-use flag clears (exercises MainReceiver's ACL /
   profile broadcasts).
3. Confirm the foreground-service notification posts and survives (MainService).
4. Reboot with the app installed; confirm `BOOT_COMPLETED` auto-start still
   reaches MainReceiver (exercises the protected-broadcast-with-`exported=false`
   path end to end).

If every step passes, the tightening is safe; if any regresses, the specific
component reverts to `exported="true"` with the reason recorded here. The change
touches only manifest export flags, no encoder, decoder, or native code.

## Cross-references

- Export edits and rationale: `patches/modernize/patch.cmake` (manifest block).
- Permissions that gate the exported listener service: `PERMISSION_AUDIT.md`
  (`MEDIA_CONTENT_CONTROL`, `BIND_NOTIFICATION_LISTENER_SERVICE`).
