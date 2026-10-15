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

## serialport library

- `native_open(JNIEnv*, jobject, jstring path, int baud)`,
  `native_close(JNIEnv*, jobject)`, `JNI_OnLoad` (RegisterNatives).
- Matches the widely-used `android-serialport-api`. The arm64 build comes
  from that public source compiled with the NDK; nothing device-specific.

## Next

Decompile a representative `Encode` builder (e.g. `setLedCtrl`,
`getFirmwareInfo`) and `checksum` to pin the exact frame: opcode table,
header/length framing, and checksum algorithm. That frame spec is what both
the arm64 reimplementation and the own app are built on. Decompilation via
REA/Ghidra; findings land here.
