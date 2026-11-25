# sign_apk.cmake: align and sign an unsigned APK for test-release or release.
#
#   cmake -DMODE=<test-release|release> -DPREFIX=<env prefix>
#         -DUNSIGNED=<apk> -DOUT=<final apk path> -DWORK=<dir>
#         -DAPKSIGNER=<path> -DZIPALIGN=<path> -DAAPT2=<path>
#         -DBUILD_TOOLS_PROPERTIES=<source.properties>
#         -DBUILD_TOOLS_VERSION=<pin> -P sign_apk.cmake
#
# Credentials come from the environment only (see sbc_signing.cmake);
# apksigner reads the passwords itself through its env: syntax, so they never
# appear on a command line. apksigner's standard input is empty, so a missing
# or wrong password fails instead of prompting.
#
# Output: <OUT>.unverified. <OUT> and its .sha256 and .json files are removed
# first, so a failure here or in a later step leaves no current-looking
# release.

foreach(v MODE PREFIX UNSIGNED OUT WORK APKSIGNER ZIPALIGN BUILD_TOOLS_PROPERTIES BUILD_TOOLS_VERSION)
    if(NOT DEFINED ${v} OR "${${v}}" STREQUAL "")
        message(FATAL_ERROR "sign_apk: ${v} is not set")
    endif()
endforeach()

file(REMOVE "${OUT}" "${OUT}.sha256" "${OUT}.json" "${OUT}.unverified")
file(REMOVE_RECURSE "${WORK}")
file(MAKE_DIRECTORY "${WORK}")
get_filename_component(out_dir "${OUT}" DIRECTORY)
file(MAKE_DIRECTORY "${out_dir}")

# Pinned build-tools release.
foreach(f APKSIGNER ZIPALIGN BUILD_TOOLS_PROPERTIES)
    if(NOT EXISTS "${${f}}")
        message(
            FATAL_ERROR
                "sign_apk: ${f} not found: ${${f}}\n"
                "  Install Android SDK build-tools ${BUILD_TOOLS_VERSION} or set android_sdk_root.")
    endif()
endforeach()
file(STRINGS "${BUILD_TOOLS_PROPERTIES}" bt_rev REGEX "^Pkg\\.Revision=")
string(REGEX REPLACE "^Pkg\\.Revision=" "" bt_rev "${bt_rev}")
if(NOT bt_rev STREQUAL BUILD_TOOLS_VERSION)
    message(FATAL_ERROR "sign_apk: build-tools revision is '${bt_rev}', pinned ${BUILD_TOOLS_VERSION}")
endif()

# Credentials of this mode only.
set(missing "")
foreach(k KEYSTORE KEYSTORE_PASS KEY_ALIAS CERT_SHA256)
    if("$ENV{${PREFIX}${k}}" STREQUAL "")
        string(APPEND missing " ${PREFIX}${k}")
    endif()
endforeach()
if(NOT missing STREQUAL "")
    message(FATAL_ERROR "sign_apk[${MODE}]: required environment variables are not set:${missing}")
endif()
set(keystore "$ENV{${PREFIX}KEYSTORE}")
if(NOT EXISTS "${keystore}")
    message(FATAL_ERROR "sign_apk[${MODE}]: ${PREFIX}KEYSTORE names a file that does not exist")
endif()
set(key_pass_env "${PREFIX}KEY_PASS")
if("$ENV{${key_pass_env}}" STREQUAL "")
    set(key_pass_env "${PREFIX}KEYSTORE_PASS")
endif()

if(NOT EXISTS "${UNSIGNED}")
    message(FATAL_ERROR "sign_apk: unsigned APK not found: ${UNSIGNED}")
endif()

set(empty_stdin "${WORK}/stdin.empty")
file(WRITE "${empty_stdin}" "")

function(_run step)
    execute_process(
        COMMAND ${ARGN}
        INPUT_FILE "${empty_stdin}"
        RESULT_VARIABLE rc
        OUTPUT_VARIABLE out
        ERROR_VARIABLE err)
    if(NOT rc EQUAL 0)
        file(REMOVE "${OUT}.unverified")
        message(FATAL_ERROR "sign_apk[${MODE}]: ${step} failed (${rc})\n${out}${err}")
    endif()
endfunction()

# Align: 4-byte entries, uncompressed native libraries on 16 KiB boundaries.
set(aligned "${WORK}/aligned.apk")
message(STATUS "sign_apk[${MODE}]: zipalign -P 16 4")
_run(align "${ZIPALIGN}" -P 16 -f 4 "${UNSIGNED}" "${aligned}")

# Sign: v1 for API 14 to 23, v2 and v3 for later releases. No v4 .idsig.
message(STATUS "sign_apk[${MODE}]: apksigner sign (v1, v2, v3)")
_run(sign
     "${APKSIGNER}" sign
     --ks "${keystore}"
     --ks-key-alias "$ENV{${PREFIX}KEY_ALIAS}"
     --ks-pass "env:${PREFIX}KEYSTORE_PASS"
     --key-pass "env:${key_pass_env}"
     --v1-signing-enabled true
     --v2-signing-enabled true
     --v3-signing-enabled true
     --v4-signing-enabled false
     --out "${OUT}.unverified"
     "${aligned}")
file(REMOVE "${aligned}")
message(STATUS "sign_apk[${MODE}]: signed => ${OUT}.unverified")
