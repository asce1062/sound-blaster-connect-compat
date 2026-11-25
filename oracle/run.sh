#!/usr/bin/env bash
# Oracle / differential harness runner.
#
#   oracle/run.sh <path-to-.so> <enc|dec> [corpus-hex-file]
#
# Compiles the mirror SbxSppCommandManager, dexes it, pushes it and the chosen
# libsbxapplogic_ctprotocol_jni.so to a running 32-bit x86 emulator, and runs
# the harness under app_process32. Prints the harness stdout (ENC/DEC lines).
#
#   <path-to-.so>      the library under test: the stock x86 library or an x86
#                      build of the portable reimplementation
#   enc                runs the fixed encode vector set (no corpus)
#   dec | seq          runs the decode corpus given as the third argument
#   [corpus-hex-file]  one hex frame per line (dec) or blank-line-separated
#                      groups of frames (seq); required for dec and seq
#
# Requires: Android SDK (platform-tools, platforms/android-30, build-tools
# 33.0.1 for d8) and a running x86 emulator reachable by adb.
#
# MSYS path conversion is disabled so adb remote paths (/data/...) survive; the
# few local paths handed to java/javac/adb are converted to Windows form.
set -euo pipefail
export MSYS_NO_PATHCONV=1
w() { cygpath -m "$1"; }

SO="${1:?usage: run.sh <so> <enc|dec> [corpus]}"
MODE="${2:-enc}"
CORPUS="${3:-}"

# Android SDK root: $ANDROID_SDK_ROOT, else $ANDROID_HOME, else the Android
# Studio default under %LOCALAPPDATA%.
SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$(cygpath -u "${LOCALAPPDATA:-}")/Android/Sdk}}"
[ -d "$SDK/platform-tools" ] || { echo "run.sh: Android SDK not found at '$SDK'; set ANDROID_SDK_ROOT" >&2; exit 2; }
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

if [ "$MODE" = "enc" ]; then
    "$ADB" shell "cd $DEV && CLASSPATH=$DEV/oracle.jar app_process32 $DEV $CLS $DEV/lib.so enc"
else
    # Any corpus-driven mode (dec, seq): push the corpus and pass the mode through.
    "$ADB" push "$(w "$CORPUS")" "$DEV/corpus.txt" >/dev/null
    "$ADB" shell "cd $DEV && CLASSPATH=$DEV/oracle.jar app_process32 $DEV $CLS $DEV/lib.so $MODE $DEV/corpus.txt"
fi
