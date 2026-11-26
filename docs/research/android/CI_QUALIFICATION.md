# CI qualification

The first GitHub-hosted runs of the four workflows
([CI.md](../../development/CI.md)), in the private repository, on
2026-11-26: source CI, the APK build, a test-release rehearsal, the
production signing boundary, and CI verification of the locally signed
production candidate. Both repositories, this one and the build-input
repository, are private for the whole run. Nothing was published, and no
tag exists in the repository.

## Before the first push

| Check | Result |
|---|---|
| working tree | clean; `main` is an ancestor of `phase-e/release-infra` (fast-forward) |
| host suites, local | 7 / 7 pass |
| `check_pins.py --download` | every action pinned to a commit SHA; apktool 3.0.3 and uber-apk-signer 1.3.0 match their pins; 0 problems |
| `check_links.py` | 671 relative links, 0 broken |
| `check_hygiene.py --history` | 0 problems |
| history | no APK, keystore or key object in any commit; every author and committer email is a noreply address |
| candidate | `sbconnect-compat-v0.1.0.apk`, SHA-256 `63dcd889...`, kept outside the build directory with its `.sha256` and `.json` |

## Runs

| Run | Workflow, mode | Commit | Result | Wall time |
|---|---|---|---|---|
| [45846009848](https://github.com/asce1062/sound-blaster-connect-compat/actions/runs/45846009848) | CI | `70fef08` | success | 1 min 31 s |
| [45846042518](https://github.com/asce1062/sound-blaster-connect-compat/actions/runs/45846042518) | Build APKs | `70fef08` | failure at configure, all four variants | 1 min 04 s |
| [45847882517](https://github.com/asce1062/sound-blaster-connect-compat/actions/runs/45847882517) | CI | `38d4461` | success | 41 s |
| [45847875588](https://github.com/asce1062/sound-blaster-connect-compat/actions/runs/45847875588) | Build APKs | `38d4461` | success | 4 min 49 s |
| [45849352710](https://github.com/asce1062/sound-blaster-connect-compat/actions/runs/45849352710), [45849358678](https://github.com/asce1062/sound-blaster-connect-compat/actions/runs/45849358678), [45849364646](https://github.com/asce1062/sound-blaster-connect-compat/actions/runs/45849364646) | Release: test-release, release, local | `d412ebc` | failure in the called build's stock-input checkout | about 1.5 min each |
| [45850290385](https://github.com/asce1062/sound-blaster-connect-compat/actions/runs/45850290385) | Release, test-release, label `ci.1` | `2b9b289` | success, draft `v0.1.0-ci.1-test-release.4` | 5 min 29 s |
| [45850295988](https://github.com/asce1062/sound-blaster-connect-compat/actions/runs/45850295988) | Release, release, label `failclosed.1` | `2b9b289` | failure at `Keystore (release)`, as intended | 4 min 18 s |
| [45850303253](https://github.com/asce1062/sound-blaster-connect-compat/actions/runs/45850303253) | Release, local, draft `v0.1.0-local-verify.1` | `2b9b289` | success | 5 min 02 s |
| [45852169074](https://github.com/asce1062/sound-blaster-connect-compat/actions/runs/45852169074) | CI | `dbd5df5` | success | 51 s (jobs) |
| [45852175919](https://github.com/asce1062/sound-blaster-connect-compat/actions/runs/45852175919) | Build APKs | `dbd5df5` | success | 4 min 16 s |

Every run was dispatched. Pushes do not start workflow runs in this
repository: the activity API records each push to `main` and
`phase-e/release-infra`, and no check suite or run exists for any pushed
commit. Actions is enabled with all actions allowed, and dispatch works.
The cause is not isolated; the push and pull-request triggers are
unqualified.

## Failures and corrective commits

All four fixes are infrastructure only; no application file changed.

| Failure | Cause | Commit |
|---|---|---|
| `file DOWNLOAD cannot open file for write` for both tool jars, at configure | the Android SDK's CMake 3.22.1 on the Linux runner fails to open the `file(DOWNLOAD)` output; the same call succeeds with its Windows build, and the same CMake builds the native libraries on the runner | `38d4461`: `check_pins.py --download` fetches and checks the jars before configure, which then verifies them again |
| release.yml refused at dispatch (HTTP 422, `Unrecognized named-value: 'runner'`) | the sign job set `IN` from `runner.temp` in its job-level `env`, where the runner context does not exist; the workflow had never parsed | `d412ebc` |
| `Not Found` checking out the input repository in the build called by release.yml | without `secrets: inherit` the called job sees an empty deploy key, so checkout used the workflow token | `2b9b289` |
| SDK cache restore fails (`tar` exit 2, 32 s) | the runner image preinstalls the SDK packages in root-owned directories; the restore cannot set their modes, and installing the one missing package takes less time | `2b9b289`: SDK packages are installed and verified, not cached |
| local and runner builds compare as different | apktool writes entries in a different order on Windows and Linux; names, methods and bytes are identical | `dbd5df5`: `compare_apks.py --any-order` |

`7595538` adds mode `local` for the local signing route (below).

## Source CI

Run `45847882517` at `38d4461` (`45846009848` at `70fef08` alike):

| Job | Runner | Result |
|---|---|---|
| Host regression | `ubuntu-24.04` | 7 / 7 suites pass |
| Host regression | `windows-2025` | 7 / 7 suites pass |
| Native libraries, arm64-v8a | `ubuntu-24.04` | NDK 25.1.8937393; both libraries 64-bit AArch64, `PT_LOAD` alignment 0x4000, `DT_NEEDED` and the 36 and 1 exported symbols as expected; SHA-256 `970d1744...` and `ca380c7c...`, the accepted hashes |
| Native libraries, x86 | `ubuntu-24.04` | both libraries 32-bit x86, alignment 0x1000, needed libraries and exports as expected |
| Pins, links, privacy | `ubuntu-24.04` | 25 action references pinned, both jars match their pins, 671 links resolve, hygiene over the full history (`fetch-depth: 0`): 0 problems |

The workflow names no environment and reads no secret, and it does not
fetch the stock APK.

## APK build

Run `45847875588` at `38d4461`:

- **Stock input**: the job runs in environment `build-inputs`, checks out
  the private input repository with the read-only deploy key, verifies
  SHA-256 `fe1ffe0c93b6476ae6ed1d2cb6891cde2fbe206d4e898d6ad8c75222e9bf99be`
  against `apk_input_sha256`, and removes the checkout.
- **Toolchain**: JDK 23.0.2+7, then SDK packages verified by revision. The
  runner image provides all but `build-tools/33.0.1`, which is installed.
- **Variants**: all four jobs succeed. For `arm64` and `compat` the native
  libraries match the accepted hashes.
- **Resign**: `sbc_resign-aligned.apk` is byte-identical to the stock APK
  (`fe1ffe0c...`); payload preserved.
- **Identity**: `compat` is `com.creative.apps.sbconnect.compat`,
  versionName `1.04.02-compat.0.1.0`, versionCode 1000.
- **Access**: the APK artifacts are uploaded only because the repository
  is private (the step's condition), for 7 days; release inputs are kept
  for 1 day.

### Runner build times

| Job (toolchain and stock input included) | Time |
|---|---|
| `resign` | 1 min 48 s |
| `compat` | 4 min 09 s |
| `arm64` | 4 min 25 s |
| `modernize` | 4 min 40 s |
| `compat` called by release.yml | 4 min 03 s |

For comparison, the four variants built locally at once, on Windows with
`apktool_jobs` 8, took 20 min 29 s.

### APK equivalence

The runner build at `38d4461` and a local Windows build at `70fef08` (the
commits differ in workflow and documentation files only), compared with
`compare_apks.py`:

| Variant | Unsigned | Debug-signed (`--ignore-signatures`) |
|---|---|---|
| `resign` | byte-identical | equivalent, 0 entries differing |
| `arm64` | 4309 entries, same names, methods and bytes; order differs | same |
| `compat` | 4309 entries, same names, methods and bytes; order differs | same |
| `modernize` | 4307 entries, same names, methods and bytes; order differs | same |

With `--any-order` every pair is equivalent. The digest
`compare_apks.py --digest --any-order --ignore-signatures` is the same for
the three `compat` builds:

| `compat` | Digest |
|---|---|
| runner unsigned, `38d4461` | `03851153d60cb24dc9193359911b864a24fa2b51b995f5ae7040e6d60c183bd6` |
| local unsigned, `70fef08` | `03851153d60cb24dc9193359911b864a24fa2b51b995f5ae7040e6d60c183bd6` |
| production candidate `63dcd889...`, `596f3bb` | `03851153d60cb24dc9193359911b864a24fa2b51b995f5ae7040e6d60c183bd6` |

## Test-release rehearsal

Run `45850290385`: mode `test-release`, label `ci.1`, environment
`release-rehearsal`.

- **Signing**: the sign job names only `SBC_TEST_RELEASE_*` secrets and
  variables; the `release` environment holds no secret.
- **Release inputs**: their checksums and the label match.
- **Verification**: `verify-release.yml` runs as a separate job with no
  secret and no environment.

The verification report:

| Check | Result |
|---|---|
| checksums | `release-inputs/SHA256SUMS` and the APK's `.sha256` OK |
| signature | apksigner v1, v2, v3, one signer |
| alignment | `zipalign -c -P 16 4` ok |
| certificate | `e618df0803ce10042e7035d44812bc1e343486d3b94c1419285caf7f4a7e7686` (CN=SB Connect Compat test), the rehearsal certificate |
| package and version | `com.creative.apps.sbconnect.compat`, 1000, `1.04.02-compat.0.1.0-ci.1` |
| ABIs | arm64-v8a, armeabi, armeabi-v7a, x86; arm64-v8a libraries match the build |
| payload | 4309 non-signature entries identical to the unsigned APK |
| `verify_release.py` | PASS |

The draft `v0.1.0-ci.1-test-release.4` is marked pre-release and targets
`2b9b289`. Its notes name the file, SHA-256, version, certificate, mode and
source commit. It holds these assets:

- `sbconnect-compat-v0.1.0-ci.1-test-release.apk`, SHA-256
  `573ec6cb3f4dbe59985d32f3b1a24d96ee8bc8ecbdec292d97aad5fcdab238ff`;
- its `.sha256`;
- its `.json` (provenance);
- `INVENTORY.md` and `inventory.json`.

Neither the rehearsal identity nor the draft uses the name `v0.1.0`.

## Production signing boundary

The `release` environment has no secret; production signing is local.

Run `45850295988` dispatched mode `release` with label `failclosed.1`:

- The build and the release-input check pass.
- `Keystore (release)` fails with `SBC_RELEASE_KEYSTORE_B64 is not set`.
- `Keystore (test-release)` and both signing steps are skipped, so nothing
  is signed with any key.
- Verify and draft are skipped, and no draft exists.

Mode `local` (`7595538`) verifies a locally signed APK with no key in CI.
Run `45850303253` checked the production candidate itself:

1. The candidate, its `.sha256` and its `.json`, unchanged from the
   evidence copy, are attached to the draft `v0.1.0-local-verify.1`
   (pre-release, target `596f3bb`).
2. `collect` confirms that the release is a draft and downloads the three
   files.
3. `verify-release.yml` checks the APK in release mode against the run's
   own unsigned build at `2b9b289`:

| Check | Result |
|---|---|
| signature | apksigner v1, v2, v3, one signer; `zipalign -c -P 16 4` ok |
| certificate | `3c726afab7e94ca20c5d44f854eb357e684323a0bc4ae5d747d3281439e82b57` (CN=SB Connect Compat), from `signing/release-certificate.sha256` |
| package and version | `com.creative.apps.sbconnect.compat`, 1000, `1.04.02-compat.0.1.0`, tag `v0.1.0`, commit `596f3bb` |
| native libraries | arm64-v8a libraries match the build |
| payload | 4309 non-signature entries identical to the runner's unsigned build |
| `verify_release.py` | PASS |

The draft job then adds the notes and the inventory. After the run, the
APK asset still has SHA-256 `63dcd889...`.

## Result

| Verdict | Basis |
|---|---|
| PRIVATE_UPSTREAM_PASS | both branches pushed at the same commit; both repositories private; history clean |
| SOURCE_CI_PASS | Linux and Windows host suites, both native ABIs, pins, links and hygiene, with no stock APK and no credential |
| APK_PIPELINE_PASS | read-only stock input with the exact SHA-256, all four variants, payload-preserving resign, accepted arm64 hashes, compat identity, content equal to the local build |
| RELEASE_AUTOMATION_PASS | rehearsal signed in `release-rehearsal`, verified independently, draft with checksums, provenance, inventory and notes; no `v0.1.0` tag or draft |
| PRODUCTION_SIGNING_BOUNDARY_PASS | release mode fails closed without the production secrets; mode `local` verifies the locally signed APK with no key in CI |
| RELEASE_CANDIDATE_PASS | `63dcd889...` from `596f3bb`, certificate `3c726afa...`, unchanged, verified by CI against the runner's own build |

Limitation: pushes start no workflow runs (see [Runs](#runs)). The two
drafts stay unpublished in the private repository. Publishing one, and
the repository's visibility, remain the operator's decisions.
