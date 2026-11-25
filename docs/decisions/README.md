# Architecture decisions

Each record states one decision with lasting consequences: the context that
forced it, the decision, and what follows from it. A decision is changed by a
new record that supersedes the old one, not by editing it.

| # | Decision | Status |
|---|---|---|
| [0001](0001-portable-protocol-core.md) | Keep all protocol behavior in a portable, JNI-free C core | Accepted |
| [0002](0002-differential-testing.md) | Accept the reimplementation only by differential testing against the stock library | Accepted |
| [0003](0003-native-android-separation.md) | Separate native-library work from Android packaging work | Accepted |
| [0004](0004-native-from-pinned-source.md) | Build native libraries from source with a pinned NDK; track no binaries | Accepted |
| [0005](0005-source-and-binary-distribution.md) | Offer both source builds and signed binaries as first-class outputs | Accepted, not yet implemented |
| [0006](0006-resign-bypasses-apktool.md) | Build the `resign` control without apktool | Accepted |
| [0007](0007-component-export-hardening.md) | Narrow manifest component exports; keep stock exposure for runtime receivers | Accepted |
| [0008](0008-separate-distribution-identity.md) | Distribute under a separate application ID; keep stock-identity controls | Accepted |
| [0009](0009-version-scheme.md) | Derive all version metadata from the CMake project version | Accepted |
| [0010](0010-16k-page-alignment.md) | Align 64-bit native libraries to 16 KiB with a linker flag | Accepted |

Release signing will be recorded once it is established.

Template: Context, Decision, Consequences, Status. Keep records short and
link to the technical reference or research record that holds the detail.
