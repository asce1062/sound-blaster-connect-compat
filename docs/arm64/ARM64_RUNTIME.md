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

The first-ever run on a real arm64 runtime surfaced four stock-app defects that
a current Android release (API 33) exposes and the original 32-bit device era
did not. Each is a platform-API compatibility shim in the modernize patch;
none touches CtProtocol encode/decode semantics, which stay frozen.

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

Fixes 1-3 were needed to reach the Dashboard; fix 4 was needed for the preset
screens reached from it.

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
| Final arm64 APK (signed) | `5afae081aaabf22f3baf0509220184087ab87a370e91c810b0d25b3d1a4d6ec5` |
| `libsbxapplogic_ctprotocol_jni.so` (arm64-v8a) | `ef9bad520bd1c94d9a942857425b80722d650190dd120dad8d9d070490e52c6e` |
| `libserialport_jni.so` (arm64-v8a) | `e50efa5e59d111a695b6eb7d1457824df03921f53eb6e4eda04fc524f4d58a87` |

The APK hash supersedes the pre-junit-fix build
(`b53a88939adc8ecd3cdf33416fb42382d25c071d76e52d62a305b36e19dc2319`); the two
`.so` hashes are unchanged across every iteration, since the fixes are
manifest/smali-only.
