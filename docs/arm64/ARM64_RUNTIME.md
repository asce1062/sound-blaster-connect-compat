# ARM64_RUNTIME

Phase 5 gates A4, A5, A6. Installs the multi-ABI APK on a native arm64-v8a
runtime and proves the stock Java app loads and binds its native surface and
reaches its normal device-connection UI.

## A4 - native arm64-v8a runtime

| Field | Value |
|---|---|
| Model | Pixel 7a (`lynx`) |
| Android | 13 (SDK 33) |
| Serial | <redacted> |
| `ro.product.cpu.abilist` | `arm64-v8a` |
| `ro.product.cpu.abilist64` | `arm64-v8a` |
| `ro.product.cpu.abilist32` | *(empty)* |

`abilist32` is empty: this is a 64-bit-only device with no 32-bit bridge, so it
can run only `arm64-v8a` native code. A satisfied A4 (device evidence frozen in
`runtime/device_abi.txt`).

## A5 - launch, load, bind, connect

Installed via `adb install -r`; `Success`, and `dumpsys package` reports
`primaryCpuAbi=arm64-v8a` - the loader selected the arm64 libraries. On launch
(`runtime/launch_log_excerpt.txt`):

- Process starts (`MainActivity`).
- `nativeloader` configures the classloader namespace with the arm64 library
  path (`...!/lib/arm64-v8a`) and the `org.apache.http.legacy.jar` shared
  library (`uses_libraries=ALL`).
- `SbxSppCommandManager` initializes, its native library loads, and its JNI
  natives bind with no `UnsatisfiedLinkError`, wrong-ELF, or missing-symbol
  error.
- The app opens an RFCOMM SPP channel (`uuid=0x1101`) to the Katana
  (`bd_addr xx:xx:xx:xx:xx:xx`); `BluzManager` binds its custom
  command/data listeners.
- `SbxAppLogic.SbxSppCommandManager: [handleProtocolEvent]
  SOUNDCORE_COMMAND_MAXPAYLOAD` - the native-backed command manager processes
  a real inbound command from the device.
- The app reaches the full connected Dashboard (user-confirmed) and the
  BlasterX Experience preset screens render against the Katana's installed
  profiles.

`JNI binding = PASS`, `connection UI reached = PASS`.

### Platform-compatibility fixes required to reach a clean launch

Running on real arm64 hardware surfaced five stock-app defects that current
Android releases expose and the original 32-bit device era did not: fixes 1-4
on the Pixel 7a (API 33) and fix 5 on a Galaxy S24 Ultra (API 36), which
enforces an API 34 rule the Pixel's platform does not. Each is a platform-API
compatibility shim in the modernize patch; none touches CtProtocol encode/decode
semantics, which stay frozen.

1. **PendingIntent register clobber / FLAG_IMMUTABLE** - `MainService.a()` built
   its `getActivity` PendingIntents without the API 31+ mutability flag. The
   fix takes the immutable flag from `v14` (which already holds `0x4000000`)
   instead of writing it into `v11`, the shared-zero register the method also
   uses as an `ArrayList` index; clobbering `v11` produced
   `IndexOutOfBoundsException: Index: 67108864`.

2. **Foreground-service notification channel** - the app posted its
   `startForeground` notification with a channel-less builder. On API 33+ this
   throws `CannotPostForegroundServiceNotificationException` and kills the
   process. The `FgChannelCompat` overlay stamps a channel id and registers the
   channel on API 26+.

3. **Apache HTTP legacy** - `JSONParser` uses `DefaultHttpClient`, dropped from
   the bootclasspath at API 28; re-added as a `uses-library`.

4. **junit.framework.Assert** - `Utils.b()` calls `junit.framework.Assert` as
   an inline runtime assertion, reached when the preset-list adapter
   (`SbxModifiableProfileMainFragment$ProfileListAdapter.onBindViewHolder`)
   binds a row - i.e. opening the "See All" or "Blaster Experience" preset
   lists. `junit.framework.*` was removed from the bootclasspath at API 28 and
   survives on device as the `android.test.base` shared library, so without it
   binding a row throws `NoClassDefFoundError: junit.framework.Assert` and
   finishes the activity (`runtime/junit_crash_excerpt.txt`). Re-added as a
   `uses-library` alongside the Apache one. Confirmed on device: the preset
   screens open without crashing, crash buffer clean, process survives.

