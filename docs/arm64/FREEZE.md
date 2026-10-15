# Frozen contract (STATIC-MAPPED)

The behavioral contract the arm64 reimplementation must satisfy, frozen from the
stock 32-bit libraries in `SBConnect_v1.04.02.apk` and the decoded smali. The
original 32-bit library is the behavioral oracle; this file is the static map,
not an implementation. Grade: **STATIC-MAPPED** (no oracle capture yet).

Evidence: `lib/armeabi-v7a/*.so` (llvm-readelf/objdump/Ghidra headless) and
`decompiled/smali/...`. Frame spec and decode architecture in
[RE.md](RE.md); this file is the frozen inventory Phases E and D build against.

## Native libraries (complete)

The entire app loads exactly two native libraries (grep of every
`System.loadLibrary` / `System.load`):

| Lib | Loaded by | Binding model |
|---|---|---|
| `sbxapplogic_ctprotocol_jni` | `SbxSppCommandManager.<clinit>` (fallback `System.load("/system/lib/libsbxapplogic_ctprotocol_jni.so")`) | static `Java_...` exports; `JNI_OnLoad` only caches callbacks |
| `serialport_jni` | `com.creative.serialport.SerialPort.<clinit>` | `RegisterNatives` in `JNI_OnLoad` |

`com.creative.lib.protocolmgr.CtProtocolMgr` (the `BluzSocket` transport
framing) is **pure Java**, no native lib. There is no third native stack.

## Transport / reachability gate

Transport is chosen in `SbxSppCommandManager$2` (the command-handler thread).
`DeviceUtils.a(name)` is true for `"SOUND BLASTERX KATANA"` (and
`"SOUND BLASTER EDGE"`); that routes the connect to
`new BluzSocket(Context, CtProtocolMgr)` ("BluzSocket" branch), not to
`SbxSocketUART` and not to plain `SbxSocketBluetooth`.

- **ctprotocol — REQUIRED (gate POSITIVE).** `SbxSppCommandManager`'s own
  methods call the native encoders (`getFwInfo`@4181, `getGeneralInfo`@6750,
  `getBatteryLevel`@9812, ...) and `decode([BI)Z`@17715. Katana command flow:
  `SbxSppCommandManager.<cmd>()` -> native frame `byte[]` -> `BluzSocket` ->
  `CtProtocolMgr.a([B,int)` -> BT; inbound reverses into `decode`.
- **serialport — NOT on the Katana path (gate NEGATIVE).** `SerialPort` is
  reached only via `SbxSocketUART$ConnectThread`, which the Katana never
  selects. Kept as an isolated arm64 compat component for UART devices; it does
  not block ctprotocol.

## serialport_jni — frozen

- JNI_OnLoad: `RegisterNatives` on `com/creative/serialport/SerialPort`, JNI 1.6:
  - `open  (Ljava/lang/String;I)Ljava/io/FileDescriptor;` -> `native_open`
  - `close ()I`                                           -> `native_close`
- Deps: `liblog.so`, `libm.so`, `libdl.so`, `libc.so`.
- Primitives: baud->CBAUD table; `open(path, 0x1102)`; raw termios masks
  (`c_iflag&=0xfffffa14`, `c_oflag&=0xfffffffe`, `c_lflag&=0xffff7fb4`,
  `c_cflag=(c_cflag&0xffffeec0)|0x30|speed`); single process-global fd.
  Full detail in [RE.md](RE.md); reimplemented at
  `patches/arm64/native/serialport/serialport.c` (built, arm64-v8a).

## ctprotocol_jni — frozen

Deps of the stock lib: `libstdc++.so`, `libm.so`, `libc.so`, `libdl.so`. The
reimplementation core is written in **C** (no STL), so the arm64 build drops
`libstdc++` and adds only `liblog` if it logs.

### JNI exports — 35 Java native methods (`SbxSppCommandManager`, all `private static native`)

Bound by export name `Java_com_creative_logic_sbxapplogic_vendor_sbx_SbxSppCommandManager_<name>`.

