# Documentation

| Section | For | Contents |
|---|---|---|
| [user/](user/) | people installing the app | [INSTALLATION.md](user/INSTALLATION.md): which variant, install, first launch, troubleshooting |
| [development/](development/) | people building or changing the project | [BUILDING.md](development/BUILDING.md), [TESTING.md](development/TESTING.md), [ARCHITECTURE.md](development/ARCHITECTURE.md), [TOOLCHAIN.md](development/TOOLCHAIN.md), [SIGNING.md](development/SIGNING.md), [RELEASE.md](development/RELEASE.md), [PLAY_PROTECT_REVIEW.md](development/PLAY_PROTECT_REVIEW.md) |
| [technical/](technical/) | anyone reimplementing or verifying behavior | maintained contracts, each claim marked with its evidence basis |
| [decisions/](decisions/) | maintainers | architecture decision records |
| [research/](research/) | anyone checking how behavior was established | historical research and validation records, errata, frozen-evidence checksums |
| [PROVENANCE.md](PROVENANCE.md) | anyone checking where the contents come from | origin of each kind of content, license scope, what the published history contains |

## Technical references

| Reference | Covers |
|---|---|
| [CTPROTOCOL.md](technical/CTPROTOCOL.md) | Command frame format, encoder builders, decoder dispatch, preserved stock quirks |
| [JNI_INTERFACE.md](technical/JNI_INTERFACE.md) | Native methods of the stock Java class, marshalling rules, callbacks |
| [NATIVE_LIBRARIES.md](technical/NATIVE_LIBRARIES.md) | The two native libraries, ABIs, build reproducibility, test coverage |
| [ANDROID_COMPATIBILITY.md](technical/ANDROID_COMPATIBILITY.md) | What each variant changes, per Android platform rule |
| [PERMISSIONS.md](technical/PERMISSIONS.md) | Permissions, component exports, runtime receivers, signing identity |
| [APPLICATION_IDENTITY.md](technical/APPLICATION_IDENTITY.md) | The `compat` application ID, label and version scheme, and the package-dependence audit |

## Which document to update

Git history records how the software evolved. Research records explain how
behavior was established. Source comments explain why the current
implementation works as it does. Technical documentation describes the
contracts that future implementations must preserve. Details in
[CONTRIBUTING.md](../CONTRIBUTING.md).
