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

# The stock application ID plus ".compat": it names the app this is a
# compatibility build of, and installs as a separate package next to it.
set(sbc_app_id "com.creative.apps.sbconnect.compat")
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

# A pre-release label marks a build that is not a release, for example an
# update rehearsal signed with the production key. It is appended to the
# versionName, the tag and the file name; the versionCode stays that of the
# version, so the label consumes no versionCode and the release of that
# version still installs over it. The release workflow refuses a labelled
# build for a release tag.
set(sbc_prerelease
    ""
    CACHE STRING "Pre-release label, e.g. rehearsal.1 (empty for a release)")
if(NOT sbc_prerelease STREQUAL "" AND NOT sbc_prerelease MATCHES "^[0-9A-Za-z]+(\\.[0-9A-Za-z]+)*$")
    message(FATAL_ERROR "sbc_version: sbc_prerelease '${sbc_prerelease}' must be dot-separated alphanumerics")
endif()

set(sbc_version "${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}.${PROJECT_VERSION_PATCH}")
if(NOT sbc_prerelease STREQUAL "")
    string(APPEND sbc_version "-${sbc_prerelease}")
endif()
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
    "PRERELEASE=${sbc_prerelease}\n"
    "UPSTREAM_VERSION=${sbc_upstream_version}\n")

message(
    STATUS
        "version: ${sbc_version} (${sbc_release_tag}), versionName ${sbc_version_name},"
        " versionCode ${sbc_version_code}, id ${sbc_app_id}")
