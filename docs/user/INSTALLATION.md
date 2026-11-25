# Installation

Which build to use on which phone, how to install it, and what to expect on
first launch. There is no published release yet: you build the APK yourself
from your own copy of the stock app, as described in
[BUILDING.md](../development/BUILDING.md).

## Choose a variant

| Your phone | Use | Status |
|---|---|---|
| 64-bit only (no 32-bit app support), for example Pixel 7 and later, Galaxy S24 | `arm64` | Tested on a Pixel 7a (Android 13) and a Galaxy S24 Ultra (Android 16) with a Katana speaker |
| Supports 32-bit apps, Android 12 or later | `arm64` or `modernize` | Expected to work; not tested on such a device |
| Supports 32-bit apps, Android 11 or earlier | `resign`, `modernize` or `arm64` | Expected to work; not tested on such a device |

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

1. **Remove the stock app first** if it is installed. These builds are signed
   with a different key than Creative's release, and Android refuses to
   replace an app with one signed by another key. Uninstalling deletes the
   stock app's settings.
2. Enable USB debugging on the phone, connect it, and run:

   ```sh
   adb install -r build/sbc_arm64-aligned-debugSigned.apk
   ```

   Or copy the APK to the phone and open it; Android asks you to allow
   installs from the app you opened it with.
3. Google Play Protect may warn about an app from an unknown developer or scan
   it before installing. That warning is expected for a self-built app;
   [PERMISSIONS.md](../technical/PERMISSIONS.md) records the behavior observed
   on the test phones.

Builds made on different computers may carry different debug keys. Installing
one over another then fails the same way, and the app has to be uninstalled
first.

## First launch

On Android 12 and later the `modernize` and `arm64` builds ask, in order:

1. the stock app's own requests (location and microphone);
2. **Nearby devices**, needed to find and connect to the speaker over
   Bluetooth;
3. **Notifications** (Android 13 and later), for the app's status
   notification.

Without Nearby devices the app cannot see the speaker. If you declined it,
grant it in Settings, Apps, Sound Blaster Connect, Permissions.

The app's "now playing" feature, which relied on notification access through
an API that current Android no longer supports, does not work, and the app no
longer asks for notification access.

## Troubleshooting

| Symptom | Cause |
|---|---|
| `INSTALL_FAILED_NO_MATCHING_ABIS` | 64-bit-only phone with a `resign` or `modernize` build. Use `arm64`. |
| `INSTALL_FAILED_UPDATE_INCOMPATIBLE` or "App not installed" | A copy signed with another key is installed (the stock app or another build). Uninstall it first. |
| Speaker not found | Nearby devices permission not granted, or Bluetooth off. |

Known limits of these builds are listed in
[ANDROID_COMPATIBILITY.md](../technical/ANDROID_COMPATIBILITY.md#not-addressed-and-limits).
