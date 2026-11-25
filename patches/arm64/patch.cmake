# arm64 patch: add the arm64-v8a native libraries built from patches/arm64/native/.
#
# SBC_NATIVE_LIB_DIR is the build output of sbc_native.cmake for arm64-v8a. The
# stock armeabi-v7a libraries stay in place, so the result is one APK carrying
# both ABIs.

set(_abi_dir "${TREE}/lib/arm64-v8a")
set(_libs libserialport_jni.so libsbxapplogic_ctprotocol_jni.so)

if(NOT SBC_NATIVE_LIB_DIR OR NOT IS_DIRECTORY "${SBC_NATIVE_LIB_DIR}")
    message(FATAL_ERROR "arm64 patch: SBC_NATIVE_LIB_DIR is not a directory: '${SBC_NATIVE_LIB_DIR}'")
endif()

file(MAKE_DIRECTORY "${_abi_dir}")
foreach(_lib IN LISTS _libs)
    if(NOT EXISTS "${SBC_NATIVE_LIB_DIR}/${_lib}")
        message(FATAL_ERROR "arm64 patch: missing ${SBC_NATIVE_LIB_DIR}/${_lib}")
    endif()
    file(COPY "${SBC_NATIVE_LIB_DIR}/${_lib}" DESTINATION "${_abi_dir}")
    message(STATUS "arm64 patch: lib/arm64-v8a/${_lib}")
endforeach()
