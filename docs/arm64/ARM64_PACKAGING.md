# ARM64_PACKAGING

Phase 5 gates A2 and A3. Audits every native-library load site in the stock
Java app, then packages the arm64 libraries into a multi-ABI APK via the
modernize path.

## A2 - native-loader audit

Every `System.loadLibrary()` / `System.load()` site in the decompiled app,
with the Java class that owns it and when the load fires. The rule is that a
library is loaded when its owning class is initialized, not when a given
feature is used; "unused for Katana" does not mean "never loaded."

| Library | Owning class | Load site | Timing |
|---|---|---|---|
| `sbxapplogic_ctprotocol_jni` | `...SbxAppLogic...SbxSppCommandManager` | static initializer (`<clinit>`) | class init, on first reference to the command manager during connection setup |
| `serialport` | `...SerialPort` | static initializer (`<clinit>`), load wrapped in try/catch | class init; failure is swallowed, so a missing lib degrades rather than crashes |

Netty's `NativeLibraryLoader` appears in the bundled dependency but is
parameterized and conditional, and the APK ships no netty native `.so`; it
loads nothing at runtime on this app's paths.

`SbxSppCommandManager` is on the mandatory connection path: the live launch
(A5) shows its `<clinit>` running and its natives bound before any device
command is handled. Both shipped native libraries therefore must be present in
the selected ABI, which is what A3 packages and A5 confirms.

## A3 - multi-ABI packaging

Built through the modernize variant extended for arm64:
`sbc_add_variant(arm64 PATCHES modernize arm64)`. The arm64 overlay adds the
two `arm64-v8a` libraries; the existing 32-bit ABIs from the stock APK are
preserved, so the package is genuinely multi-ABI and still installs on legacy
32-bit devices.

### Package identity (final APK)

| Field | Value |
|---|---|
| Package | `com.creative.apps.sbconnect` |
| versionCode / versionName | 10402 / 1.04.02 |
| minSdk / targetSdk | 14 / 34 |
| Final APK SHA-256 | `b53a88939adc8ecd3cdf33416fb42382d25c071d76e52d62a305b36e19dc2319` |
| Unsigned intermediate SHA-256 | `4a74c267d2ccfe0debd1ecf8593224c7f76f7cc10cdcca750fef880f78be5fa9` |
| Size | 45.33 MiB |
| Signing | v1 + v2 + v3 (Android Debug key, CN=Android Debug) |
| Signature verified | yes (uber-apk-signer, 0 errors) |

### ABI inventory

`lib/` contains: `arm64-v8a`, `armeabi`, `armeabi-v7a`, `x86`. (The `lib/`
tree also carries non-ABI utility entries, which are not ABI directories.)
`arm64-v8a` is the ABI added by this phase; the three 32-bit ABIs are the
stock set, preserved.

### Extracted-equals-built verification

The `arm64-v8a` libraries extracted from the signed APK hash-match the
libraries built in A1, proving packaging and signing did not alter them:

| Library | SHA-256 (built = extracted) |
|---|---|
| `libsbxapplogic_ctprotocol_jni.so` | `ef9bad520bd1c94d9a942857425b80722d650190dd120dad8d9d070490e52c6e` |
| `libserialport_jni.so` | `e50efa5e59d111a695b6eb7d1457824df03921f53eb6e4eda04fc524f4d58a87` |

### Modernize fixes carried into the package

The arm64 variant layers the modernize patch, which this phase extended with
three fixes required for the app to launch cleanly on a current (API 33)
runtime. They are platform-compatibility shims, not protocol changes; CtProtocol
encode/decode semantics are untouched. See `ARM64_RUNTIME.md` for how each was
surfaced by the live run.

1. **PendingIntent FLAG_IMMUTABLE** - API 31+ requires an explicit mutability
   flag. The `MainService.a()` `getActivity` sites take the immutable flag
   (`0x4000000`) from `v14`, which already holds it, rather than clobbering the
   shared-zero register `v11`.
2. **Foreground notification channel** - new `FgChannelCompat.ensure()` shim
   (overlay) stamps a channel id on each `MainService` notification builder and
   registers the channel on API 26+, so `startForeground()` no longer throws
   `CannotPostForegroundServiceNotificationException` on API 33+.
3. **Apache HTTP legacy** - manifest `<uses-library
   android:name="org.apache.http.legacy" android:required="false"/>`, needed
   since API 28 dropped the Apache HTTP client from the boot classpath.
