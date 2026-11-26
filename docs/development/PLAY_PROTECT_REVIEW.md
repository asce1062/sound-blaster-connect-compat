# Play Protect review submission (draft)

Status: **not submitted, not needed so far.** This draft is used only if the
user install route (file manager, then the system package installer) blocks a
`compat` build on a device with Play Protect on. The debug-signed build with the
reduced permission set is not blocked on a Pixel 8: Play Protect recommends a
scan and then reports it safe
([PERMISSIONS.md](../technical/PERMISSIONS.md#play-protect)). The release-signed
APK has not been through the route. Play Protect is not disabled, bypassed or
excluded to install the app, and an `adb install` is not presented as evidence
that the user route works.

## Before submitting

1. **A fixed APK.** The form identifies the app by the SHA-256 of one APK.
   Debug-signed builds differ per machine, so an appeal covers only a file
   that is actually distributed: the release APK signed with the project's
   release key ([SIGNING.md](SIGNING.md)). No release-signed build exists yet.
2. **The user-route result for that APK**, on a named device and Android
   version, with the exact dialog text.
3. **VirusTotal.** The form asks for the hash "of the uploaded file on Virus
   Total". Uploading makes the APK available to VirusTotal and its partners.
   The APK contains Creative Technology's code and resources, so the upload is
   the maintainer's decision, made with the project's redistribution position
   ([PROVENANCE.md](../PROVENANCE.md)).
4. **Contact.** The form asks for an email address. Use a project address,
   not a personal one.

Google states that appeal decisions are final and that no reply is sent; the
outcome is visible only by retesting the user route.

## Form fields

| Field | Value |
|---|---|
| Email address | project contact (to be chosen) |
| Developer name | project maintainer name as published |
| Application package name | `com.creative.apps.sbconnect.compat` |
| SHA-256 of the APK on VirusTotal | release APK hash (to be filled) |
| Additional information | text below |

## Additional information (draft)

> SB Connect Compat is an unofficial compatibility rebuild of Creative
> Technology's Sound Blaster Connect 1.04.02, a Bluetooth remote-control app
> for Sound Blaster speakers. It is not made by or affiliated with Creative.
> The original app targets Android 8 and ships only 32-bit native code, so it
> does not install or run on current 64-bit-only phones. The rebuild raises the
> target to API 34, adds arm64 native libraries built from source, and
> installs under its own package name.
>
> Permissions: the rebuild removes the original app's notification-listener
> service and the MEDIA_CONTENT_CONTROL, SYSTEM_ALERT_WINDOW, GCM receive and
> WRITE_EXTERNAL_STORAGE permissions. It declares no SMS, accessibility or
> notification-listener capability. Runtime permissions are requested only
> where used: Nearby devices (Bluetooth speaker connection;
> BLUETOOTH_SCAN carries neverForLocation), notifications (status
> notification), microphone (room calibration only) and location (Wi-Fi
> speaker setup, and Bluetooth discovery on Android 11 and earlier). The
> foreground service type is connectedDevice. The app's own exported component
> is the launcher activity; the one other exported component is Google Play
> services' sign-in revocation service, guarded by the Play services
> permission REVOCATION_NOTIFICATION.
>
> On [device, Android version], opening the APK from the file manager shows
> "[dialog text]". [Install route and observed result.] The source, the patch
> set and the permission rationale are public at [repository URL].

Every bracketed item is filled from the retest record before submission.
Statements in the text must match [PERMISSIONS.md](../technical/PERMISSIONS.md)
and the built manifest of the submitted APK at that time.
