# sign_release.cmake: the test-release and release signing pipeline in one
# call: sign_apk.cmake, verify_signed_apk.cmake, release_metadata.cmake, each
# in its own process, in that order. A failing step stops the pipeline; the
# steps themselves remove partial outputs (see sbc_signing.cmake).
#
# The apk-<variant>-<mode> targets call it with every value given. The release
# workflow's signing job, which has no build tree, calls it with RELEASE_ENV
# set to the release.env of the build that produced UNSIGNED; values given
# with -D take precedence over that file.
#
#   cmake -DMODE=<test-release|release> -DUNSIGNED=<apk> -DOUT_DIR=<dir>
#         -DWORK=<dir> -DNATIVE_LIB_DIR=<dir> -DSOURCE_DIR=<repository>
#         -DREF_SCRIPT=<resign_verify.cmake>
#         -DAPKSIGNER=<path> -DZIPALIGN=<path> -DAAPT2=<path>
#         -DBUILD_TOOLS_PROPERTIES=<source.properties> -DBUILD_TOOLS_VERSION=<pin>
#         [-DRELEASE_ENV=<release.env>]
#         [-DPACKAGE= -DVERSION_CODE= -DVERSION_NAME= -DTAG= -DRELEASE_APK=
#          -DABIS=<a,b> -DNATIVE_ABI= -DNATIVE_LIBS=<names> -DINPUT_SHA256=]
#         -P sign_release.cmake
#
# NATIVE_LIBS are file names inside NATIVE_LIB_DIR. Credentials are read from
# the environment by the steps (prefix SBC_TEST_RELEASE_ or SBC_RELEASE_).

cmake_minimum_required(VERSION 3.22)

# release.env key -> variable
set(_env_map
    APP_ID=PACKAGE VERSION_CODE=VERSION_CODE VERSION_NAME=VERSION_NAME
    RELEASE_TAG=TAG RELEASE_APK=RELEASE_APK RELEASE_ABIS=ABIS NATIVE_ABI=NATIVE_ABI
    NATIVE_LIBS=NATIVE_LIBS STOCK_INPUT_SHA256=INPUT_SHA256)
if(DEFINED RELEASE_ENV AND NOT RELEASE_ENV STREQUAL "")
    file(STRINGS "${RELEASE_ENV}" _lines)
    foreach(line IN LISTS _lines)
        if(line MATCHES "^([A-Z0-9_]+)=(.*)$")
            set(_k "${CMAKE_MATCH_1}")
            set(_v "${CMAKE_MATCH_2}")
            foreach(pair IN LISTS _env_map)
                string(REPLACE "=" ";" pair "${pair}")
                list(GET pair 0 key)
                list(GET pair 1 var)
                if(_k STREQUAL key AND (NOT DEFINED ${var} OR "${${var}}" STREQUAL ""))
                    set(${var} "${_v}")
                endif()
            endforeach()
        endif()
    endforeach()
endif()

foreach(v MODE UNSIGNED OUT_DIR WORK NATIVE_LIB_DIR SOURCE_DIR REF_SCRIPT APKSIGNER ZIPALIGN AAPT2
          BUILD_TOOLS_PROPERTIES BUILD_TOOLS_VERSION PACKAGE VERSION_CODE VERSION_NAME TAG
          RELEASE_APK ABIS NATIVE_ABI NATIVE_LIBS INPUT_SHA256)
    if(NOT DEFINED ${v} OR "${${v}}" STREQUAL "")
        message(FATAL_ERROR "sign_release: ${v} is not set")
    endif()
endforeach()

if(MODE STREQUAL "test-release")
    set(prefix "SBC_TEST_RELEASE_")
    string(REGEX REPLACE "\\.apk$" "-test-release.apk" out_name "${RELEASE_APK}")
elseif(MODE STREQUAL "release")
    set(prefix "SBC_RELEASE_")
    set(out_name "${RELEASE_APK}")
else()
    message(FATAL_ERROR "sign_release: MODE must be test-release or release, not '${MODE}'")
endif()
set(out "${OUT_DIR}/${out_name}")

string(REPLACE "," ";" _names "${NATIVE_LIBS}")
set(libs_csv "")
foreach(n IN LISTS _names)
    if(NOT libs_csv STREQUAL "")
        string(APPEND libs_csv ",")
    endif()
    string(APPEND libs_csv "${NATIVE_LIB_DIR}/${n}")
endforeach()

set(tool_args
    "-DAPKSIGNER=${APKSIGNER}" "-DZIPALIGN=${ZIPALIGN}" "-DAAPT2=${AAPT2}"
    "-DBUILD_TOOLS_PROPERTIES=${BUILD_TOOLS_PROPERTIES}"
    "-DBUILD_TOOLS_VERSION=${BUILD_TOOLS_VERSION}")
set(here "${CMAKE_CURRENT_LIST_DIR}")

execute_process(
    COMMAND "${CMAKE_COMMAND}" "-DMODE=${MODE}" "-DPREFIX=${prefix}" "-DUNSIGNED=${UNSIGNED}"
            "-DOUT=${out}" "-DWORK=${WORK}" ${tool_args} -P "${here}/sign_apk.cmake"
    COMMAND_ERROR_IS_FATAL ANY)
execute_process(
    COMMAND "${CMAKE_COMMAND}" "-DMODE=${MODE}" "-DAPK=${out}.unverified"
            "-DCERT_ENV=${prefix}CERT_SHA256" "-DUNSIGNED=${UNSIGNED}" "-DWORK=${WORK}"
            "-DPACKAGE=${PACKAGE}" "-DVERSION_CODE=${VERSION_CODE}"
            "-DVERSION_NAME=${VERSION_NAME}" "-DABIS=${ABIS}" "-DNATIVE_ABI=${NATIVE_ABI}"
            "-DNATIVE_LIBS=${libs_csv}" "-DREF_SCRIPT=${REF_SCRIPT}" -DDISCARD_ON_FAILURE=ON
            ${tool_args} -P "${here}/verify_signed_apk.cmake"
    COMMAND_ERROR_IS_FATAL ANY)
execute_process(
    COMMAND "${CMAKE_COMMAND}" "-DMODE=${MODE}" "-DOUT=${out}" "-DWORK=${WORK}"
            "-DUNSIGNED=${UNSIGNED}" "-DINPUT_SHA256=${INPUT_SHA256}" "-DTAG=${TAG}"
            "-DSOURCE_DIR=${SOURCE_DIR}" -P "${here}/release_metadata.cmake"
    COMMAND_ERROR_IS_FATAL ANY)
message(STATUS "sign_release[${MODE}]: ${out}")