5. **registerReceiver export flag (API 34)** - `Context.registerReceiver()` for
   a non-system broadcast must pass `RECEIVER_EXPORTED`/`RECEIVER_NOT_EXPORTED`
   when the app targets API 34+, or the platform throws
   `SecurityException ("One of RECEIVER_EXPORTED or RECEIVER_NOT_EXPORTED should
   be specified ...")`. The check exists only on API 34+ devices, so the Pixel 7a
   (API 33) never hit it; the S24 Ultra (API 36) crashes at launch - first in
   `MainActivity.onCreate` (`LocalMusicManager`), then in `onStart` (fragments).
   The call is made through four static types (`Context`, support
   `FragmentActivity`, `MainActivity`, `MainService`), 96 sites across the whole
   smali tree - including the bundled `com.actions.ibluz` library (`smali/c/`),
   which performs the SPP/RFCOMM connection and whose own `registerReceiver` call
   threw after launch was fixed, leaving the device stuck "in use". All route
   through the `RcvCompat.register` overlay, which passes `RECEIVER_EXPORTED` on
   API 34+ (reproducing the pre-Android-13 implicit-export behaviour the stock app
   relied on) and the original two-arg call below. Confirmed on the S24: clean
   launch, crash buffer empty, app reaches the Dashboard (`runtime/s24_launch.txt`).

6. **Nearby Devices + notification runtime permissions (API 31 / 33)** - at
   `targetSdk 34` the legacy install-time `BLUETOOTH`/`BLUETOOTH_ADMIN` grants no
   longer cover Bluetooth; the app needs the runtime `BLUETOOTH_CONNECT`
   (bonded-device enumeration, SPP connection) and `BLUETOOTH_SCAN` (discovery)
   permissions, and to post its own notifications it needs `POST_NOTIFICATIONS`
   (API 33). The stock app predates all three and never calls `requestPermissions`,
   so each stays denied and every Bluetooth call throws `SecurityException` - no
   device is found. The `BtPermCompat` overlay drives a sequential request chain
   from `MainActivity.onRequestPermissionsResult`: the stock permission batch
   (camera/mic/location, code `0x457`) returns, then `BLUETOOTH_CONNECT`/`SCAN`
   (`0x42c`), then `POST_NOTIFICATIONS` (`0x42d`), then `recreate()` resumes the
   connection path. The requests are chained rather than fired together because
   Android drops a second `requestPermissions` while a dialog is pending. The
   connection manager's discovery and bonded-enumeration entry points are gated so
   they no-op instead of throwing until the grant lands. Below API 31 the shim is
   inert and the legacy permissions apply. Confirmed on the S24: the dialogs appear
   in order (location/mic, Nearby devices, notifications), all five permissions end
   `granted=true`, and the app connects to the Katana with no Settings step.

Fixes 1-3 were needed to reach the Dashboard; fix 4 for the preset screens
reached from it; fix 5 for launch on Android 14+ (API 34+) devices; fix 6 for the
Bluetooth connection itself on Android 12+ (API 31+) devices.

## A6 - negative control

A payload-preserving re-sign of the stock APK (32-bit ABIs only) installed on
the same Pixel fails:

```
INSTALL_FAILED_NO_MATCHING_ABIS ... res=-113
```

The stock APK provides no `arm64-v8a` native code, so a 64-bit-only device
rejects it at install. This is the condition the multi-ABI arm64 package
removes, and the direct evidence that the original APK cannot run on this
device class.

## Final artifacts

| Artifact | SHA-256 |
|---|---|
| Final arm64 APK (signed) | `d46d580e465c6cd8c9527b9bc5600bfcdf8eda96bdd5def321cf2522620a57d2` |
| `libsbxapplogic_ctprotocol_jni.so` (arm64-v8a) | `ef9bad520bd1c94d9a942857425b80722d650190dd120dad8d9d070490e52c6e` |
| `libserialport_jni.so` (arm64-v8a) | `e50efa5e59d111a695b6eb7d1457824df03921f53eb6e4eda04fc524f4d58a87` |

The APK hash is the current build with all six fixes; it supersedes the
Pixel-only builds (`5afae081...` junit fix, `b53a8893...` pre-junit). The two
`.so` hashes are unchanged across every iteration, since all fixes are
manifest/smali-only.

## Second runtime - Galaxy S24 Ultra (Android 16 / API 36)

A second 64-bit-only arm64 device confirms the package on a much newer platform:

| Field | Value |
|---|---|
| Model | SM-S928U1 |
| Android | 16 (SDK 36) |
| `abilist` / `abilist32` | `arm64-v8a` / *(empty)* |
| Install | Success, `primaryCpuAbi=arm64-v8a` |
| Launch | 0 FATAL, process alive, reaches Dashboard (`runtime/s24_launch.txt`) |

The S24 required fix 5 (API 34 receiver export) and fix 6 (API 31+ runtime
Bluetooth permissions), which the Pixel's API 33 platform did not force. With
them, the app installs, loads the arm64 libraries, requests its permissions
in-app, and connects over Bluetooth SPP to the Katana on both runtimes.
