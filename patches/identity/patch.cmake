# identity/patch.cmake: give the distributable build its own application
# identity and version, leaving the stock class names, JNI interface and
# internal action strings unchanged.
#
# Runs with ${TREE} set to the staged tree, after modernize and arm64. The
# values come from cmake/sbc_version.cmake through sbc_add_variant DEFINES:
#
#   SBC_APP_ID              new package name (application ID)
#   SBC_APP_LABEL           launcher and settings label
#   SBC_VERSION_NAME        Android versionName
#   SBC_VERSION_CODE        Android versionCode
#   SBC_UPSTREAM_VERSION    stock versionName, asserted as an anchor
#   SBC_UPSTREAM_VERSION_CODE  stock versionCode, asserted as an anchor
#
# Every edit asserts its stock occurrence count. The package-dependence audit
# behind this list is docs/technical/APPLICATION_IDENTITY.md.
#
#   * Manifest package attribute. Every component name in the stock manifest
#     is fully qualified, so no component resolves through the package name.
#     aapt2 names the resource table after the manifest package, which keeps
#     Resources.getIdentifier(name, type, getPackageName()) resolving.
#   * Measurement provider authority. Authorities are unique per device; the
#     stock value would block installing next to the stock app.
#   * Labels of the application, the launcher activity and the notification
#     listener service.
#   * SbxDeviceManager compares getPackageName() with the stock package to
#     select SB Connect host behavior (offline browsing leaves the device name
#     unset). Both comparisons name the new package so the host behavior is
#     unchanged.
#   * versionName and versionCode in apktool.yml.

foreach(v SBC_APP_ID SBC_APP_LABEL SBC_VERSION_NAME SBC_VERSION_CODE SBC_UPSTREAM_VERSION
          SBC_UPSTREAM_VERSION_CODE)
    if(NOT DEFINED ${v} OR "${${v}}" STREQUAL "")
        message(FATAL_ERROR "identity: ${v} is not set (pass it through sbc_add_variant DEFINES)")
    endif()
endforeach()

set(_stock_pkg "com.creative.apps.sbconnect")

# Literal find-and-replace in <path>, asserting <needle> occurs exactly
# <expected> times.
function(_sbc_identity_sub path needle replacement expected)
    if(NOT EXISTS "${path}")
        message(FATAL_ERROR "identity: file missing: ${path}")
    endif()
    file(READ "${path}" c)
    set(n 0)
    set(s "${c}")
    string(LENGTH "${needle}" nl)
    string(FIND "${s}" "${needle}" pos)
    while(NOT pos EQUAL -1)
        math(EXPR n "${n}+1")
        math(EXPR cut "${pos}+${nl}")
        string(SUBSTRING "${s}" ${cut} -1 s)
        string(FIND "${s}" "${needle}" pos)
    endwhile()
    if(NOT n EQUAL expected)
        message(
            FATAL_ERROR
                "identity: anchor found ${n} time(s), expected ${expected}, in ${path}\n"
                "  anchor: ${needle}")
    endif()
    string(REPLACE "${needle}" "${replacement}" c "${c}")
    file(WRITE "${path}" "${c}")
endfunction()

set(_manifest "${TREE}/AndroidManifest.xml")
_sbc_identity_sub("${_manifest}" "package=\"${_stock_pkg}\"" "package=\"${SBC_APP_ID}\"" 1)
_sbc_identity_sub("${_manifest}" "android:authorities=\"${_stock_pkg}.google_measurement_service\""
                  "android:authorities=\"${SBC_APP_ID}.google_measurement_service\"" 1)
# application and LocalMusicRemoteControllerService
_sbc_identity_sub("${_manifest}" "android:label=\"@string/app_name\"" "android:label=\"${SBC_APP_LABEL}\"" 2)
# MainActivity (launcher entry)
_sbc_identity_sub("${_manifest}" "android:label=\"@string/launcher_name\"" "android:label=\"${SBC_APP_LABEL}\"" 1)

_sbc_identity_sub("${TREE}/smali/com/creative/logic/sbxapplogic/SbxDeviceManager.smali" "\"${_stock_pkg}\""
                  "\"${SBC_APP_ID}\"" 2)

set(_yml "${TREE}/apktool.yml")
_sbc_identity_sub("${_yml}" "versionCode: ${SBC_UPSTREAM_VERSION_CODE}\n" "versionCode: ${SBC_VERSION_CODE}\n" 1)
_sbc_identity_sub("${_yml}" "versionName: ${SBC_UPSTREAM_VERSION}\n" "versionName: ${SBC_VERSION_NAME}\n" 1)

message(STATUS "identity: ${SBC_APP_ID} \"${SBC_APP_LABEL}\" ${SBC_VERSION_NAME} (${SBC_VERSION_CODE})")
