cmake_minimum_required(VERSION 3.22)

project(
    sbconnect_bringup
    VERSION 1.0.0
    DESCRIPTION "Sound Blaster Connect APK bring-up: decode, patch, rebuild, sign"
    HOMEPAGE_URL "https://github.com/asce1062/SBConnect"
    LANGUAGES NONE)

# ---------------------------------------------------------------------------
# 3-state pipeline (mirrors a sibling project's model, minus the asset
# crypto this APK does not use):
#
#   1. configure  verify the input APK, fetch + verify apktool + signer,
#                 decode => decompiled/ (pristine)
#   2. build      per variant: fresh copy of decompiled/, apply the variant's
#                 patch set (overlay files + optional patch.cmake edits),
#                 apktool b, then zipalign + sign (uber-apk-signer debug key)
#   3. deploy     adb install one signed variant, launch it, tail logcat
#
# decompiled/ is PRISTINE: patches never touch it. Every variant builds from
# a fresh copy under build/<variant>/tree, so changing a patch rebuilds only
# that variant, never a re-decode (the slow step, ~90 s on this APK).
#
# A "variant" is one output APK = one patch set. The two deliverables are
# MUTUALLY EXCLUSIVE outputs built side by side in a single configure:
#
#   resign     no code changes at all. Stock app, rebuilt and re-signed with
#              a debug key so it sideloads. Bypasses the Play Store listing
#              filter; runs on any modern phone that still has 32-bit support.
#   modernize  resign + targetSdk raised and the Android 12/13/14 behavior
#              changes that follow (see patches/modernize/). More modern,
#              more smali surgery, more risk.
#
# Neither reaches a 64-bit-only device (Pixel 7/8): both still ship only the
# stock 32-bit native libs. arm64-v8a support is the separate native track
# (patches/arm64/ + the own-app protocol work); see docs/FINDINGS.md.
# ---------------------------------------------------------------------------

# --- inputs -----------------------------------------------------------------

set(apk_input
    "${CMAKE_CURRENT_SOURCE_DIR}/SBConnect_v1.04.02.apk"
    CACHE FILEPATH "Path to the stock Sound Blaster Connect APK")
set(apk_input_sha256
    "fe1ffe0c93b6476ae6ed1d2cb6891cde2fbe206d4e898d6ad8c75222e9bf99be"
    CACHE STRING "Expected SHA-256 of apk_input (empty = print actual only)")

# Tool pins. These exact jars + hashes are the ones a sibling project
# builds against (CI-verified there); reused so a corrupted or swapped
# download fails the configure instead of breaking a build mid-run.
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
            "  the stock APK is tracked with git-lfs; run 'git lfs pull' after cloning,\n"
            "  or pass -Dapk_input=<path to SBConnect_v1.04.02.apk>")
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
            "  (a git-lfs pointer that was not pulled hashes wrong too)")
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

# resign    pure repackage, no patches (empty set).
# modernize targetSdk bump + Android 12/13/14 behavior fixes.
# arm64     native 64-bit track; built on the modernize base once its libs
#           exist. Registered here so neither track edits this file again.
sbc_add_variant(resign PATCHES "")
sbc_add_variant(modernize PATCHES modernize)
sbc_add_variant(arm64 PATCHES modernize arm64)

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
