# Security

## Reporting a vulnerability

Report a vulnerability privately through the repository's GitHub security
advisories (**Security**, **Report a vulnerability**), not in a public
issue. Include the affected version or commit, the device and Android
version, and the steps that show the problem. Reports are answered on a
best-effort basis; this is a volunteer project.

In scope: this project's patches, shim classes, native libraries, build and
signing scripts, and workflows. Defects in the stock app's own code are
Creative's; they are in scope only where a patch here makes them reachable
or worse.

## Supported versions

Only the latest release, and `main`, receive fixes.

## What a release guarantees

- **One signer.** Every release is signed with the same production key. Its
  certificate SHA-256 is committed as `signing/release-certificate.sha256`;
  an APK signed by anything else is not a release of this project
  ([INSTALLATION.md](docs/user/INSTALLATION.md#check-a-release-download)).
- **Verified before publication.** The signature (schemes v1, v2, v3),
  alignment, package metadata, native library hashes and the payload against
  the unsigned build are checked by the build and again by an independent
  workflow without secrets ([SIGNING.md](docs/development/SIGNING.md),
  [CI.md](docs/development/CI.md#release)).
- **Traceable.** Each release has a `.json` with the source commit, the
  stock input SHA-256 and the hashes of the APK and its native libraries,
  and a dependency and license inventory.
- **Least privilege.** The permission set and component exports are reduced
  to what the app's features use ([PERMISSIONS.md](docs/technical/PERMISSIONS.md)).

## Secrets and build inputs

- No signing key, password or keystore is in the repository; keystore and
  key files are refused by the hygiene check that runs on every change.
- The production key and its password exist only on the maintainer's
  machine; releases are signed there. CI holds only a disposable test key,
  in an environment of a private build-input repository. This repository's
  workflows hold no secrets, so pull-request code never reaches one
  ([CI.md](docs/development/CI.md#trust-model)).
- The stock APK is a private, SHA-256-pinned build input, fetched only by
  the trusted workflows in that private repository; it is not in this
  repository or its history.

This project is not affiliated with Creative Technology Ltd; Creative does
not handle reports about it ([NOTICE.md](NOTICE.md)).

If you believe a signing key or credential has been exposed, report it as a
vulnerability at once.
