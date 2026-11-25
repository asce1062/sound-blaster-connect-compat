cmake_minimum_required(VERSION 3.22)

project(
    sbconnect_bringup
    VERSION 1.0.0
    DESCRIPTION "Sound Blaster Connect APK bring-up: decode, patch, rebuild, sign"
    HOMEPAGE_URL "https://github.com/asce1062/SBConnect"
    LANGUAGES NONE)

# ---------------------------------------------------------------------------
# 3-state pipeline:
#
#   1. configure  verify the input APK, fetch + verify apktool + signer,
#                 decode => decompiled/ (pristine)
#   2. build      modernize/arm64: fresh copy of decompiled/, apply the
#                 variant's patch set (overlay files + optional patch.cmake
#                 edits), apktool b, then sign (uber-apk-signer debug key).
#                 resign: NOT via apktool — copy the stock archive verbatim
#                 (align once only if needed) and re-sign, then prove the
#                 payload is SHA-256 identical to stock (see below).
#   3. deploy     adb install one signed variant, launch it, tail logcat
#
# decompiled/ is PRISTINE: patches never touch it. Every variant builds from
# a fresh copy under build/<variant>/tree, so changing a patch rebuilds only
# that variant, never a re-decode (the slow step, ~90 s on this APK).
#
# A "variant" is one output APK = one patch set. The two deliverables are
# MUTUALLY EXCLUSIVE outputs built side by side in a single configure:
#
#   resign     payload-preserving signing control. The stock archive is copied
#              verbatim and re-signed with a debug key so it installs by adb;
#              no resource, manifest, or dex bytes are re-encoded. Runs only on
#              devices that still have 32-bit support.
#   modernize  stock + targetSdk raised and the Android 12/13/14 behavior
#              changes that follow (see patches/modernize/). Decode->rebuild
#              via apktool; more smali surgery, more risk.
#   arm64      modernize + arm64-v8a native libraries built from source, so the
#              app runs on 64-bit-only devices (Pixel 7/8, Galaxy S24).
# ---------------------------------------------------------------------------

# --- inputs -----------------------------------------------------------------

# The stock APK is third-party software and is never committed. Supply your
# own copy at inputs/SBConnect_v1.04.02.apk (gitignored) or pass -Dapk_input.
set(apk_input
    "${CMAKE_CURRENT_SOURCE_DIR}/inputs/SBConnect_v1.04.02.apk"
    CACHE FILEPATH "Path to the stock Sound Blaster Connect APK")
set(apk_input_sha256
    "fe1ffe0c93b6476ae6ed1d2cb6891cde2fbe206d4e898d6ad8c75222e9bf99be"
    CACHE STRING "Expected SHA-256 of apk_input (empty = print actual only)")

# Tool pins. Each jar is verified against its SHA-256, so a corrupted or
# swapped download fails the configure instead of breaking a build mid-run.
set(apktool_version
    "3.0.3"
    CACHE STRING "apktool version")
set(apktool_sha256
    "dbf930b076c6b9be08d57c449cacefc3bdd6b71ebd59b3066fc0e1f5b14f9423"
    CACHE STRING "SHA-256 of apktool_${apktool_version}.jar")
set(uber_signer_version
    "1.3.0"
    CACHE STRING "uber-apk-signer version")
set(uber_signer_sha256
    "e1299fd6fcf4da527dd53735b56127e8ea922a321128123b9c32d619bba1d835"
    CACHE STRING "SHA-256 of uber-apk-signer-${uber_signer_version}.jar")

set(apktool_jobs
    "8"
    CACHE STRING "apktool --jobs thread count (decode + build)")

set(java_bin
    "java"
    CACHE FILEPATH "Java binary (17+; apktool 3.x requires it)")
set(zipalign_bin
    "zipalign"
    CACHE FILEPATH "zipalign binary (Android build-tools; resign alignment check)")
set(adb_bin
    "adb"
    CACHE FILEPATH "adb binary (deploy)")
set(adb_serial
    ""
    CACHE STRING "adb device serial for deploy (empty = default device)")
set(sbc_package
    "com.creative.apps.sbconnect"
    CACHE STRING "android package name (deploy)")
