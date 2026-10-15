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
- `dec` mode: `DEC <frameHex> -> ret=<0|1>` then `  CB <name> <args>` per
  callback in dispatch order, for each frame in the corpus file.

## Run

Needs a running 32-bit x86 AVD (e.g. `Pixel_3a_API_30_x86`; `abilist` must
include `x86`) and JDK + the Android SDK (`platform-tools`, `platforms/android-30`,
`build-tools/33.0.1`).

```bash
oracle/run.sh <path-to-.so> enc                 # encode vectors
oracle/run.sh <path-to-.so> dec corpus.txt      # decode a hex-frame corpus
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
