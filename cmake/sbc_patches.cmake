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
