# RELEASE_SIGNING

> **Historical record.** Kept as evidence of how behavior was established; not updated for later changes. Status, corrections and the maintained references: [research index](../README.md).

Verification of the `test-release` and `release` signing modes of `compat`
([SIGNING.md](../../development/SIGNING.md),
[0011](../../decisions/0011-release-signing-modes.md)) with disposable keys,
and an update rehearsal on the API 30 emulator. Run on 2026-11-25 at the
commit that introduced the modes. No production key exists. Nothing here
shows that production signing is ready.

## Disposable keys

PKCS#12 keystores (RSA 3072, 30-day validity, random 24-character passwords)
were generated with `keytool` in a scratch directory
outside the source tree and the build directory. They were deleted after the
run.

| Key | Certificate DN | Certificate SHA-256 |
|---|---|---|
| key-a | `CN=SB Connect Compat rehearsal key-a` | `c84241820207df8d18dab08e9d18f79c1bd14a8a05d2d513196ee0bac10781ed` |
| key-b | `CN=SB Connect Compat rehearsal key-b` | `a70cd4e6ffb63fb7acf60e1758a63f646a9fa5a21eb07d9c66c5dd7bb59ace1a` |
| debug DN | `C=US, O=Android, CN=Android Debug` (a new key with the debug DN) | not the stock debug key |

Credentials were passed only as `SBC_TEST_RELEASE_*` or `SBC_RELEASE_*`
environment variables of the `cmake --build` process.

## Signing controls

Target `apk-compat-test-release` unless stated. "Files" lists the output
directory after the run. A failing run must leave neither the APK nor
`<apk>.unverified`.

| Case | Input | Result | Files |
|---|---|---|---|
| P1 | key-a, correct password, alias and expected certificate | Exit 0. apksigner v1, v2 and v3 verified with 1 signer. `zipalign -c -P 16 4` ok. Certificate `c8424182...` matches. Badging: package `io.github.asce1062.sbconnect.compat`, 1000, `1.04.02-compat.0.1.0`. ABIs `arm64-v8a armeabi armeabi-v7a x86`, with the arm64 libraries matching the build. 4309 non-signature entries identical to the unsigned APK. `sha256sum -c` of the `.sha256` file ok. An independent `apksigner verify --print-certs` and `zipalign -c` agree | APK, `.sha256`, `.json` |
| N1 | no `SBC_TEST_RELEASE_*` variables | "required environment variables are not set" naming all four | none |
| N1b | fingerprint variable missing | same message, naming `SBC_TEST_RELEASE_CERT_SHA256` | none |
| N2 | wrong keystore password | apksigner: "keystore password was incorrect" | none |
| N3 | wrong alias | apksigner: `entry "sbc-no-such-alias" does not contain a key` | none |
| N4 | key-a keystore, key-b's certificate expected | verify: "signer certificate SHA-256 c8424182..., expected a70cd4e6..." | none |
| N5 | key-b keystore, key-a's certificate expected | verify: certificate mismatch | none |
| N6 | `apk-compat-release` with only `SBC_TEST_RELEASE_*` set | "required environment variables are not set: SBC_RELEASE_KEYSTORE ..." | none |
| N7 | `apk-compat-release` with the debug-DN key and its own certificate expected | verify: "signed with an Android debug certificate" | none |
| N8 | P1's APK with one byte changed in a stored `resources.arsc`, a deflated arm64 library, or a deflated `AndroidManifest.xml` | apksigner `DOES NOT VERIFY`, `CHUNKED_SHA256 digest mismatch` for the first two; manifest parse failure for the third. The standalone verify fails each and keeps its input | not applicable |
| P2 | P1 again after the failures | Exit 0; outputs current | APK, `.sha256`, `.json` |

No case logged a debug-signing line, and no failure fell back to another mode
or key.

## Credential exposure

After the runs, the four passwords used were searched for in 10 locations: the
build directory, `CMakeCache.txt`, `build.ninja`, every case log, the
generated metadata and the scratch logs. None was found. `CMakeCache.txt`
holds no `SBC_*` entry. Neither `CMakeCache.txt` nor `build.ninja` names the
keystore directory, an alias or a certificate digest. The passwords reach
apksigner as `--ks-pass env:` and `--key-pass env:` references. The command
lines carry the variable names, not their values, and apksigner's stdin is
empty.

## Other variants

A clean build of the `apks` target at the same commit produces every
variant. `resign` reports `PAYLOAD-PRESERVING PASS` (4307 entries identical
to the stock APK), and the arm64 libraries keep their accepted digests
(`libsbxapplogic_ctprotocol_jni.so` `970d1744...`,
`libserialport_jni.so` `ca380c7c...`). Debug signing of `modernize`, `arm64`
and `compat` is unchanged.

## Update rehearsal (emulator)

Three `test-release` builds at rehearsal-only versions, produced by setting
`project(VERSION)` in a scratch worktree, uncommitted. The first
production version (`0.1.0`, versionCode 1000) appears only in the signing
controls above, and no APK at that version was installed on any device or
emulator.

| APK | versionCode / versionName | Signer | SHA-256 |
|---|---|---|---|
| `sbconnect-compat-v0.0.1-test-release.apk` | 1 / `1.04.02-compat.0.0.1` | key-a `c8424182...` | `e8ec643c311b7b7fd47ee9602d5a51c3bf29403a307d93662b181cc890602194` |
| `sbconnect-compat-v0.0.2-test-release.apk` | 2 / `1.04.02-compat.0.0.2` | key-a `c8424182...` | `6b13e4761c863abe88e066fc11423c4238c9b582ebfd60de431aad02fa349e08` |
| `sbconnect-compat-v0.0.3-test-release.apk` | 3 / `1.04.02-compat.0.0.3` | key-b `a70cd4e6...` | `869d3f57e00c7d87c42997f3d13f75829963cf85656bd07a5b3d3f41890e509d` |

Each build passed the pipeline's verify step. On the API 30 x86 emulator
(Pixel 3a image), with any earlier install of the package removed first:

| Step | Action | Result |
|---|---|---|
| R1 | `adb install` v1 | `Success`. versionCode 1, signing scheme v3, uid 10169. The launch starts the process and reaches the app's permission request, with no fatal exception, `UnsatisfiedLinkError` or ANR. The app creates its own `shared_prefs` (`SBConnect.xml`, `SbxAppLogic.xml` and others) and `files/gaClientId`. A marker file `files/s5_marker` is added with the app's owner |
| R2 | `adb install -r` v2, same key | `Success`. versionCode 2, uid 10169, `firstInstallTime` unchanged, `lastUpdateTime` advanced, signature set unchanged. The marker and the app's own files are intact. The launch starts the process with no fatal exception |
| R3 | `adb install -r` v3, key-b | `INSTALL_FAILED_UPDATE_INCOMPATIBLE: Package io.github.asce1062.sbconnect.compat signatures do not match previously installed version`. The installed package stays at versionCode 2 with its data and signature set unchanged |

This shows that on the emulator a `test-release` APK installs, that an
update with a higher versionCode and the same certificate keeps the data and
launches, and that a different certificate is refused as an incompatible
update. It shows nothing about the Play Protect user route, physical devices,
or a production key.
