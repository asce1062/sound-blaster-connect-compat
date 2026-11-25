# Host regression tests for the portable CtProtocol core.
#
# Builds ctprotocol-core and tests/ctprotocol/ctp_regress.c with the host C
# compiler and replays every frozen vector set in oracle/vectors/ through it.
# No Android SDK, NDK, emulator or stock APK is needed.
#
#   cmake -S tests/ctprotocol -B build/host-tests
#   cmake --build build/host-tests
#   ctest --test-dir build/host-tests --output-on-failure
cmake_minimum_required(VERSION 3.20)
project(ctprotocol_host_tests C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

get_filename_component(SBC_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../.." ABSOLUTE)
set(CORE_DIR "${SBC_ROOT}/patches/arm64/native/ctprotocol/core")
set(VECTOR_DIR "${SBC_ROOT}/oracle/vectors")

add_executable(ctp_regress
    ctp_regress.c
    "${CORE_DIR}/ctprotocol_encode.c"
    "${CORE_DIR}/ctprotocol_decode.c")
target_include_directories(ctp_regress PRIVATE "${CORE_DIR}")
if(NOT MSVC)
    target_link_libraries(ctp_regress PRIVATE m)
endif()

enable_testing()

# name, driver mode, corpus (or "-" for the encoder), expected output
set(cases
    "enc_stock|enc|-|enc_stock.txt"
    "dec_entry|dec|dec_entry.txt|dec_entry.out.txt"
    "dec_valid|dec|dec_valid.txt|dec_valid.out.txt"
    "dec_reject|seq|dec_reject.txt|dec_reject.out.txt"
    "dec_state|seq|dec_state.txt|dec_state.out.txt"
    "dec_stream|seq|dec_stream.txt|dec_stream.out.txt")
foreach(c IN LISTS cases)
    string(REPLACE "|" ";" f "${c}")
    list(GET f 0 name)
    list(GET f 1 mode)
    list(GET f 2 corpus)
    list(GET f 3 expected)
    if(corpus STREQUAL "-")
        set(corpus_arg "")
    else()
        set(corpus_arg "${VECTOR_DIR}/${corpus}")
    endif()
    add_test(NAME ${name}
        COMMAND "${CMAKE_COMMAND}"
            "-DDRIVER=$<TARGET_FILE:ctp_regress>"
            "-DMODE=${mode}"
            "-DCORPUS=${corpus_arg}"
            "-DEXPECTED=${VECTOR_DIR}/${expected}"
            "-DOUT=${CMAKE_CURRENT_BINARY_DIR}/${name}.out.txt"
            -P "${CMAKE_CURRENT_SOURCE_DIR}/compare.cmake")
endforeach()
