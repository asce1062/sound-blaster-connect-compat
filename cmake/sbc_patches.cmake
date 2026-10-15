# sbc_patches.cmake — variant framework.
#
# A variant is one output APK built from one patch set. sbc_add_variant
# stages a FRESH copy of the pristine decompiled/ tree, applies the named
# patches onto that copy, then rebuilds (apktool b) and signs
# (uber-apk-signer debug key) into build/sbc_<name>-aligned-debugSigned.apk.
#
#   sbc_add_variant(<name> PATCHES a b c)   # empty PATCHES = pure repackage
#
# A patch is a patches/<name>/ directory with either or both of:
#   overlay/      a file tree copied verbatim onto the staged tree (its paths
#                 mirror the decoded layout: AndroidManifest.xml, res/...,
#                 smali/..., lib/<abi>/...).
#   patch.cmake   CMake run with ${TREE} set to the staged tree, for edits
#                 that are not whole-file replacements (bump a value in
#                 apktool.yml, rewrite a smali line, inject a manifest attr).
#
# Patches apply in the order listed, so a later patch can build on an earlier
# one (e.g. arm64 layered on modernize).

include_guard(GLOBAL)

function(sbc_add_variant name)
    cmake_parse_arguments(V "" "" "PATCHES" ${ARGN})

    set(payload_deps)
    set(patch_csv "")
    foreach(p IN LISTS V_PATCHES)
        if(NOT IS_DIRECTORY "${PROJECT_SOURCE_DIR}/patches/${p}")
            message(
                FATAL_ERROR
                    "variant '${name}': unknown patch '${p}' — no patches/${p}/ directory"
            )
        endif()
        file(
            GLOB_RECURSE pl CONFIGURE_DEPENDS
            LIST_DIRECTORIES FALSE
            "${PROJECT_SOURCE_DIR}/patches/${p}/*")
        list(APPEND payload_deps ${pl})
        if(patch_csv STREQUAL "")
            set(patch_csv "${p}")
        else()
            set(patch_csv "${patch_csv},${p}")
        endif()
    endforeach()

    set(tree "${CMAKE_BINARY_DIR}/${name}/tree")
    set(unsigned "${CMAKE_BINARY_DIR}/sbc_${name}.apk")
    set(signed "${CMAKE_BINARY_DIR}/sbc_${name}-aligned-debugSigned.apk")

    add_custom_command(
        OUTPUT "${signed}"
        COMMAND "${CMAKE_COMMAND}" -E rm -f "${unsigned}" "${signed}"
        COMMAND "${CMAKE_COMMAND}" -E rm -rf "${tree}"
        COMMAND "${CMAKE_COMMAND}" -E copy_directory "${decompiled_dir}"
                "${tree}"
        COMMAND
            "${CMAKE_COMMAND}" "-DTREE=${tree}"
            "-DPATCHES_ROOT=${PROJECT_SOURCE_DIR}/patches"
            "-DPATCHES=${patch_csv}" -P "${apply_script}"
        COMMAND
            "${CMAKE_COMMAND}" -E echo
            "+ ${java_bin} -jar ${apktool_jar} b ${tree} -o ${unsigned} -f --jobs ${apktool_jobs}"
        COMMAND "${java_bin}" -jar "${apktool_jar}" b "${tree}" -o "${unsigned}"
                -f --jobs "${apktool_jobs}"
        COMMAND
            "${CMAKE_COMMAND}" -E echo
            "+ ${java_bin} -jar ${signer_jar} -a ${unsigned} --out ${CMAKE_BINARY_DIR} --allowResign"
        COMMAND "${java_bin}" -jar "${signer_jar}" -a "${unsigned}" --out
                "${CMAKE_BINARY_DIR}" --allowResign
        DEPENDS "${stamp_decompiled}"
                ${decompiled_files}
                ${payload_deps}
                "${apply_script}"
                "${apktool_jar}"
                "${signer_jar}"
        COMMENT
            "variant[${name}]: stage + patch [${patch_csv}] + apktool b + sign"
        USES_TERMINAL VERBATIM)

    add_custom_target(apk-${name} DEPENDS "${signed}")

    set_property(GLOBAL APPEND PROPERTY sbc_variants "${name}")
    set_property(GLOBAL APPEND PROPERTY sbc_all_apks "${signed}")
    set(sbc_variant_${name}_apk
        "${signed}"
        PARENT_SCOPE)
endfunction()

# sbc_add_resign_control(<name>) — the payload-preserving signing control.
#
# Unlike sbc_add_variant, this does NOT go through apktool: it isolates
# signing/distribution from every other change. It copies the stock APK
# verbatim (aligning once only if the stock is not already aligned), re-signs
# with the debug key via resign_control.cmake, then PROVES with
# resign_verify.cmake that every non-signature entry's uncompressed bytes are
# SHA-256 identical to stock. The build FAILS if any payload byte differs.
#
# It registers the same globals as sbc_add_variant (sbc_variants / sbc_all_apks
# / sbc_variant_<name>_apk / apk-<name>), so deploy and the `apks` target treat
# it like any other variant, and it produces the same output path
# (sbc_<name>-aligned-debugSigned.apk).
function(sbc_add_resign_control name)
    set(staged "${CMAKE_BINARY_DIR}/sbc_${name}-aligned.apk")
    set(signed "${CMAKE_BINARY_DIR}/sbc_${name}-aligned-debugSigned.apk")
    set(verify_work "${CMAKE_BINARY_DIR}/${name}/verify")

    add_custom_command(
        OUTPUT "${signed}"
        COMMAND
            "${CMAKE_COMMAND}" "-DINPUT=${apk_input}" "-DSTAGED=${staged}"
            "-DOUTDIR=${CMAKE_BINARY_DIR}" "-DJAVA=${java_bin}"
            "-DSIGNER=${signer_jar}" "-DZIPALIGN=${zipalign_bin}" -P
            "${resign_script}"
        COMMAND
            "${CMAKE_COMMAND}" "-DSTOCK=${apk_input}" "-DCAND=${signed}"
            "-DWORK=${verify_work}" -P "${resign_verify_script}"
        DEPENDS "${apk_input}"
                "${signer_jar}"
                "${resign_script}"
                "${resign_verify_script}"
        COMMENT
            "control[${name}]: payload-preserving re-sign of stock + SHA-256 payload proof"
        USES_TERMINAL VERBATIM)

    add_custom_target(apk-${name} DEPENDS "${signed}")

    set_property(GLOBAL APPEND PROPERTY sbc_variants "${name}")
    set_property(GLOBAL APPEND PROPERTY sbc_all_apks "${signed}")
    set(sbc_variant_${name}_apk
        "${signed}"
        PARENT_SCOPE)
endfunction()
