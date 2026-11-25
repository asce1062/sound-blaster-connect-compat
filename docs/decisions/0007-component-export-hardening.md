# 0007. Narrow manifest exports; keep stock exposure for runtime receivers

Status: Accepted

## Context

From targetSdk 31 every manifest component with an intent filter must declare
`android:exported`, and from targetSdk 34 every runtime `registerReceiver`
call for a non-system broadcast must choose exported or not exported. The
stock app relied on the old implicit defaults, under which these components
were exported.

## Decision

- **Manifest components:** each first-party component gets the narrowest
  value that keeps its observed function. `MainReceiver`, `MainService` and
  `MediaButtonReceiver` are not exported: they receive protected system
  broadcasts, system-targeted deliveries or intents from the app itself.
  Components that the system or the launcher must reach from outside stay
  exported.
- **Runtime receivers:** all 96 two-argument `registerReceiver` sites pass
  `RECEIVER_EXPORTED` on API 34 and later, through the `RcvCompat` shim. This
  reproduces the stock app's exposure rather than auditing each site.

## Consequences

- Third-party apps can no longer start `MainService` or send the app's own
  `START_SERVICE` action to `MainReceiver`.
- Runtime receivers remain as exposed as in the stock app. Narrowing them
  needs a per-site audit and a device run for each change.
- `MediaButtonReceiver`'s value rests on static reasoning; it was not
  exercised on a device.

Per-component detail and the device results are in
[PERMISSIONS.md](../technical/PERMISSIONS.md).
