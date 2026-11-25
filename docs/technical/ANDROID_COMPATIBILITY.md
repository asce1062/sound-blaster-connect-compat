# Android compatibility

This document describes, per build variant, what the pipeline changes in the stock Sound Blaster Connect 1.04.02 APK (package `com.creative.apps.sbconnect`, versionCode 10402, minSdk 14, targetSdk 26, 32-bit native libraries only) and what it leaves byte-identical. The `resign` variant re-signs the stock archive without re-encoding it. The `modernize` variant raises targetSdk to 34 through an apktool decode, manifest and smali patches, and three smali shim classes. The `arm64` variant is `modernize` plus `arm64-v8a` native libraries built from source. The `compat` variant is `arm64` with its own application ID, label and version. Each claim carries a verification basis tag, and the sections at the end list known stock-app defects, limits, and statements in older records that this document supersedes. Permission and component-export detail is in [PERMISSIONS.md](PERMISSIONS.md).

## Verification basis

| Tag | Meaning |
|---|---|
| **Build** | Enforced by the build: an anchor or site count asserted in [patch.cmake](../../patches/modernize/patch.cmake), a configure check, or the `resign` payload comparison. A drift fails the variant build. |
| **Device** | Observed on hardware, per [ARM64_RUNTIME.md](../research/arm64/ARM64_RUNTIME.md) and the acceptance matrices in [RECEIVER_AUDIT.md](../research/android/RECEIVER_AUDIT.md). Raw runtime logs were not preserved; only the excerpts in [runtime/](../research/arm64/runtime/) exist. |
| **Emulator** | Observed on the Android emulator (Pixel 3a AVD, API 30, x86 image). No Katana; the x86 libraries run, not `arm64-v8a`. |
| **Static** | Read from code, the built manifest, or a recorded structural check (aapt2, apksigner). Not executed. |
| **Expected** | Platform documentation or inference. Not observed in this project. |

Hardware coverage is two devices: a Pixel 7a (Android 13, API 33, 64-bit only) and a Galaxy S24 Ultra (64-bit only), each with one Sound BlasterX Katana speaker. The S24 Ultra ran Android 16 (API 36) for the `arm64` records and Android 17 (API 37) for the `compat` run. No 32-bit-capable device was ever tested, so every statement that `resign` or `modernize` installs or runs on a 32-bit device is **Expected**. No device at API 31, 32, 34 or 35 was tested; the API 34 rules were exercised through the API 36 device.

## Variants at a glance

| Aspect | `resign` | `modernize` | `arm64` |
|---|---|---|---|
| Build path | Stock archive copied, aligned only if needed, re-signed. No apktool. | Fresh copy of the apktool-decoded tree, patches applied, `apktool b`, sign. | Same as `modernize` with the `arm64` patch applied after it. |
| targetSdk | 26 (stock) | 34 | 34 |
| minSdk, package, versionCode, versionName | Stock | Stock (**Static**, aapt2 badging) | Stock (**Static**) |
| Manifest, dex, resources | Byte-identical to stock (**Build**) | Re-encoded by apktool; manifest and dex carry the patches (**Static**) | Same as `modernize` |
| Native libraries | Stock 32-bit set, byte-identical (**Build**) | Stock 32-bit set, identical per recorded comparison (**Static**) | Stock set plus `lib/arm64-v8a/` with two libraries |
| Signature | Android debug key, v1+v2+v3 | Same | Same |
| Runs on | 32-bit-capable devices only (**Expected**) | 32-bit-capable devices only (**Expected**) | 64-bit-only devices (**Device**); 32-bit devices **Expected** |

