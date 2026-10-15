cmake_minimum_required(VERSION 3.22)
project(sbconnect_native C)

# arm64-v8a rebuilds of the two stock native libraries, cross-compiled with the
# Android NDK. Built out-of-tree by build.ps1 into patches/arm64/overlay/lib/,
# from where the APK pipeline copies them onto the decoded app.

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_VISIBILITY_PRESET hidden)

add_library(serialport_jni SHARED serialport/serialport.c)
target_link_libraries(serialport_jni log)

# ctprotocol is added once its source lands (see ctprotocol/).
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/ctprotocol/CMakeLists.txt")
    add_subdirectory(ctprotocol)
endif()
