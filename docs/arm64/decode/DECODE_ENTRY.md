# Decode entry contract (ORACLE-CAPTURED)

Gate D0 of the decoder-oracle phase. The observable entry contract of the stock
x86 CtProtocol library's inbound path, captured against the behavioral oracle,
not inferred from decompiler structure. Oracle `.so`:
`lib/x86/libsbxapplogic_ctprotocol_jni.so`, 99672 bytes,
SHA-256 `215a0bd15ef6f2dd9a5dca0a3c867824d9a61313b7a23cab8f6622779bee7f0e`
(the canonical oracle, [CHECKPOINT.md](../CHECKPOINT.md#1-stock-x86-ctprotocol-library)).
Harness: `oracle/run.sh … dec|seq`, mirror
`oracle/src/.../SbxSppCommandManager.java`, on AVD `Pixel_3a_API_30_x86` under
`app_process32`.

## JNI entry point

One reachable inbound method:

```
decode ([BI)Z   ->   Java_..._SbxSppCommandManager_decode(JNIEnv*, jclass, jbyteArray frame, jint len)
```

`static`, class-level (`jclass`, not `jobject`): there is no Java-side decoder
instance. The frame bytes and the length arrive as two separate arguments.

## Length is the explicit parameter, not the array length

Captured ([`vectors/dec_entry.out.txt`](../../../oracle/vectors/dec_entry.out.txt)):

| frame (array) | len arg | result |
|---|---|---|
| `5a03020000` (5) | 5 | `maxPlsCallback 0` |
| `5a03020000ff` (6) | 5 | `maxPlsCallback 0` |
| `5a03020000` (5) | 4 | no callback |
| `5a03020000ff` (6) | 6 | no callback |

A 6-byte array decoded with `len=5` fires the callback for the 5-byte frame: the
decoder reads exactly `len` bytes from offset 0 and ignores trailing array bytes.
`len=4` truncates below the frame and rejects; `len=6` pulls the trailing byte
in range and rejects on the length gate (below). Offset is implicitly 0; there is
no offset argument.

## Per-call lifetime: no persistent native decoder

`Decode::decode` (Ghidra `@0001a520`) constructs a fresh stack-local `Decode`
object and a fresh `Context` on every JNI call. The context is initialised each
call: capacity field = 1 (valid range 1..255), the callback-manager pointer
(`Context+4`) points at the process-global `MyListener` whose vtable is at real
vaddr `0x18dc8`. Nothing in the context survives the call.

No Java-visible init / reset / open / close / destroy method exists: construction
and destruction are implicit per call. This is confirmed behaviorally, not assumed
from constructor shape, by the D4 statefulness controls
([DECODE_REJECTION_MATRIX.md](DECODE_REJECTION_MATRIX.md) companion capture
`dec_state`): identical bytes produce identical output regardless of history, and
no call leaves residue for the next. There is therefore no decoder state to
persist, reset, or tear down in a reimplementation.

## Dispatch mechanism

A recognised frame dispatches one callback through the `MyListener` vtable:

```
iVar14 = *(int *)pbVar2;                 // pbVar2 = callback-manager (Context+4); iVar14 = its vtable
(**(code **)(iVar14 + OFFSET))(pbVar2, …argv);
```

Each `MyListener` vtable slot is a C++ `listen(...)` bridge that does
`GetEnv` + `CallStaticVoidMethod` into one cached Java callback. The opcode (and,
for several opcodes, a sub-command or length discriminant) selects `OFFSET`. The
full offset -> callback map is in
[DECODE_CALLBACK_MATRIX.md](DECODE_CALLBACK_MATRIX.md).

## Callback table resolves whole

`JNI_OnLoad` caches the `SbxSppCommandManager` class ref and 28 static method IDs
and is all-or-nothing: it returns `-1` unless every `GetStaticMethodID` succeeds.
The mirror class loads the stock `.so` without error, which proves all 28 callback
names, JNI signatures, and the declaring class resolve exactly as frozen in
[FREEZE.md](../FREEZE.md#inbound-callbacks-28-cached-static-methods-name---jni-signature).

## Return value is not the accept/reject signal

`decode` returns `jboolean`. Across every captured vector it returns `1`, with one
exception: an unknown top-level opcode returns `0`
([DECODE_REJECTION_MATRIX.md](DECODE_REJECTION_MATRIX.md), D3-7). A rejected frame
with a *recognised* opcode (bad length, bad sub-command, starved payload) still
returns `1`. **Acceptance is signaled by callback emission, not by the return
value.** A reimplementation must drive its accept/reject contract off whether a
callback is dispatched, and may reproduce `ret=0` only for the unrecognised-opcode
case.

## Frozen entry facts

1. Signature `decode([BI)Z`, static, one inbound method.
2. Reads exactly `len` bytes from offset 0; array may be longer; no offset arg.
3. Fresh `Decode`+`Context` per call; no persistent instance; no lifecycle method.
4. One callback per recognised frame, dispatched through the `MyListener` vtable.
5. All 28 callbacks resolve (JNI_OnLoad all-or-nothing, mirror loads clean).
6. `ret` is not the accept signal; callback emission is. `ret=0` only for an
   unknown opcode.
