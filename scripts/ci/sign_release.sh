#!/usr/bin/env bash
# Sign the release inputs of a build-apk.yml run with cmake/sign_release.cmake,
# the same driver the apk-compat-<mode> targets run. Used by the release
# workflow's signing job; it has no build tree, so the values come from the
# build's release.env.
#
# Environment: MODE (test-release|release), SDK (Android SDK root), IN (the
# downloaded release-inputs artifact), RUNNER_TEMP, and the credentials of
# MODE's prefix, which only sign_apk.cmake reads. Output: $RUNNER_TEMP/out/
# <apk>, <apk>.sha256, <apk>.json.
set -euo pipefail

: "${MODE:?}" "${SDK:?}" "${IN:?}" "${RUNNER_TEMP:?}"
bt="$SDK/build-tools/37.0.0"
# Windows build-tools (Git Bash) name the same tools with extensions.
if [ -f "$bt/zipalign.exe" ]; then sx=.bat x=.exe; else sx="" x=""; fi
out="$RUNNER_TEMP/out"
rm -rf "$out" "$RUNNER_TEMP/sign-work"
mkdir -p "$out"

"$SDK/cmake/3.22.1/bin/cmake" \
  "-DMODE=$MODE" \
  "-DRELEASE_ENV=$IN/release.env" \
  "-DUNSIGNED=$IN/sbc_compat.apk" \
  "-DNATIVE_LIB_DIR=$IN/native" \
  "-DOUT_DIR=$out" \
  "-DWORK=$RUNNER_TEMP/sign-work" \
  "-DSOURCE_DIR=$PWD" \
  "-DREF_SCRIPT=$PWD/cmake/resign_verify.cmake" \
  "-DAPKSIGNER=$bt/apksigner$sx" \
  "-DZIPALIGN=$bt/zipalign$x" \
  "-DAAPT2=$bt/aapt2$x" \
  "-DBUILD_TOOLS_PROPERTIES=$bt/source.properties" \
  "-DBUILD_TOOLS_VERSION=37.0.0" \
  -P cmake/sign_release.cmake

ls -l "$out"
