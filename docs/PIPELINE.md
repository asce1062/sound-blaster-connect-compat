# SBConnect bring-up pipeline

The decode -> patch -> rebuild -> sign pipeline for the Sound Blaster Connect
APK, and the recorded evidence for its two mutually exclusive outputs. This
lane is **APK packaging / Android compatibility only** — it does not touch
CtProtocol or any native code. The native libraries ship unchanged; arm64 is a
separate lane and **no arm64 support is claimed here**.

## Variants

| Variant | Intent | targetSdk | Native libs | Code/manifest patches |
|---|---|---|---|---|
| `resign` | semantic control | 26 (original) | original, byte-identical | none |
| `modernize` | Android 12/13/14 compatibility | 34 | original, byte-identical | manifest + smali (see `COMPAT_MATRIX.md`) |

Both are 32-bit-only outputs: they run only on devices that can execute the
original 32-bit native libraries.

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

```bash
cmake --preset default            # verify input, fetch+verify tools, generate
cmake --build build --target decode   # apktool d -> decompiled/ (pristine)
cmake --build --preset resign     # -> build/sbc_resign-aligned-debugSigned.apk
cmake --build --preset modernize  # -> build/sbc_modernize-aligned-debugSigned.apk
```

Each variant stages a fresh copy of the pristine `decompiled/` tree, applies
its patch set (`resign` applies none), runs `apktool b`, then zipaligns and
signs with uber-apk-signer's debug key. `decompiled/` is never mutated, so the
two outputs are independent and the build is repeatable.

### Deploy (optional, needs a device)

```bash
cmake --build build --target deploy                      # installs resign
cmake --build build --target deploy -Ddeploy_variant=modernize
```

## Outputs

| Output | SHA-256 | Size |
|---|---|---|
| `sbc_resign-aligned-debugSigned.apk` | `90e9ec6ece16401a2fd1ef155a9893ecfbf0c5b3890fcba823aa87295bcb6516` | 47,476,506 |
| `sbc_modernize-aligned-debugSigned.apk` | `0e0b5b00bce5446d38b386f792b919f257833876e939f6fa670d61e8b4b7b013` | 47,476,506 |

Output hashes are not reproducible bit-for-bit across machines: apktool's aapt2
resource compile and the signing timestamps vary. The evidence below (metadata,
ABI, native-lib CRC, signature) is the stable contract.

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

### Native libraries — byte-identity (zip CRC-32, all lib/ entries)

Comparing the stock APK against each output at the zip level (CRC-32 is over
the uncompressed bytes, so it proves content identity independent of the
compression method):

| Comparison | lib/ entries | content differs | compression-only differs |
|---|---|---|---|
| stock vs resign | 6 / 6 common | **0** | 0 |
| stock vs modernize | 6 / 6 common | **0** | 0 |

**Confirmed: neither variant alters any native library.** The two JNI
libraries (`libsbxapplogic_ctprotocol_jni.so`, `libserialport_jni.so`) and the
rest of `lib/` are passed through unchanged.

### Application resources / dex — NOT byte-preserved (disclosure)

The apktool decode -> rebuild round-trip re-encodes everything that is not a
raw passthrough file, in **both** variants, including `resign`:

| Artifact | stock vs resign | Nature of change |
|---|---|---|
| `resources.arsc` | CRC differs | re-serialized by aapt2 |
| `res/` tree | ~953 of 990 same-named entries differ; ~3280 entries renamed | aapt2 re-compiles and re-mangles resource paths |
| `AndroidManifest.xml` | CRC differs | re-compiled to binary XML |
| `classes.dex` / `classes2.dex` | CRC differs (`149b5af7`->`e7593b2c`, `73253dcf`->`820857a9`) | baksmali -> smali round-trip re-assembles dalvik bytecode |

`resign` applies **zero** patches, so these differences are semantic no-ops
(equivalent resources and bytecode, different bytes). They are a property of
the apktool toolchain, not a targeted edit. **This means `resign` is a
semantic control, not a byte-level control:** it isolates "stock behavior,
re-signed" but it is not "only the signature changed". See
*Open decision* below.

### Signing

| | stock | resign / modernize |
|---|---|---|
| Certificate DN | CN=Creative Technology Ltd., O=Creative Technology Ltd., L=Singapore, C=SG | C=US, O=Android, CN=Android Debug |
| Cert SHA-256 | `549a10ca103aa35a6f120c00f081c9a8e33911715a302f2251ccd74f407052e4` | `665d62c0db7db08aa52b50825e2a45992aaa0056d82a80a6d1bc491ce2c54202` |
| Cert SHA-1 | `a0717041a23267c32658960ffa342af171de4604` | `112a61fa35193e9b5cc48bce63e8bbf0cebbae76` |
| Schemes | v1 only | v1 + v2 + v3 |

The original Creative signing block (`META-INF/CERT.RSA`/`CERT.SF`) is replaced
by the debug key (`META-INF/ANDROIDD.RSA`/`ANDROIDD.SF`). The Creative private
key is not available; these outputs are **sideload-only**. All other
`META-INF/` entries (MANIFEST.MF, INDEX.LIST, license/*, kotlin modules,
io.netty.versions) are preserved.

### Signature verification (Android SDK apksigner)

```
resign     Verifies   v1: true  v2: true  v3: true   (exit 0)
modernize  Verifies   v1: true  v2: true  v3: true   (exit 0)
```

uber-apk-signer independently reported `signature verified [v1, v2, v3]` for
both, with zipalign verified.

## Open decision — byte-level control

If the lane needs a true byte-level control (stock app with **only** the
signature changed, no resource/dex re-encoding), the `resign` target would have
to re-sign the stock APK directly (`zipalign` + `apksigner` on
`SBConnect_v1.04.02.apk`, skipping apktool entirely). That is a change to the
pipeline wiring (`CMakeLists.txt` / `cmake/sbc_patches.cmake`), which this lane
has not made unprompted. The current apktool-based `resign` is retained because
it shares the exact decode/rebuild path with `modernize`, so differences
between the two are attributable to the documented patches alone and nothing
else in the toolchain.

## Verification status

No 32-bit-capable Android 13/14 device was attached for this work (`adb devices`
was empty). All evidence above is **static/structural** (aapt2, apksigner, zip
CRC). Install and launch were **not** confirmed on hardware. See the test-result
column in `COMPAT_MATRIX.md`.
