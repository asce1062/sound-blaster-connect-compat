# Run ctp_regress in one mode and compare its output with a frozen vector file.
#
#   cmake -DDRIVER=<exe> -DMODE=<enc|dec|seq> [-DCORPUS=<file>]
#         -DEXPECTED=<file> -DOUT=<file> -P compare.cmake
#
# Line endings are normalized and lines starting with '#' are ignored on both
# sides. The harness echoes corpus comment lines in seq mode, and two corpora
# (dec_reject.txt, dec_state.txt) carry header comments that were added after
# their outputs were captured; comments carry no protocol behavior. Every other
# line must match exactly.
foreach(v DRIVER MODE EXPECTED OUT)
    if(NOT DEFINED ${v})
        message(FATAL_ERROR "compare.cmake: -D${v}= is required")
    endif()
endforeach()

set(args "${MODE}")
if(CORPUS)
    list(APPEND args "${CORPUS}")
endif()
execute_process(COMMAND "${DRIVER}" ${args}
    OUTPUT_VARIABLE actual
    ERROR_VARIABLE err
    RESULT_VARIABLE rc)
if(NOT rc EQUAL 0)
    message(FATAL_ERROR "ctp_regress ${MODE} exited ${rc}: ${err}")
endif()
file(WRITE "${OUT}" "${actual}")

function(behavior_lines text out_var)
    string(REPLACE "\r" "" text "${text}")
    # Protect list separators before splitting into lines.
    string(REPLACE ";" "\\;" text "${text}")
    string(REPLACE "\n" ";" lines "${text}")
    set(kept "")
    foreach(l IN LISTS lines)
        if(NOT l MATCHES "^#")
            string(APPEND kept "${l}\n")
        endif()
    endforeach()
    set(${out_var} "${kept}" PARENT_SCOPE)
endfunction()

file(READ "${EXPECTED}" expected)
behavior_lines("${expected}" want)
behavior_lines("${actual}" got)
if(NOT want STREQUAL got)
    message(FATAL_ERROR "output differs from ${EXPECTED}; actual output: ${OUT}")
endif()
