# Checkpoint - 32-bit oracle lane (CLOSED)

Final checkpoint for the 32-bit behavioral-oracle lane of the arm64 native
track. This lane froze the ctprotocol contract, built the 32-bit differential
harness, and captured the encode oracle from the stock library. It stops here
by direction: no `ctprotocol-core`, no further protocol implementation in this
lane. The record below is what a later implementation lane inherits.

Date: 2026-10-15. Branch: `native/arm64` (absorbed into `main`).

## 1. Stock x86 CtProtocol library

- Path in APK: `lib/x86/libsbxapplogic_ctprotocol_jni.so` (from
  `SBConnect_v1.04.02.apk`), 99672 bytes.
- SHA-256: `215a0bd15ef6f2dd9a5dca0a3c867824d9a61313b7a23cab8f6622779bee7f0e`

This exact file is the encode oracle. For cross-reference, the armeabi-v7a
sibling used for static RE is
`3097c0bebea0ba14c36418bd38be1bdf97edb5554831dbcf92aeaf8ea1b1e803`.

## 2. Oracle emulator

- AVD: `Pixel_3a_API_30_x86`
- API level: 30 (Android 11)
- ABI: `x86` (32-bit; device `abilist` = `x86,armeabi-v7a,armeabi`)
- Image: Google APIs x86 system image, API 30

The stock x86 `.so` runs here under `app_process32`, 32-bit, matching the
library's word size. This is the ground-truth environment; the reimplementation
is diffed against output captured on the same AVD.

## 3. Oracle harness

- Source: [`oracle/`](../../../oracle/) - mirror class
  `oracle/src/com/creative/logic/sbxapplogic/vendor/sbx/SbxSppCommandManager.java`
  (exact FQN so the lib's static `Java_...` exports bind and `JNI_OnLoad`
  resolves the callbacks), runner `oracle/run.sh`, docs `oracle/README.md`.
- Commit: `b6e92b9` (`test(oracle): add the 32-bit differential harness and
  capture encode vectors`).
- Mechanism: compile mirror -> `d8` dex -> push dex + chosen `.so` to the AVD ->
  run under `app_process32`, printing deterministic `ENC`/`INT`/`DEC` lines.
  Running the stock lib and the reimplementation through the same harness and
  diffing the output is the byte-for-byte differential check.

## 4. Encode-vector corpus

- File: [`oracle/vectors/enc_stock.txt`](../../../oracle/vectors/enc_stock.txt)
- Count: 97 vectors - 96 `ENC` (command frame) + 1 `INT`
  (`getFileTransferMaxDataSize` scalar getter).
- 77 emit a frame / value; 20 `ENC` rows are empty-hex, which is the stock
  lib's input validation (e.g. `setBtAutoConnect` accepts only 0/1,
  `setVoicePromptCtrl` 0-2). The reimplementation must reject the same args
  identically, not merely match the non-empty frames.
- Grade: ORACLE-CAPTURED. Captured from the stock x86 `.so` above.

## 5. Frozen JNI native-method table

