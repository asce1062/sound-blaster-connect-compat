#!/usr/bin/env bash
# Oracle / differential harness runner.
#
#   oracle/run.sh <path-to-.so> <enc|dec> [corpus-hex-file]
#
# Compiles the mirror SbxSppCommandManager, dexes it, pushes it and the chosen
# libsbxapplogic_ctprotocol_jni.so to a running 32-bit x86 emulator, and runs
# the harness under app_process32. Prints the harness stdout (ENC/DEC lines).
#
# MSYS path conversion is disabled so adb remote paths (/data/...) survive; the
# few local paths handed to java/javac/adb are converted to Windows form.
set -euo pipefail
export MSYS_NO_PATHCONV=1
w() { cygpath -m "$1"; }

SO="${1:?usage: run.sh <so> <enc|dec> [corpus]}"
MODE="${2:-enc}"
CORPUS="${3:-}"

SDK="$ANDROID_SDK_ROOT"
ADB="$SDK/platform-tools/adb.exe"
ANDROID_JAR="$(w "$SDK/platforms/android-30/android.jar")"
D8_JAR="$(w "$SDK/build-tools/33.0.1/lib/d8.jar")"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$HERE/build"
SRC="$HERE/src/com/creative/logic/sbxapplogic/vendor/sbx/SbxSppCommandManager.java"
DEV=/data/local/tmp/oracle

rm -rf "$OUT"; mkdir -p "$OUT/classes"
javac --release 8 -cp "$ANDROID_JAR" -d "$(w "$OUT/classes")" "$(w "$SRC")"
# Invoke d8.jar directly (its .bat wrapper uses java.ext.dirs, rejected by JDK 9+).
CLASSES="$(w "$OUT")/classes/com/creative/logic/sbxapplogic/vendor/sbx"
java -cp "$D8_JAR" com.android.tools.r8.D8 --min-api 30 \
    --output "$(w "$OUT/oracle.jar")" "$CLASSES"/*.class

"$ADB" shell "mkdir -p $DEV"
"$ADB" push "$(w "$OUT/oracle.jar")" "$DEV/oracle.jar" >/dev/null
"$ADB" push "$(w "$SO")" "$DEV/lib.so" >/dev/null
CLS=com.creative.logic.sbxapplogic.vendor.sbx.SbxSppCommandManager

if [ "$MODE" = "dec" ]; then
    "$ADB" push "$(w "$CORPUS")" "$DEV/corpus.txt" >/dev/null
    "$ADB" shell "cd $DEV && CLASSPATH=$DEV/oracle.jar app_process32 $DEV $CLS $DEV/lib.so dec $DEV/corpus.txt"
else
    "$ADB" shell "cd $DEV && CLASSPATH=$DEV/oracle.jar app_process32 $DEV $CLS $DEV/lib.so enc"
fi
