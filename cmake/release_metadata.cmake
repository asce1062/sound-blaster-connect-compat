# release_metadata.cmake: publish a verified APK under its final name.
#
#   cmake -DMODE=<test-release|release> -DOUT=<final apk path> -DWORK=<dir>
#         -DUNSIGNED=<apk> -DINPUT_SHA256=<stock apk pin> -DTAG=<release tag>
#         -DSOURCE_DIR=<repository> -P release_metadata.cmake
#
# Runs only after verify_signed_apk.cmake passed for <OUT>.unverified. It
# renames that file to <OUT> without changing a byte, then writes
#   <OUT>.sha256  "<sha256>  <file name>", as sha256sum prints it
#   <OUT>.json    signing mode, package, versions, certificate, hashes of the
#                 APK, the unsigned APK, the stock input and the native
#                 libraries, and the source commit
# Release mode refuses a source tree with uncommitted changes to tracked files.

foreach(v MODE OUT WORK UNSIGNED INPUT_SHA256 TAG SOURCE_DIR)
    if(NOT DEFINED ${v} OR "${${v}}" STREQUAL "")
        message(FATAL_ERROR "release_metadata: ${v} is not set")
    endif()
endforeach()

set(verified "${WORK}/verified.env")
if(NOT EXISTS "${verified}" OR NOT EXISTS "${OUT}.unverified")
    message(FATAL_ERROR "release_metadata[${MODE}]: no verified APK for ${OUT}")
endif()
file(STRINGS "${verified}" lines)
set(native_json "{}")
foreach(line IN LISTS lines)
    if(line MATCHES "^([A-Za-z0-9_.]+)=(.*)$")
        set(key "${CMAKE_MATCH_1}")
        set(val "${CMAKE_MATCH_2}")
        if(key MATCHES "^NATIVE_(.+)$")
            string(JSON native_json SET "${native_json}" "${CMAKE_MATCH_1}" "\"${val}\"")
        else()
            set(V_${key} "${val}")
        endif()
    endif()
endforeach()
if(NOT V_APK STREQUAL "${OUT}.unverified")
    message(FATAL_ERROR "release_metadata[${MODE}]: verification record is for '${V_APK}', not '${OUT}.unverified'")
endif()

find_package(Git QUIET)
set(commit "unknown")
set(dirty "unknown")
if(GIT_FOUND)
    execute_process(
        COMMAND "${GIT_EXECUTABLE}" -C "${SOURCE_DIR}" rev-parse HEAD
        RESULT_VARIABLE rc
        OUTPUT_VARIABLE commit
        OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
    if(NOT rc EQUAL 0)
        set(commit "unknown")
    endif()
    execute_process(
        COMMAND "${GIT_EXECUTABLE}" -C "${SOURCE_DIR}" status --porcelain --untracked-files=no
        RESULT_VARIABLE rc
        OUTPUT_VARIABLE changes
        ERROR_QUIET)
    if(rc EQUAL 0)
        if(changes STREQUAL "")
            set(dirty "false")
        else()
            set(dirty "true")
        endif()
    endif()
endif()
if(MODE STREQUAL "release" AND NOT dirty STREQUAL "false")
    file(REMOVE "${OUT}.unverified")
    message(
        FATAL_ERROR
            "release_metadata[release]: the source tree is not a clean git checkout"
            " (commit ${commit}, uncommitted changes: ${dirty})")
endif()

file(RENAME "${OUT}.unverified" "${OUT}")
get_filename_component(name "${OUT}" NAME)
file(SHA256 "${OUT}" apk_sha)
file(SIZE "${OUT}" apk_size)
file(SHA256 "${UNSIGNED}" unsigned_sha)
# file(WRITE) writes CRLF on Windows; sha256sum -c needs LF.
file(CONFIGURE OUTPUT "${OUT}.sha256" CONTENT "${apk_sha}  ${name}\n" @ONLY NEWLINE_STYLE LF)

set(j "{}")
foreach(
    pair
    "signing_mode|${MODE}"
    "file|${name}"
    "sha256|${apk_sha}"
    "package|${V_PACKAGE}"
    "version_name|${V_VERSION_NAME}"
    "release_tag|${TAG}"
    "certificate_sha256|${V_CERT_SHA256}"
    "certificate_dn|${V_CERT_DN}"
    "abis|${V_ABIS}"
    "unsigned_sha256|${unsigned_sha}"
    "stock_input_sha256|${INPUT_SHA256}"
    "source_commit|${commit}")
    string(REPLACE "|" ";" kv "${pair}")
    list(GET kv 0 k)
    list(GET kv 1 v)
    string(REPLACE "\\" "\\\\" v "${v}")
    string(REPLACE "\"" "\\\"" v "${v}")
    string(JSON j SET "${j}" "${k}" "\"${v}\"")
endforeach()
string(JSON j SET "${j}" "size" "${apk_size}")
string(JSON j SET "${j}" "version_code" "${V_VERSION_CODE}")
if(dirty STREQUAL "unknown")
    string(JSON j SET "${j}" "source_uncommitted_changes" "null")
else()
    string(JSON j SET "${j}" "source_uncommitted_changes" "${dirty}")
endif()
string(JSON j SET "${j}" "signature_schemes" "[\"v1\", \"v2\", \"v3\"]")
string(JSON j SET "${j}" "native_libraries_arm64_v8a_sha256" "${native_json}")
file(CONFIGURE OUTPUT "${OUT}.json" CONTENT "${j}\n" @ONLY NEWLINE_STYLE LF)

message(STATUS "release_metadata[${MODE}]: ${OUT}")
message(STATUS "  SHA-256      ${apk_sha}")
message(STATUS "  certificate  ${V_CERT_SHA256}")
message(STATUS "  commit       ${commit} (uncommitted changes: ${dirty})")
