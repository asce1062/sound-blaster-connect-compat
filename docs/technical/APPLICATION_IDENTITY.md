# Application identity

This document describes the identity of the distributable `compat` variant:
its application ID, label and version, what the
[`identity`](../../patches/identity/) patch changes to produce them, which
parts of the stock app depend on the package name, and why each one keeps
working. The version scheme itself is defined in
[`cmake/sbc_version.cmake`](../../cmake/sbc_version.cmake). Where this
document and the build files disagree, the build files are correct.

## Verification tags

| Tag | Meaning |
|---|---|
| **Build** | Enforced by the build: an anchor count in `patches/identity/patch.cmake`, or a check in `cmake/sbc_version.cmake`. |
| **Static** | Read from the decoded stock tree (`smali/`, `smali_classes2/`, the manifest, the native libraries). |
| **Artifact** | Read from the built APK with `aapt2 dump badging` or by comparing archive entries. |
| **Emulator** | Observed on the Android emulator: Pixel 3a AVD, Android 11 (API 30), x86 system image. It exercises the package manager, the activity manager and component export rules. It has no Katana, and it runs the x86 libraries, not `arm64-v8a`. |
| **Device** | Observed on a device; see [Verification](#verification). |

## Identities

| Field | Stock, `resign`, `modernize`, `arm64` | `compat` |
|---|---|---|
| Application ID (`package`) | `com.creative.apps.sbconnect` | `io.github.asce1062.sbconnect.compat` |
| Label (application, launcher, notification listener) | `@string/app_name`, `@string/launcher_name` (Sound Blaster Connect) | `SB Connect Compat` |
| versionName | `1.04.02` | `1.04.02-compat.0.1.0` |
| versionCode | `10402` | `1000` |
| Measurement provider authority | `com.creative.apps.sbconnect.google_measurement_service` | `io.github.asce1062.sbconnect.compat.google_measurement_service` |
| Java packages and class names | `com.creative.*` | unchanged |
| JNI class names | `com/creative/logic/...`, `com/creative/serialport/SerialPort` | unchanged |
| Internal intent actions | `com.creative.apps.sbconnect.action.*` | unchanged |
| Resource table package | `com.creative.apps.sbconnect`, id `0x7f` | `io.github.asce1062.sbconnect.compat`, id `0x7f` |

The `resign`, `modernize` and `arm64` variants keep the stock identity. They
are the controls: `resign` is payload-identical to the stock archive
([ANDROID_COMPATIBILITY.md](ANDROID_COMPATIBILITY.md)), and `arm64` is the
build the device runs in the research records used. `compat` is `arm64` plus
the identity patch and nothing else. **Artifact**: of the 4312 archive
entries of `compat` and `arm64`, 6 differ: `AndroidManifest.xml`,
`resources.arsc`, `classes.dex` and the three signature files.

The in-app strings are not changed. The about screen and other UI text still
read the stock `app_name` resource.

## What the identity patch changes

[`patches/identity/patch.cmake`](../../patches/identity/patch.cmake) runs after
`modernize` and `arm64`. Each edit asserts how many times its stock anchor
occurs and stops the build on any other count. **Build**

| File | Edit | Sites |
|---|---|---|
| `AndroidManifest.xml` | `package` attribute | 1 |
| `AndroidManifest.xml` | `google_measurement_service` provider authority | 1 |
| `AndroidManifest.xml` | `android:label="@string/app_name"` (application, `LocalMusicRemoteControllerService`) | 2 |
| `AndroidManifest.xml` | `android:label="@string/launcher_name"` (`MainActivity`) | 1 |
| `smali/com/creative/logic/sbxapplogic/SbxDeviceManager.smali` | the string `"com.creative.apps.sbconnect"` | 2 |
| `apktool.yml` | `versionCode: 10402`, `versionName: 1.04.02` | 1 each |

There is no global namespace replacement. The stock string
`com.creative.apps.sbconnect` occurs 5 times in the decoded code; the patch
changes the 2 whose meaning is "this app's package", and leaves the 3 that are
action names (below).

apktool 3.0.3 has no option to rename the manifest package. Editing the
`package` attribute is enough: aapt2 names the resource table after the
manifest package, so resources resolve under the new name. **Artifact**
(`aapt2 dump`: `Package name=io.github.asce1062.sbconnect.compat id=7f`)

## Package-dependence audit

Every place the stock app could depend on its own package name, and why the
new ID keeps the stock behavior. **Static** unless noted.

| Contract | Finding | Outcome |
|---|---|---|
| Manifest component names | All `<activity>`, `<service>`, `<receiver>` and `<provider>` names are fully qualified (`com.creative...`). None is relative to `package`. | Resolve unchanged. |
| Custom permissions | The manifest defines no `<permission>` and uses none named after the package. | Nothing to rename. |
| Content provider authority | One provider, `AppMeasurementContentProvider`, authority `<package>.google_measurement_service`. The class does not compare its authority with anything. Authorities are unique per device. | Renamed so `compat` can be installed next to the stock app. |
| Hardcoded package string, host check | `SbxDeviceManager.a(Z)V` (query of the connected device) compares `getPackageName()` with `com.creative.apps.sbconnect`. For the stock package, offline browsing leaves the device name unset; any other package sets it from saved preferences. `SbxDeviceManager.a(Landroid/content/Context;)V` makes the same comparison, and both of its branches set the same device name. | Both comparisons name the new ID, so `compat` takes the stock host path. This is the one contract that fails if only the manifest changes. **Build** (2 sites) |
| Hardcoded package strings, actions | `MainService` uses `com.creative.apps.sbconnect.action.PLAY_PAUSE` in an explicit-component `PendingIntent` and `com.creative.apps.sbconnect.action.START_SERVICE` in an implicit broadcast from `onDestroy`. Both are action names, matched by string, not by package. | Unchanged. The implicit `START_SERVICE` broadcast does not reach manifest receivers on API 26 and later for either package. |
| Other-app package checks | Comparisons with other Creative app packages (`avatarconnect`) are false for the stock ID and for the new ID alike. | Unchanged behavior. |
| `getPackageName()` consumers | 45 call sites in app code: broadcasts scoped with `setPackage(getPackageName())`, `bindService`, 13 `Resources.getIdentifier(name, type, getPackageName())` lookups (`ProfileDetailFragment$10`, `SbxModifiableProfileMainFragment$InstalledProfileAdapter`, `Utils`), `RemoteViews`, `getPackageInfo` and `getApplicationInfo` on the app itself, a `VoiceMorphFragment` URI, the notification-listener check in `LocalMusicManager`, and the main-process check in `smali_classes2`. Each uses the running package as an opaque value. | Self-relative: they follow the new ID. `getIdentifier` resolves because the resource table carries the new name. |
| Broadcast scope | 15 sends are scoped to the app's own package. 2 are unscoped: the iBluz disconnect broadcast, which carries the sender's package as an extra and is meant for other apps, and `START_SERVICE`. | Scoped sends follow the new ID; the unscoped ones do not depend on it. |
| Reflection | `Class.forName` names only library and framework classes. | Unaffected. |
| SharedPreferences | File names are fixed strings, not derived from the package. | Unaffected. The new package has its own data directory; nothing migrates from a stock install. |
| Native libraries | The stock `armeabi`, `armeabi-v7a`, `x86` libraries and the arm64 builds contain no package name and no `PackageManager` or signature lookup. JNI binds by Java class name (`com/creative/logic/...`). | Unaffected: class names are not renamed. |
| Build and deploy | The patches reference the package only through `sbc_package`. Each variant records the package it produces, and `deploy` launches that one (`monkey -p <package>`). | `deploy_variant=compat` launches the new ID. |

## Versions

One source: `project(VERSION 0.1.0)` in [`CMakeLists.txt`](../../CMakeLists.txt).
[`cmake/sbc_version.cmake`](../../cmake/sbc_version.cmake) derives the rest
and fails configure if a component is missing or above 999. **Build**

| Value | Rule | 0.1.0 |
|---|---|---|
| Project version | `project(VERSION)` | `0.1.0` |
| Upstream version | the stock release the input pin fixes | `1.04.02` |
| versionName | `<upstream>-compat.<project>` | `1.04.02-compat.0.1.0` |
| versionCode | `MAJOR * 1000000 + MINOR * 1000 + PATCH` | `1000` |
| Release tag | `v<project>` | `v0.1.0` |
| Release APK | `sbconnect-compat-<tag>.apk` | `sbconnect-compat-v0.1.0.apk` |

The versionCode order follows the project version order, so each release has a
larger code than the last, which Android requires for an update. It stays
below Android's limit of 2100000000 for every major version up to 2099. The
code is independent of the stock code 10402: the two packages differ, so the
system never compares them. Configure writes the values to
`build/release.env` as `KEY=VALUE` lines for release tooling.

## Consequences

- **Coexistence.** `compat` and the stock app (or any stock-identity variant)
  are different packages. Both can be installed at once, each with its own
  data, permissions and notification-listener grant.
- **No data carry-over.** Settings, presets and paired-device state of a stock
  install do not appear in `compat`. Bluetooth pairing is held by the system
  and is shared.
- **Updates.** A later `compat` release installs over an earlier one only when
  both are signed with the same key. Debug-signed builds from different
  machines carry different keys.
- **Notification listener.** The listener service is listed under the
  `SB Connect Compat` label in system settings and needs its own grant.

## Verification

| Check | Result | Tag |
|---|---|---|
| Package, label, versions, launchable activity, targetSdk 34, native ABIs `arm64-v8a armeabi armeabi-v7a x86` | As in the table above | **Artifact** |
| Staged-tree difference from `arm64` | Only `AndroidManifest.xml`, `apktool.yml` and `SbxDeviceManager.smali` at the two comparisons | **Artifact** |
| Stock-identity variants | `arm64` still reports `com.creative.apps.sbconnect`, 10402, Sound Blaster Connect | **Artifact** |
| Side-by-side install | `arm64` (stock identity) and `compat` install together; `pm` lists both packages, and both measurement provider authorities are registered | **Emulator** |
| Installed metadata | `compat`: versionCode 1000, versionName `1.04.02-compat.0.1.0`, targetSdk 34. `arm64`: 10402, `1.04.02`, targetSdk 34 | **Emulator** |
| Launch | `compat` starts from the launcher, shows the runtime permission request (location, storage, microphone at API 30), and after the grants shows the `MainActivity` dashboard. The Connect to Device screen starts Bluetooth discovery. Logcat has no `FATAL EXCEPTION`, `UnsatisfiedLinkError` or `dlopen` failure. `arm64` launches with `compat` installed | **Emulator** |
| Component exports | From the shell uid, `am startservice` of `MainService` and explicit broadcasts to `MainReceiver` and `android.support.v4.media.session.MediaButtonReceiver` of `compat` are refused as not exported. `MediaButtonReceiver` of `arm64` is refused the same way | **Emulator** |
| Native library load | Not reached. `sbxapplogic_ctprotocol_jni` and `serialport_jni` load in the static initializers of `SbxSppCommandManager` and `SerialPort`, which run only when a device connects; without a Katana neither library is mapped into the process | Pending (**Device**) |
| Katana discovery and SPP, live state and presets, Nearby Devices permission flow (API 31+), boot receiver and foreground service, Play Protect install result | Not yet run under the new ID | Pending (**Device**) |

## Sources

- [`patches/identity/patch.cmake`](../../patches/identity/patch.cmake), [`patches/identity/README.md`](../../patches/identity/README.md)
- [`cmake/sbc_version.cmake`](../../cmake/sbc_version.cmake), [`cmake/sbc_patches.cmake`](../../cmake/sbc_patches.cmake), [`CMakeLists.txt`](../../CMakeLists.txt)
- Companion documents: [ANDROID_COMPATIBILITY.md](ANDROID_COMPATIBILITY.md), [PERMISSIONS.md](PERMISSIONS.md), [JNI_INTERFACE.md](JNI_INTERFACE.md)
- Decision: [0008](../decisions/0008-separate-distribution-identity.md)
- Earlier record of the stock-identity build: [APP_IDENTITY.md](../research/android/APP_IDENTITY.md)
