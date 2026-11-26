# sbc_signing.cmake: test-release and release signing of a variant.
#
# Signing modes:
#
#   debug         every variant, uber-apk-signer debug key, as built by
#                 sbc_add_variant: build/sbc_<name>-aligned-debugSigned.apk
#   test-release  apk-<name>-test-release, a disposable key for rehearsals:
#                 build/test-release/<release apk stem>-test-release.apk
#   release       apk-<name>-release, the production key:
#                 build/release/<release apk>
#
# Each mode is its own target with its own credentials. A mode reads only the
# environment variables with its own prefix (SBC_TEST_RELEASE_ or
# SBC_RELEASE_) and stops when one is missing; no mode falls back to another
# mode's key. The variables are read when the target runs, so no credential,
# keystore path or fingerprint reaches the CMake cache or build.ninja.
#
#   <prefix>KEYSTORE       keystore path (PKCS12 or JKS)
#   <prefix>KEYSTORE_PASS  keystore password
#   <prefix>KEY_ALIAS      key alias
#   <prefix>KEY_PASS       key password; optional, default the keystore password
#   <prefix>CERT_SHA256    expected SHA-256 of the signer certificate
#
# Pipeline, run by sign_release.cmake (which the release workflow also calls),
# one process per step:
#   sign_apk.cmake          remove earlier outputs, zipalign the unsigned APK,
#                           sign it with apksigner (<out>.unverified)
#   verify_signed_apk.cmake apksigner verify, zipalign check, certificate
#                           fingerprint, package metadata, native library
#                           inventory, payload against the unsigned APK
#   release_metadata.cmake  rename to <out>, write <out>.sha256 and
#                           <out>.json
# A failed step leaves neither <out> nor a signed <out>.unverified.
#
# The tools come from one pinned Android SDK build-tools release.

include_guard(GLOBAL)

# The SDK is searched like the NDK in sbc_native.cmake.
set(_sdk_default "")
foreach(sdk IN ITEMS "$ENV{ANDROID_SDK_ROOT}" "$ENV{ANDROID_HOME}" "$ENV{LOCALAPPDATA}/Android/Sdk")
    if(_sdk_default STREQUAL "" AND NOT sdk STREQUAL "" AND NOT sdk STREQUAL "/Android/Sdk"
       AND IS_DIRECTORY "${sdk}/build-tools")
        set(_sdk_default "${sdk}")
    endif()
endforeach()
set(android_sdk_root
    "${_sdk_default}"
    CACHE PATH "Android SDK root (release signing tools)")
set(android_build_tools_version
    "37.0.0"
    CACHE STRING "Pinned Android SDK build-tools release used for release signing")

set(_bt "${android_sdk_root}/build-tools/${android_build_tools_version}")
if(CMAKE_HOST_WIN32)
    set(sbc_apksigner "${_bt}/apksigner.bat")
    set(sbc_bt_zipalign "${_bt}/zipalign.exe")
    set(sbc_aapt2 "${_bt}/aapt2.exe")
else()
    set(sbc_apksigner "${_bt}/apksigner")
    set(sbc_bt_zipalign "${_bt}/zipalign")
    set(sbc_aapt2 "${_bt}/aapt2")
endif()
set(sbc_bt_properties "${_bt}/source.properties")

set(sbc_sign_release_script "${CMAKE_CURRENT_LIST_DIR}/sign_release.cmake")

# sbc_add_signed_apk(<variant> MODE <test-release|release> ABIS <abi>...
#                    NATIVE_ABI <abi> NATIVE_LIB_DIR <dir> NATIVE_LIBS <files>...)
#
# ABIS is the exact set of lib/<abi>/ directories the APK must contain.
# NATIVE_LIBS, built into NATIVE_LIB_DIR for NATIVE_ABI, must be in the APK
# byte for byte. Package and version come from sbc_version.cmake.
function(sbc_add_signed_apk name)
    cmake_parse_arguments(S "" "MODE;NATIVE_ABI;NATIVE_LIB_DIR" "ABIS;NATIVE_LIBS" ${ARGN})
    if(S_MODE STREQUAL "test-release")
        set(prefix "SBC_TEST_RELEASE_")
        string(REGEX REPLACE "\\.apk$" "-test-release.apk" out_name "${sbc_release_apk}")
    elseif(S_MODE STREQUAL "release")
        set(prefix "SBC_RELEASE_")
        set(out_name "${sbc_release_apk}")
    else()
        message(FATAL_ERROR "sbc_add_signed_apk: MODE must be test-release or release, not '${S_MODE}'")
    endif()

    set(unsigned "${sbc_variant_${name}_unsigned}")
    set(out_dir "${CMAKE_BINARY_DIR}/${S_MODE}")
    set(out "${out_dir}/${out_name}")
    set(work "${CMAKE_BINARY_DIR}/${name}/${S_MODE}")
    string(REPLACE ";" "," abis_csv "${S_ABIS}")
    set(lib_names "")
    foreach(lib IN LISTS S_NATIVE_LIBS)
        cmake_path(GET lib FILENAME lib_name)
        list(APPEND lib_names "${lib_name}")
    endforeach()
    string(REPLACE ";" "," lib_names_csv "${lib_names}")

    # The release workflow signs without a build tree; release.env carries the
    # values it needs (sign_release.cmake reads them with -DRELEASE_ENV). Both
    # modes share them, so they are written once.
    get_property(env_written GLOBAL PROPERTY sbc_release_env_signing)
    if(NOT env_written)
        file(
            APPEND "${CMAKE_BINARY_DIR}/release.env"
            "RELEASE_ABIS=${abis_csv}\n"
            "NATIVE_ABI=${S_NATIVE_ABI}\n"
            "NATIVE_LIBS=${lib_names_csv}\n"
            "STOCK_INPUT_SHA256=${apk_input_actual}\n")
        set_property(GLOBAL PROPERTY sbc_release_env_signing TRUE)
    endif()

    add_custom_target(
        apk-${name}-${S_MODE}
        COMMAND
            "${CMAKE_COMMAND}" "-DMODE=${S_MODE}" "-DUNSIGNED=${unsigned}"
            "-DOUT_DIR=${out_dir}" "-DWORK=${work}"
            "-DNATIVE_LIB_DIR=${S_NATIVE_LIB_DIR}" "-DNATIVE_LIBS=${lib_names_csv}"
            "-DNATIVE_ABI=${S_NATIVE_ABI}" "-DABIS=${abis_csv}"
            "-DPACKAGE=${sbc_variant_${name}_package}"
            "-DVERSION_CODE=${sbc_version_code}" "-DVERSION_NAME=${sbc_version_name}"
            "-DTAG=${sbc_release_tag}" "-DRELEASE_APK=${sbc_release_apk}"
            "-DINPUT_SHA256=${apk_input_actual}" "-DSOURCE_DIR=${PROJECT_SOURCE_DIR}"
            "-DREF_SCRIPT=${resign_verify_script}"
            "-DAPKSIGNER=${sbc_apksigner}" "-DZIPALIGN=${sbc_bt_zipalign}"
            "-DAAPT2=${sbc_aapt2}" "-DBUILD_TOOLS_PROPERTIES=${sbc_bt_properties}"
            "-DBUILD_TOOLS_VERSION=${android_build_tools_version}"
            -P "${sbc_sign_release_script}"
        DEPENDS "${unsigned}"
        COMMENT "variant[${name}]: ${S_MODE} sign + verify => ${out}"
        USES_TERMINAL VERBATIM)
endfunction()
