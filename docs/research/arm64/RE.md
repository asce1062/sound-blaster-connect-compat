# arm64 native track — reverse engineering

Recovering the two 32-bit native libraries so they can be rebuilt for
`arm64-v8a` (64-bit-only devices) and so the command protocol is documented
for a future first-party app.

Source: `SBConnect_v1.04.02.apk`, `lib/armeabi-v7a/`. Both libs are the same
across ABIs. Tools: NDK 25.1 llvm-readelf / objdump / cxxfilt.

## Feasibility verdict

Both libraries are **recoverable**. Neither is obfuscated; both keep a full
dynamic symbol table (stripped of debug info only).

| Library | Nature | arm64 path |
|---|---|---|
| `libserialport_jni.so` | Stock `android-serialport-api` (`native_open`/`native_close`, `JNI_OnLoad` + RegisterNatives) | Rebuild from public source for arm64-v8a. No RE needed. |
| `libsbxapplogic_ctprotocol_jni.so` | Creative's SPP command protocol: `Encode` (encoder), `MsgListener` (decoder), named JNI bridge | Decompile the command builders to recover byte layouts, then reimplement + build for arm64-v8a. This is also the protocol the own app needs. |

"SPP" = Bluetooth Serial Port Profile: commands are framed byte arrays sent
over an RFCOMM SPP link to the device.

## ctprotocol library

- 271 exported FUNCs. Classes: `Encode` (79), `MsgListener` (62),
  `MyListener` (31), plus `checksum(int, uint8_t*, uint8_t*)` and libgcc
  unwind helpers.
- Every `Encode` method has the shape
  `Encode::<cmd>(Context*, uint8_t* buf, int* len, <args...>)` — it writes the
  command frame into `buf` and its length into `len`. Recovering the protocol
  = decompiling these to read the opcode, framing and payload layout.
- JNI bridge class: `com.creative.logic.sbxapplogic.vendor.sbx.SbxSppCommandManager`
  (static `Java_...` exports, not RegisterNatives, so the Java↔native binding
  is fully visible on both sides).

### JNI methods (41)

```
cancelFileTransfer        getBatteryStatus            getProfileInfoRec
commitSettings            getBatteryStatusSupport     getVoicePromptCtrl
decode                    getBtAutoConnect            hwBtnEnabled
getActiveProfileMega      getDeviceFwString           releaseControl
getActiveProfileRec       getFileDataBlk              requestControl
getAudioCtrlInfo          getFileTransferMaxDataSize  resetFactoryDefault
getAudioLvl               getFwInfo                   setActiveProfileMega
getAudioLvlRange          getGeneralInfo              setActiveProfileMegaVoicePreview
getBatteryLevel           getHwBtn                    setActiveProfileRec
getBatteryLevelSupport    getHwBtnStatusSupport       setActiveProfileRecVoicePreview
                          getHwBtnSupport             setAudioLvl
                          getMalcolmParam             setBtAutoConnect
                          getMaxPayloadSize           setFileSize
                                                      setHwBtn
                                                      setHwBtnWithSaveState
                                                      setMalcolmParam
                                                      setTime
                                                      setVoicePromptCtrl
```

### Encode command builders (76)

Control / session:
`getProtocolVer` · `setProtocolVer` · `requestControl` · `releaseControl` ·
`commitSettings` · `resetFactoryDefault` · `ackObsolete` · `ackPending` ·
`ackWithData`

Device info:
`getGeneralInfo` · `getFirmwareInfo` · `getFirmwareString` ·
`getMaxPayloadSize` · `getFeatureGroupSupport` · `getHwCtrlSubfeature`

Audio:
`getAudioCtrl` · `getAudioCtrlName` · `getAudioLvl` · `setAudioLvl` ·
`getAudioLvlRange` · `getAudioMute` · `setAudioMute`

Battery:
`getBattLvl` · `getBattLvlSupport` · `getBattStatus` · `getBattStatusSupport`

Hardware buttons:
`getHwBtn` · `setHwBtn` · `hwBtnEnabled` · `getHwBtnSupport` ·
`getHwBtnStatusSupport` · `setHwBtnWithSaveState`

LED:
`getLedCtrl` · `setLedCtrl` · `getLedCtrlSupport`

EQ / coefficients:
`getCoeff` · `setCoeff` · `getCoeffSetup` · `setCoeffSetup` ·
`getCoeffPreset` · `setCoeffPreset` · `getCoeffPresetName` ·
`setCoeffPresetName` · `getCoeffPresetSupport`

