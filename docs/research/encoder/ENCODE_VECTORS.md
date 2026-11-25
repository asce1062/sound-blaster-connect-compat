# Encode vectors

> **Historical record.** Kept as evidence of how behavior was established; not updated for later changes. Status, corrections and the maintained references: [research index](../README.md).

Catalog of the frozen encode corpus
[`oracle/vectors/enc_stock.txt`](../../../oracle/vectors/enc_stock.txt) and the
boundary coverage behind it. The corpus is captured from the stock x86
`libsbxapplogic_ctprotocol_jni.so`
(SHA-256 `215a0bd1...bee7f0e`) under `app_process32` on the
`Pixel_3a_API_30_x86` AVD, by
[`oracle/run.sh`](../../../oracle/run.sh) driving the mirror
`SbxSppCommandManager`. Each line is `ENC <method> <argspec> = <hex>` (empty
hex = stock rejection), one `INT` line for the scalar getter, and
`ENC setMalcolmParam ... = <hex> e=<e0>,<e1>` carrying the two output ints the
stock wrapper writes back.

Coverage principle: for every statically observed validation range, sweep
min-1 / min / min+1 / representative / max-1 / max / max+1, and keep the stock
rejection (empty frame) wherever the stock rejects.

## Fixed getters (constant frames)

One vector each; no input domain. `getMaxPayloadSize`, `getGeneralInfo`,
`getDeviceFwString`, `releaseControl`, `commitSettings`, `getHwBtn`,
`getHwBtnSupport`, `getHwBtnStatusSupport`, `hwBtnEnabled`, `getBatteryLevel`,
`getBatteryLevelSupport`, `getBatteryStatus`, `getBatteryStatusSupport`,
`getBtAutoConnect`, `getVoicePromptCtrl`, `resetFactoryDefault`,
`cancelFileTransfer`, `getProfileInfoRec`, `getActiveProfileRec`,
`getActiveProfileMega`, plus the scalar `getFileTransferMaxDataSize` (INT 253).

## One-argument builders

| Method | Field | Range | Vectors |
|---|---|---|---|
| `getFwInfo(n)` | n | 0..255 | -1, 0, 1, 64, 254, 255, 256, 257 |
| `getAudioLvl(n)` | n | 0..255 | -1, 0, 1, 64, 254, 255, 256, 257 |
| `setActiveProfileRec(n)` | n | 0..255 | -1, 0, 1, 64, 254, 255, 256, 257 |
| `setActiveProfileMega(n)` | n | 0..255 | (same) |
| `setActiveProfileRecVoicePreview(n)` | n | 0..255 | (same) |
| `setActiveProfileMegaVoicePreview(n)` | n | 0..255 | (same) |
| `setBtAutoConnect(v)` | v | {0,1} | -1, 0, 1, 2 |
| `setVoicePromptCtrl(v)` | v | {0,1,2} | -1, 0, 1, 2, 3 |
| `setTime(t)` | t | full int32 | 0, 1, 0x100, 0x12345678, 0x7fffffff, 0x80000000, 0xffffffff |

`-1`, `256`, `257` sit just outside the byte domain and are rejected;
`setTime` has no validation, so the sign-boundary values all emit.

## Two-argument builders

| Method | Field | Range | Vectors |
|---|---|---|---|
| `setHwBtn(id,val)` | id | 1..20 | id in {0,1,2,19,20,21} at val=1; plus {10,0} |
| `setHwBtn(id,val)` | val | {0,1} | val in {-1,0,1,2} at id=1 |
| `setFileSize(a,b)` | a | ==1 | a in {0,1,2} at b=2 |
| `setFileSize(a,b)` | b | LE32 | b in {0,1,0x100,0x12345678,0xffffffff} at a=1 |

## Variable-length builder

`getFileDataBlk(data,len,flag)`: `off = flag ? 0x81 : 0x80`, `len` in 1..253.
len swept {0,1,2,64,252,253,254} with `flag=false`, plus {64,1} with
`flag=true`. len 0 and 254 are rejected. (The stock builder's `data==null`
guard is not exercised: a null array aborts the VM in the JNI marshalling
before the builder runs, so it carries no vector.)

## setMalcolmParam

Validated fields: array-length agreement (marshalling), per-param group id,
per-param sub-index, per-param float range, and the group-splitting seed `d`.

- **Group-splitting (`grp_*`)**: `a[i]=0x97, b[i]=2` (float ignored) isolates
  the split. `n` in {0,1,2,3,5,7,8} across `d` in {0,16,43,259} exercises
  one-remainder, one-full, full+remainder, multi-full, the `(d-1)/6` group
  size, and the clamp to 42.
- **Group-id boundary (`gid_*`)**: `0x48`/`0x4a`/`0x98` reject (0x18),
  `0x49`/`0x8f`/`0x95`/`0x96`/`0x97` accept with an in-range sub/float, and
  `0x195` rejects (the full int is matched, not the low byte).
- **Sub-index boundary (`sub97_*`)**: group `0x97` subs {0,1,2,8,9}; 9 rejects
  (0x19).
- **Float range, continuous (`f95s1_*`)**: group `0x95` sub 1, range
  `[0, 11.66]`; -0.01 and 11.67 reject, 0.0 / 0.01 / 5.0 / 11.65 / 11.66 accept.
- **Float range, boolean (`f95s0_*`)**: group `0x95` sub 0 accepts only
  `{0.0, 1.0}`; -1.0 / 0.5 / 2.0 reject.
- **Whole-call rejection (`mix_reject`)**: one valid + one invalid param emits
  an empty frame.
- **Marshalling guard (`len_mismatch`)**: unequal array lengths emit an empty
  frame.

## Statefulness controls

- `STATE_repeat_getGeneralInfo` / `STATE_repeat_setTime` /
  `STATE_repeat_smp`: the same call three times.
- `STATE_inter_probe` a/b/c around `setTime(5)` and a `setMalcolmParam` call:
  a fixed probe before, between, and after unrelated calls.

The repeated and interleaved outputs are byte-identical within a run, and two
independent fresh-process runs are identical (see
[ENCODE_DIFFERENTIAL.md](ENCODE_DIFFERENTIAL.md)), so encode is stateless.
