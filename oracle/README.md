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

Needs:

- A running 32-bit x86 emulator reachable by adb. `app_process32` must exist
  and `ro.product.cpu.abilist` must include `x86`. An API 30 `google_apis/x86`
  system image works, for example an AVD named `Pixel_3a_API_30_x86`. 64-bit
  x86_64 images from API 31 on drop the 32-bit runtime and do not work.
- A JDK (`javac`, `java`) and the Android SDK with `platform-tools`,
  `platforms/android-30` and `build-tools/33.0.1`. The SDK is found through
  `ANDROID_SDK_ROOT`, then `ANDROID_HOME`, then `%LOCALAPPDATA%/Android/Sdk`.
- Windows with a bash that provides `cygpath` (Git Bash or MSYS2). The script
  converts local paths with `cygpath -m` and calls `adb.exe`; it does not run
  unchanged on Linux or macOS.

The library under test is an x86 build: the stock
`lib/x86/libsbxapplogic_ctprotocol_jni.so` extracted from the stock APK, or the
portable reimplementation built with the NDK for `x86`.

For a check that needs no emulator, [`tests/ctprotocol/`](../tests/ctprotocol/)
replays the same vector files against the portable core with a host compiler.

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
only 0/1, `setVoicePromptCtrl` 0-2). Builders that need in-range arguments to
emit a frame (`setHwBtn`, `setFileSize`, `setMalcolmParam`) have valid-domain
vectors derived from the stock range checks.

The decode oracle (grade: ORACLE-CAPTURED) is captured in five input/output
pairs; each `.out.txt` is the frozen capture its `.txt` reproduces line for line:

- `dec_entry.txt` - length-semantics probe (`dec` mode, `|N` override).
- `dec_valid.txt` - valid-frame corpus, one accepted frame per reachable
  callback family plus op19 record-ordering demonstrators (`dec` mode).
- `dec_stream.txt` - stream/framing, 8 scenarios (`seq` mode).
- `dec_reject.txt` - bounded rejection matrix, each mutant paired with a
  known-good control (`seq` mode).
- `dec_state.txt` - statefulness controls (`seq` mode).

In `seq` mode the harness echoes corpus comment lines. `dec_reject.txt` and
`dec_state.txt` gained header comments after their outputs were captured, so
compare outputs on lines that do not start with `#`.

The vector files are the behavioral contract of the encoder and decoder and are
never edited. Their checksums, grades and the records behind them are listed
in [`docs/research/README.md`](../docs/research/README.md); the contract itself
is described in [`docs/technical/CTPROTOCOL.md`](../docs/technical/CTPROTOCOL.md).