"Malcolm" DSP (SBX / Acoustic Engine effects):
`getMalcolmParam` · `setMalcolmParam` · `getMalcolmParamConfig` ·
`getMalcolmParamCustom` · `getMalcolmParamDefault` · `getMalcolmSubfeatureSupport` ·
`getMalcolmProfile` · `setMalcolmProfile` · `getMalcolmProfileInfo` ·
`getMalcolmActiveProfile` · `setMalcolmActiveProfile` ·
`setMalcolmActiveProfileVoicePreview` · `saveMalcolmProfile` ·
`restoreMalcolmProfile` · `getDefaultProfile`

Other feature control:
`getFeatureCtrl` · `setFeatureCtrl` · `getFeatureCtrlSupport` ·
`getFeatureCtrlSetOnly` · `getFeatureCtrlStatusOnly` ·
`getAdvCtrlSubfeatureSupport` · `getVoicePromptCtrl` · `getBtAutoConnect` ·
`setBtAutoConnect` · `setTime`

Room calibration:
`getRoomCalibSetupParam` · `startSweepTone` · `stopSweepTone`

File transfer (firmware / profile files):
`getFileDataBlk` · `sendFile` · `fileTransferCancel`

## serialport library — DONE (arm64-v8a built)

Decompiled `native_open` / `native_close` / `JNI_OnLoad` and rebuilt faithfully
at [patches/arm64/native/serialport/serialport.c](../../../patches/arm64/native/serialport/serialport.c);
arm64-v8a `.so` staged in `patches/arm64/overlay/lib/arm64-v8a/`.

- Bound to `com.creative.serialport.SerialPort` via `RegisterNatives` in
  `JNI_OnLoad` (JNI 1.6): `open(String,int)->FileDescriptor`, `close()->int`.
- `open`: maps baud to its CBAUD code (the Katana uses 38400 = `0x9600`),
  `open(path, 0x1102)` (`O_RDWR|O_NOCTTY|0x1000`), `TCGETS`, applies the raw
  masks (`c_iflag &= 0xfffffa14`, `c_oflag &= 0xfffffffe`, `c_lflag &=
  0xffff7fb4`, `c_cflag = (c_cflag & 0xffffeec0) | 0x30 | speed`), `TCSETS`,
  then returns a `java.io.FileDescriptor` with its `descriptor` int set.
- One process-global fd: `open` stores it, `close` shuts it and returns 1.

## ctprotocol library — port scoped, encode/decode open

Lib name `sbxapplogic_ctprotocol_jni` (fallback `System.load
("/system/lib/libsbxapplogic_ctprotocol_jni.so")`), bound to
`SbxSppCommandManager` by static `Java_...` export name (no RegisterNatives).
Full surface to rebuild:

- **checksum**: `(0xFF - sum(bytes)) & 0xFF` (above).
- **76 `Encode` builders**: fixed `5A <op> <sub> <payload>` templates with
  little-endian args spliced in; mechanical to port from the decompilation.
- **35 JNI wrappers**: marshal the Java args / `byte[]` and call the matching
  `Encode::<cmd>`, returning the frame as a `byte[]` (or `decode`/sizes).
- **`Decode::decode(Context*, uint8_t*, int)`**: one 7390-byte dispatcher that
  validates `[5A][type][plen]` (`plen == len-3`), builds a typed `XxxMsg`, and
  calls the registered listener.
- **~27 listener upcalls**: `MsgListener` declares ~60 virtual `listen(XxxMsg)`
  slots; `MyListener` overrides the ~27 the app consumes, each doing
  `GetEnv` + `CallStaticVoidMethod` into a cached `SbxSppCommandManager`
  static callback.
- **`JNI_OnLoad`**: caches the `SbxSppCommandManager` global class ref and the
  ~27 callback method IDs.

### Inbound callback API (device response -> Java static method)

`JNI_OnLoad` caches these `SbxSppCommandManager` static methods; `Decode`
upcalls them with the parsed fields. Names + JNI signatures:

```
requestControlCallback          dataAckCallback            obsoleteAckCallback
pendingAckCallback              fileAckCallback            deviceInfoCallback
fwInfoCallback                  maxPlsCallback             hwBtnCallback
audioCtrlCallback               audioLvlCallback           audioLvlRangeCallback
batteryLevelSupportCallback     batteryLevelCallback       batteryStatusSupportCallback
batteryStatusCallback           hwBtnSupportCallback       hwBtnStatusSupportCallback
hwBtnEnabledCallback            sbxProfileInfoCallback     sbxProfileDataCallback
btAutoConnectCallback           devicefwStringCallback     profileInfoRecFirstCallback
profileInfoRestCallback         activeProfileRecCallback   activeProfileMegaCallback
voicePromptCtrlCallback
```

Observed JNI signatures (map to the callbacks above): `(I)V`, `(IZ)V`,
`(ZZ)V`, `(II)V`, `(III)V`, `(IIIII)V`, `(II[B)V`, `([I)V`, `(IFI)V`,
`(IFFFIII)V`, `(IZZZZZZZ)V`, `(IIIZIZZIZ)V`, `(IIZIZZIZ)V`, `(Z)V`.