The `compat` variant is `arm64` under its own application ID and version; it
is described [below](#compat-distribution-identity).

Pinned tools (**Build**, SHA-256 verified at configure): apktool 3.0.3, uber-apk-signer 1.3.0. The stock APK must match the pinned SHA-256 `fe1ffe0c...f99be` or configure fails. Outputs are not bit-for-bit reproducible across machines: signatures depend on the signing key, and aapt2 resource compilation is not byte-stable (**Static**, recorded in [PIPELINE.md](../research/android/PIPELINE.md)).

## `resign`: payload-preservation contract

`cmake/resign_control.cmake` runs `zipalign -c -p 4` on the stock APK. If aligned, the archive is copied verbatim; otherwise it is aligned once with `zipalign -p 4 -f` (no recompression). It then signs with uber-apk-signer using `--skipZipAlign --allowResign` and requires the signed output to still pass `zipalign -c -p 4`. All of this is **Build**.

`cmake/resign_verify.cmake` then extracts the stock and signed archives and compares them. The variant build fails on any difference listed under "Enforced".

| | Enforced (**Build**) | Not compared |
|---|---|---|
| Entry set | Every non-signature entry in stock is present in the output; no extra non-signature entry exists in the output | Directory entries and empty directories (the comparison lists files only) |
| Entry content | SHA-256 of each entry's uncompressed bytes is identical | Compressed bytes and compression method of each entry |
| Signature files | Excluded from comparison: `META-INF/MANIFEST.MF` and `META-INF/*.SF`, `*.RSA`, `*.DSA`, `*.EC` (single level) | Their content; they are replaced (`MANIFEST.MF` regenerated, Creative `CERT.*` replaced by the debug-key `ANDROIDD.*`) |
| APK Signing Block (v2/v3) | Not a ZIP entry; never compared | Present only in the output |
| ZIP structure | Output must be 4-byte/page aligned per `zipalign -c -p 4` | Entry order, offsets, extra fields, central directory, timestamps, comments |

A recorded run compared 4307 non-signature entries, all identical: 6 under `lib/`, 2 dex, 1 `resources.arsc`, 4270 under `res/`, 0 under `assets/`, 28 other (**Build** at the time of that run; the count is a record, not an assertion). The pre-sign staged copy had the same SHA-256 as the stock APK, so the stock archive was already aligned and was copied verbatim (**Static**, recorded).

`resign` changes the signer only. Because the signer changes, the installed package cannot update a Creative-signed install (see [PERMISSIONS.md](PERMISSIONS.md), signing identity). `resign` keeps working on API 31 to 34 only because an app that targets API 26 is exempt from rules keyed to the target SDK (**Expected**). It does not change the 32-bit-only limitation: on the Pixel 7a it fails with `INSTALL_FAILED_NO_MATCHING_ABIS` (`res=-113`) (**Device**).

## `modernize`: transformations

`patches/modernize/patch.cmake` runs on a fresh staged copy of the decoded tree; the three shim classes are copied in from `patches/modernize/overlay/smali/com/creative/apps/sbconnect/` first. Every literal substitution goes through `_sbc_sub`, which aborts the variant build unless the anchor occurs exactly the stated number of times, so stock-text drift fails loudly. That count assertion is the **Build** basis for each row; the Device and Expected tags in the last column refer to runtime behavior.

| # | Platform rule | Patch change | Shim | Verification |
|---|---|---|---|---|
| 1 | Behavior changes are keyed to targetSdk; raising it opts into API 31, 33 and 34 rules | `apktool.yml`: `targetSdkVersion: 26` -> `34` (anchor count 1) | none | **Build** (anchor). **Static**: built manifest reports 34 |
| 2 | API 31: a component with an `<intent-filter>` must declare `android:exported` or the package fails to parse | Explicit `android:exported` added to `MainActivity` (true), `MainReceiver` (false), `LocalMusicRemoteControllerService` (true), `MediaButtonReceiver` (false), `AppMeasurementReceiver` (false); stock `MainService` `exported="true"` flipped to `false`. Six anchors, one occurrence each. Rationale per component in [PERMISSIONS.md](PERMISSIONS.md) | none | **Build** (six anchors). **Static**: values present in built manifest. **Device** (Galaxy S24 Ultra, API 36): app installs; `MainReceiver` receives `BOOT_COMPLETED` and `MainService` starts as a foreground service with both set to `false`. `MediaButtonReceiver` not exercised (no active media session) |
| 3 | API 31: `PendingIntent` creation without `FLAG_IMMUTABLE` or `FLAG_MUTABLE` throws `IllegalArgumentException` | `FLAG_IMMUTABLE` (0x04000000) OR-ed into the flags of all 23 construction sites (breakdown below) | none | **Build** (23 sites, each anchor counted). **Device**: the app's own `MainService` notification path runs on the Pixel 7a and S24 Ultra. Bundled library sites **Static** only |
| 4 | Register clobber in `MainService.a()` (a defect the naive form of row 3 introduces) | Two `getActivity` sites take flags from `v14`, which already holds 0x04000000, instead of loading the constant into `v11`. `v11` is the method's shared zero, later used as an `ArrayList` index and as the `setAutoCancel` boolean | none | **Build** (two anchors). **Device** (Pixel 7a): loading the constant into `v11` produced `IndexOutOfBoundsException: Index: 67108864`; the `v14` form runs |
| 5 | API 31: legacy `BLUETOOTH` and `BLUETOOTH_ADMIN` no longer grant discovery or connection; runtime `BLUETOOTH_SCAN` and `BLUETOOTH_CONNECT` are required | `BLUETOOTH` and `BLUETOOTH_ADMIN` gain `maxSdkVersion="30"`; `BLUETOOTH_SCAN` and `BLUETOOTH_CONNECT` added (anchors 1 each) | see row 11 | **Build**. **Static**: aapt2 badging shows the caps. **Device** (S24 Ultra): granted at runtime, device connects |
| 6 | API 33: notifications need runtime `POST_NOTIFICATIONS` | `POST_NOTIFICATIONS` added to the manifest | see row 11 | **Build**. **Device** (S24 Ultra): requested in the chain and granted |
| 7 | API 34: a foreground service must declare a type and hold the matching `FOREGROUND_SERVICE_*` permission | `FOREGROUND_SERVICE` and `FOREGROUND_SERVICE_MEDIA_PLAYBACK` added; `MainService` gets `android:foregroundServiceType="mediaPlayback"` (anchor 1). `MainService` uses the two-argument `startForeground`, so it adopts the manifest type. `mediaPlayback` has no dangerous-permission prerequisite, so the service can start before the Bluetooth grants | none | **Build**. **Device** (S24 Ultra): `isForeground=true`, type `mediaPlayback`. Failure without the change (`MissingForegroundServiceTypeException`) is **Expected** |
| 8 | API 28: `org.apache.http.legacy` and `android.test.base` (holding `junit.framework.*`) left the default bootclasspath | Two `<uses-library ... android:required="false"/>` entries inserted as the first children of `<application>` (anchor 1). `required=false` keeps install working where a library is absent. `JSONParser` uses `DefaultHttpClient`; `Utils.b()` calls `junit.framework.Assert`, reached when `ProfileListAdapter.onBindViewHolder` binds a preset row | none | **Build**. **Device** (Pixel 7a): the classloader namespace includes `org.apache.http.legacy.jar`; before the change, opening "See All" or "Blaster Experience" preset lists crashed with `NoClassDefFoundError: junit.framework.Assert` (excerpt in `runtime/junit_crash_excerpt.txt`), and after it the preset screens open without a crash. The Apache failure itself has no preserved log |
| 9 | API 26 requires a notification channel; API 33 kills the process when `startForeground` posts a channel-less notification (`CannotPostForegroundServiceNotificationException`) | `FgChannelCompat.ensure(Context, NotificationCompat.Builder)` is called after each of the two `NotificationCompat.Builder(Context)` constructions in `MainService.a()` (anchors 1 each, builder in `v3` and `v5`). It calls `setChannelId("sbconnect_fg")` and, on API 26+, creates channel `sbconnect_fg` named "Sound Blaster Connect" with importance 2 (low). Creation is idempotent | `FgChannelCompat` | **Build** (two sites). **Device**: process kill reproduced and fixed on the Pixel 7a; the S24 Ultra shows the service in channel `sbconnect_fg` |
| 10 | API 34: `registerReceiver` for a non-system broadcast must pass `RECEIVER_EXPORTED` or `RECEIVER_NOT_EXPORTED`; the two-argument form throws `SecurityException` on a 34+ device when the app targets 34+ | Every two-argument `registerReceiver(BroadcastReceiver, IntentFilter)` invoke in every dex and package is rewritten to `invoke-static` of `RcvCompat.register(Context, BroadcastReceiver, IntentFilter)`. The register tuple is preserved; only opcode and method reference change. `RcvCompat.smali` itself is skipped. **96 sites**, asserted: the build fails if the total differs or any site survives. On API 34+ the shim calls the three-argument form with `RECEIVER_EXPORTED` (0x2); below 34 it calls the original two-argument form | `RcvCompat` | **Build** (96 sites). **Device** (S24 Ultra, API 36): launch without a crash, Dashboard reached. The Pixel 7a (API 33) never raised the error. Before the change the launch crashed in `MainActivity.onCreate` (`LocalMusicManager`), then in `onStart`; a further site in the bundled `ibluz` library (`smali/c`) threw a swallowed `SecurityException` that left the device stuck "in use". Export rationale in [PERMISSIONS.md](PERMISSIONS.md) |
| 11 | API 31 and 33: Bluetooth and notification permissions are runtime-granted; the stock app never calls `requestPermissions` for them, so Bluetooth calls throw `SecurityException` and no device is found | `BtPermCompat` request chain wired from `MainActivity.onRequestPermissionsResult` (one anchor: a call to `BtPermCompat.onResult` inserted after the `invoke-super`). Chain: stock batch (request code 0x457, started by the stock `onCreate` path) returns -> `ensure()` requests `BLUETOOTH_CONNECT` and `BLUETOOTH_SCAN` (0x42c) -> `askNotif()` requests `POST_NOTIFICATIONS` (0x42d, API 33+) -> `resume()` calls `Activity.recreate()` if `BLUETOOTH_CONNECT` is held. The requests are sequential because Android drops a second `requestPermissions` while a dialog is pending. `ok(Context)` is true below API 31 and otherwise reflects `BLUETOOTH_CONNECT`; it guards two `SbxConnectionManager` entry points: `a()` (discovery, `startDiscovery`) and `f()` (bonded enumeration, `getBondedDevices`), each patched with a one-anchor early return. Below API 31 the shim is inert; `askNotif()` is a no-op below API 33 | `BtPermCompat` | **Build** (three anchors). **Device** (S24 Ultra): dialogs appear in order (location and microphone, Nearby devices, notifications), the five recorded permissions end `granted=true`, and the app connects to the Katana without a Settings step (per [ARM64_RUNTIME.md](../research/arm64/ARM64_RUNTIME.md) and the eight-point regression in [RECEIVER_AUDIT.md](../research/android/RECEIVER_AUDIT.md)). Behavior below API 31 **Expected** |
| 12 | `MainActivity.v()` prompts for notification-listener access to feed a now-playing feature built on the `android.media.RemoteController` API, which no longer works on modern Android | The `invoke-direct ... MainActivity;->w()V` call is removed from `v()` (anchor 1); the accessibility check and logging remain | none | **Build** (one anchor). Feature being inert is **Expected** (platform removal). The code comment's claims about vendor settings behavior and background-activity-launch limits have no preserved trace |

`RcvCompat` passes `RECEIVER_EXPORTED` rather than `RECEIVER_NOT_EXPORTED` to reproduce the stock exposure: before Android 13 every dynamically registered receiver was implicitly exported. The registration-site count asserted by the build is 96. A figure of 78 in `runtime/s24_launch.txt` is superseded by that count.

### PendingIntent sites (row 3, 23 total)

The new flags value is the stock value OR 0x04000000: 0 -> 0x4000000, `UPDATE_CURRENT` 0x08000000 -> 0xc000000, `CANCEL_CURRENT` 0x10000000 -> 0x14000000, `ONE_SHOT` 0x40000000 -> 0x44000000. The patch loads the combined constant into the flags register immediately before the invoke, which supersedes any earlier value in that register.

| Group | Class (smali path under `smali/` or `smali_classes2/`) | Factory | Sites |
|---|---|---|---|
| App | `MainService` | `getActivity` (flags from `v14`, row 4) | 2 |
| App | `MainService` | `getService` | 1 |
| App | `LocalMusicManager` (`logic/sbxapplogic`) | `getBroadcast` | 1 |
| Support | `TaskStackBuilder$TaskStackBuilderApi16Impl`, `$TaskStackBuilderBaseImpl` | `getActivities` | 1 + 1 |
| Support | `MediaButtonReceiver`, `MediaSessionCompat` | `getBroadcast` | 1 + 1 |
| Support | `v7/media/RemotePlaybackClient` | `getBroadcast` | 2 |
| Support | `v7/widget/SearchView` | `getActivity` (`ONE_SHOT`) | 1 |
| Play services | `analytics/internal/zzv`, `gcm/GoogleCloudMessaging`, `iid/zzc`, `measurement/internal/zzag`, `gcm/GcmNetworkManager`, `cast/CastRemoteDisplayLocalService` | `getBroadcast` | 6 |
| Play services | `auth/api/credentials/internal/zzd`, `common/api/internal/zzd`, `common/zzc`, `gcm/zzb` | `getActivity` | 4 |
| Play services | `gcm/zzb` | `getService` | 2 |

Side effect (**Static**): at six sites the flags register is also the request-code register (`MediaSessionCompat`, both `RemotePlaybackClient` sites, `zzv`, `GcmNetworkManager`, `zzag`), so the request code becomes the same constant. This changes only `PendingIntent` identity for de-duplication. The build checks the constant is loaded, not that no later instruction reads the overwritten register; only `MainService` has a runtime trace.

## `arm64`: packaging

| Item | Detail | Basis |
|---|---|---|
| Variant definition | `sbc_add_variant(arm64 PATCHES modernize arm64 ...)`; every `modernize` row applies | **Build** |
| Libraries added | `lib/arm64-v8a/libsbxapplogic_ctprotocol_jni.so` and `lib/arm64-v8a/libserialport_jni.so`, copied by `patches/arm64/patch.cmake`; the patch fails if either is missing or the library directory is not set | **Build** |
| Native source | `patches/arm64/native/`, an NDK project built with NDK 25.1.8937393 (revision matched against `source.properties`) and `ANDROID_PLATFORM=android-21`. If no matching NDK is found, the `arm64` variant is not defined and `apk-arm64` is an unknown target | **Build** |
| Stock ABIs | `armeabi`, `armeabi-v7a`, `x86` and the non-ABI `utility` directory are retained; the APK is multi-ABI. No `x86_64` is provided | **Static** |
| Library integrity | Libraries extracted from the signed APK matched the built libraries by SHA-256 (`ef9bad52...` and `e50efa5e...`); the two hashes did not change across packaging iterations | **Static** (recorded in [ARM64_PACKAGING.md](../research/arm64/ARM64_PACKAGING.md)) |
| Loader behavior | `sbxapplogic_ctprotocol_jni` loads in the `<clinit>` of `SbxSppCommandManager`, on the mandatory connection path; `serialport` loads in the `<clinit>` of `SerialPort` inside try/catch, so a missing library degrades rather than crashes | **Static** (loader audit) |
| 64-bit-only install and load | `primaryCpuAbi=arm64-v8a`; natives bind with no `UnsatisfiedLinkError`; `SbxSppCommandManager` handles a live inbound command; RFCOMM SPP channel opened to the Katana | **Device** (Pixel 7a API 33, S24 Ultra API 36) |
| Negative control | `resign` APK on the Pixel 7a: `INSTALL_FAILED_NO_MATCHING_ABIS` | **Device** |
| Install on 32-bit devices | The 32-bit libraries are still present | **Expected** |
| 16 KiB page size | The arm64-v8a libraries link with `-z max-page-size=16384`, so their `PT_LOAD` segments are 16 KiB aligned, as the Android 15+ loader requires on 16 KiB-page devices. No such device has been tested ([NATIVE_LIBRARIES.md](NATIVE_LIBRARIES.md#16-kib-page-size)) | **Build**; device load **Expected** |
| Native behavior parity | JNI parity was established differentially against an x86 oracle build of the same source; command/response correctness against hardware is not claimed | **Static**, scope limit |

## `compat`: distribution identity

| Item | Detail | Basis |
|---|---|---|
| Variant definition | `sbc_add_variant(compat PATCHES modernize arm64 identity ... PACKAGE <app id> DEFINES ...)`; every `modernize` and `arm64` row applies | **Build** |
| Identity | Package `io.github.asce1062.sbconnect.compat`, label `SB Connect Compat`, versionName `1.04.02-compat.0.1.0`, versionCode 1000, provider authority under the new package | **Build** (anchor counts), **Static** (aapt2 badging) |
| Difference from `arm64` | 6 of 4312 archive entries: `AndroidManifest.xml`, `resources.arsc`, `classes.dex` and the three signature files. Staged tree: manifest, `apktool.yml`, two lines of `SbxDeviceManager.smali` | **Static** |
| Coexistence | A separate package with its own data directory and a unique provider authority, so it installs next to the stock app or a stock-identity variant | **Emulator** (API 30 x86, next to `arm64`). **Device** (S24 Ultra, API 37, next to an `arm64` install, Katana connected): both run, and each keeps its own data; a volume write from `compat` is read back by `arm64`. Detail in [APPLICATION_IDENTITY.md](APPLICATION_IDENTITY.md#verification) |
| Play Protect, user install | A debug-signed `compat` opened from the file manager is blocked ("App blocked to protect your device", no install-anyway option). ADB install succeeds | **Device** (S24 Ultra, API 37), [HARDWARE_VALIDATION.md](../research/android/HARDWARE_VALIDATION.md) |

Package-dependence audit and version scheme:
[APPLICATION_IDENTITY.md](APPLICATION_IDENTITY.md).

## Known stock-app defects on modern devices

| Defect in the stock app | Surfaces at | Addressed by | Basis |
|---|---|---|---|
| Only 32-bit native libraries; 64-bit-only devices reject the install | Any 64-bit-only device (Pixel 7a observed) | `arm64` variant | **Device** |
| Filtered components without explicit `android:exported`; `PendingIntent`s without a mutability flag | Target API 31+ | `modernize` rows 2 and 3 | **Build**, **Expected** failure modes |
| `MainService` posts a channel-less foreground notification | API 33 (process killed) | Row 9 | **Device** |
| `JSONParser` depends on the removed Apache HTTP client | API 28+ | Row 8 (`org.apache.http.legacy`) | **Device** (library loaded); crash log not preserved |
| `Utils.b()` calls `junit.framework.Assert` at runtime | API 28+, when a preset row is bound | Row 8 (`android.test.base`) | **Device** |
| Two-argument `registerReceiver` at 96 sites, including the bundled `ibluz` library | Target 34 on an API 34+ device | Row 10 | **Device** (S24 Ultra) |
| No `requestPermissions` for `BLUETOOTH_CONNECT`, `BLUETOOTH_SCAN`, `POST_NOTIFICATIONS` | Target 31+ (Bluetooth), 33+ (notifications) | Row 11 | **Device** (S24 Ultra) |
| Foreground service without a declared type | Target 34 | Row 7 | **Expected** failure; **Device** result with the fix |
| Notification-listener prompt for a feature built on a removed API | Modern Android | Row 12 (prompt suppressed, feature not restored) | **Build**; inertness **Expected** |
| `CtProtocolMgr.d()` throws a swallowed `ArrayIndexOutOfBoundsException` (length 13, index 13) on certain live Katana frames | Observed on arm64 hardware | Not addressed | **Device** (logged, app stays alive); the claim that the 32-bit app behaves identically is **Expected** |

## Not addressed and limits

- **No 32-bit device test.** `resign` and `modernize` install and run on 32-bit-capable devices only as an **Expected** result. The `arm64` variant's retained 32-bit libraries are likewise untested.
- **Narrow hardware matrix.** One Pixel 7a (API 33), one Galaxy S24 Ultra (API 36, later API 37), one Katana. API 31, 32, 34 and 35 hardware, other speakers, and other vendors' Bluetooth stacks and permission UIs were not tested. Whether the Katana connected on the S24 Ultra is reported differently by two records: `runtime/s24_launch.txt` lists the Dashboard with the "Touch to connect to an Audio Device" prompt and "Katana not connected", while `ARM64_RUNTIME.md` and the connection regression in `RECEIVER_AUDIT.md` report a connection. Those records do not settle it. The later `compat` run on the same phone, then at Android 17 (API 37), records the SPP connection, CtProtocol traffic and a volume write ([HARDWARE_VALIDATION.md](../research/android/HARDWARE_VALIDATION.md)).
- **Raw logs not published.** Device claims rest on the written records and the four excerpts in `docs/research/arm64/runtime/`. The raw captures of the API 37 run are kept outside the repository because they contain device identifiers.
- **Play Store "not compatible" causes are inferred.** [FINDINGS.md](../research/android/FINDINGS.md) attributes the Play listing filter to the low targetSdk, missing ABIs, and implied hardware features. That was not tested. The variants are sideload-only and are not distributed through a store.
- **Protocol correctness is not claimed.** Encoder and decoder semantics were not modified. Command/response verification against hardware has not been done.
- **Bundled-library `PendingIntent` sites.** Applying `FLAG_IMMUTABLE` to every site assumes none needs a mutable intent (for example fill-in or inline-reply use). Only the app's own `MainService` path has a runtime trace.
- **Receiver exposure is uniform.** All 96 rewritten registrations use `RECEIVER_EXPORTED` on API 34+. No per-site audit determined which could be `RECEIVER_NOT_EXPORTED`.
- **`neverForLocation` omitted.** apktool 3.0.3's bundled framework predates `android:usesPermissionFlags`, and aapt2 rejects it. `BLUETOOTH_SCAN` is therefore declared without it, and `ACCESS_FINE_LOCATION` remains uncapped, so the app still prompts for location (**Static**).
- **Notification-listener feature not restored.** `LocalMusicRemoteControllerService` and the now-playing path remain in the package; the access prompt is suppressed.
- **`MediaButtonReceiver` is not exercised at runtime** (no active media session on the test device); its `exported="false"` value rests on static reasoning.
- **Rules keyed to targets above 34** (35 and 36) do not apply to a target-34 app and were not evaluated. Platform-wide changes were observed only as far as the API 36 device ran the app. Android 15 and later restrict foreground services started from `BOOT_COMPLETED`. On the S24 Ultra at API 37, `MainReceiver` starts `MainService` from `BOOT_COMPLETED` as a background service. The service becomes foreground only after a Bluetooth connection, and no start exception occurs (**Device**, [HARDWARE_VALIDATION.md](../research/android/HARDWARE_VALIDATION.md)). A foreground start from the boot path was not observed.
- **Device runs used debug signing.** Test-release and release signing are described in [SIGNING.md](../development/SIGNING.md); no release-signed build has run on hardware. Consequences of the signer are listed in [PERMISSIONS.md](PERMISSIONS.md).
- **Resources and dex are re-encoded** by `modernize` and `arm64`; byte-level differences from stock in those entries are expected and not individually audited.

## Superseded statements in other records

| Record | Statement | Current behavior |
|---|---|---|
| [FINDINGS.md](../research/android/FINDINGS.md) and [COMPAT_MATRIX.md](../research/android/COMPAT_MATRIX.md) | No overlay; `MainReceiver` and `MediaButtonReceiver` stay exported; runtime permission requests are not wired; modernize ledger has five rows | Rows 2, 4, 8 to 12 postdate those records |
| `runtime/s24_launch.txt` | 78 two-argument `registerReceiver` sites | 96, as asserted by `patch.cmake` and stated in `ARM64_RUNTIME.md` |
| FINDINGS.md | Arm64 libraries require reverse engineering, "no source shipped" | The libraries in the `arm64` variant are built from `patches/arm64/native/` |

## Sources

- [patches/modernize/patch.cmake](../../patches/modernize/patch.cmake), authoritative for anchors, counts and replacements
- [patches/modernize/overlay/smali/com/creative/apps/sbconnect/BtPermCompat.smali](../../patches/modernize/overlay/smali/com/creative/apps/sbconnect/BtPermCompat.smali)
- [patches/modernize/overlay/smali/com/creative/apps/sbconnect/FgChannelCompat.smali](../../patches/modernize/overlay/smali/com/creative/apps/sbconnect/FgChannelCompat.smali)
- [patches/modernize/overlay/smali/com/creative/apps/sbconnect/RcvCompat.smali](../../patches/modernize/overlay/smali/com/creative/apps/sbconnect/RcvCompat.smali)
- [patches/arm64/patch.cmake](../../patches/arm64/patch.cmake) and [patches/arm64/README.md](../../patches/arm64/README.md)
- [CMakeLists.txt](../../CMakeLists.txt), [cmake/sbc_patches.cmake](../../cmake/sbc_patches.cmake), [cmake/apply_patch.cmake](../../cmake/apply_patch.cmake), [cmake/sbc_native.cmake](../../cmake/sbc_native.cmake)
- [cmake/resign_control.cmake](../../cmake/resign_control.cmake), [cmake/resign_verify.cmake](../../cmake/resign_verify.cmake)
- [docs/research/android/FINDINGS.md](../research/android/FINDINGS.md), [PIPELINE.md](../research/android/PIPELINE.md), [COMPAT_MATRIX.md](../research/android/COMPAT_MATRIX.md), [RECEIVER_AUDIT.md](../research/android/RECEIVER_AUDIT.md)
- [docs/research/arm64/ARM64_RUNTIME.md](../research/arm64/ARM64_RUNTIME.md), [ARM64_VERDICT.md](../research/arm64/ARM64_VERDICT.md), [ARM64_PACKAGING.md](../research/arm64/ARM64_PACKAGING.md)
- [docs/research/arm64/runtime/](../research/arm64/runtime/): `device_abi.txt`, `launch_log_excerpt.txt`, `junit_crash_excerpt.txt`, `s24_launch.txt`
