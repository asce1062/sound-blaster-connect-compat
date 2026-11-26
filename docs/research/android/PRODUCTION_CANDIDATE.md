# PRODUCTION_CANDIDATE

> **Historical record.** Kept as evidence of how behavior was established; not updated for later changes. Status, corrections and the maintained references: [research index](../README.md).

Qualification of the first production-signed `compat` build against the
[release gates](../../development/RELEASE.md#release-gates). Started
2026-11-26.

## Candidate

| Item | Value |
|---|---|
| File | `sbconnect-compat-v0.1.0.apk`, 47521734 bytes |
| SHA-256 | `63dcd8892ef612191dfd253f5bfd5c45fc0d8a85c42c261b40f152bf922a1543` |
| Source | `596f3bb`, no uncommitted changes |
| Package | `com.creative.apps.sbconnect.compat`, versionCode 1000, versionName `1.04.02-compat.0.1.0`, label SB Connect Compat |
| Signer | `CN=SB Connect Compat`, RSA 4096, certificate SHA-256 `3c726afab7e94ca20c5d44f854eb357e684323a0bc4ae5d747d3281439e82b57` (the committed fingerprint) |
| Unsigned input | `ee302140895372b4c1bb56da1fdb9750b8b93adb5c171345551200ae8ea87a6e` |
| arm64 libraries | `970d1744...`, `ca380c7c...` (the accepted digests) |

The operator signed it on their machine through `apk-compat-release`. An
earlier production-signed build, `81b32401...` from `25b7f61`, carried the
first application ID and was never installed.

## Signing gate

The build's own verification passed (apksigner v1, v2, v3 with one signer;
`zipalign -c -P 16 4`; certificate equal to the committed fingerprint;
package and versions; ABIs `arm64-v8a armeabi armeabi-v7a x86` with the
arm64 libraries matching the build; 4309 non-signature entries identical to
the unsigned APK). Separately: `sha256sum -c` of the `.sha256` file,
`verify_release.py --mode release` against `release.env` and tag `v0.1.0`,
an independent `apksigner verify --print-certs`, `zipalign -c`, `aapt2 dump
badging`, and `compare_apks.py --ignore-signatures` against the unsigned
APK (equivalent) all pass.

## User install route (Pixel 8, Android 17, API 37)

No `compat` package was installed beforehand: the debug-signed b4 build had
been removed with `adb uninstall`. The APK was copied to `Download/` with
`adb push`; its on-device SHA-256 matched the candidate. Play Protect was on
and was not changed.

| Step | Observation |
|---|---|
| 1 | The operator opened the APK in the file manager. Play Protect: "App scan recommended", "Play Protect hasn't seen this app before", with **Scan app** and **Don't install app** |
| 2 | The operator chose **Scan app**. Play Protect: "This app looks safe", "You can continue to install it", with **Install** and **Don't install** |
| 3 | The operator chose **Install**. The package installed |

Installed state, read with `pm` and `dumpsys package` before the first
launch:

| Field | Value |
|---|---|
| Package | `com.creative.apps.sbconnect.compat`, versionCode 1000, versionName `1.04.02-compat.0.1.0`, targetSdk 34 |
| `base.apk` SHA-256 | `63dcd889...`, equal to the candidate |
| Signer of the installed APK | `CN=SB Connect Compat`, `3c726afa...` |
| Installer | `installerPackageName` and `initiatingPackageName` `com.google.android.packageinstaller`; `originatingPackageName` the file manager; `packageSource` 3 (downloaded file) |
| ABI | `primaryCpuAbi` `arm64-v8a` |
| Runtime permissions | `POST_NOTIFICATIONS` and `ACCESS_FINE_LOCATION` not granted. `ACCESS_LOCAL_NETWORK` granted by the platform with `REVOKE_WHEN_REQUESTED` |
| Process | not running |

**Verdict: PRODUCTION_PLAY_PROTECT_PASS** for this APK and certificate on
this device. It says nothing about other builds, other signers or other
devices.

Screenshots: `pp-1-scan-recommended.png`, `pp-2-after-scan.png`,
`pp-3-installed.png` in the operator's evidence folder
`production-candidate-v0.1.0-596f3bb-2026-11-26`.

## Remaining gates

Hardware (Katana) and update qualification have not run on this candidate.
