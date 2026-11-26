#!/usr/bin/env bash
# Install the Android SDK packages named in sdk-packages.txt (or a subset given
# as arguments, by path) and verify each one's Pkg.Revision. Fails when a
# package is missing or has another revision after the install, so an
# installer that exits 0 without installing cannot pass unnoticed.
#
#   ANDROID_HOME=<sdk> scripts/ci/android_sdk_install.sh [ndk/25.1.8937393 ...]
#
# Uses the Android CLI (`android sdk install <path>`) when present, otherwise
# sdkmanager with the `;`-separated package name. A package whose directory
# already has the expected revision (for example restored from a cache) is
# not reinstalled.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
[ -n "$sdk" ] || { echo "ANDROID_HOME is not set" >&2; exit 1; }

revision() {
    local props="$sdk/$1/source.properties"
    [ -f "$props" ] || return 0
    sed -n 's/^Pkg\.Revision *= *//p' "$props" | tr -d '\r'
}

want=("$@")
fail=0
while read -r path rev; do
    case "$path" in ''|'#'*) continue ;; esac
    if [ ${#want[@]} -gt 0 ] && ! printf '%s\n' "${want[@]}" | grep -qx "$path"; then
        continue
    fi
    if [ "$(revision "$path")" != "$rev" ]; then
        echo "installing $path ($rev)"
        if command -v android >/dev/null 2>&1; then
            android sdk install "$path"
        else
            sm="$sdk/cmdline-tools/latest/bin/sdkmanager"
            [ -x "$sm" ] || sm=sdkmanager
            { yes || true; } | "$sm" --sdk_root="$sdk" --install "${path//\//;}" >/dev/null
        fi
    fi
    got="$(revision "$path")"
    if [ "$got" = "$rev" ]; then
        echo "ok   $path $got"
    else
        echo "FAIL $path: revision '${got}' want '$rev'" >&2
        fail=1
    fi
done < "$here/sdk-packages.txt"
exit $fail