### Verification without the device

The Katana can't be paired right now (dead batteries, no working app), so the
port can't be validated against real hardware. The APK ships `lib/x86/`, so the
practical check is differential: build the reimplementation for x86, load it and
the stock x86 `.so` in an Android x86 emulator, and compare `Encode` `byte[]`
outputs and `decode` callback sequences for the same inputs. Encode diffs are
exact; decode is checked by callback name + argument values.

## Command frame format

Recovered by decompiling the `Encode` builders, `Decode::decode`, and
`checksum` (Ghidra 12.1.4 headless; REA's win32 Ghidra provider is PE-only so
it cannot open ARM ELF, same decompiler engine either way).

Every method has the shape
`Encode::<cmd>(Context*, uint8_t* buf, int* len, <args...>)`: it validates
capacity, writes the frame into `buf`, and stores the byte count in `*len`.

### Outbound (host -> device)

```
offset 0   0x5A            fixed start marker ('Z'), every command
offset 1   op              operation/feature group
offset 2   sub             sub-selector within the group
offset 3.. payload         command arguments, little-endian scalars
```

The length is implicit: fixed per opcode for simple commands, carried in the
frame for variable ones (see file transfer). No trailing checksum on command
frames. Worked examples:

| Command | Bytes | Len |
|---|---|---|
| `requestControl` | `5A 06 01 01` | 4 |
| `releaseControl` | `5A 06 01 00` | 4 |
| `getFirmwareInfo(n)` | `5A 07 02 01 nn` | 5 |
| `setTime(t)` | `5A 3B 04 t0 t1 t2 t3` | 7 |
| `setLedCtrl(...)` | `5A 3A 09 00 FF 00 00 00 pp 00 00 00` | 12 |
| `getFileDataBlk(buf,n,blk)` | `5A 98 (n+2) blk n <n data bytes>` | n+5 |

`setTime` writes the 32-bit value little-endian (`buf[3..6] = t>>0,8,16,24`);
that byte order holds for every multi-byte scalar. `requestControl` vs
`releaseControl` differ only in `buf[3]` (1 = take control, 0 = release), so
`op=0x06 sub=0x01` is the control-session command and byte 3 its on/off flag.

`getFileDataBlk` is the one builder with an in-frame length: `buf[2]` =
payload + 2, `buf[4]` = payload length `n` (1..0xFD), `buf[3]` = block id
(0x80..0x82), then `n` raw data bytes.

### Inbound (device -> host) — `Decode::decode(Context*, uint8_t*, int len)`

One 7390-byte dispatcher. Framing:

```
offset 0   0x5A            echoed start marker
offset 1   type            response type/status (e.g. 0x22, 0x13)
offset 2   plen            payload length == total len - 3
offset 3.. payload
```

It rejects `len < 3`, checks `plen == len - 3`, then dispatches on the
feature id and total length (`len == 5 / 6 / 7 / 0xD ...`) into the
`MsgListener` vtable (`listen` overloads at vtable offsets 0x0C, 0x10, 0x14,
0xE0, 0xE4, ...), each a typed callback for one response shape. Feature ids
match the outbound side (`0x3A` LED, `0x98`/`0x99` file data, etc.). The
~60 `MsgListener::listen` thunks are these per-response vtable entries.

### checksum

```c
uint8_t checksum(int len, const uint8_t* data, uint8_t* out) {
    if (len < 0)   return 0x71;
    if (!data)     return 0x72;
    if (!out)      return 0x73;
    uint8_t c = 0xFF;
    for (int i = 0; i < len; i++) c -= data[i];
    *out = c;                 // *out = (0xFF - sum(data)) & 0xFF
    return 0;
}
```

Exported but not called by any `Encode` builder or by `Decode::decode`; it is
the file-transfer / integrity helper, available to callers rather than part of
the command framing above.

### JNI binding

`Java_...SbxSppCommandManager_<cmd>` wrappers marshal the Java `byte[]` and
call the matching `Encode::<cmd>`; `..._decode` hands the inbound buffer to
`Decode::decode`. Static exports (not RegisterNatives), so both sides of every
binding are visible by name.

## Next

`libserialport_jni.so` is done. For `libsbxapplogic_ctprotocol_jni.so`, port in
this order under `patches/arm64/native/ctprotocol/`:

1. `checksum` + the 76 `Encode` builders + the 35 JNI wrappers (encode path;
   byte-exact against the decompilation, independently verifiable).
2. `JNI_OnLoad` callback caching + `Decode::decode` + the ~27 `MyListener`
   upcalls (decode path; verify differentially against the stock x86 lib).

Build with the NDK (`patches/arm64/native/build.ps1`) into the `arm64` overlay.
