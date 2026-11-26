# Continuous integration

The GitHub Actions workflows, where each runs, what each may access, how
they are set up, and how to run each check locally. Signing is in
[SIGNING.md](SIGNING.md), the release process in [RELEASE.md](RELEASE.md).

## Two places

| Where | Workflows | Holds |
|---|---|---|
| this repository (public) | [`ci.yml`](../../.github/workflows/ci.yml) | source only: no secret, no environment, no variable, no artifact, no cache |
| the private build-input repository | the trusted workflows, copied from [`ci/trusted/`](../../ci/trusted) | the stock APK, the trusted workflows, the rehearsal signing key, private artifacts and private draft releases |

An APK contains the stock app ([NOTICE.md](../../NOTICE.md)). The workflows
that build, sign or verify one hand the unsigned APK and the signed APK from
job to job as artifacts. Artifacts, caches and logs of a public repository
are readable by anyone, so those workflows run from the private
build-input repository, and this repository holds nothing they produce. The
only APK this repository distributes is a release asset the operator
attaches to a draft release and publishes ([RELEASE.md](RELEASE.md)).

| Workflow | Runs from | Trigger | Stock APK | Secrets | Produces |
|---|---|---|---|---|---|
| [`ci.yml`](../../.github/workflows/ci.yml) | this repository | every push and pull request, dispatch | no | none | test results, native library hashes |
| [`build-apk.yml`](../../ci/trusted/build-apk.yml) | build-input repository | dispatch, called by `release.yml` | yes, from the repository it runs in | none | the four variants as private artifacts |
| [`release.yml`](../../ci/trusted/release.yml) | build-input repository | dispatch | through `build-apk.yml` | the rehearsal key (`release-rehearsal`), signing job only; none in mode `local` | a private draft release with the signed APK, `.sha256`, `.json`, notes and inventory; in mode `local`, verification of the operator's private draft |
| [`verify-release.yml`](../../ci/trusted/verify-release.yml) | build-input repository | called by `release.yml`, dispatch | no | none | verification report |

[`check_workflows.py`](../../scripts/ci/check_workflows.py) keeps the
boundary: it fails a workflow in `.github/workflows/` that reads a secret,
names an environment, uploads an artifact, uses a cache, has a
`pull_request_target`, `workflow_run` or `workflow_call` trigger or grants a
write permission, and a workflow in `ci/trusted/` that has an event trigger,
skips the trusted-definition action or uploads an artifact without the
private-repository guard.

## Source CI

`ci.yml` needs neither the stock APK nor a credential, so it runs on pull
requests from anyone:

| Job | Checks |
|---|---|
| Host regression, Linux and Windows | the portable CtProtocol core and all seven host suites ([TESTING.md](TESTING.md)) |
| Native libraries, arm64-v8a and x86 | builds `patches/arm64/native` with the pinned NDK; [`check_elf.py`](../../scripts/ci/check_elf.py) checks ELF class and machine, minimum `PT_LOAD` alignment (16 KiB for 64-bit, 4 KiB for 32-bit), `DT_NEEDED` and the exported symbols exactly, and for arm64-v8a the accepted SHA-256s, all against [`tests/native/expected_abi.json`](../../tests/native/expected_abi.json) |
| Pins, links, privacy, workflow boundary | [`check_pins.py`](../../scripts/ci/check_pins.py): every action pinned to a commit SHA, the tool pins well formed, the apktool and uber-apk-signer downloads match their SHA-256; [`check_links.py`](../../scripts/ci/check_links.py): every relative link and anchor in the Markdown resolves; [`check_hygiene.py`](../../scripts/ci/check_hygiene.py): no APK, native binary, dex, jar, keystore or key file is tracked, no decoded app tree, no file over 1 MiB, no private key, MAC address, private IPv4 address, local user path or personal email in tracked files, and every commit author and committer email is a noreply address; [`check_workflows.py`](../../scripts/ci/check_workflows.py): the boundary above |

The accepted arm64 hashes are the libraries verified on hardware. A
toolchain or source change that moves them fails the native job until the
new libraries are verified and the hashes are changed with a recorded
reason ([NATIVE_LIBRARIES.md](../technical/NATIVE_LIBRARIES.md)).

## Trusted builds

The trusted workflows are kept in [`ci/trusted/`](../../ci/trusted), where
they are reviewed with the source, and copied unchanged into
`.github/workflows/` of the build-input repository, where they run. Every
run takes `ref`, the full SHA of the compat commit to build, and each job:

1. checks out that commit of the compat source from the repository named
   by the variable `SBC_SOURCE_REPOSITORY`;
