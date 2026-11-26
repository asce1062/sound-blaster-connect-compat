# Continuous integration

The four GitHub Actions workflows, what each may access, how they are set
up, and how to run each check locally. Signing is in [SIGNING.md](SIGNING.md),
the release process in [RELEASE.md](RELEASE.md).

## Workflows

| Workflow | Trigger | Stock APK | Secrets | Produces |
|---|---|---|---|---|
| [`ci.yml`](../../.github/workflows/ci.yml) | every push and pull request, dispatch | no | none | test results, native library hashes |
| [`build-apk.yml`](../../.github/workflows/build-apk.yml) | push to `main`, dispatch, called by `release.yml` | yes, from the private input repository | input deploy key (`build-inputs`) | the four variants; artifacts only while the repository is private |
| [`release.yml`](../../.github/workflows/release.yml) | tag `v*`, dispatch | through `build-apk.yml` | signing key (`release` or `release-rehearsal`), signing job only | signed APK, `.sha256`, `.json`, notes, inventory, a draft release |
| [`verify-release.yml`](../../.github/workflows/verify-release.yml) | called by `release.yml`, dispatch | no | none | verification report |

### Source CI

`ci.yml` needs neither the stock APK nor a credential, so it runs on pull
requests from anyone:

| Job | Checks |
|---|---|
| Host regression, Linux and Windows | the portable CtProtocol core and all seven host suites ([TESTING.md](TESTING.md)) |
| Native libraries, arm64-v8a and x86 | builds `patches/arm64/native` with the pinned NDK; [`check_elf.py`](../../scripts/ci/check_elf.py) checks ELF class and machine, minimum `PT_LOAD` alignment (16 KiB for 64-bit, 4 KiB for 32-bit), `DT_NEEDED` and the exported symbols exactly, and for arm64-v8a the accepted SHA-256s, all against [`tests/native/expected_abi.json`](../../tests/native/expected_abi.json) |
| Pins, links, privacy | [`check_pins.py`](../../scripts/ci/check_pins.py): every action pinned to a commit SHA, the tool pins well formed, the apktool and uber-apk-signer downloads match their SHA-256; [`check_links.py`](../../scripts/ci/check_links.py): every relative link and anchor in the Markdown resolves; [`check_hygiene.py`](../../scripts/ci/check_hygiene.py): no APK, native binary, dex, jar, keystore or key file is tracked, no decoded app tree, no file over 1 MiB, no private key, MAC address, private IPv4 address, local user path or personal email in tracked files, and every commit author and committer email is a noreply address |

The accepted arm64 hashes are the libraries verified on hardware. A
toolchain or source change that moves them fails the native job until the
new libraries are verified and the hashes are changed with a recorded
reason ([NATIVE_LIBRARIES.md](../technical/NATIVE_LIBRARIES.md)).

### APK build

`build-apk.yml` builds `resign`, `modernize`, `arm64` and `compat` in four
parallel jobs. Each job:

