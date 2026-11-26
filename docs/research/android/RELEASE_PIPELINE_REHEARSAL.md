# RELEASE_PIPELINE_REHEARSAL

> **Historical record.** Kept as evidence of how behavior was established; not updated for later changes. Status, corrections and the maintained references: [research index](../README.md).

The signing driver ([`sign_release.cmake`](../../../cmake/sign_release.cmake))
on both of its routes, with one disposable key: the build target
`apk-compat-test-release`, and the release workflow's sign step
([`sign_release.sh`](../../../scripts/ci/sign_release.sh)) run locally from
staged release inputs, the way the workflow's sign job receives them. Run on
2026-11-26 on Windows, at `a5514d8` plus the uncommitted release
infrastructure that introduced the driver. No production key exists; nothing
here shows that production signing is ready, and no workflow ran on GitHub.

## Key

One PKCS#12 keystore (RSA 2048, SHA384withRSA, 30-day validity,
`CN=SB Connect Compat rehearsal (disposable)`), generated with `keytool` in a
scratch directory outside the source tree, with a random password that was
never written to a file. Certificate SHA-256
`f4fb39acb9b126445b348f4ea68dd3b0e627534c73b6786860ff268cd58e7646`. The
keystore was deleted at the end of the run.

## Cases

The build tree was reconfigured first; `release.env` then carried the
signing inputs the workflow route reads (`RELEASE_ABIS`, `NATIVE_ABI`,
`NATIVE_LIBS`, `STOCK_INPUT_SHA256 fe1ffe0c...`).

| Case | Route | Input | Result | Files left |
|---|---|---|---|---|
| N1 | target `apk-compat-release` | only `SBC_TEST_RELEASE_*` set | exit 1, "required environment variables are not set" | none in `build/release` |
| N2 | target `apk-compat-test-release` | the key, a wrong expected certificate | exit 1, "signer certificate SHA-256 ... expected ..." | no APK, no `.unverified` |
| P1 | target `apk-compat-test-release` | the key, its certificate | exit 0. apksigner v1, v2, v3 with 1 signer; `zipalign -c -P 16 4` ok; certificate matches; `io.github.asce1062.sbconnect.compat` 1000 `1.04.02-compat.0.1.0`; ABIs `arm64-v8a armeabi armeabi-v7a x86` with the arm64 libraries matching the build; 4309 non-signature entries identical to the unsigned APK | APK, `.sha256`, `.json` |
| P2 | `sign_release.sh`, `MODE=test-release` | the unsigned APK, `release.env` and the two native libraries copied to a staging directory; the key as `SBC_TEST_RELEASE_*` | exit 0, the same checks as P1 | APK, `.sha256`, `.json` |

[`verify_release.py`](../../../scripts/ci/verify_release.py) passes on the
outputs of P1 and P2 against the disposable certificate and `release.env`.

## Outputs

| Item | Value |
|---|---|
| Signed APK SHA-256, P1 and P2 | `89aaec9e2308eca4b9e3f317cfb50829ee7c87b042c2a10fa7e2c7b3d6e9e487` (47517638 bytes), identical between the routes |
| Unsigned input SHA-256 | `2eac156703b89f657f6b99e42bb82abce99bddbea7cd036ee48bca78006ab9c2` |
| Content digest (`compare_apks.py --digest --ignore-signatures`), unsigned and both signed | `246acc68ecab1b07f816fe24ed7942b966da92ed7dc7a9b9a0da2bac13d6b836` |
| arm64 libraries | `970d1744...` and `ca380c7c...`, the accepted digests |
| `.json` | `signing_mode` `test-release`, `release_tag` `v0.1.0`, `source_uncommitted_changes` true |

The content digest equals the accepted b5 build's: N1 rebuilt `compat`
after the reconfigure, and the rebuild differs from b5 in entry timestamps
only ([BUILD_TIMES.md](BUILD_TIMES.md)). The two routes produce the same
bytes from the same unsigned APK and key.

This shows that the build target and the workflow's sign step share one
signing path, fail closed without credentials or with a wrong certificate,
and verify their output. It shows nothing about the GitHub-hosted runners,
environment secrets, the draft job, or a production key.
