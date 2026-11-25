# PLAY_PROTECT_MATRIX

> **Historical record.** Kept as evidence of how behavior was established; not updated for later changes. Status, corrections and the maintained references: [research index](../README.md).

Phase 5A record of Google Play Protect behavior toward the modernized,
debug-signed arm64 build across install paths and devices. This project does not
disable, bypass, patch, suppress, or otherwise interfere with Play Protect; this
document only observes and predicts its behavior so the bring-up is understood,
not worked around.

## Legend

- **Observed** - seen directly on a device in this project, with the evidence noted.
- **Expected** - predicted from documented Play Protect behavior and this build's
  signer profile; **not** yet observed here. Not to be read as a measured result.

## Signer profile that Play Protect reacts to

The build is signed with the standard Android debug key
(`CN=Android Debug`, SHA-256 `665d62c0...`, see `APP_IDENTITY.md`) and carries no
Play Store installer record. To Play Protect this is an **unknown-developer**
app: no known-good signer, no store provenance. That profile, not the app's
content, is what draws scrutiny.

## Device / verifier state (observed)

Galaxy S24 Ultra, Android 16 (SDK 36), arm64-v8a. Read-only, nothing changed:

| Setting | Value | Meaning |
|---|---|---|
| `package_verifier_user_consent` | `1` | Verify-apps consent granted. |
| `package_verifier_enable` | `null` | Not explicitly overridden; platform default applies. |
| `upload_apk_enable` | `1` | "Improve harmful app detection" on: unknown APKs may be uploaded to Google for analysis. |
| `com.google.android.gms`, `com.android.vending` | present | GMS and Play Store present, so Play Protect is active. |

## Install-path matrix

| Install path | Installer attribution | Play Protect at install | Result |
|---|---|---|---|
| `adb install -r` (used for all bring-up testing) | `installerPackageName=null` | **Observed:** no install-time Play Protect prompt or block; the app installed and ran. `adb` installs are developer installs and do not raise the end-user consent/scan dialog. | App runs. No warning surfaced. |
| User sideload (file manager / browser -> package installer) | set to the installer app | **Expected:** "Allow from this source" step, then a Play Protect scan; for an unknown-developer debug-signed app, commonly an "app not recognized" / "scan app" notice with an Install-anyway choice. A warning, not necessarily a removal. | Installs if the user proceeds; Play Protect stays on. |
| Play Store | `com.android.vending` | N/A - not distributed through the Store. | - |

## Runtime / post-install (observed)

- No automatic removal of the installed app was observed. The app was present
  and running across multiple reinstall/test cycles.
- The one uninstall that happened was **user-initiated** (the operator removed it
  manually), not a Play Protect action. No Play-Protect-driven uninstall or
  disable event has been seen on this device.
- With "send apps to Google" on (`upload_apk_enable=1`), a novel debug-signed
  build may be sampled for analysis; this is background behavior and did not
  block or alter the app here.

## Why the friction exists, and the legitimate ways to reduce it

The scrutiny follows from the signer profile in `APP_IDENTITY.md`, a debug key
with no provenance, not from anything in the app. The supported ways to reduce
it, none of which touch Play Protect:

1. **Sign with a stable project keystore** instead of the per-build debug key, so
   the signer is consistent and can be recognized across installs
   (`APP_IDENTITY.md`, "If a stable identity is wanted later").
2. **Distribute through a channel that carries provenance** (the Play Store or
   another store that records an installer) if this ever moves past a personal
   sideload.
3. On a user sideload, the user may choose to keep the app past a Play Protect
   warning. That is the user's decision in the system UI; the warning is expected
   and Play Protect remains enabled.

Disabling Play Protect, excluding the app from scanning, or spoofing an installer
are explicitly out of scope and are not done.

## Open data point

A real user-driven sideload (not `adb`) with Play Protect on has not been run on
this device, so the "Expected" row for that path is unverified here. If that
observation is wanted, sideloading the signed APK through a file manager on the
S24 and recording the exact Play Protect prompt would promote that row from
Expected to Observed. Not required for the bring-up grade.

## Cross-references

- Signer identity driving this behavior: `APP_IDENTITY.md`.
- Permissions that depend on signer level: `PERMISSION_AUDIT.md`.