set(deploy_variant
    "resign"
    CACHE STRING "variant installed by the deploy target")

set(decompiled_dir
    "${CMAKE_CURRENT_SOURCE_DIR}/decompiled"
    CACHE PATH "Pristine decoded tree (gitignored; patches never touch it)")

set(tools_dir "${CMAKE_CURRENT_BINARY_DIR}/tools")
set(apktool_jar "${tools_dir}/apktool_${apktool_version}.jar")
set(signer_jar "${tools_dir}/uber-apk-signer-${uber_signer_version}.jar")
set(apply_script "${CMAKE_CURRENT_SOURCE_DIR}/cmake/apply_patch.cmake")
set(deploy_script "${CMAKE_CURRENT_SOURCE_DIR}/cmake/deploy_apk.cmake")
set(resign_script "${CMAKE_CURRENT_SOURCE_DIR}/cmake/resign_control.cmake")
set(resign_verify_script
    "${CMAKE_CURRENT_SOURCE_DIR}/cmake/resign_verify.cmake")
set(stamp_decompiled "${CMAKE_CURRENT_BINARY_DIR}/decompiled.stamp")

set(apktool_url
    "https://github.com/iBotPeaches/Apktool/releases/download/v${apktool_version}/apktool_${apktool_version}.jar"
)
set(signer_url
    "https://github.com/patrickfav/uber-apk-signer/releases/download/v${uber_signer_version}/uber-apk-signer-${uber_signer_version}.jar"
)

if(NOT IS_ABSOLUTE "${apk_input}")
    cmake_path(
        ABSOLUTE_PATH
        apk_input
        BASE_DIRECTORY
        "${CMAKE_CURRENT_SOURCE_DIR}"
        NORMALIZE)
endif()
if(NOT EXISTS "${apk_input}")
    message(
        FATAL_ERROR
            "apk_input does not exist: '${apk_input}'\n"
            "  The stock APK is not part of this repository. Place your own copy of\n"
            "  SBConnect_v1.04.02.apk (SHA-256 ${apk_input_sha256}) at\n"
            "  inputs/SBConnect_v1.04.02.apk, or pass -Dapk_input=<path>. See BUILDING.md.")
endif()

# --- fetch helper: download once, verify SHA-256 when provided --------------

function(
    sbc_fetch
    url
    output
    expected_sha256)
    if(EXISTS "${output}")
        if(NOT
           expected_sha256
           STREQUAL
           "")
            file(SHA256 "${output}" actual)
            if(NOT
               actual
               STREQUAL
               expected_sha256)
                message(
                    FATAL_ERROR
                        "SHA-256 mismatch: ${output}\n"
                        "  expected: ${expected_sha256}\n"
                        "  actual:   ${actual}\n"
                        "  fix: delete the file and re-configure, or correct the hash"
                )
            endif()
        endif()
        return()
    endif()

    cmake_path(
        GET
        output
        PARENT_PATH
        output_dir)
    file(MAKE_DIRECTORY "${output_dir}")

    set(hash_args)
    if(NOT
       expected_sha256
       STREQUAL
       "")
        list(
            APPEND
            hash_args
            EXPECTED_HASH
            "SHA256=${expected_sha256}")
    endif()

    message(STATUS "downloading '${url}'")
    file(
        DOWNLOAD "${url}" "${output}"
        SHOW_PROGRESS
        STATUS status
        ${hash_args})
    list(
        GET
        status
        0
        rc)
    if(rc)
        file(REMOVE "${output}")
        message(FATAL_ERROR "download failed: ${url}\n${status}")
    endif()
endfunction()

file(SHA256 "${apk_input}" apk_input_actual)
if(NOT
   apk_input_sha256
   STREQUAL
   ""
   AND NOT
       apk_input_actual
       STREQUAL
       apk_input_sha256)
    message(
        FATAL_ERROR
            "apk_input SHA-256 mismatch: ${apk_input}\n"
            "  expected: ${apk_input_sha256}\n"
            "  actual:   ${apk_input_actual}\n"
            "  Only the exact 1.04.02 release is supported; patches anchor on its bytes.")