```
cancelFileTransfer                ()[B          getHwBtnStatusSupport ()[B
commitSettings                    ()[B          getHwBtnSupport       ()[B
decode                            ([BI)Z        getMaxPayloadSize     ()[B
getActiveProfileMega              ()[B          getProfileInfoRec     ()[B
getActiveProfileRec               ()[B          getVoicePromptCtrl    ()[B
getAudioLvl                       (I)[B         hwBtnEnabled          ()[B
getBatteryLevel                   ()[B          releaseControl        ()[B
getBatteryLevelSupport            ()[B          resetFactoryDefault   ()[B
getBatteryStatus                  ()[B          setActiveProfileMega  (I)[B
getBatteryStatusSupport           ()[B          setActiveProfileMegaVoicePreview (I)[B
getBtAutoConnect                  ()[B          setActiveProfileRec   (I)[B
getDeviceFwString                 ()[B          setActiveProfileRecVoicePreview  (I)[B
getFileDataBlk                    ([BIZ)[B      setBtAutoConnect      (I)[B
getFileTransferMaxDataSize        ()I           setFileSize           (II)[B
getFwInfo                         (I)[B         setHwBtn              (II)[B
getGeneralInfo                    ()[B          setMalcolmParam       ([I[I[FI[I)[B
                                                setTime               (I)[B
                                                setVoicePromptCtrl    (I)[B
```

Return `[B` = the command frame to send; `decode([BI)Z` = feed an inbound
frame; `getFileTransferMaxDataSize()I` = a scalar getter.

### Inbound callbacks — 28 cached static methods (name -> JNI signature)

`JNI_OnLoad` caches the `SbxSppCommandManager` global class ref and these method
IDs; `Decode` upcalls them via `CallStaticVoidMethod`. Signatures are the
authoritative Java-side descriptors.

```
requestControlCallback        (Z)V
dataAckCallback               (II[B)V
obsoleteAckCallback           (II)V
pendingAckCallback            (III)V
fileAckCallback               (III)V
deviceInfoCallback            (II)V
fwInfoCallback                (IIIII)V
maxPlsCallback                (I)V
hwBtnCallback                 (IZZZZZZZ)V
audioCtrlCallback             (IZ)V
audioLvlCallback              (IFI)V
audioLvlRangeCallback         (IFFFIII)V     [declared-synchronized]
batteryLevelCallback          (I)V
batteryLevelSupportCallback   (III)V
batteryStatusCallback         (ZZ)V
batteryStatusSupportCallback  (ZZ)V
hwBtnSupportCallback          (IZZZZZZZ)V
hwBtnStatusSupportCallback    (IZZZZZZZ)V
hwBtnEnabledCallback          (IZZZZZZZ)V
sbxProfileInfoCallback        (II)V
sbxProfileDataCallback        (I)V
btAutoConnectCallback         (I)V
devicefwStringCallback        ([I)V
profileInfoRecFirstCallback   (IIIZIZZIZ)V
profileInfoRestCallback       (IIZIZZIZ)V
activeProfileRecCallback      (IZ)V
activeProfileMegaCallback     (IZ)V
voicePromptCtrlCallback       (I)V
```

### Encode builder inventory

271 exported FUNCs; `Encode` has 76 command builders (full list in
[RE.md](RE.md)), each `Encode::<cmd>(Context*, uint8_t* buf, int* len, args...)`.
Not all 76 are reachable: the reachable set is those invoked by the 35 JNI
wrappers above (e.g. `getFwInfo` -> `Encode::getFirmwareInfo`, `setMalcolmParam`
-> several). Phase E pins the exact reachable set by reading each JNI wrapper's
`Encode` call; dead builders are documented, not reimplemented.

### Callback / listener inventory

`MsgListener` declares ~60 virtual `listen(XxxMsg)` slots; `MyListener`
overrides the 28 above. Each override does `GetEnv` + `CallStaticVoidMethod`
into the matching cached callback. `Decode::decode` (7390 bytes) is the single
inbound dispatcher.

### Framing / checksum primitives

- Outbound: `0x5A <op> <sub> <payload...>`, length implicit per opcode (or
  in-frame for file transfer), little-endian scalars, no trailing checksum.
- Inbound: `[0x5A][type][plen]` + payload, `plen == len - 3`, dispatched on
  feature id + length.
- `checksum(len, data, out)`: `*out = (0xFF - sum(data[0..len])) & 0xFF`;
  returns 0 / `0x71` (len<0) / `0x72` (null data) / `0x73` (null out). Exported,
  not used by the command framing (file-transfer / integrity helper).

## Architecture target

- `ctprotocol-core`: portable C, no JNI, no Android. Encoder (builders +
  framing + checksum) and parser (decode + typed message structs). Directly
  reusable by a future first-party app.
- JNI shim: translate Java args <-> core types, call core, translate decode
  events into the stock Java callbacks. No protocol logic.

## Open items before COMPLETE

Per the mission stop conditions, none of the following may be assumed:
exact reachable-builder set (pin in Phase E), decode callback ordering and
per-field argument values (capture in Phase D against the oracle), any field
whose value depends on device state not reproducible in the oracle harness.
Hardware is unavailable (dead batteries, no pairing), so the ceiling grade is
**ARM64-INTEGRATED**.
