# Signing

How the build signs APKs, where signing credentials come from, and what each
signing step checks. The release process that uses it is in
[RELEASE.md](RELEASE.md); the decision is
[0011](../decisions/0011-release-signing-modes.md).

## Signing modes

| Mode | Target | Key | Output |
|---|---|---|---|
| debug | `apk-<variant>` (every variant, part of `apks`) | uber-apk-signer debug key | `build/sbc_<variant>-aligned-debugSigned.apk` |
| test-release | `apk-compat-test-release` | a disposable key, `SBC_TEST_RELEASE_*` | `build/test-release/sbconnect-compat-<tag>-test-release.apk` |
| release | `apk-compat-release` | the production key, `SBC_RELEASE_*` | `build/release/sbconnect-compat-<tag>.apk` |

- **debug** is unchanged from the earlier pipeline. The `resign` control is
  still debug-signed and still verified payload-identical to the stock APK.
- **test-release** runs the release pipeline with a throwaway key. It exists
  to rehearse signing, verification and updates; its APKs are never
  published.
- **release** produces the distributable APK. It requires a clean git
  checkout and refuses an Android debug certificate.

Each mode is its own target and reads only the environment variables with its
own prefix. A mode with missing credentials stops; it never signs with
another mode's key, and neither signed target builds the debug-signed APK.
Both start from the unsigned APK (`apk-compat-unsigned`,
`build/sbc_compat.apk`), the same file the debug signature is applied to.

## Credentials

Set these in the environment of the build command, with the prefix
`SBC_TEST_RELEASE_` or `SBC_RELEASE_`:

| Variable | Content | Required |
|---|---|---|
| `<prefix>KEYSTORE` | path to the keystore (PKCS12 or JKS) | yes |
| `<prefix>KEYSTORE_PASS` | keystore password | yes |
| `<prefix>KEY_ALIAS` | key alias in the keystore | yes |
| `<prefix>KEY_PASS` | key password | no; default the keystore password |
| `<prefix>CERT_SHA256` | expected SHA-256 of the signer certificate, hexadecimal; colons and case are ignored | yes |

The variables are read when the target runs, not at configure, so none of
them reaches `CMakeCache.txt` or `build.ninja`. `apksigner` reads the
passwords itself (`--ks-pass env:...`, `--key-pass env:...`), so no
password appears on a command line or in the build log. Its standard input
is empty, so a missing or wrong password fails instead of prompting.

Keep the keystore outside the source tree and outside `build/`. The
repository ignores keystore files (`*.jks`, `*.keystore`, `*.p12`, `*.pfx`)
and credential files (`*.signing.env`, `.env`), but the variables above need
no file in the tree at all.

A local release build:

```sh
export SBC_RELEASE_KEYSTORE=/secure/path/sbconnect-compat-release.p12
export SBC_RELEASE_KEY_ALIAS=sbconnect-compat
export SBC_RELEASE_CERT_SHA256=<certificate SHA-256>
read -rs SBC_RELEASE_KEYSTORE_PASS && export SBC_RELEASE_KEYSTORE_PASS
cmake --build build --target apk-compat-release
unset SBC_RELEASE_KEYSTORE_PASS
```

`read -s` keeps the password out of the shell history. In CI the values come
from environment secrets ([RELEASE.md](RELEASE.md)).

## Pipeline

