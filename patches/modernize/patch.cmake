# modernize/patch.cmake — raise the target API level.
#
# STARTER STEP ONLY. Bumps targetSdkVersion 26 -> 30. 30 (Android 11) is the
# highest level reachable WITHOUT the extra smali work that 31+ forces
# (explicit android:exported, PendingIntent FLAG_IMMUTABLE, runtime
# BLUETOOTH_CONNECT/SCAN, POST_NOTIFICATIONS, foregroundServiceType). It
# stays installable on every device while being a real step up from 26.
#
# apktool reads targetSdkVersion from apktool.yml at build time and writes it
# into the built manifest, so editing the yml is the whole change. Push
# further only alongside the matching manifest/smali edits — see README.md
# and docs/FINDINGS.md.

set(target_from "26")
set(target_to "30")

set(yml "${TREE}/apktool.yml")
if(NOT EXISTS "${yml}")
    message(FATAL_ERROR "modernize: apktool.yml missing: ${yml}")
endif()

file(READ "${yml}" yml_text)
string(
    REPLACE "targetSdkVersion: '${target_from}'"
            "targetSdkVersion: '${target_to}'"
            yml_new
            "${yml_text}")
if(yml_new STREQUAL yml_text)
    message(
        FATAL_ERROR
            "modernize: targetSdkVersion: '${target_from}' not found in apktool.yml "
            "(already bumped, or the stock value changed)")
endif()
file(WRITE "${yml}" "${yml_new}")
message(STATUS "modernize: targetSdkVersion ${target_from} -> ${target_to}")
