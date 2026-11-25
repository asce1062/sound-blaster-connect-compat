# APP_IDENTITY

> **Historical record.** Kept as evidence of how behavior was established; not updated for later changes. Status, corrections and the maintained references: [research index](../README.md).

Phase 5A record of the modernized arm64 build's identity and signing, against the
stock `SBConnect_v1.04.02.apk`. Covers package identity, version, SDK range, and
the signing certificate and scheme, with the distribution implications of each.

## Identity (unchanged from stock)

| Field | Value | Note |
|---|---|---|
| Package | `com.creative.apps.sbconnect` | Unchanged. Same package as stock, so it is the same app identity to the system. |
| versionName | `1.04.02` | Unchanged. |
| versionCode | `10402` | Unchanged. No version bump; the rebuild is the same release, re-targeted. |
| minSdkVersion | 14 | Unchanged. |
| targetSdkVersion | 34 | Raised from 26 by the modernize patch. |
| Label | `@string/app_name` (Sound Blaster Connect) | Unchanged. |

The package name, version, and user-facing identity are deliberately held
identical to stock: this is a bring-up of the same app, not a fork or a rename.
The only identity-level change is the signing key, below.

## Signing certificate

| | Stock | Rebuilt (arm64) |
|---|---|---|
| Subject (DN) | `CN=Creative Technology Ltd., OU=Creative Technology Ltd., O=Creative Technology Ltd., L=Singapore, ST=Singapore, C=SG` | `C=US, O=Android, CN=Android Debug` |
| Key algorithm | RSA 2048 | RSA 2048 |
| Certificate SHA-256 | `549a10ca103aa35a6f120c00f081c9a8e33911715a302f2251ccd74f407052e4` | `665d62c0db7db08aa52b50825e2a45992aaa0056d82a80a6d1bc491ce2c54202` |
| Certificate SHA-1 | `a0717041a23267c32658960ffa342af171de4604` | `112a61fa35193e9b5cc48bce63e8bbf0cebbae76` |
| Signer | Creative's release key | Android debug key (uber-apk-signer default) |

The rebuild is signed with the **standard Android debug key**, the well-known
`CN=Android Debug` certificate that every SDK install can produce. It is not a
secret and asserts nothing about origin: anyone can mint the same subject DN
(though not the same exact certificate). It is appropriate for a sideloaded
bring-up and is **not** a distribution-grade identity.

## Signing scheme

| Scheme | Stock | Rebuilt |
|---|---|---|
| v1 (JAR) | yes | yes |
| v2 (APK Signature Scheme v2) | no | yes |
| v3 (APK Signature Scheme v3) | no | yes |

On device the rebuild reports `apkSigningVersion=4` (v4 incremental signature
present alongside v2/v3). Stock is **v1-only**. The v2+ signing requirement binds
at targetSdk 30+: the rebuild targets 34, so a v2+ signature is mandatory, and
the v2+v3 schemes present satisfy it. Stock's v1-only signature is accepted at
its own targetSdk 26 where the ABI matches, but a v1-only signature becomes
insufficient the moment the app is re-targeted to 34, so the rebuild had to gain
v2+v3 regardless of the ABI work.

## Implications

1. **No in-place update over a stock install.** Different signing certificates
   mean the system treats the rebuild as signed by a different author.
   `INSTALL_FAILED_UPDATE_INCOMPATIBLE` results if a Creative-signed copy is
   present; the stock app must be uninstalled first. (Moot on the 64-bit-only
   target, where stock cannot install at all.)

2. **No origin attestation.** The debug certificate does not bind the build to
   Creative or to this project. It proves only that whoever signed it held the
   public debug key. Consumers of the APK cannot use the signature to establish
   provenance.

3. **Signature-gated permissions stay ungranted.** Permissions at protection
   level `signature` or `signature|privileged` (for example
   `MEDIA_CONTENT_CONTROL`) are never granted to a debug-signed sideload. See
   `PERMISSION_AUDIT.md`.

4. **Play Protect treats it as an unknown-developer app.** A debug-signed
   package with no known-good signer and no Play Store installer record is the
   exact profile Play Protect scrutinizes on a user-driven sideload. Behavior and
   observations are tracked in `PLAY_PROTECT_MATRIX.md`; this project does not
   disable or work around Play Protect.

## If a stable identity is wanted later

For a build meant to be reinstalled across devices or kept through updates
without the debug-key caveats, generate a dedicated project keystore once and
sign every build with it. That gives a stable, self-consistent signer (still not
Creative's, so still a distinct author from stock) and a fingerprint that can be
allow-listed. This is a packaging decision, not a code change, and is out of
scope for the bring-up grade; recorded here as the known next step for
distribution.

## Cross-references

- Signing toolchain (uber-apk-signer debug key): `CMakeLists.txt`,
  `cmake/resign_control.cmake`.
- Permission protection levels: `PERMISSION_AUDIT.md`.
- Play Protect behavior for this signer: `PLAY_PROTECT_MATRIX.md`.
