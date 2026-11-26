# Release

How a signed `compat` release is produced, rehearsed, qualified and checked.
Signing itself, its credentials and its checks are in
[SIGNING.md](SIGNING.md); the workflows are in [CI.md](CI.md); the decision
is [0011](../decisions/0011-release-signing-modes.md).

Whether a binary containing the stock app's code may be published is an open
question for the project owner ([0005](../decisions/0005-source-and-binary-distribution.md)).
This document describes how a release APK is made and qualified, not whether
or where it may be distributed. The workflows prepare draft releases only;
publishing one, and the repository's visibility, are the operator's
decisions.

## State

| Item | State |
|---|---|
| test-release and release targets | implemented; one signing driver for local and CI signing |
| test-release rehearsal (sign, verify, update, foreign-signer refusal) | done on the API 30 emulator; [record](../research/android/RELEASE_SIGNING.md) |
| production key | created 2026-11-26 on the operator's machine, outside every repository; two offline copies, each byte-identical to the original (SHA-256) |
| published certificate fingerprint | `3c726afa...` in [`signing/release-certificate.sha256`](../../signing/release-certificate.sha256) ([SIGNING.md](SIGNING.md#the-production-key)) |
| production-signed build | `sbconnect-compat-v0.1.0.apk`, package `com.creative.apps.sbconnect.compat`, SHA-256 `63dcd8892ef612191dfd253f5bfd5c45fc0d8a85c42c261b40f152bf922a1543`, from `596f3bb`; all four release gates passed ([record](../research/android/PRODUCTION_CANDIDATE.md)). It supersedes `81b32401...` from `25b7f61`, built under the first application ID and never installed |
| source CI, APK build, release and verification workflows | qualified on GitHub-hosted runners: source CI, the four variants, a test-release rehearsal to a draft, release mode failing closed without production secrets, and mode `local` verifying `63dcd889...` against the runner's own build ([record](../research/android/CI_QUALIFICATION.md)). The APK workflows now run from the private build-input repository ([CI.md](CI.md#two-places)). Pushes start no runs; every run is dispatched ([CI.md](CI.md#event-delivery)) |
| user install route (file manager, system installer, Play Protect on) | passed for the production candidate `63dcd889...` on a Pixel 8 (API 37): "App scan recommended", scan, "This app looks safe", installed through the system installer ([record](../research/android/PRODUCTION_CANDIDATE.md)). The result covers that APK and certificate only |

A release is not published until the
release gates below pass with the release-signed APK itself.

## Release gates

Each gate runs against the exact APK that would be published, identified by
its SHA-256 and certificate. A result for another build, another certificate
or a debug-signed APK does not count.

| Gate | Passes when |
|---|---|
| Signing | the APK verifies with the committed production fingerprint ([SIGNING.md](SIGNING.md#pipeline) checks 1 to 6 and `verify_release.py`) |
| User install route | on the Pixel 8, the APK opened from the file manager installs with Play Protect on; the scan result is recorded. An `adb install` does not qualify it. If Play Protect blocks it, the appeal draft is [PLAY_PROTECT_REVIEW.md](PLAY_PROTECT_REVIEW.md) |
| Hardware | on a device with the speaker: fresh-install permission flow, discovery and paired connection, native library load, live state and presets, reversible writes, the foreground service, revocation and recovery ([TESTING.md](TESTING.md)) |
| Update | a later labelled build signed with the same key installs over it and keeps the app's data ([Update qualification](#update-qualification)) |

## Once: create the release key

An operator ceremony, on a machine the operator trusts, outside every
repository. Nobody else needs the passwords, and they never go into a chat,
an issue, a commit, a file in a repository or a command line.

1. Choose the alias and validity. Android checks an update only against the
   signer of the installed app, so this key signs every release for the life
   of the application ID `com.creative.apps.sbconnect.compat`. Use the alias
   `sbconnect-compat` and a validity of 10000 days (27 years); the Play
   requirement for app keys is past 2033, and 25 years is the usual floor.
2. Choose the keystore location: a directory outside every repository and
   outside any synced folder, for example `%USERPROFILE%\keys\` on Windows.
3. Generate a strong password in a password manager and keep it there. With
   PKCS12, one password protects both the keystore and the key.
4. Generate the key. keytool reads the password from an environment variable,
   so it is on no command line and in no history.

   PowerShell:

   ```powershell
   $env:SBC_RELEASE_KEYSTORE_PASS = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR((Read-Host -AsSecureString 'keystore password')))
   keytool -genkeypair -keystore "$env:USERPROFILE\keys\sbconnect-compat-release.p12" -storetype PKCS12 -alias sbconnect-compat -keyalg RSA -keysize 4096 -validity 10000 -dname "CN=SB Connect Compat" -storepass:env SBC_RELEASE_KEYSTORE_PASS -keypass:env SBC_RELEASE_KEYSTORE_PASS
   ```

   sh:

   ```sh
   read -rs SBC_RELEASE_KEYSTORE_PASS && export SBC_RELEASE_KEYSTORE_PASS
   keytool -genkeypair -keystore ~/keys/sbconnect-compat-release.p12 -storetype PKCS12 \
       -alias sbconnect-compat -keyalg RSA -keysize 4096 -validity 10000 \
       -dname "CN=SB Connect Compat" \
       -storepass:env SBC_RELEASE_KEYSTORE_PASS -keypass:env SBC_RELEASE_KEYSTORE_PASS
   ```

   The DN is public: it is in every release's certificate. Put nothing in it
   you do not want published.
5. Extract the certificate fingerprint and keep it with the password entry:

   ```powershell
   keytool -list -v -keystore "$env:USERPROFILE\keys\sbconnect-compat-release.p12" -storepass:env SBC_RELEASE_KEYSTORE_PASS -alias sbconnect-compat | Select-String 'SHA256:'
   ```

6. Back up the keystore to at least two offline locations kept apart from
   each other (for example two encrypted USB drives in different places).
   The password lives in the password manager, not next to the keystore
   file. A lost key means no further update can install over an existing
   release; a leaked key lets anyone sign an update that installs over it.
7. Verify each backup from the backup copy itself: the file SHA-256 equals
   the original's (`Get-FileHash` or `sha256sum`), and `keytool -list -v` on
   the copy prints the fingerprint from step 5.
8. Commit the fingerprint, lowercase hexadecimal without colons, as the only
   line of `signing/release-certificate.sha256`, and list it in
   [SIGNING.md](SIGNING.md). It is public by design: users check downloads
   against it.
9. Clear the variable: `Remove-Item Env:SBC_RELEASE_KEYSTORE_PASS` or
   `unset SBC_RELEASE_KEYSTORE_PASS`.

The first production build ([Each release](#each-release), local route) is
the end-to-end check of the new key.

## Each release

1. Set the release version: `VERSION` in `project()` in `CMakeLists.txt`
   ([0009](../decisions/0009-version-scheme.md)). The versionCode must be
   higher than every published versionCode; Android refuses a downgrade.
2. Regenerate the changelog for that version and commit both:

   ```sh
   python3 scripts/release/release_notes.py changelog --version <VERSION> -o CHANGELOG.md
   ```

3. Build and sign from a clean checkout of that commit. The production key
   stays on the operator's machine; no workflow holds it, and the release
   workflow refuses mode `release` without a pre-release label.

   ```powershell
   cmake --preset default
   cmake --build build --target apk-compat-unsigned
   $env:SBC_RELEASE_KEYSTORE = "$env:USERPROFILE\keys\sbconnect-compat-release.p12"
   $env:SBC_RELEASE_KEY_ALIAS = 'sbconnect-compat'
   $env:SBC_RELEASE_CERT_SHA256 = (Get-Content signing\release-certificate.sha256)
   $env:SBC_RELEASE_KEYSTORE_PASS = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR((Read-Host -AsSecureString 'keystore password')))
   cmake --build build --target apk-compat-release
   Remove-Item Env:SBC_RELEASE_KEYSTORE_PASS
   ```

4. Check the outputs: `sha256sum -c <apk>.sha256`, and
   `python3 scripts/ci/verify_release.py --apk <apk> --mode release --cert <fingerprint>`.
   `<apk>.json` shows `source_commit` equal to the release commit and
   `source_uncommitted_changes` false.
5. Run the [release gates](#release-gates) on that APK.
6. In the private build-input repository, create a draft release
   `v<VERSION>` holding the APK, its `.sha256` and `.json` unchanged, and
   dispatch the release workflow there with mode `local`, `release` set to
   that name and `ref` set to the commit to verify against (the release
   commit, or a later commit whose build output is unchanged):

   ```sh
   gh release create v<VERSION> --repo <build-input repository> --draft sbconnect-compat-v<VERSION>.apk*
   gh workflow run release.yml --repo <build-input repository> -f ref=<full commit SHA> -f mode=local -f release=v<VERSION>
   ```

   The workflow verifies the APK against its own unsigned build of `ref`
   with no key ([CI.md](CI.md#release)) and adds the notes and the
   inventory to that draft. Any byte change after signing invalidates the
   signature; re-run the target instead of editing an output.
7. Copy the five assets and the notes of that private draft unchanged to a
   draft release `v<VERSION>` of the compat repository, targeting the
   release commit, then download each asset back and compare its SHA-256:

   ```sh
   gh release create v<VERSION> --repo <compat repository> --draft --target <release commit> --title "SB Connect Compat v<VERSION>" --notes-file notes.md <assets>
   ```

8. Publishing the compat draft creates the tag `v<VERSION>` at its target
   commit. That is the operator's decision. Delete the private draft once
   the public one is verified.

## Update qualification

Shows that a later build signed with the production key updates a release
install and keeps its data, without spending a version number:

1. Install the release candidate (versionCode `C`) and use the app so it
   stores state (permissions granted, a paired speaker remembered).
2. Build the same commit with `-Dsbc_prerelease=rehearsal.1` and sign it with
   the production key (`apk-compat-release`). It has
   versionCode `C`, versionName `...-rehearsal.1` and file
   `sbconnect-compat-v<VERSION>-rehearsal.1.apk`.
3. Install it over the candidate (`adb install -r`, or the file manager). It
   installs as an update, the app starts, and the stored state is there.
4. Reinstall the candidate itself over it (same versionCode, same key) to
   return the device to the release build.

The labelled build is never published. Its versionCode equals the release's,
so it consumes no number and the published release installs over it.

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

In CI, the release workflow dispatched with mode `test-release` rehearses
the whole automated path with the disposable key in the `release-rehearsal`
environment of the build-input repository; its draft is named `<tag>-test-release.<run number>` and marked
pre-release.

A rehearsal shows that signing, verification and updates behave on the
device it ran on. It says nothing about the production key, which does not
take part.
