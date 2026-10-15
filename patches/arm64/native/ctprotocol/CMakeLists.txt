# ctprotocol-core + thin JNI adapter -> libsbxapplogic_ctprotocol_jni.so
#
# One portable core (core/, no JNI) plus a thin adapter (jni/) that binds the
# stock SbxSppCommandManager native exports. The same core compiles for x86
# (oracle differential) and arm64-v8a (device). The output .so keeps the stock
# name so the APK overlay drops it in unchanged.

add_library(sbxapplogic_ctprotocol_jni SHARED
    core/ctprotocol_encode.c
    jni/ctprotocol_jni.c)

target_include_directories(sbxapplogic_ctprotocol_jni PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/core")

# JNIEXPORT already forces default visibility on the bound symbols, so the
# parent's hidden visibility preset keeps everything else (core internals)
# unexported, matching the stock library's surface.
