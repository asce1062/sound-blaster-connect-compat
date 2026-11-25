# SBConnect bring-up pipeline

> **Historical record.** Kept as evidence of how behavior was established; not updated for later changes. Status, corrections and the maintained references: [research index](../README.md).

The decode -> patch -> rebuild -> sign pipeline for the Sound Blaster Connect
APK, and the recorded evidence for its two mutually exclusive outputs. This
lane is **APK packaging / Android compatibility only** — it does not touch
CtProtocol or any native code. The native libraries ship unchanged; arm64 is a
separate lane and **no arm64 support is claimed here**.

## Variants

| Variant | Intent | targetSdk | Native libs | Code/manifest patches | Build path |
|---|---|---|---|---|---|
| `resign` | payload-preserving signing control | 26 (original) | original, byte-identical | none | copy stock + re-sign (no apktool) |
| `modernize` | Android 12/13/14 compatibility | 34 | original, byte-identical | manifest + smali (see `COMPAT_MATRIX.md`) | apktool decode -> patch -> rebuild -> sign |

Both are 32-bit-only outputs: they run only on devices that can execute the
original 32-bit native libraries.

`resign` is a **payload-preserving signing control**: the stock archive is
copied verbatim (aligned once only if the stock were not already aligned) and
re-signed with a debug key. It does not go through apktool, so no resource,
manifest, or dex bytes are re-encoded. Every non-signature ZIP entry is proven
SHA-256 identical to stock at build time (see *resign — payload-preserving*
below); the build fails if any payload byte differs. This isolates
signing/distribution from every other change. `modernize` keeps the
decode -> patch -> rebuild path, so its differences from stock are attributable
to the documented patches plus the apktool round-trip.

## Inputs (pinned, SHA-256 verified at configure time)

| Input | SHA-256 |
|---|---|
| `SBConnect_v1.04.02.apk` (stock) | `fe1ffe0c93b6476ae6ed1d2cb6891cde2fbe206d4e898d6ad8c75222e9bf99be` |
| `apktool_3.0.3.jar` | `dbf930b076c6b9be08d57c449cacefc3bdd6b71ebd59b3066fc0e1f5b14f9423` |
| `uber-apk-signer-1.3.0.jar` | `e1299fd6fcf4da527dd53735b56127e8ea922a321128123b9c32d619bba1d835` |

The stock APK is tracked with git-lfs; run `git lfs pull` before the first
build. `CMakeLists.txt` fails the configure if any hash does not match.

## Build (reproducible)

CMake 3.22.1 + Ninja ship inside the Android SDK and are not on `PATH`. Add
`<sdk>/cmake/3.22.1/bin`, `<sdk>/cmake/3.10.2.4988404/bin`, and
`<sdk>/platform-tools` (for `adb`). Java 17+ is required by apktool 3.x
(Java 23 was used here).

`zipalign` from the Android build-tools is required by `resign` (alignment
check); pass `-Dzipalign_bin=<sdk>/build-tools/<ver>/zipalign` if it is not on
`PATH`.

```bash
cmake --preset default            # verify input, fetch+verify tools, generate
cmake --build build --target decode   # apktool d -> decompiled/ (modernize only)
cmake --build --preset resign     # -> build/sbc_resign-aligned-debugSigned.apk
cmake --build --preset modernize  # -> build/sbc_modernize-aligned-debugSigned.apk
```

`modernize` stages a fresh copy of the pristine `decompiled/` tree, applies its
patch set, runs `apktool b`, then signs with uber-apk-signer's debug key.
`decompiled/` is never mutated, so the output is independent and repeatable.

`resign` does **not** use `decompiled/` or apktool. `cmake/resign_control.cmake`
copies the stock APK verbatim (or aligns it once with `zipalign -p 4` if the
stock were not already aligned), then re-signs with uber-apk-signer
(`--skipZipAlign`, since the input is already aligned). `cmake/resign_verify.cmake`
then extracts both archives and compares the SHA-256 of every entry's
uncompressed bytes; the build fails unless all non-signature entries are
identical to stock.