One driver, [`cmake/sign_release.cmake`](../../cmake/sign_release.cmake),
runs three processes in order; a failing step stops it. The
`apk-compat-<mode>` targets call it with every value given. The release
workflow's signing job, which has no build tree, calls it through
[`scripts/ci/sign_release.sh`](../../scripts/ci/sign_release.sh) with
`-DRELEASE_ENV=<release.env>` from the build that produced the unsigned APK
([CI.md](CI.md#release)). Local and CI signing therefore run the same steps
with the same checks.

| Step | Script | Does |
|---|---|---|
| sign | [`cmake/sign_apk.cmake`](../../cmake/sign_apk.cmake) | removes the previous output, its `.sha256` and `.json`; checks the build-tools revision and the credentials; `zipalign -P 16 -f 4`; `apksigner sign` with schemes v1, v2 and v3 (no v4 `.idsig`) to `<output>.unverified` |
| verify | [`cmake/verify_signed_apk.cmake`](../../cmake/verify_signed_apk.cmake) | the checks below, on `<output>.unverified` |
| publish | [`cmake/release_metadata.cmake`](../../cmake/release_metadata.cmake) | renames `<output>.unverified` to `<output>` without changing a byte; writes `<output>.sha256` and `<output>.json` |

The verify step fails the build unless:

1. `apksigner verify` verifies schemes v1, v2 and v3, with one signer. v1
   covers API 14 to 23, the app's minSdk range below v2.
2. `zipalign -c -P 16 4` passes.
3. The signer certificate SHA-256 equals `<prefix>CERT_SHA256`. In release
   mode the certificate DN must not be an Android debug certificate.
4. `aapt2 dump badging` reports the variant's package and the versionCode and
   versionName from [`cmake/sbc_version.cmake`](../../cmake/sbc_version.cmake).
5. `lib/` holds exactly `arm64-v8a`, `armeabi`, `armeabi-v7a` and `x86`, and
   `lib/arm64-v8a/` holds exactly the two libraries of this build, byte for
   byte.
6. Every entry except `META-INF/MANIFEST.MF` and the `.SF`/`.RSA` signature
   files is SHA-256 identical, uncompressed, to the unsigned APK
   ([`cmake/resign_verify.cmake`](../../cmake/resign_verify.cmake) with
   `REF_NAME=unsigned`). The v2/v3 signing block is not a ZIP entry.

Release mode then refuses to publish from a checkout with uncommitted changes
to tracked files.

A failure leaves no signed file behind: the sign step deletes the previous
output first, and a failing sign, verify or publish step deletes
`<output>.unverified`. Only the publish step creates `<output>`. Run on its
own (below), the verify step never deletes the APK it checks.

### Outputs

| File | Content |
|---|---|
| `<output>` | the signed APK |
| `<output>.sha256` | `<sha256>  <file name>`, checkable with `sha256sum -c` |
| `<output>.json` | signing mode, package, versionCode, versionName, release tag, certificate SHA-256 and DN, signature schemes, ABIs, SHA-256 of the APK, the unsigned APK, the stock input and both arm64 libraries, source commit and whether the tree had uncommitted changes |

### Tools

`apksigner`, `zipalign` and `aapt2` come from one pinned build-tools release:
`android_build_tools_version` (default `37.0.0`) under `android_sdk_root`
(default: `ANDROID_SDK_ROOT`, `ANDROID_HOME`, then the Android Studio SDK
directory). The sign step compares the release with `Pkg.Revision` in its
`source.properties` and stops on a mismatch. The debug mode keeps its own
signer, uber-apk-signer 1.3.0.

## Checking an APK without a build tree

The verify step runs on its own against any APK, for example a downloaded
release:

```sh
BT=<sdk>/build-tools/37.0.0
cmake -DMODE=release -DAPK=sbconnect-compat-v0.1.0.apk \
      -DCERT_SHA256=<published certificate SHA-256> \
      -DPACKAGE=io.github.asce1062.sbconnect.compat \
      -DVERSION_CODE=1000 -DVERSION_NAME=1.04.02-compat.0.1.0 \
      -DABIS=arm64-v8a,armeabi,armeabi-v7a,x86 -DWORK=/tmp/sbc-verify \
      -DAPKSIGNER=$BT/apksigner -DZIPALIGN=$BT/zipalign -DAAPT2=$BT/aapt2 \
      -P cmake/verify_signed_apk.cmake
```

Without `-DUNSIGNED` and `-DNATIVE_LIBS` it skips the payload and library
byte comparisons and runs checks 1 to 4 and the ABI check.

[`scripts/ci/verify_release.py`](../../scripts/ci/verify_release.py) adds
the checks that need no Android tools: the `.sha256` file, the `.json`
metadata against the APK and the expected certificate, and the arm64
libraries in the APK against the accepted SHA-256s in
[`tests/native/expected_abi.json`](../../tests/native/expected_abi.json):

```sh
python3 scripts/ci/verify_release.py --apk sbconnect-compat-v0.1.0.apk \
    --mode release --cert <published certificate SHA-256>
```

## Pre-release label

`-Dsbc_prerelease=<label>` (dot-separated alphanumerics, for example
`rehearsal.1`) marks a build that is not a release. The label is appended to
the versionName, the tag and the file name
(`1.04.02-compat.0.1.0-rehearsal.1`, `v0.1.0-rehearsal.1`); the versionCode
stays that of the version. A labelled build signed with the production key
therefore updates an installed release of the same certificate, and the
release of that version, with the same versionCode, still installs over it.
This is the update qualification build ([RELEASE.md](RELEASE.md#update-qualification)).
The release workflow refuses a label on a release tag.

## Disposable keys

test-release needs a key nobody depends on. Create one outside the
repository; `keytool` reads the password from a variable, so it is not on
the command line:

```sh
read -rs KS_PW && export KS_PW
keytool -genkeypair -keystore /tmp/sbc-test.p12 -storetype PKCS12 \
    -alias sbc-test -keyalg RSA -keysize 3072 -validity 30 \
    -dname "CN=SB Connect Compat test" -storepass:env KS_PW -keypass:env KS_PW
keytool -list -v -keystore /tmp/sbc-test.p12 -storepass:env KS_PW | grep SHA256:
```

Android installs an update only when it is signed with the same key as the
installed app. A test-release APK therefore never updates a release install,
and the reverse; uninstalling is the only way between them.

## The production key

Its creation, backup and the publication of its certificate fingerprint are
operator steps in [RELEASE.md](RELEASE.md#once-create-the-release-key).

| Item | Value |
|---|---|
| Subject | `CN=SB Connect Compat` |
| Key | RSA 4096, PKCS#12, alias `sbconnect-compat`, 10000-day validity, created 2026-11-26 |
| Certificate SHA-256 | `3c726afab7e94ca20c5d44f854eb357e684323a0bc4ae5d747d3281439e82b57` |

The fingerprint is committed as
[`signing/release-certificate.sha256`](../../signing/release-certificate.sha256);
the release workflow's verification accepts no other certificate in release
mode, and fails while the file does not exist. A debug or disposable key
never substitutes for the production key: `apk-compat-release` reads only
`SBC_RELEASE_*`, refuses an Android debug certificate, and compares the
signer with the expected fingerprint.