2. runs the [trusted-definition](../../.github/actions/trusted-definition/action.yml)
   action, which stops the job when the repository it runs in is public,
   when the checkout is not `ref`, or when the running repository's workflow
   files differ from `ci/trusted/` at `ref`. A run therefore executes only
   the definition published with the source it builds.

The stock APK is read from the repository the workflow runs in, with the
workflow's own read-only token; no deploy key exists.

### APK build

`build-apk.yml` builds `resign`, `modernize`, `arm64` and `compat` in four
parallel jobs. Each job, after the two steps above:

1. installs the pinned JDK and the SDK packages the runner image lacks, and
   checks every package's revision ([caching](#caching));
2. takes the stock APK ([stock-input](../../.github/actions/stock-input/action.yml))
   and checks its SHA-256 against `apk_input_sha256` in `CMakeLists.txt`
   before anything reads it; the input checkout is deleted in the same
   action;
3. fetches the tool jars with `check_pins.py --download` and checks them
   against their pins (the SDK's CMake 3.22.1 cannot write a
   `file(DOWNLOAD)` output on the Linux runner);
4. configures (which checks the stock SHA-256 and the tool jars again) and
   builds `apk-<variant>`;
5. for `arm64` and `compat`, checks the native libraries against the
   accepted hashes;