35 reachable `private static native` methods on `SbxSppCommandManager`, bound
by export name
`Java_com_creative_logic_sbxapplogic_vendor_sbx_SbxSppCommandManager_<name>`.
Full table with signatures in [FREEZE.md](FREEZE.md#jni-exports). Summary:

```
cancelFileTransfer ()[B       getFwInfo (I)[B                 setActiveProfileMega (I)[B
commitSettings ()[B           getGeneralInfo ()[B             setActiveProfileMegaVoicePreview (I)[B
decode ([BI)Z                 getHwBtnStatusSupport ()[B      setActiveProfileRec (I)[B
getActiveProfileMega ()[B      getHwBtnSupport ()[B           setActiveProfileRecVoicePreview (I)[B
getActiveProfileRec ()[B       getMaxPayloadSize ()[B          setBtAutoConnect (I)[B
getAudioLvl (I)[B              getProfileInfoRec ()[B          setFileSize (II)[B
getBatteryLevel ()[B           getVoicePromptCtrl ()[B         setHwBtn (II)[B
getBatteryLevelSupport ()[B    hwBtnEnabled ()[B               setMalcolmParam ([I[I[FI[I)[B
getBatteryStatus ()[B          releaseControl ()[B             setTime (I)[B
getBatteryStatusSupport ()[B   resetFactoryDefault ()[B        setVoicePromptCtrl (I)[B
getBtAutoConnect ()[B          getFileDataBlk ([BIZ)[B
getDeviceFwString ()[B         getFileTransferMaxDataSize ()I
```

## 6. Frozen callback table

28 inbound callbacks, cached by `JNI_OnLoad` and upcalled from `Decode::decode`
via `CallStaticVoidMethod`. Full table with JNI signatures in
[FREEZE.md](FREEZE.md#inbound-callbacks). Names:

```
requestControlCallback        dataAckCallback               obsoleteAckCallback
pendingAckCallback            fileAckCallback               deviceInfoCallback
fwInfoCallback                maxPlsCallback                hwBtnCallback
audioCtrlCallback             audioLvlCallback              audioLvlRangeCallback
batteryLevelCallback          batteryLevelSupportCallback   batteryStatusCallback
batteryStatusSupportCallback  hwBtnSupportCallback          hwBtnStatusSupportCallback
hwBtnEnabledCallback          sbxProfileInfoCallback        sbxProfileDataCallback
btAutoConnectCallback         devicefwStringCallback        profileInfoRecFirstCallback
profileInfoRestCallback       activeProfileRecCallback      activeProfileMegaCallback
voicePromptCtrlCallback
```

## 7. Exports confirmed unbound by this APK

The `.so` exports 41 `Java_...SbxSppCommandManager_<name>` symbols; 6 have no
matching Java `native` declaration in `SBConnect_v1.04.02.apk`, so this APK
never binds or calls them. Vestigial; not reimplemented:

```
requestControl      getMalcolmParam     setAudioLvl
getAudioLvlRange    getAudioCtrlInfo    setHwBtnWithSaveState
```

## 8. Katana transport-path conclusion

The Katana (`"SOUND BLASTERX KATANA"`) connects through
`new BluzSocket(Context, CtProtocolMgr)`, selected in
`SbxSppCommandManager$2` via `DeviceUtils.a(name)`. Command flow:
`SbxSppCommandManager.<cmd>()` -> native frame `byte[]` -> `BluzSocket` ->
`CtProtocolMgr.a([B,int)` (pure Java) -> Bluetooth; inbound reverses into
`decode([BI)Z`.

- `ctprotocol_jni` is REQUIRED on the Katana path (gate POSITIVE).
- `serialport_jni` is NOT on the Katana path (gate NEGATIVE): reached only via
  `SbxSocketUART$ConnectThread`, which the Katana never selects. It is retained
  as an isolated arm64 compat component for UART devices and is already rebuilt
  for arm64-v8a
  ([`patches/arm64/overlay/lib/arm64-v8a/libserialport_jni.so`](../../patches/arm64/overlay/lib/arm64-v8a/libserialport_jni.so)).

The entire app loads exactly these two native libraries; there is no third
native stack. `CtProtocolMgr` itself is pure Java.

## 9. Current evidence grade

**ORACLE-CAPTURED / ENCODE.** The encode surface is captured from the stock
library as deterministic vectors. Nothing beyond encode capture is claimed:
no reimplementation has been differentially verified, and the decode surface
has no oracle yet.

## 10. Unresolved work (inherited by a later lane)

1. Encoder differential implementation - write a portable encoder and reach
   DIFFERENTIAL-PASS against `enc_stock.txt` (including identical arg
   rejection), plus valid-domain vectors for builders that need in-range args
   (`setHwBtn`, `setFileSize`, `setMalcolmParam`).
2. Decoder oracle - build the `dec`-mode corpus of inbound frames and capture
   callback name + typed args + dispatch order from the stock lib.
3. Decoder implementation - parser to DIFFERENTIAL-PASS against the decode
   oracle.
4. JNI parity - the thin shim translating Java args <-> core types and decode
   events -> the 28 Java callbacks, with no protocol logic.
5. arm64 integration - build core + shim for arm64-v8a, wire into the overlay,
   reach ARM64-INTEGRATED.
6. Hardware validation - unavailable (dead batteries, no pairing). The ceiling
   grade for this project is therefore ARM64-INTEGRATED; HARDWARE-VERIFIED is
   not reachable until a live device exists.

Do not begin `ctprotocol-core` in this lane.

## Lane status

CLOSED - ABSORBED INTO MAIN.
