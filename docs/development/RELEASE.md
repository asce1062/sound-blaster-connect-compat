# Release

How a signed `compat` release is produced, rehearsed and checked. Signing
itself, its credentials and its checks are in [SIGNING.md](SIGNING.md); the
decision is [0011](../decisions/0011-release-signing-modes.md).

Whether a binary containing the stock app's code may be published is an open
question for the project owner ([0005](../decisions/0005-source-and-binary-distribution.md)).
This document describes how a release APK is made, not whether or where it
may be distributed.

## State

| Item | State |
|---|---|
| test-release and release targets | implemented |
| test-release rehearsal (sign, verify, update, foreign-signer refusal) | done on the API 30 emulator; [record](../research/android/RELEASE_SIGNING.md) |
| production key | not created |
| published certificate fingerprint | none |
| release CI | interface defined below; no workflow, no remote secrets |
| user install route (file manager, system installer, Play Protect on) | not qualified: blocked for the build with the stock permission set; the current build is untested on that route ([PERMISSIONS.md](../technical/PERMISSIONS.md#play-protect)) |

A release cannot be produced until the production key exists, is backed up
and its fingerprint is published. A release is not published until the user
install route passes with the release-signed APK on at least one current
device with Play Protect on. An `adb install` does not qualify it. If Play
Protect blocks it, the appeal draft is
[PLAY_PROTECT_REVIEW.md](PLAY_PROTECT_REVIEW.md).

## Once: create the release key

An operator step, on a machine the operator trusts, outside any repository.

1. Generate the key. Android verifies an update only against the signer of
   the installed app, so this key signs every future release for the life of
   the application ID; give it a validity of at least 25 years.

   ```sh
   read -rs SBC_RELEASE_KEYSTORE_PASS && export SBC_RELEASE_KEYSTORE_PASS
   keytool -genkeypair -keystore sbconnect-compat-release.p12 -storetype PKCS12 \
       -alias sbconnect-compat -keyalg RSA -keysize 4096 -validity 10000 \
       -dname "CN=SB Connect Compat, O=asce1062" \
       -storepass:env SBC_RELEASE_KEYSTORE_PASS -keypass:env SBC_RELEASE_KEYSTORE_PASS
   ```

2. Record the certificate SHA-256:

   ```sh
   keytool -list -v -keystore sbconnect-compat-release.p12 \
       -storepass:env SBC_RELEASE_KEYSTORE_PASS | grep SHA256:
   ```

3. Back up the keystore and its password to at least two separate offline
   locations, stored apart from each other. A lost key means no further
   update can install over an existing release; a leaked key lets anyone sign
   an update that installs over it.
4. Verify each backup: list it with `keytool -list -v` from the backup copy
   and compare the SHA-256 with step 2.
5. Verify the key end to end: a `apk-compat-release` build from the backup
   copy, then install it on a test device.
6. Publish the certificate SHA-256 in this repository (the release notes and
   [SIGNING.md](SIGNING.md)), so users can check a downloaded APK.

Only after step 6 is the release process below usable.

## Each release

1. Set the release version: `VERSION` in `project()` in `CMakeLists.txt`
   ([0009](../decisions/0009-version-scheme.md)). The versionCode must be
   higher than every versionCode already published; Android refuses a
   downgrade.
2. Commit, and build from a clean checkout of that commit. The release target
   refuses a tree with uncommitted changes to tracked files.
3. Configure and build the unsigned APK, then the release:

   ```sh
   cmake --preset default
   cmake --build build --target apk-compat-unsigned
   # set SBC_RELEASE_* (SIGNING.md)
   cmake --build build --target apk-compat-release
   ```

4. Check the outputs in `build/release/`: `sha256sum -c <apk>.sha256`, and
   that `<apk>.json` shows the expected `version_code`, `version_name`,
   `certificate_sha256` and a `source_commit` equal to the commit being
   released with `source_uncommitted_changes` false.
5. Install it as an update over the previous release on a test device, and
   install it fresh through the user route (open the APK from the file
   manager) on a device with Play Protect on.
6. Tag the commit with the release tag (`v<VERSION>`) and publish the APK,
   its `.sha256` and its `.json`, unchanged. Any byte change after signing
   invalidates the signature; re-run the target instead of editing an
   output.

## Rehearsal

A rehearsal runs the same pipeline with a disposable key and never uses a
real version number.

1. Create two disposable keys, A and B ([SIGNING.md](SIGNING.md#disposable-keys)).
2. In a scratch checkout, set `VERSION` to a rehearsal value (for example
   `0.0.1`), build `apk-compat-test-release` with key A and install it.
3. Use the app so it writes data, then set `VERSION` to a higher rehearsal
   value (`0.0.2`), build with key A again and install it with
   `adb install -r`. The app keeps its data and starts.
4. Build with key B and install it over the same app. Android refuses it
   (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`).
5. Delete both keys and the scratch checkout.

A rehearsal shows that signing, verification and updates behave on the
device it ran on. It says nothing about the production key, which does not
take part.

## CI

### Pull requests

Pull-request CI, when added, builds and tests without any signing
credential and without the stock APK: the portable core, the host tests and
the oracle comparison need neither. It does not run `apk-compat-release` or
`apk-compat-test-release`, and has no access to the release environment
below. No signed APK comes from a pull request.

### Release job

The release job is not implemented. Its interface:

| Item | Contract |
|---|---|
| Trigger | manual dispatch on a release tag only; never on push or pull request |
| Environment | `release`, restricted to the default branch's tags, with a required reviewer |
| Runner | trusted, because it needs the operator's stock APK (`-Dapk_input=`), which the project does not redistribute; the stock input SHA-256 is checked by configure |
| Secrets (environment-scoped) | `SBC_RELEASE_KEYSTORE_B64` (the keystore, base64), `SBC_RELEASE_KEYSTORE_PASS`, `SBC_RELEASE_KEY_PASS` if it differs |
| Variables (not secret) | `SBC_RELEASE_KEY_ALIAS`, `SBC_RELEASE_CERT_SHA256` (public by design) |
| Credentials | passed to the build step as environment variables, never as arguments |
| Keystore file | decoded into the runner's temporary directory, not the workspace, mode `600`, and exported as `SBC_RELEASE_KEYSTORE` |
| Cleanup | a final step that runs on success, failure and cancellation deletes the decoded keystore; the build tree is not cached or uploaded except the three release outputs |
| Outputs | the APK, `.sha256` and `.json` from `build/release/`, as job artifacts, for the operator to publish |

Secrets stay unset until the production key exists. Pull-request workflows
from forks get no access to the environment.
