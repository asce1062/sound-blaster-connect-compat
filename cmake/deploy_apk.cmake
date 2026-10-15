# deploy_apk.cmake — adb install + launch + logcat watch.
#
#   cmake -DPKG= -DAPK= -DDEBUG=ON|OFF -DTIMEOUT=<s> -DADB_SERIAL= -DADB_BIN=adb -P deploy_apk.cmake
#
# DEBUG=ON  => launch, then tail logcat forever (Ctrl+C to stop); use on a
#              real phone you are watching.
# DEBUG=OFF => launch, capture TIMEOUT seconds of logcat, fail on a crash of
#              this package. Bounded, for a scripted / CI check.

set(adb "${ADB_BIN}")
set(serial_args)
if(NOT ADB_SERIAL STREQUAL "")
    set(serial_args -s "${ADB_SERIAL}")
endif()

if(NOT EXISTS "${APK}")
    message(FATAL_ERROR "deploy: APK not found: ${APK}")
endif()

message(STATUS "deploy: install ${APK}")
execute_process(
    COMMAND "${adb}" ${serial_args} install -r -d "${APK}"
    RESULT_VARIABLE rc)
if(rc)
    # -r (reinstall) fails when the signing key differs from an installed
    # copy; uninstall and retry once.
    message(STATUS "deploy: reinstall failed, uninstalling ${PKG} and retrying")
    execute_process(COMMAND "${adb}" ${serial_args} uninstall "${PKG}")
    execute_process(
        COMMAND "${adb}" ${serial_args} install "${APK}"
        COMMAND_ERROR_IS_FATAL ANY)
endif()

execute_process(COMMAND "${adb}" ${serial_args} logcat -c)
message(STATUS "deploy: launch ${PKG}")
execute_process(
    COMMAND "${adb}" ${serial_args} shell monkey -p "${PKG}" -c
            android.intent.category.LAUNCHER 1
    COMMAND_ERROR_IS_FATAL ANY)

if(DEBUG)
    message(STATUS "deploy: tailing logcat (Ctrl+C to stop)")
    execute_process(COMMAND "${adb}" ${serial_args} logcat)
else()
    message(STATUS "deploy: watching logcat for ${TIMEOUT}s")
    execute_process(
        COMMAND "${adb}" ${serial_args} logcat -v time
        TIMEOUT "${TIMEOUT}"
        OUTPUT_VARIABLE log
        ERROR_VARIABLE log)
    message("${log}")
    if(log MATCHES "FATAL EXCEPTION" OR log MATCHES "ANR in ${PKG}")
        message(FATAL_ERROR "deploy: crash detected for ${PKG}")
    endif()
    message(STATUS "deploy: no crash of ${PKG} in the watch window")
endif()
