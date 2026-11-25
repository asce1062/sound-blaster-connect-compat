# Testing

What checks exist, what each one proves, and how to run it. The CtProtocol
encoder and decoder have a frozen contract: the vector files in
[`oracle/vectors/`](../../oracle/vectors/), captured from the stock library.
Any change to `patches/arm64/native/ctprotocol/` must leave every vector set
passing, and the vector files themselves are never edited.

## Checks

| Check | Runs on | Proves | Command |
|---|---|---|---|
| Host regression | any C11 host compiler | The portable core reproduces all six frozen vector sets and the supplementary set through a driver that mirrors the JNI adapter's marshalling | see [Host regression](#host-regression) |
| Emulator differential | 32-bit x86 Android emulator | The stock x86 library and an x86 build of the portable source give byte-identical harness output, and both match the recorded vectors | see [Emulator differential](#emulator-differential) |
| `resign` payload proof | every `resign` build | Every non-signature entry of the re-signed APK is SHA-256 identical to stock | built into `apk-resign` |
| Patch anchor counts | every `modernize`/`arm64` build | Each manifest and smali edit hit exactly the expected number of sites in the stock tree | built into the variant targets |
| Native toolchain pin | every configure | The arm64 libraries are built by NDK `25.1.8937393` and no other | built into configure |
| Deploy crash watch | a connected device | The app installs, launches and does not crash within the watch window | `deploy` with `-Ddeploy_debug=OFF` |

The build-time checks fail the build; they need no separate step.

## Host regression

[`tests/ctprotocol/`](../../tests/ctprotocol/) is a standalone CMake project.
It compiles the portable core (`patches/arm64/native/ctprotocol/core/`) and
[`ctp_regress.c`](../../tests/ctprotocol/ctp_regress.c) with the host
compiler, runs the driver in `enc`, `dec` and `seq` mode, and compares the
output with the frozen files. It needs no Android SDK, NDK, emulator or stock
APK.

```sh
cmake -S tests/ctprotocol -B build/host-tests
cmake --build build/host-tests --config Release
ctest --test-dir build/host-tests -C Release --output-on-failure
```

`--config Release` and `-C Release` matter only for multi-config generators
such as Visual Studio. The seven tests are `enc_stock`, `dec_entry`,
`dec_valid`, `dec_reject`, `dec_state`, `dec_stream` and the supplementary
`dec_reject_gaps`. They pass with MSVC and with gcc.

The driver prints the format of the Java oracle harness and reproduces the
JNI adapter's marshalling:

- a builder that rejects its arguments yields an empty frame;
- `setMalcolmParam` checks the lengths of its three arrays and writes the
  `e` outputs only when the builder succeeds;
- `decode` copies `min(len, array length)` bytes into a zeroed
  `CTP_DECODE_MINBUF` buffer and returns `status != UNRECOGNIZED`.

[`compare.cmake`](../../tests/ctprotocol/compare.cmake) normalizes line
endings and ignores lines that start with `#` on both sides. The harness
echoes corpus comments in `seq` mode, and two corpora gained header comments
after their outputs were captured. Every other line must match exactly.

What the host test does not cover: the JNI adapter source itself (the driver
reimplements its marshalling), and the arm64 machine code. Both are exercised
by the emulator differential (x86) and by device runs (arm64).

## Emulator differential

[`oracle/run.sh`](../../oracle/run.sh) runs a library through the Java mirror
harness on a 32-bit x86 emulator. Its requirements are listed in
[`oracle/README.md`](../../oracle/README.md).

1. Extract the stock x86 library from your stock APK:
   `lib/x86/libsbxapplogic_ctprotocol_jni.so`.
2. Build the portable source for x86 with the pinned NDK:

   ```sh
   cmake -S patches/arm64/native -B build/native-x86 -G Ninja \
       -DCMAKE_TOOLCHAIN_FILE=<ndk>/build/cmake/android.toolchain.cmake \
       -DANDROID_ABI=x86 -DANDROID_PLATFORM=android-21 -DCMAKE_BUILD_TYPE=Release
   cmake --build build/native-x86
   ```

3. Run each vector set for both libraries:

   ```sh
   oracle/run.sh <lib.so> enc                                  > enc_stock.txt
   oracle/run.sh <lib.so> dec oracle/vectors/dec_entry.txt     > dec_entry.txt
   oracle/run.sh <lib.so> dec oracle/vectors/dec_valid.txt     > dec_valid.txt
   oracle/run.sh <lib.so> seq oracle/vectors/dec_reject.txt    > dec_reject.txt
   oracle/run.sh <lib.so> seq oracle/vectors/dec_state.txt     > dec_state.txt
   oracle/run.sh <lib.so> seq oracle/vectors/dec_stream.txt    > dec_stream.txt
   oracle/run.sh <lib.so> seq oracle/vectors/dec_reject_gaps.txt > dec_reject_gaps.txt
   ```

4. Compare: the stock and reimplementation outputs must be byte-identical
   (after removing `\r`), and each must equal the recorded file
   (`enc_stock.txt`, or `<set>.out.txt` for decode) on lines that do not start
   with `#`.

## Supplementary vector set

The frozen sets reach only one of the decoder's four reject branches, the
unknown opcode. [`dec_reject_gaps.txt`](../../oracle/vectors/dec_reject_gaps.txt)
covers the other three in
[`ctprotocol_decode.c`](../../patches/arm64/native/ctprotocol/core/ctprotocol_decode.c):

| Group | Branch | Frames |
|---|---|---|
| G1 | op02 with an unknown code | codes `0x00`, `0x04`, `0xff` at frame length 5, code `0x04` at length 7 |
| G2 | op02 with a known code and an unknown length | code `0x01` at length 4 and 8, and at length 6 with `b[4]` = 0 |
| G3 | op07 with an unknown length | lengths 3, 5, 8 and 20 |

Each mutant is followed by the `maxPls` control `5a03020000`, so a mutant that
disturbed decoder state would show in the control's output. Every frame passes
the entry gate (magic `0x5a`, declared payload length equal to the frame
length minus 3), so each one reaches its branch rather than the gate.

The expected output, `dec_reject_gaps.out.txt`, is the stock x86 library's
output for these frames: every mutant returns `ret=0` with no callback, and
every control raises `maxPlsCallback(0)`. The x86 build of the portable source
gives byte-identical output on the emulator, and the host driver matches it on
every non-comment line.

The set is additive. It is not part of the frozen contract, and no frozen
file changed when it was added. Replacing `CTP_DECODE_UNRECOGNIZED` with
`CTP_DECODE_OK` at any of the three branches fails `dec_reject_gaps` and no
other test; the same mutation of the unknown-opcode branch fails `dec_reject`
and `dec_state`.

| File | SHA-256 |
|---|---|
| `oracle/vectors/dec_reject_gaps.txt` | `acaa9fc0242000e1c260c8233845b2d9c4b8f738ea3d8cd8118ee619a3037bef` |
| `oracle/vectors/dec_reject_gaps.out.txt` | `65daa9ba4a85648c0f9f9bdac4ada6faea25fcd6cbe56763d189c0a0f2d2b65c` |

## Known coverage gaps

- The oracle harness needs a 32-bit x86 runtime, so the vectors have never
  been run against the arm64 build. Its correctness rests on the identical
  source, the 64-bit host tests and the device runs.
- `libserialport_jni.so` has no automated test and has not been exercised on
  hardware.
- Three callbacks the stock library registers are unreachable from its
  dispatcher and have no vector.

## Device runs

The arm64 build has been run on a Pixel 7a (Android 13) and a Galaxy S24
Ultra (Android 16) with one Katana speaker. The results are recorded in
[ARM64_RUNTIME.md](../research/arm64/ARM64_RUNTIME.md); the evidence limits
are listed in [the research index](../research/README.md#evidence-limits).
