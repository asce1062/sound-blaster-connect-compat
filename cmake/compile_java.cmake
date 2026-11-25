# compile_java.cmake: compile a patch's Java sources to smali.
#
#   cmake -DSRC=<patches/<p>/java> -DOUT=<dir> -DJAVAC=<javac> -DJAVA=<java>
#         -DD8=<d8> -DANDROID_JAR=<android.jar> -DMIN_API=<n>
#         -DAPKTOOL_JAR=<apktool.jar> -DFRAMEWORK_DIR=<dir> -P compile_java.cmake
#
# javac (Java 8 bytecode, android.jar on the class path), d8 to one
# classes.dex, then apktool decodes that dex to smali in <OUT>/smali, which
# apply_patch.cmake copies onto the staged tree's smali/ directory. The
# result depends only on the sources and the pinned tools. <OUT>/smali.stamp
# is written last.

foreach(v SRC OUT JAVAC JAVA D8 ANDROID_JAR MIN_API APKTOOL_JAR FRAMEWORK_DIR)
    if(NOT DEFINED ${v} OR "${${v}}" STREQUAL "")
        message(FATAL_ERROR "compile_java: ${v} not set")
    endif()
endforeach()
if(NOT EXISTS "${ANDROID_JAR}")
    message(FATAL_ERROR "compile_java: android.jar missing: ${ANDROID_JAR}")
endif()

file(GLOB_RECURSE sources LIST_DIRECTORIES FALSE "${SRC}/*.java")
list(SORT sources)
if(NOT sources)
    message(FATAL_ERROR "compile_java: no .java files under ${SRC}")
endif()

file(REMOVE_RECURSE "${OUT}")
file(MAKE_DIRECTORY "${OUT}/classes" "${OUT}/dex")

execute_process(
    COMMAND "${JAVAC}" --release 8 -Xlint:-options -encoding UTF-8 -cp
            "${ANDROID_JAR}" -d "${OUT}/classes" ${sources}
    COMMAND_ERROR_IS_FATAL ANY)

file(GLOB_RECURSE classes LIST_DIRECTORIES FALSE "${OUT}/classes/*.class")
list(SORT classes)
execute_process(
    COMMAND "${D8}" --release --min-api "${MIN_API}" --lib "${ANDROID_JAR}"
            --output "${OUT}/dex" ${classes}
    COMMAND_ERROR_IS_FATAL ANY)

execute_process(
    COMMAND "${CMAKE_COMMAND}" -E tar cf "${OUT}/classes.zip" --format=zip
            classes.dex
    WORKING_DIRECTORY "${OUT}/dex"
    COMMAND_ERROR_IS_FATAL ANY)

execute_process(
    COMMAND "${JAVA}" -jar "${APKTOOL_JAR}" d --no-res -f -p "${FRAMEWORK_DIR}"
            -o "${OUT}/decoded" "${OUT}/classes.zip"
    COMMAND_ERROR_IS_FATAL ANY)

if(NOT IS_DIRECTORY "${OUT}/decoded/smali")
    message(FATAL_ERROR "compile_java: apktool produced no smali")
endif()
file(RENAME "${OUT}/decoded/smali" "${OUT}/smali")
file(REMOVE_RECURSE "${OUT}/decoded" "${OUT}/classes" "${OUT}/dex")
file(REMOVE "${OUT}/classes.zip")
file(TOUCH "${OUT}/smali.stamp")
