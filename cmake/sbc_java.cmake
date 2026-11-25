# sbc_java.cmake: Java sources of a patch, compiled to smali at build time.
#
# A patch may carry patches/<p>/java/, a Java source tree in the app's
# package layout. sbc_java_smali(<p> <out_var>) registers one build step per
# patch (cmake/compile_java.cmake): javac to Java 8 bytecode against the
# pinned android.jar, d8, then apktool decodes the dex to smali in
# build/java/<p>/smali. <out_var> receives the step's stamp file;
# sbc_add_variant depends on it and apply_patch.cmake copies the smali onto
# the staged tree after the patch's overlay.
#
# Tools: javac from a JDK (17+), d8 from the pinned build-tools release,
# android.jar from the pinned SDK platform.

include_guard(GLOBAL)

set(_sdk_default "")
foreach(sdk IN ITEMS "$ENV{ANDROID_SDK_ROOT}" "$ENV{ANDROID_HOME}" "$ENV{LOCALAPPDATA}/Android/Sdk")
    if(_sdk_default STREQUAL "" AND NOT sdk STREQUAL "" AND NOT sdk STREQUAL "/Android/Sdk"
       AND IS_DIRECTORY "${sdk}/build-tools")
        set(_sdk_default "${sdk}")
    endif()
endforeach()
set(android_sdk_root
    "${_sdk_default}"
    CACHE PATH "Android SDK root (build-tools, platform)")
set(android_build_tools_version
    "37.0.0"
    CACHE STRING "Pinned Android SDK build-tools release")
set(android_platform
    "android-34"
    CACHE STRING "Pinned SDK platform whose android.jar compiles patch Java sources")
find_program(
    javac_bin
    NAMES javac
    DOC "javac (JDK 17+) for patch Java sources")

set(sbc_android_jar "${android_sdk_root}/platforms/${android_platform}/android.jar")
if(CMAKE_HOST_WIN32)
    set(sbc_d8 "${android_sdk_root}/build-tools/${android_build_tools_version}/d8.bat")
else()
    set(sbc_d8 "${android_sdk_root}/build-tools/${android_build_tools_version}/d8")
endif()
set(sbc_java_script "${CMAKE_CURRENT_LIST_DIR}/compile_java.cmake")
set(sbc_java_out "${CMAKE_BINARY_DIR}/java")

# Lowest API level the app supports (apktool.yml of the stock release).
set(sbc_min_api "14")

function(sbc_java_smali patch out_var)
    set(src "${PROJECT_SOURCE_DIR}/patches/${patch}/java")
    set(out "${sbc_java_out}/${patch}")
    set(stamp "${out}/smali.stamp")
    get_property(done GLOBAL PROPERTY sbc_java_${patch})
    if(NOT done)
        foreach(req javac_bin sbc_d8 sbc_android_jar)
            if(NOT EXISTS "${${req}}")
                message(
                    FATAL_ERROR
                        "patch '${patch}' has Java sources; ${req} not found: '${${req}}'\n"
                        "  Install a JDK (javac), build-tools ${android_build_tools_version} and "
                        "platform ${android_platform}, or set javac_bin / android_sdk_root.")
            endif()
        endforeach()
        file(
            GLOB_RECURSE java_sources CONFIGURE_DEPENDS
            LIST_DIRECTORIES FALSE
            "${src}/*.java")
        add_custom_command(
            OUTPUT "${stamp}"
            COMMAND
                "${CMAKE_COMMAND}" "-DSRC=${src}" "-DOUT=${out}" "-DJAVAC=${javac_bin}"
                "-DJAVA=${java_bin}" "-DD8=${sbc_d8}" "-DANDROID_JAR=${sbc_android_jar}"
                "-DMIN_API=${sbc_min_api}" "-DAPKTOOL_JAR=${apktool_jar}"
                "-DFRAMEWORK_DIR=${apktool_framework_dir}" -P "${sbc_java_script}"
            DEPENDS ${java_sources} "${sbc_java_script}" "${apktool_jar}"
            COMMENT "java[${patch}]: javac + d8 + smali"
            VERBATIM)
        set_property(GLOBAL PROPERTY sbc_java_${patch} TRUE)
    endif()
    set(${out_var}
        "${stamp}"
        PARENT_SCOPE)
endfunction()
