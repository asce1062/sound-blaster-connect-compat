# Installation

Which build to use on which phone, how to install it, and what to expect on
first launch. There is no published release yet: you build the APK yourself
from your own copy of the stock app, as described in
[BUILDING.md](../development/BUILDING.md).

## Check a release download

A release is the `compat` build, published as
`sbconnect-compat-v<version>.apk` with a `.sha256` and a `.json` file next
to it. Before installing one:

1. Check the file: `sha256sum -c sbconnect-compat-v<version>.apk.sha256`, or
   in PowerShell `Get-FileHash sbconnect-compat-v<version>.apk` and compare
   with the `.sha256` file.
2. Check the signer: `apksigner verify --print-certs <apk>` (Android SDK
   build-tools) prints the certificate SHA-256. It must equal the project's
   published fingerprint in
   [`signing/release-certificate.sha256`](../development/SIGNING.md#the-production-key).
   An APK with any other signer is not a release of this project.

Every release is signed with the same key, so a later release installs over
an earlier one and keeps your settings. A self-built debug-signed APK has a
different signer: switching between it and a release needs an uninstall,
which deletes the app's settings.

## Choose a variant

| Your phone | Use | Status |
|---|---|---|
| 64-bit only (no 32-bit app support), for example Pixel 7 and later, Galaxy S24 | `compat` (or `arm64`) | `arm64` tested on a Pixel 7a (Android 13) and a Galaxy S24 Ultra (Android 16) with a Katana speaker |
| Supports 32-bit apps, Android 12 or later | `compat`, `arm64` or `modernize` | Expected to work; not tested on such a device |
| Supports 32-bit apps, Android 11 or earlier | `compat`, `resign`, `modernize` or `arm64` | Expected to work; not tested on such a device |

`compat` is the `arm64` build under its own name: it appears as
**SB Connect Compat**, has the package name
`com.creative.apps.sbconnect.compat`, and installs next to the stock app
instead of replacing it. The other builds keep the stock name and package.

How to tell: `adb shell getprop ro.product.cpu.abilist32` prints nothing on
a 64-bit-only phone. On such a phone the stock app and the `resign` and
`modernize` builds do not install (`INSTALL_FAILED_NO_MATCHING_ABIS`).

`resign` is the unmodified stock app with a different signature. `modernize`
targets Android 14 and asks for permissions the way current Android requires.
`arm64` is `modernize` plus native libraries for 64-bit-only phones; it also
keeps the stock 32-bit libraries.

Only the Sound BlasterX Katana has been used with these builds. Other Sound
Blaster devices that the stock app supports may work but have not been tried.

## Install

1. For `resign`, `modernize` or `arm64`: **remove the stock app first** if it
   is installed. These builds are signed with a different key than Creative's
   release, and Android refuses to replace an app with one signed by another
   key. Uninstalling deletes the stock app's settings. `compat` does not need
   this step; it starts with empty settings of its own.
2. Enable USB debugging on the phone, connect it, and run:

   ```sh
   adb install -r build/sbc_compat-aligned-debugSigned.apk
   ```

   Or copy the APK to the phone and open it; Android asks you to allow
   installs from the app you opened it with.
3. Google Play Protect may say it has not seen the app before and offer
   **Scan app**. Scanning sends the APK to Google; on a Pixel 8 one
   debug-signed build with the current permission set came back as "This app
   looks safe", with **Install**. An earlier build with more permissions was
   blocked outright on a Galaxy S24 Ultra. A scan judges the exact file it
   sees, so another build or signer can get a different result. Do not
   turn off Play Protect to install the app;
   [PERMISSIONS.md](../technical/PERMISSIONS.md#play-protect) records the
   behavior observed on the test phones.

Builds made on different computers may carry different debug keys. Installing
one over another then fails the same way, and the app has to be uninstalled
first.

## First launch

The `modernize`, `arm64` and `compat` builds ask once, on the first launch
after installing:

1. **Nearby devices** (Android 12 and later), needed to find and connect to
   the speaker over Bluetooth. On Android 6 to 11 they ask for **location**
   instead, which those versions require for finding Bluetooth devices that
   are not paired yet;
2. **Notifications** (Android 13 and later), for the app's status
   notification. Declining it does not affect the speaker connection.

Later launches do not ask again. Other permissions are asked for only when you
open the feature that needs them, with a short explanation first:

| Feature | Permission |
|---|---|
| Connect to Device screen, tapping a speaker | Nearby devices (Android 12+); location (Android 6 to 11) |
| Room calibration | Microphone |
| Wi-Fi speaker setup | Location (precise) |

Speaker control, presets and volume do not need the microphone or location.

If you decline a permission, the app keeps working offline and shows the
explanation again the next time you open that feature, with **Allow** to ask
again. After a second refusal Android stops showing its dialog; the
explanation then offers **Open settings**, which opens the app's page in
Settings. You can also grant it in Settings, Apps, Sound Blaster Connect
(SB Connect Compat for the `compat` build), Permissions.

The app's "now playing" feature relied on notification access through a
deprecated API. It does not work, and the app does not ask for notification
access.

## Troubleshooting

| Symptom | Cause |
|---|---|
| `INSTALL_FAILED_NO_MATCHING_ABIS` | 64-bit-only phone with a `resign` or `modernize` build. Use `compat` or `arm64`. |
| `INSTALL_FAILED_UPDATE_INCOMPATIBLE` or "App not installed" | A copy signed with another key is installed (the stock app or another build). Uninstall it first. |
| Speaker not found, Connect to Device screen empty | Nearby devices permission not granted (open the screen again and choose Allow or Open settings), or Bluetooth off. |
| A new, unpaired speaker is not found on Android 6 to 11 | Location not granted. Pair the speaker in the system Bluetooth settings, or allow location. |

Known limits of these builds are listed in
[ANDROID_COMPATIBILITY.md](../technical/ANDROID_COMPATIBILITY.md#not-addressed-and-limits).
