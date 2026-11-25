# SB Connect Compat

A reproducible build pipeline that makes the stock **Sound Blaster Connect**
1.04.02 Android app install and run on current Android, including phones
that can only run 64-bit code.

The stock app was last updated in 2019. It targets Android 8 and ships its
native libraries for 32-bit processors only, so current phones either refuse
it or crash it. This project does not modify how the app talks to the
speaker. It takes your own copy of the stock APK and applies the changes
current Android requires:

- the target API level raised to Android 14, with the manifest, permission
  and runtime changes that requires;
- 64-bit (arm64-v8a) builds of the app's two native libraries, rebuilt from a
  source reimplementation that reproduces the stock libraries' behavior
  byte for byte on a frozen test corpus.

This is an independent compatibility project, not affiliated with or endorsed
by Creative Technology Ltd. It does not include or distribute the stock app.
See [NOTICE.md](NOTICE.md).

## Variants

One build produces four independent APKs:

| Variant | What it changes | For |
|---|---|---|
| `resign` | Nothing: the stock archive re-signed, payload verified identical | phones that still run 32-bit apps |
| `modernize` | targetSdk 34 and the Android 12 to 14 fixes | phones that still run 32-bit apps |
| `arm64` | `modernize` plus arm64-v8a native libraries built from source | 64-bit-only phones, and the others |
| `compat` | `arm64` under its own application ID, `io.github.asce1062.sbconnect.compat`, labelled SB Connect Compat | the distributable build; installs next to the stock app |

The first three keep the stock package name and serve as controls. `compat`
is the build meant for distribution
([APPLICATION_IDENTITY.md](docs/technical/APPLICATION_IDENTITY.md)).

The `arm64` build has been tested on a Pixel 7a (Android 13) and a Galaxy S24
Ultra (Android 16) with a Sound BlasterX Katana. Other combinations are
untested; see [INSTALLATION.md](docs/user/INSTALLATION.md).

## Quick start

Requires Java 17+, CMake 3.22+, Ninja, Android build-tools and, for the
`arm64` variant, Android NDK 25.1.8937393. Put your copy of
`SBConnect_v1.04.02.apk` at `inputs/SBConnect_v1.04.02.apk`, then:

```sh
cmake --preset default
cmake --build --preset apks
adb install -r build/sbc_compat-aligned-debugSigned.apk
```

`compat` installs alongside the stock app. The stock-identity variants are
signed with a different key than Creative's, so the stock app must be
uninstalled before installing one of them. Details in [BUILDING.md](docs/development/BUILDING.md).

## Documentation

[docs/README.md](docs/README.md) indexes everything. In short:

- users: [INSTALLATION.md](docs/user/INSTALLATION.md)
- building and testing: [BUILDING.md](docs/development/BUILDING.md),
  [TESTING.md](docs/development/TESTING.md),
  [ARCHITECTURE.md](docs/development/ARCHITECTURE.md)
- technical references: [`docs/technical/`](docs/technical/)
- design decisions: [`docs/decisions/`](docs/decisions/)
- how the behavior was established: [`docs/research/`](docs/research/)
- contributing: [CONTRIBUTING.md](CONTRIBUTING.md)

## License

MIT for this project's original contributions ([LICENSE](LICENSE)). The stock
app and Creative's trademarks are not covered; see [NOTICE.md](NOTICE.md) and
[PROVENANCE.md](docs/PROVENANCE.md).
