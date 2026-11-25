# sbc_version.cmake: project version, distribution identity and the release
# metadata derived from them.
#
# The project version has one source: project(VERSION) in CMakeLists.txt.
# Everything else is derived here:
#
#   sbc_upstream_version   stock app version the patches apply to. The input
#                          SHA-256 pin fixes it; the identity patch asserts it
#                          against the decoded apktool.yml.
#   sbc_version_name       Android versionName, <upstream>-compat.<project>
#   sbc_version_code       Android versionCode, see below
#   sbc_release_tag        Git tag, v<project>
#   sbc_release_apk        release artifact file name
#   sbc_app_id, sbc_app_label   identity of the distributable variant
#
# versionCode = MAJOR * 1000000 + MINOR * 1000 + PATCH, each component
# 0..999. Ordering of codes follows ordering of project versions, so every
# release has a larger code than the one before it. 0.1.0 is 1000; the scheme
# stays below Android's limit of 2100000000 for every MAJOR up to 2099.
#
# ${CMAKE_BINARY_DIR}/release.env lists the derived values as KEY=VALUE lines
# for release tooling, so no script repeats a version constant.

include_guard(GLOBAL)

set(sbc_upstream_version "1.04.02")
set(sbc_upstream_version_code "10402")

set(sbc_app_id "io.github.asce1062.sbconnect.compat")
set(sbc_app_label "SB Connect Compat")

foreach(part MAJOR MINOR PATCH)
    if(NOT DEFINED PROJECT_VERSION_${part} OR PROJECT_VERSION_${part} STREQUAL "")
        message(FATAL_ERROR "sbc_version: project(VERSION) must have MAJOR.MINOR.PATCH")
    endif()
    if(PROJECT_VERSION_${part} GREATER 999)
        message(
            FATAL_ERROR
                "sbc_version: version component ${part}=${PROJECT_VERSION_${part}} exceeds 999,"
                " the versionCode scheme's range")
    endif()
endforeach()

set(sbc_version "${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}.${PROJECT_VERSION_PATCH}")
set(sbc_version_name "${sbc_upstream_version}-compat.${sbc_version}")
math(
    EXPR
    sbc_version_code
    "${PROJECT_VERSION_MAJOR} * 1000000 + ${PROJECT_VERSION_MINOR} * 1000 + ${PROJECT_VERSION_PATCH}")
set(sbc_release_tag "v${sbc_version}")
set(sbc_release_apk "sbconnect-compat-${sbc_release_tag}.apk")

file(
    WRITE "${CMAKE_BINARY_DIR}/release.env"
    "PROJECT_VERSION=${sbc_version}\n"
    "RELEASE_TAG=${sbc_release_tag}\n"
    "RELEASE_APK=${sbc_release_apk}\n"
    "APP_ID=${sbc_app_id}\n"
    "APP_LABEL=${sbc_app_label}\n"
    "VERSION_NAME=${sbc_version_name}\n"
    "VERSION_CODE=${sbc_version_code}\n"
    "UPSTREAM_VERSION=${sbc_upstream_version}\n")

message(
    STATUS
        "version: ${sbc_version} (${sbc_release_tag}), versionName ${sbc_version_name},"
        " versionCode ${sbc_version_code}, id ${sbc_app_id}")