1. installs the pinned JDK and SDK packages ([toolchain cache](#caching));
2. fetches the stock APK from the private input repository with a read-only
   deploy key and checks its SHA-256 against `apk_input_sha256` in
   `CMakeLists.txt` before anything reads it; the input checkout is deleted
   in the same step sequence;
3. configures (which checks the SHA-256 again, and the tool jars) and builds
   `apk-<variant>`;
4. for `arm64` and `compat`, checks the native libraries against the
   accepted hashes;
5. writes the APK SHA-256s and [content digests](#equivalent-builds) to the
   job summary.

The stock APK never enters this repository or its history. The workflow
uploads APKs only while the repository is private, because an APK contains
the stock app ([NOTICE.md](../../NOTICE.md)).

### Release

`release.yml` runs five jobs, each with only the permissions it needs:

| Job | Permissions | Does |
|---|---|---|
| plan | `contents: read` | a tag run: the tag must equal `v<project VERSION>`, so a labelled tag is refused; a dispatch in mode `release` must carry a pre-release label; selects the environment |
| build | `contents: read` | `build-apk.yml` for `compat` only, uploads the unsigned APK, `release.env` and the native libraries with `SHA256SUMS` |
| sign | `contents: read`, environment `release` or `release-rehearsal` | checks the inputs' checksums and the label, decodes the keystore into the runner's temporary directory (mode 600), runs the signing driver ([SIGNING.md](SIGNING.md#pipeline)), deletes the keystore in a step that always runs |
| verify | `contents: read`, `actions: read`, no secrets | `verify-release.yml` |
| draft | `contents: write`, no secrets | generates the notes and the dependency and license inventory, refuses an existing release of the same name, creates a draft release |

Release mode and test-release mode have separate signing steps, each naming
only its own secrets, so a missing production secret fails the job and can
never fall back to the rehearsal key. Nothing is published: the operator
reviews the draft and publishes it. The sign step and the build target
produce the same signed bytes from the same inputs
([RELEASE_PIPELINE_REHEARSAL.md](../research/android/RELEASE_PIPELINE_REHEARSAL.md)).

`verify-release.yml` repeats verification without any secret: checksums,
the signature, alignment, package metadata, native libraries and payload
against the unsigned APK (`verify_signed_apk.cmake`), then
[`verify_release.py`](../../scripts/ci/verify_release.py). In release mode
the expected certificate is `signing/release-certificate.sha256` from the
repository; a missing file fails the job, so no other certificate passes.

## Trust model

- No workflow has a `pull_request_target` or `workflow_run` trigger, and
  only `ci.yml` runs on pull requests. Pull-request code never runs with the
  input deploy key or a signing key.
- Secrets live in environments, not at repository level. An environment's
  deployment policy admits only `main` and `v*` tags, so a dispatch from any
  other branch is refused before a step runs.
- `release` has a required reviewer: a person approves each production
  signing run.
- Every checkout uses `persist-credentials: false`; the workflow token is
  read-only except in the draft job.
- Every external action is pinned to a full commit SHA with its version in a
  comment; `check_pins.py` fails on a tag or branch reference.

## Setup

Done once by the operator in the repository settings. None of these values
enter the repository.

1. **Input repository.** A separate private repository (for example
   `sbconnect-build-inputs`) holding only `SBConnect_v1.04.02.apk` at its
   root. Add a read-only deploy key to it; keep the private half for step 3.
2. **Variable** (repository level): `SBC_INPUTS_REPOSITORY` = `owner/name`
   of the input repository; `SBC_TEST_RELEASE_CERT_SHA256` = the disposable
   rehearsal certificate's fingerprint.
3. **Environment `build-inputs`**: deployment branches `main` and tags `v*`;
   secret `SBC_INPUTS_DEPLOY_KEY` = the deploy key's private half.
4. **Environment `release-rehearsal`**: deployment branches `main` and tags
   `v*`; secrets `SBC_TEST_RELEASE_KEYSTORE_B64` (a disposable keystore,
   base64), `SBC_TEST_RELEASE_KEYSTORE_PASS`, optional
   `SBC_TEST_RELEASE_KEY_PASS`; variables `SBC_TEST_RELEASE_KEY_ALIAS`,
   `SBC_TEST_RELEASE_CERT_SHA256`.
5. **Environment `release`**: deployment tags `v*` and branch `main`, a
   required reviewer where the account's plan allows one on a private
   repository; secrets `SBC_RELEASE_KEYSTORE_B64`,
   `SBC_RELEASE_KEYSTORE_PASS`, optional `SBC_RELEASE_KEY_PASS`; variables
   `SBC_RELEASE_KEY_ALIAS`, `SBC_RELEASE_CERT_SHA256`. Leave the secrets
   unset to keep production signing on the local route
   ([RELEASE.md](RELEASE.md#each-release)); the release workflow then fails
   at the signing job in release mode and never signs with another key.

The base64 form of a keystore: `base64 -w0 <keystore>` or, in PowerShell,
`[Convert]::ToBase64String([IO.File]::ReadAllBytes('<keystore>'))`. Paste it
into the secret field directly; do not write it to a file.

## Caching

Only verified, immutable inputs are cached; nothing signed or built is.

| Cache | Key | Verified after restore |
|---|---|---|
| Android SDK packages | runner OS and architecture, the SHA-256 of [`sdk-packages.txt`](../../scripts/ci/sdk-packages.txt), the requested package list | [`android_sdk_install.sh`](../../scripts/ci/android_sdk_install.sh) checks each package's `Pkg.Revision` and reinstalls a mismatch |
| apktool and uber-apk-signer jars | the SHA-256 of `CMakeLists.txt`, which holds their versions and SHA-256 pins | configure checks each jar's SHA-256 and stops on a mismatch |
| JDK | `setup-java`'s own tool cache, by exact version | |

The decoded stock tree, the variant trees, the native build and every APK
are rebuilt in each run. Signing material is never cached: the keystore
exists only in the signing job's temporary directory and is deleted at its
end. A signed APK is never reused from an earlier run; each release run
signs its own build.

### Build times

From local builds on Windows with `apktool_jobs` 8
([record](../research/android/BUILD_TIMES.md)):

| Stage | Time |
|---|---|
| decode (apktool d) | 57 s |
| Java shims (javac, d8, smali) | 16 s |
| `compat` alone, from a fresh tree to the unsigned APK (decode, shims, native, `apktool b`) | 27 min (1618 s) |
| the same, four variants at once on one machine | 7 to 35 min each |
| `resign` control | 3.5 min |
| test-release signing and verification | 4.5 min |

`apktool b` of the full resource table is the cost, and it is not
incremental; caching cannot shorten it without caching built output. The
workflow runs variants in parallel jobs instead, so the wall time of a
build is about that of its slowest variant.

## Equivalent builds

APK files are not byte-reproducible: apktool writes the build time into
every ZIP entry. Their content is.
[`compare_apks.py`](../../scripts/ci/compare_apks.py) compares two APKs
entry by entry: same names in the same order, same compression method,
same uncompressed bytes. `--digest` reduces that to one value, the content
digest. Two builds are equivalent when their digests are equal.

A clean build of `compat` in a separate tree, with a fresh decode and no
cached tool state, is equivalent to the accepted build: all 4309 entries
match and only timestamps differ. The arm64 libraries are byte-identical.

| `compat` unsigned, commit `a5514d8` | Value |
|---|---|
| content digest | `246acc68ecab1b07f816fe24ed7942b966da92ed7dc7a9b9a0da2bac13d6b836` |
| `libsbxapplogic_ctprotocol_jni.so` | `970d1744d765e80a3e4b82854add4dd1d96402f0841b0a78070f9d80432d7836` |
| `libserialport_jni.so` | `ca380c7c549c197777d8b76a1c763806030992da4fe0af74e6cf47f8d9eff232` |

Signature files are left out with `--ignore-signatures`, so a signed APK has
the digest of the build it was signed from when signing changed no other
entry.

## Running the checks locally

```sh
python3 scripts/ci/check_hygiene.py --history .
python3 scripts/ci/check_links.py .
python3 scripts/ci/check_pins.py --download /tmp/sbc-tools .
python3 scripts/ci/check_elf.py arm64-v8a build/native/arm64-v8a/lib
python3 scripts/ci/compare_apks.py build/sbc_compat.apk other/sbc_compat.apk
```

The host suites: [TESTING.md](TESTING.md).

## Changing a pin

1. Change the version and its SHA-256 or revision in the one place that
   holds it: `CMakeLists.txt` (apktool, uber-apk-signer, the stock input),
   `scripts/ci/sdk-packages.txt` (SDK packages), the `uses:` line (actions,
   commit SHA with the version as a comment), or the `java-version` of the
   toolchain action.
2. Every cache key that depends on it changes with it.
3. If the native libraries change, verify them and record the reason before
   changing the accepted hashes.