endif()
message(STATUS "apk_input: ${apk_input}")
message(STATUS "apk_input SHA-256: ${apk_input_actual}")

file(MAKE_DIRECTORY "${tools_dir}")
sbc_fetch("${apktool_url}" "${apktool_jar}" "${apktool_sha256}")
sbc_fetch("${signer_url}" "${signer_jar}" "${uber_signer_sha256}")

# --- state 1: decode => pristine decompiled/ --------------------------------

add_custom_command(
    OUTPUT "${stamp_decompiled}"
    COMMAND "${CMAKE_COMMAND}" -E rm -rf "${decompiled_dir}"
    COMMAND
        "${CMAKE_COMMAND}" -E echo
        "+ ${java_bin} -jar ${apktool_jar} d ${apk_input} -o ${decompiled_dir} -f --jobs ${apktool_jobs}"
    COMMAND
        "${java_bin}" -jar "${apktool_jar}" d "${apk_input}" -o
        "${decompiled_dir}" -f --jobs "${apktool_jobs}"
    COMMAND "${CMAKE_COMMAND}" -E touch "${stamp_decompiled}"
    DEPENDS "${apk_input}" "${apktool_jar}"
    COMMENT "decode => decompiled/ (apktool d)"
    USES_TERMINAL VERBATIM)

add_custom_target(decode DEPENDS "${stamp_decompiled}")

# Manual edits in decompiled/ re-stage the variant trees (re-globbed per build).
file(
    GLOB_RECURSE decompiled_files CONFIGURE_DEPENDS
    LIST_DIRECTORIES FALSE
    "${decompiled_dir}/*")

# --- state 2: variants ------------------------------------------------------

include(cmake/sbc_patches.cmake)

# resign    payload-preserving signing control. NOT routed through apktool:
#           the stock archive is copied verbatim (aligned once only if needed)
#           and re-signed, then proven SHA-256 payload-identical to stock. This
#           isolates signing/distribution from every other change.
# modernize targetSdk bump + Android 12/13/14 behavior fixes (decode->rebuild).
# arm64     modernize + arm64-v8a native libraries built from
#           patches/arm64/native/ with the pinned NDK (sbc_native.cmake).
#           Skipped when that NDK is not available.
sbc_add_resign_control(resign)
sbc_add_variant(modernize PATCHES modernize)

include(cmake/sbc_native.cmake)
if(sbc_native_available)
    sbc_add_native_abi(arm64-v8a native_arm64_dir native_arm64_libs)
    sbc_add_variant(
        arm64
        PATCHES modernize arm64
        NATIVE_LIB_DIR "${native_arm64_dir}"
        NATIVE_LIBS ${native_arm64_libs})
endif()

get_property(all_apks GLOBAL PROPERTY sbc_all_apks)
add_custom_target(apks ALL DEPENDS ${all_apks})

# --- state 3: deploy = adb install + launch + logcat ------------------------

set(deploy_watch_timeout
    "15"
    CACHE STRING "logcat watch window in seconds when deploy debug is OFF")
option(deploy_debug "deploy: infinite logcat tail after launch (OFF = bounded crash watch)" ON)

get_property(known_variants GLOBAL PROPERTY sbc_variants)
if(NOT
   deploy_variant
   IN_LIST
   known_variants)
    message(
        FATAL_ERROR
            "deploy_variant '${deploy_variant}' is not a variant (known: ${known_variants})"
    )
endif()

add_custom_target(
    deploy
    DEPENDS "${sbc_variant_${deploy_variant}_apk}"
    COMMAND
        "${CMAKE_COMMAND}" "-DPKG=${sbc_package}"
        "-DAPK=${sbc_variant_${deploy_variant}_apk}"
        "-DDEBUG=$<BOOL:${deploy_debug}>" "-DTIMEOUT=${deploy_watch_timeout}"
        "-DADB_SERIAL=${adb_serial}" "-DADB_BIN=${adb_bin}" -P
        "${deploy_script}"
    COMMENT "deploy ${deploy_variant} => adb (install + launch + logcat)"
    USES_TERMINAL VERBATIM)