### Deploy (optional, needs a device)

```bash
cmake --build build --target deploy                      # installs resign
cmake --build build --target deploy -Ddeploy_variant=modernize
```

## Outputs

| Output | SHA-256 | Size |
|---|---|---|
| `sbc_resign-aligned-debugSigned.apk` | `b9de84fed512d02f658797702a6a69745fecc7ca6722b441d035e7302d45fae9` | 47,351,234 |
| `sbc_modernize-aligned-debugSigned.apk` | (apktool rebuild; machine-specific, see note) | ~47,476,506 |

Output hashes are not reproducible bit-for-bit across machines, for different
reasons per variant:
- `resign` copies the stock archive verbatim, so its only non-stock bytes are
  the signature, which is produced from the **per-machine debug keystore**
  (`~/.android/debug.keystore`). The hash above is this machine's; another
  machine's debug key yields a different signature and hash. The payload is
  identical regardless (proven below).
- `modernize` additionally varies because apktool's aapt2 resource compile is
  not byte-stable.

The stable contract is the evidence below (metadata, ABI, per-entry SHA-256
payload identity, signature verification), not the output hash.

## Evidence

### Package / version metadata (aapt2 dump badging)

| | stock | resign | modernize |
|---|---|---|---|
| package | com.creative.apps.sbconnect | same | same |
| versionCode | 10402 | 10402 | 10402 |
| versionName | 1.04.02 | 1.04.02 | 1.04.02 |
| minSdkVersion | 14 | 14 | 14 |
| targetSdkVersion | 26 | **26** | **34** |

`resign` leaves package, version and target SDK exactly as stock.

### ABI inventory (native-code)

All three carry the identical set, 32-bit only:

```
armeabi   armeabi-v7a   x86   utility
```

No `arm64-v8a`, no `x86_64` in any output. Neither variant adds or removes an
ABI.

### resign — payload-preserving (SHA-256 per uncompressed entry)

`cmake/resign_verify.cmake` extracts the stock APK and the signed `resign`
output and compares the **SHA-256 of every ZIP entry's uncompressed bytes**.
Only signature-related entries are allowed to differ
(`META-INF/MANIFEST.MF`, `META-INF/*.SF`, `META-INF/*.RSA/*.DSA/*.EC`); the
v2/v3 APK Signing Block is not a ZIP entry and never appears. The build fails
if any other entry is missing, extra, or differs. This runs on every `resign`
build and is the proof, not a diagnostic.

Result (this build):

| Category | entries | SHA-256 identical to stock |
|---|---|---|
| `lib/**` (native) | 6 | 6 / 6 |
| `classes*.dex` | 2 | 2 / 2 |
| `resources.arsc` | 1 | 1 / 1 |
| `res/**` | 4270 | 4270 / 4270 |
| `assets/**` | 0 | 0 / 0 |
| other (non-signature `META-INF/**`, etc.) | 28 | 28 / 28 |
| **total (non-signature)** | **4307** | **4307 / 4307** |

The pre-sign staged copy's SHA-256 equals the stock APK's exactly
(`fe1ffe0c…`), confirming the archive is copied verbatim before signing. The
two JNI libraries (`libsbxapplogic_ctprotocol_jni.so`, `libserialport_jni.so`)
and all of `lib/`, dex, `resources.arsc`, and `res/**` are byte-for-byte
unchanged. **`resign` is therefore a payload-preserving signing control: the
entire archive excluding the signature is proven byte-identical to stock.**
(CRC-32 remains available as a quick diagnostic, but the SHA-256 per-entry
comparison above is the acceptance proof.)

### modernize — resources / dex NOT byte-preserved (disclosure)

`modernize` keeps the apktool decode -> rebuild path, which re-encodes
everything that is not a raw passthrough file. The native libraries are still
passed through unchanged (SHA-256 identical, all 6 `lib/` entries), but the rest
is re-serialized:

| Artifact | stock vs modernize | Nature of change |
|---|---|---|
| `lib/**` | identical (SHA-256, 6/6) | passthrough, not recompiled |
| `resources.arsc` | differs | re-serialized by aapt2 |
| `res/` tree | ~953 of 990 same-named entries differ; ~3280 entries renamed | aapt2 re-compiles and re-mangles resource paths |
| `AndroidManifest.xml` | differs | re-compiled to binary XML (plus the targetSdk/permission/exported edits) |
| `classes.dex` / `classes2.dex` | differs | baksmali -> smali round-trip re-assembles dalvik bytecode (plus the FLAG_IMMUTABLE edits) |

This is expected for `modernize` and is why `resign` exists as the control:
`resign` proves the signing step alone changes nothing, so any behavior
difference in `modernize` is attributable to its documented patches (and the
apktool round-trip), never to signing.

### Signing

| | stock | resign / modernize |
|---|---|---|
| Certificate DN | CN=Creative Technology Ltd., O=Creative Technology Ltd., L=Singapore, C=SG | C=US, O=Android, CN=Android Debug |
| Cert SHA-256 | `549a10ca103aa35a6f120c00f081c9a8e33911715a302f2251ccd74f407052e4` | `665d62c0db7db08aa52b50825e2a45992aaa0056d82a80a6d1bc491ce2c54202` |
| Cert SHA-1 | `a0717041a23267c32658960ffa342af171de4604` | `112a61fa35193e9b5cc48bce63e8bbf0cebbae76` |
| Schemes | v1 only | v1 + v2 + v3 |

The original Creative signing block (`META-INF/CERT.RSA`/`CERT.SF`) is replaced
by the debug key (`META-INF/ANDROIDD.RSA`/`ANDROIDD.SF`), and `MANIFEST.MF` is
regenerated. The Creative private key is not available; these outputs are
**sideload-only**. For `resign`, every non-signature `META-INF/` entry
(INDEX.LIST, license/*, kotlin modules, io.netty.versions) is among the 28
"other" entries proven SHA-256 identical to stock above.

Stock and output certificate fingerprints are recorded separately in the table
above: stock is the Creative release certificate (v1-only); both outputs carry
the Android debug certificate (v1+v2+v3).

### Signature verification (Android SDK apksigner)

```
resign     Verifies   v1: true  v2: true  v3: true   (exit 0)
modernize  Verifies   v1: true  v2: true  v3: true   (exit 0)
```

uber-apk-signer independently reported `signature verified [v1, v2, v3]` for
both. `resign` is signed with `--skipZipAlign`; its 4-byte/page alignment is
checked separately with `zipalign -c -p 4` on both the stock input and the
signed output (both pass). `modernize` is zipaligned by uber-apk-signer.

## Design note — why resign bypasses apktool

An earlier iteration routed `resign` through the same apktool decode -> rebuild
path as `modernize` with an empty patch set. That made it a *semantic* control
(equivalent app, re-signed) but not a payload-preserving one: the apktool
round-trip re-encoded `resources.arsc`, `res/**`, and the dex even with zero
patches, so it was not "only the signature changed".

`resign` now copies the stock archive and re-signs it directly
(`cmake/resign_control.cmake`), skipping apktool entirely, and the build proves
per-entry SHA-256 payload identity (`cmake/resign_verify.cmake`). This gives a
true payload-preserving signing control: the only differences from stock are
the signature entries and the v2/v3 signing block. `modernize` keeps the
apktool path because its job is controlled Android-compatibility modification,
not byte preservation.

## Verification status

No 32-bit-capable Android 13/14 device was attached for this work (`adb devices`
was empty). All evidence above is **static/structural** (aapt2, apksigner, and
per-entry SHA-256 for `resign`). Install and launch were **not** confirmed on
hardware. See the test-result column in `COMPAT_MATRIX.md`.