6. writes the source commit, the APK SHA-256s and the
   [content digests](#equivalent-builds) to the job summary, and uploads
   the APKs as artifacts kept 7 days. Every upload step also requires a
   private repository.

### Release

`release.yml` runs six jobs, each with only the permissions it needs:

| Job | Permissions | Does |
|---|---|---|
| plan | `contents: read` | a dispatch in mode `release` must carry a pre-release label; mode `local` must name a draft `v<version>...`; selects the environment |
| build | `contents: read` | `build-apk.yml` for `compat` only, uploads the unsigned APK, `release.env` and the native libraries with `SHA256SUMS` (kept 1 day) |
| sign | `contents: read`, environment `release` or `release-rehearsal` | not in mode `local`; checks the inputs' checksums and the label, decodes the keystore into the runner's temporary directory (mode 600), runs the signing driver ([SIGNING.md](SIGNING.md#pipeline)), deletes the keystore in a step that always runs |
| collect | `contents: write` (reading a draft requires it), no secrets, no checkout | mode `local` only; downloads exactly one APK with its `.sha256` and `.json` from the named draft and refuses a published release |
| verify | `contents: read`, `actions: read`, no secrets | `verify-release.yml` |
| draft | `contents: write`, no secrets | generates the notes and the dependency and license inventory; creates a private draft release, or in mode `local` adds them to the operator's draft |

Release mode and test-release mode have separate signing steps, each naming
only its own secrets, so a missing production secret fails the job and can
never fall back to the rehearsal key. Production signing is local: the
`release` environment holds no signing secret, so release mode stops at its
keystore step.

Mode `local` serves the local signing route: the production key never
enters CI. The operator attaches the locally signed APK, its `.sha256` and
its `.json` to a draft release of the build-input repository and names that
draft. `verify-release.yml` checks it in release mode against the run's own
unsigned build of `ref`, so the payload check proves the APK holds what that
commit builds. The draft job leaves the operator's three files as they are
and adds the notes and the inventory. A draft named exactly `v<VERSION>`
must also carry that tag in its `.json`. The notes list the changes up to
the APK's source commit and, apart from them, the commits from there to
`ref`. The operator then copies the verified draft's files to the public
draft release ([RELEASE.md](RELEASE.md#each-release)). The sign step and the
build target produce the same signed bytes from the same inputs
([RELEASE_PIPELINE_REHEARSAL.md](../research/android/RELEASE_PIPELINE_REHEARSAL.md)).

`verify-release.yml` repeats verification without any secret: checksums,
the signature, alignment, package metadata, native libraries and payload
against the unsigned APK (`verify_signed_apk.cmake`), then
[`verify_release.py`](../../scripts/ci/verify_release.py). In release mode
the expected certificate is `signing/release-certificate.sha256` from the
source; a missing file fails the job, so no other certificate passes.

## Trust model

- This repository has no secret, environment or variable, and no deploy key
  of it reaches the build-input repository. A workflow at any commit of this
  repository, an old tag included, has no way to fetch the stock APK or a
  signing key.
- Only `ci.yml` runs here, on pushes and pull requests, and it reads no
  secret and writes nothing but logs.
- The trusted workflows run in a private repository that only the
  maintainer can push to, from its default branch, and only the published
  definition of the commit they build.
- Secrets live in environments of the build-input repository, not at
  repository level. Their deployment policy admits only its `main` branch.
- Every checkout uses `persist-credentials: false`; the workflow token is
  read-only except in the collect and draft jobs.
- Every external action is pinned to a full commit SHA with its version in a
  comment; `check_pins.py` fails on a tag or branch reference, in both
  places.

## Setup

Done once by the operator. None of these values enter the repository.

This repository: nothing. It has no secret, environment or variable.

The build-input repository (private, for example `sbconnect-build-inputs`):

1. **Contents.** `SBConnect_v1.04.02.apk` at the root of `main`, and the
   files of `ci/trusted/` in `.github/workflows/`, unchanged. Copy them
   again whenever `ci/trusted/` changes; a run against a commit whose
   `ci/trusted/` differs stops at the trusted-definition step.
2. **Variables** (repository level): `SBC_SOURCE_REPOSITORY` = `owner/name`
   of this repository; `SBC_TEST_RELEASE_CERT_SHA256` = the disposable
   rehearsal certificate's fingerprint. While this repository is private,
   the build-input repository's token cannot read it; then push the commit
   to build to a branch of the build-input repository
   (`git push <build-input remote> <sha>:refs/heads/source`) and set
   `SBC_SOURCE_REPOSITORY` to the build-input repository itself.
3. **Environment `release-rehearsal`**: deployment branch `main`; secrets
   `SBC_TEST_RELEASE_KEYSTORE_B64` (a disposable keystore, base64),
   `SBC_TEST_RELEASE_KEYSTORE_PASS`, optional `SBC_TEST_RELEASE_KEY_PASS`;
   variables `SBC_TEST_RELEASE_KEY_ALIAS`, `SBC_TEST_RELEASE_CERT_SHA256`.
4. **Environment `release`**: deployment branch `main`; variables
   `SBC_RELEASE_KEY_ALIAS`, `SBC_RELEASE_CERT_SHA256`; no secrets, which
   keeps production signing on the local route
   ([RELEASE.md](RELEASE.md#each-release)).

The base64 form of a keystore: `base64 -w0 <keystore>` or, in PowerShell,
`[Convert]::ToBase64String([IO.File]::ReadAllBytes('<keystore>'))`. Pipe it
into `gh secret set` or paste it into the secret field; do not write it to
a file.

### Event delivery

Since 2026-11-25, GitHub creates no push or pull-request events for the
account that owns these repositories. Pushes are recorded in each
repository's activity log, but no event and no check suite follows, so
`ci.yml` does not start on its own
([record](../research/android/CI_QUALIFICATION.md#event-delivery)). Until
that is restored, start source CI by hand after each push:
`gh workflow run ci.yml --ref <branch>`. The trusted workflows are
dispatched in any case.

## Caching

Only verified, immutable inputs are cached, and only in the build-input
repository; nothing signed or built is.

| Cache | Key | Verified after restore |
|---|---|---|
| apktool and uber-apk-signer jars | the SHA-256 of `CMakeLists.txt`, which holds their versions and SHA-256 pins | `check_pins.py --download` and configure check each jar's SHA-256 and stop on a mismatch |
| JDK | `setup-java`'s own tool cache, by exact version | |

Android SDK packages are not cached. The runner image preinstalls most of
them under a root-owned SDK directory where a cache restore fails, and
installing the missing ones takes less time than restoring them.
[`android_sdk_install.sh`](../../scripts/ci/android_sdk_install.sh)
installs any package without the pinned `Pkg.Revision` from
[`sdk-packages.txt`](../../scripts/ci/sdk-packages.txt) and fails on a
revision that still differs.

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

On the GitHub-hosted `ubuntu-24.04` runner
([record](../research/android/CI_QUALIFICATION.md#runner-build-times)):

| Job | Time |
|---|---|
| `build-apk.yml`, `resign` / `compat` / `arm64` / `modernize` (job, including toolchain and stock input) | 1 min 48 s / 4 min 09 s / 4 min 25 s / 4 min 40 s |
| `release.yml` in mode `test-release`, plan to draft | 5 min 29 s |

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

apktool writes the entries in a different order on Windows and on Linux.
`--any-order` compares names, methods and bytes without the order and sorts
the digest's lines by name; the build summaries use it. The `compat`
unsigned build of the GitHub runner, the local Windows build and the
production candidate `63dcd889...` have one such digest
([record](../research/android/CI_QUALIFICATION.md#apk-equivalence)).

## Running the checks locally

```sh
python3 scripts/ci/check_hygiene.py --history .
python3 scripts/ci/check_links.py .
python3 scripts/ci/check_workflows.py .
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
2. The jar cache key changes with `CMakeLists.txt`.
3. If the native libraries change, verify them and record the reason before
   changing the accepted hashes.
4. If a file in `ci/trusted/` changed, copy it to the build-input
   repository.
