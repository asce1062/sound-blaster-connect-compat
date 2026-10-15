# Oracle / differential harness

The stock 32-bit library is the behavioral oracle for the arm64 reimplementation
of `libsbxapplogic_ctprotocol_jni`. This harness runs the stock lib (or the
reimplementation) on a 32-bit x86 Android emulator and prints deterministic,
diffable lines; running both and diffing is the byte-for-byte differential check.

## How it works

`src/.../SbxSppCommandManager.java` is a mirror of the stock class with the exact
fully-qualified name, so the lib's static `Java_...` exports bind to its 35
native declarations and `JNI_OnLoad`'s `GetStaticMethodID` finds its 28 callback
methods. `System.load` loads whichever `.so` is passed; the harness drives a
fixed vector set and records results.

- `enc` mode: one `ENC <name> <argspec> = <hex>` per encode vector (empty hex =
  the lib rejected those args, e.g. an out-of-range value).
- `dec` mode: `DEC <line> (arr=<N>,len=<N>) -> ret=<0|1>` then `  CB <name> <args>`
  per callback in dispatch order, for each frame in the corpus file. A line may be
  `<hex>|<N>` to call `decode(bytes, N)` with `N` different from the array length
  (used to prove the length argument is explicit, not the array length).
- `seq` mode: stream/framing. Blank lines split the corpus into observation
  windows; within a window each line is one `decode()` call and the callback list
  is cleared only at window start, so cross-call buffering / state is directly
  observable. Prints `=== group`, `CALL <g>.<c> <line> (len=N) -> ret`, indented
  `CB`/`(no callback)`, `--- end group`.

## Run

Needs a running 32-bit x86 AVD (e.g. `Pixel_3a_API_30_x86`; `abilist` must
include `x86`) and JDK + the Android SDK (`platform-tools`, `platforms/android-30`,
`build-tools/33.0.1`).

```bash
oracle/run.sh <path-to-.so> enc                 # encode vectors
oracle/run.sh <path-to-.so> dec corpus.txt      # decode a hex-frame corpus
oracle/run.sh <path-to-.so> seq corpus.txt      # stream/framing (windowed calls)
```

It compiles the mirror, dexes it with `d8`, pushes the dex + lib to
`/data/local/tmp/oracle`, and runs under `app_process32`.

## vectors/

`vectors/enc_stock.txt` is the captured encode oracle from the stock
`lib/x86/libsbxapplogic_ctprotocol_jni.so` (grade: ORACLE-CAPTURED). The
reimplementation passes when `oracle/run.sh <reimpl>.so enc` matches it
byte-for-byte (grade: DIFFERENTIAL-PASS).

Empty-hex rows are the lib's input validation (e.g. `setBtAutoConnect` accepts
only 0/1, `setVoicePromptCtrl` 0-2). Builders needing in-range args to emit a
frame (`setHwBtn`, `setFileSize`, `setMalcolmParam`) get valid-domain vectors
derived from the decompiled range checks in a later pass.

The decode oracle (grade: ORACLE-CAPTURED) is captured in five input/output
pairs; each `.out.txt` is the frozen capture its `.txt` reproduces line for line:

- `dec_entry.txt` - D0 length-semantics probe (`dec` mode, `|N` override).
- `dec_valid.txt` - D1 valid-frame corpus, one accepted frame per reachable
  callback family plus op19 record-ordering demonstrators (`dec` mode).
- `dec_stream.txt` - D2 stream/framing, 8 scenarios (`seq` mode).
- `dec_reject.txt` - D3 bounded rejection matrix, each mutant paired with a
  known-good control (`seq` mode).
- `dec_state.txt` - D4 statefulness controls (`seq` mode).

Analysis and the Phase 2 verdict are in [`docs/arm64/decode/`](../docs/arm64/decode/).
