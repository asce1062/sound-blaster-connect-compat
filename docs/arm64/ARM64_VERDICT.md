# ARM64_VERDICT

Phase 5 verdict for the native CtProtocol arm64 bringup.

```
VERDICT = ARM64_INTEGRATED
```

## Grade criteria, each met

| Requirement | Status | Evidence |
|---|---|---|
| True arm64-v8a runtime (not an x86_64 AVD) | met | Pixel 7a, 64-bit-only (`abilist32` empty), `ARM64_RUNTIME.md` A4 |
| APK installs on that runtime | met | `adb install -r` Success; `primaryCpuAbi=arm64-v8a` |
| arm64 libraries selected and loaded | met | `nativeloader` arm64 path; `SbxSppCommandManager` native loads |
| JNI binding succeeds | met | natives bind, no UnsatisfiedLinkError; `handleProtocolEvent` runs |
| Normal device-connection UI reached | met | RFCOMM SPP to Katana, full Dashboard, BlasterX Experience preset screens |
| Negative control | met | stock APK -> `INSTALL_FAILED_NO_MATCHING_ABIS res=-113`, `ARM64_RUNTIME.md` A6 |

JNI parity (A0) was proven at `DIFFERENTIAL-PASS` against the x86 oracle; the
arm64 artifact is that same source recompiled, with one JNI implementation.

## Scope boundary

Hardware protocol correctness is **not** claimed by this grade. The app
connects to the physical Katana over Bluetooth SPP and the native command
manager processes live inbound commands, but systematic command/response
verification against hardware remains the separate `HARDWARE-VERIFIED` grade.

One non-fatal, out-of-scope anomaly is noted for that later phase: stock Java
`CtProtocolMgr.d()` logs a swallowed `ArrayIndexOutOfBoundsException
(length=13; index=13)` while processing certain live Katana frames. It is
caught in stock Java (not in the native library, which this project did not
modify), the app stays alive, and it would occur identically on the original
32-bit app. It is a stock-app frame-parsing quirk, not an arm64 integration
defect.

## Protocol-freeze attestation

No encoder or decoder semantics were modified during Phase 5. Every fix made to
reach a clean launch is a platform-API compatibility shim in the modernize
patch (manifest `uses-library` / permissions / foreground-service type, a
PendingIntent flag correction, and a notification-channel shim); none alters
CtProtocol byte behavior. The two native `.so` hashes are identical to the
A1-built libraries and unchanged across every packaging iteration.

## Deliverables

| Document | Covers |
|---|---|
| `ARM64_BUILD.md` | A0 JNI parity, A1 native metadata |
| `ARM64_PACKAGING.md` | A2 loader audit, A3 multi-ABI packaging |
| `ARM64_RUNTIME.md` | A4 runtime, A5 launch/load/bind/connect, A6 negative control |
| `ARM64_VERDICT.md` | this verdict |
| `runtime/device_abi.txt` | Pixel 7a ABI evidence |
| `runtime/launch_log_excerpt.txt` | bounded clean launch log |
| `runtime/junit_crash_excerpt.txt` | pre-fix preset-screen crash |
