# resign_verify.cmake: verify that a signed APK is payload-identical to the stock.
#
#   cmake -DSTOCK=<stock.apk> -DCAND=<candidate.apk> -DWORK=<scratch dir> \
#         -P resign_verify.cmake
#
# Extracts both archives and compares the SHA-256 of every entry's
# *uncompressed* bytes. Only signature-related entries may differ:
#   META-INF/MANIFEST.MF, META-INF/*.SF, META-INF/*.RSA/*.DSA/*.EC
# Every other entry must be present in both and SHA-256 identical. The v2/v3
# APK Signing Block is not a ZIP entry, so it never appears here. FATAL on any
# mismatch, missing entry, or unexpected extra non-signature entry.

foreach(v STOCK CAND WORK)
    if(NOT DEFINED ${v})
        message(FATAL_ERROR "resign_verify: ${v} not set")
    endif()
endforeach()

set(sig_re "^META-INF/(MANIFEST\\.MF|[^/]+\\.(SF|RSA|DSA|EC))$")

set(stock_x "${WORK}/stock")
set(cand_x "${WORK}/cand")
file(REMOVE_RECURSE "${stock_x}" "${cand_x}")
file(MAKE_DIRECTORY "${stock_x}" "${cand_x}")
file(ARCHIVE_EXTRACT INPUT "${STOCK}" DESTINATION "${stock_x}")
file(ARCHIVE_EXTRACT INPUT "${CAND}" DESTINATION "${cand_x}")

file(
    GLOB_RECURSE stock_files
    RELATIVE "${stock_x}"
    LIST_DIRECTORIES FALSE
    "${stock_x}/*")
file(
    GLOB_RECURSE cand_files
    RELATIVE "${cand_x}"
    LIST_DIRECTORIES FALSE
    "${cand_x}/*")

set(failures "")
set(n_payload 0)
set(n_lib 0)
set(n_dex 0)
set(n_res 0)
set(n_assets 0)
set(n_arsc 0)
set(n_other 0)

foreach(rel IN LISTS stock_files)
    if(rel MATCHES "${sig_re}")
        continue()
    endif()
    math(EXPR n_payload "${n_payload}+1")
    if(rel MATCHES "^lib/")
        math(EXPR n_lib "${n_lib}+1")
    elseif(rel MATCHES "^classes[0-9]*\\.dex$")
        math(EXPR n_dex "${n_dex}+1")
    elseif(rel STREQUAL "resources.arsc")
        math(EXPR n_arsc "${n_arsc}+1")
    elseif(rel MATCHES "^res/")
        math(EXPR n_res "${n_res}+1")
    elseif(rel MATCHES "^assets/")
        math(EXPR n_assets "${n_assets}+1")
    else()
        math(EXPR n_other "${n_other}+1")
    endif()

    if(NOT EXISTS "${cand_x}/${rel}")
        string(APPEND failures "  MISSING in candidate: ${rel}\n")
        continue()
    endif()
    file(SHA256 "${stock_x}/${rel}" a)
    file(SHA256 "${cand_x}/${rel}" b)
    if(NOT a STREQUAL b)
        string(APPEND failures "  SHA-256 MISMATCH: ${rel}\n    stock ${a}\n    cand  ${b}\n")
    endif()
endforeach()

foreach(rel IN LISTS cand_files)
    if(rel MATCHES "${sig_re}")
        continue()
    endif()
    if(NOT EXISTS "${stock_x}/${rel}")
        string(APPEND failures "  UNEXPECTED non-signature entry in candidate: ${rel}\n")
    endif()
endforeach()

message(STATUS "resign_verify: payload entries compared (non-signature): ${n_payload}")
message(STATUS "resign_verify:   lib=${n_lib} dex=${n_dex} resources.arsc=${n_arsc} res=${n_res} assets=${n_assets} other=${n_other}")

if(NOT failures STREQUAL "")
    message(FATAL_ERROR "resign_verify: PAYLOAD-PRESERVING FAIL\n${failures}")
endif()

message(STATUS "resign_verify: PAYLOAD-PRESERVING PASS (${n_payload} entries SHA-256 identical to stock)")
