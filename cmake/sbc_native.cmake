# sbc_native.cmake: build the arm64-v8a native libraries from source.
#
# patches/arm64/native/ is a standalone NDK CMake project. This module locates
# the pinned NDK, then adds a custom command that configures and builds that
# project for one ABI. The arm64 variant depends on the outputs, so every APK
# that carries the libraries carries libraries built from the tracked source.
#
# NDK lookup, first match wins, and only an NDK whose source.properties
# revision equals ndk_version is accepted:
#   -Dandroid_ndk=<root>, $ANDROID_NDK_ROOT, $ANDROID_NDK_HOME,
#   $ANDROID_SDK_ROOT/ndk/<ndk_version>, $ANDROID_HOME/ndk/<ndk_version>,
#   %LOCALAPPDATA%/Android/Sdk/ndk/<ndk_version>
#
# When no matching NDK is found, sbc_native_available is FALSE and the caller
# skips the arm64 variant; requesting apk-arm64 then fails as an unknown target.

include_guard(GLOBAL)

set(ndk_version
    "25.1.8937393"
    CACHE STRING "Pinned Android NDK revision for the native libraries (r25b)")
set(android_ndk
    ""
    CACHE PATH "Android NDK root (empty = search the environment, see sbc_native.cmake)")
set(native_platform
    "android-21"
    CACHE STRING "ANDROID_PLATFORM for the native libraries")

set(sbc_native_source_dir "${PROJECT_SOURCE_DIR}/patches/arm64/native")

function(_sbc_ndk_revision root out_var)
    set(rev "")
    if(EXISTS "${root}/source.properties")
        file(STRINGS "${root}/source.properties" line REGEX "^Pkg\\.Revision")
        string(REGEX REPLACE "^Pkg\\.Revision *= *" "" rev "${line}")
    endif()
    set(${out_var} "${rev}" PARENT_SCOPE)
endfunction()

set(_candidates
    "${android_ndk}"
    "$ENV{ANDROID_NDK_ROOT}"
    "$ENV{ANDROID_NDK_HOME}")
foreach(sdk IN ITEMS "$ENV{ANDROID_SDK_ROOT}" "$ENV{ANDROID_HOME}" "$ENV{LOCALAPPDATA}/Android/Sdk")
    if(NOT sdk STREQUAL "" AND NOT sdk STREQUAL "/Android/Sdk")
        list(APPEND _candidates "${sdk}/ndk/${ndk_version}")
    endif()
endforeach()

set(sbc_ndk_root "")
foreach(c IN LISTS _candidates)
    if(c STREQUAL "")
        continue()
    endif()
    file(TO_CMAKE_PATH "${c}" c)
    if(NOT EXISTS "${c}/build/cmake/android.toolchain.cmake")
        continue()
    endif()
    _sbc_ndk_revision("${c}" rev)
    if(rev STREQUAL ndk_version)
        set(sbc_ndk_root "${c}")
        break()
    endif()
    message(STATUS "native: skipping NDK ${c} (revision '${rev}', want ${ndk_version})")
endforeach()

if(sbc_ndk_root STREQUAL "")
    set(sbc_native_available FALSE)
    message(
        WARNING
            "native: NDK ${ndk_version} not found; the arm64 variant is disabled.\n"
            "  Install it (sdkmanager \"ndk;${ndk_version}\") or pass -Dandroid_ndk=<root>.")
    return()
endif()
set(sbc_native_available TRUE)
message(STATUS "native: NDK ${ndk_version} at ${sbc_ndk_root}")

file(
    GLOB_RECURSE sbc_native_sources CONFIGURE_DEPENDS
    LIST_DIRECTORIES FALSE
    "${sbc_native_source_dir}/*.c"
    "${sbc_native_source_dir}/*.h"
    "${sbc_native_source_dir}/CMakeLists.txt")

# sbc_add_native_abi(<abi> <out_dir_var> <out_libs_var>)
function(sbc_add_native_abi abi out_dir_var out_libs_var)
    set(bin "${CMAKE_BINARY_DIR}/native/${abi}")
    set(libdir "${bin}/lib")
    set(libs "${libdir}/libserialport_jni.so"
             "${libdir}/libsbxapplogic_ctprotocol_jni.so")
    add_custom_command(
        OUTPUT ${libs}
        COMMAND
            "${CMAKE_COMMAND}" -S "${sbc_native_source_dir}" -B "${bin}"
            -G "${CMAKE_GENERATOR}" "-DCMAKE_MAKE_PROGRAM=${CMAKE_MAKE_PROGRAM}"
            "-DCMAKE_TOOLCHAIN_FILE=${sbc_ndk_root}/build/cmake/android.toolchain.cmake"
            "-DANDROID_ABI=${abi}" "-DANDROID_PLATFORM=${native_platform}"
            "-DCMAKE_BUILD_TYPE=Release"
        COMMAND "${CMAKE_COMMAND}" --build "${bin}"
        DEPENDS ${sbc_native_sources}
        COMMENT "native[${abi}]: NDK ${ndk_version} build of serialport + ctprotocol"
        USES_TERMINAL VERBATIM)
    add_custom_target(native-${abi} DEPENDS ${libs})
    set(${out_dir_var} "${libdir}" PARENT_SCOPE)
    set(${out_libs_var} "${libs}" PARENT_SCOPE)
endfunction()
