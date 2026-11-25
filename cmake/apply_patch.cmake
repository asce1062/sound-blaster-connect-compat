# apply_patch.cmake — apply a variant's patch set onto a staged tree.
#
# Run per variant build by sbc_add_variant, after the pristine decompiled/
# tree has been copied to ${TREE}:
#
#   cmake -DTREE=<tree> -DPATCHES_ROOT=<patches/> -DPATCHES=a,b -P apply_patch.cmake
#
# For each patch, in order: copy patches/<p>/overlay/ onto the tree, then run
# patches/<p>/patch.cmake with ${TREE} in scope. PATCHES is comma-separated
# (a CMake ';' list would be split by the -D on the command line); empty = no
# patches, a plain repackage. SBC_NATIVE_LIB_DIR, when set, is in scope for
# every patch.cmake (the arm64 patch copies its libraries from it).

if(NOT DEFINED TREE OR NOT IS_DIRECTORY "${TREE}")
    message(FATAL_ERROR "apply_patch: TREE not set or missing: '${TREE}'")
endif()

if(PATCHES STREQUAL "")
    message(STATUS "apply_patch: no patches (plain repackage)")
    return()
endif()

string(
    REPLACE ","
            ";"
            patch_list
            "${PATCHES}")

foreach(p IN LISTS patch_list)
    set(pdir "${PATCHES_ROOT}/${p}")
    if(NOT IS_DIRECTORY "${pdir}")
        message(FATAL_ERROR "apply_patch: patch dir missing: ${pdir}")
    endif()

    if(IS_DIRECTORY "${pdir}/overlay")
        file(
            GLOB overlay_entries
            LIST_DIRECTORIES TRUE
            "${pdir}/overlay/*")
        if(overlay_entries)
            message(STATUS "apply_patch[${p}]: overlay => tree")
            execute_process(
                COMMAND "${CMAKE_COMMAND}" -E copy_directory "${pdir}/overlay"
                        "${TREE}" COMMAND_ERROR_IS_FATAL ANY)
        endif()
    endif()

    if(EXISTS "${pdir}/patch.cmake")
        message(STATUS "apply_patch[${p}]: patch.cmake")
        include("${pdir}/patch.cmake")
    endif()
endforeach()
