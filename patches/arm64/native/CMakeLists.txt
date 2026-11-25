cmake_minimum_required(VERSION 3.22)
project(sbconnect_native C)

# arm64-v8a rebuilds of the two stock native libraries, cross-compiled with the
# Android NDK. The root pipeline configures this project per ABI (see
# sbc_native.cmake) and the arm64 patch copies the outputs onto the decoded app.
# No prebuilt binary is tracked; every APK carries libraries built from this
# source.

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_VISIBILITY_PRESET hidden)

# Both libraries land in one directory so the patch step has a single source.
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib")

# Release binaries carry no build-machine paths and no debug info: map the
# source and build roots out of any debug record, then strip at link time.
# Neither option changes generated code.
add_compile_options(
    "-ffile-prefix-map=${CMAKE_SOURCE_DIR}=."
    "-ffile-prefix-map=${CMAKE_BINARY_DIR}=build")
add_link_options("-Wl,--build-id=sha1" "-s")

add_library(serialport_jni SHARED serialport/serialport.c)
target_link_libraries(serialport_jni log)

add_subdirectory(ctprotocol)
