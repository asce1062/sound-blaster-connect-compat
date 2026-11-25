# verify_signed_apk.cmake: verify a test-release or release APK.
#
#   cmake -DMODE=<test-release|release> -DAPK=<apk>
#         (-DCERT_SHA256=<hex> | -DCERT_ENV=<variable holding it>)
#         -DPACKAGE=<id> -DVERSION_CODE=<n> -DVERSION_NAME=<s>
#         -DABIS=<abi,abi,...> -DWORK=<dir>
#         -DAPKSIGNER=<path> -DZIPALIGN=<path> -DAAPT2=<path>
#         [-DNATIVE_ABI=<abi> -DNATIVE_LIBS=<file,file,...>]
#         [-DUNSIGNED=<apk> -DREF_SCRIPT=<resign_verify.cmake>]
#         -P verify_signed_apk.cmake
#
# Checks, each fatal:
#   1. apksigner verify: schemes v1, v2 and v3 verify, one signer
#   2. zipalign -c -P 16 4
#   3. signer certificate SHA-256 equals the expected value; in release mode
#      the certificate is not an Android debug certificate
#   4. package, versionCode and versionName (aapt2 dump badging)
#   5. lib/ holds exactly the ABIS directories; NATIVE_LIBS are present in
#      lib/<NATIVE_ABI>/ byte for byte and are the only files there
#   6. with UNSIGNED: every non-signature entry equals the unsigned APK's
#
# The optional inputs let the same script check a downloaded release APK
# without a build tree. Results go to <WORK>/verified.env for
# release_metadata.cmake. -DDISCARD_ON_FAILURE=ON, set by the build targets,
# deletes APK when a check fails, so no signed but unverified file remains.

function(_fail)
    if(DISCARD_ON_FAILURE AND DEFINED APK)
        file(REMOVE "${APK}")
    endif()
    string(CONCAT msg ${ARGN})
    message(FATAL_ERROR "${msg}")
endfunction()

foreach(v MODE APK PACKAGE VERSION_CODE VERSION_NAME ABIS WORK APKSIGNER ZIPALIGN AAPT2)
    if(NOT DEFINED ${v} OR "${${v}}" STREQUAL "")
        message(FATAL_ERROR "verify_signed_apk: ${v} is not set")
    endif()
endforeach()
if(NOT EXISTS "${APK}")
    message(FATAL_ERROR "verify_signed_apk: APK not found: ${APK}")
endif()

set(want_cert "")
if(DEFINED CERT_SHA256 AND NOT CERT_SHA256 STREQUAL "")
    set(want_cert "${CERT_SHA256}")
elseif(DEFINED CERT_ENV AND NOT "$ENV{${CERT_ENV}}" STREQUAL "")
    set(want_cert "$ENV{${CERT_ENV}}")
endif()
if(want_cert STREQUAL "")
    _fail("verify_signed_apk[${MODE}]: no expected certificate SHA-256 (CERT_SHA256 or ${CERT_ENV})")
endif()
string(TOLOWER "${want_cert}" want_cert)
string(REGEX REPLACE "[: ]" "" want_cert "${want_cert}")
if(NOT want_cert MATCHES "^[0-9a-f]+$")
    _fail("verify_signed_apk[${MODE}]: expected certificate SHA-256 is not hexadecimal")
endif()
string(LENGTH "${want_cert}" n)
if(NOT n EQUAL 64)
    _fail("verify_signed_apk[${MODE}]: expected certificate SHA-256 has ${n} digits, not 64")
endif()

set(vwork "${WORK}/verify")
file(REMOVE_RECURSE "${vwork}")
file(MAKE_DIRECTORY "${vwork}")

function(_run step)
    execute_process(
        COMMAND ${ARGN}
        RESULT_VARIABLE rc
        OUTPUT_VARIABLE out
        ERROR_VARIABLE err)
    if(NOT rc EQUAL 0)
        _fail("verify_signed_apk[${MODE}]: ${step} failed (${rc})\n${out}${err}")
    endif()
    string(REPLACE "\r" "" out "${out}${err}")
    set(_out "${out}" PARENT_SCOPE)
endfunction()

# 1. Signature.
_run("apksigner verify" "${APKSIGNER}" verify --verbose --print-certs "${APK}")
set(report "${_out}")
set(schemes "")
foreach(s "v1 scheme \\(JAR signing\\)" "v2 scheme \\(APK Signature Scheme v2\\)"
          "v3 scheme \\(APK Signature Scheme v3\\)")
    if(NOT report MATCHES "Verified using ${s}: true")
        _fail("verify_signed_apk[${MODE}]: not verified: ${s}\n${report}")
    endif()
endforeach()
if(NOT report MATCHES "Number of signers: 1\n")
    _fail("verify_signed_apk[${MODE}]: expected exactly one signer\n${report}")
endif()
message(STATUS "verify_signed_apk[${MODE}]: apksigner verify: v1, v2, v3 verified, 1 signer")

# 2. Alignment.
_run("zipalign check" "${ZIPALIGN}" -c -P 16 4 "${APK}")
message(STATUS "verify_signed_apk[${MODE}]: zipalign -c -P 16 4: ok")

# 3. Certificate. apksigner prints the digest once per scheme; all must agree.
string(REGEX MATCHALL "certificate SHA-256 digest: [0-9a-f]+" digests "${report}")
list(TRANSFORM digests REPLACE "certificate SHA-256 digest: " "")
list(REMOVE_DUPLICATES digests)
list(LENGTH digests n)
if(NOT n EQUAL 1)
    _fail("verify_signed_apk[${MODE}]: expected one signer certificate digest, found ${n}: ${digests}")
endif()
string(REGEX MATCH "certificate DN: ([^\n]+)" _ "${report}")
set(cert_dn "${CMAKE_MATCH_1}")
if(NOT digests STREQUAL want_cert)
    _fail("verify_signed_apk[${MODE}]: signer certificate SHA-256 ${digests}, expected ${want_cert}")
endif()
if(MODE STREQUAL "release" AND cert_dn MATCHES "CN=Android Debug")
    _fail("verify_signed_apk[release]: signed with an Android debug certificate (${cert_dn})")
endif()
message(STATUS "verify_signed_apk[${MODE}]: certificate ${digests} matches (${cert_dn})")

# 4. Package metadata.
_run("aapt2 dump badging" "${AAPT2}" dump badging "${APK}")
string(REGEX MATCH "package: name='([^']*)' versionCode='([^']*)' versionName='([^']*)'" _ "${_out}")
set(got "${CMAKE_MATCH_1}|${CMAKE_MATCH_2}|${CMAKE_MATCH_3}")
if(NOT got STREQUAL "${PACKAGE}|${VERSION_CODE}|${VERSION_NAME}")
    _fail("verify_signed_apk[${MODE}]: package metadata '${got}',"
          " expected '${PACKAGE}|${VERSION_CODE}|${VERSION_NAME}'")
endif()
message(STATUS "verify_signed_apk[${MODE}]: ${PACKAGE} ${VERSION_CODE} ${VERSION_NAME}")

# 5. Native library inventory.
set(libx "${vwork}/lib")
file(MAKE_DIRECTORY "${libx}")
file(ARCHIVE_EXTRACT INPUT "${APK}" DESTINATION "${libx}" PATTERNS "lib/*")
file(GLOB abi_dirs RELATIVE "${libx}/lib" LIST_DIRECTORIES TRUE "${libx}/lib/*")
list(SORT abi_dirs)
string(REPLACE "," ";" want_abis "${ABIS}")
list(SORT want_abis)
if(NOT abi_dirs STREQUAL want_abis)
    _fail("verify_signed_apk[${MODE}]: lib/ ABIs '${abi_dirs}', expected '${want_abis}'")
endif()
set(lib_report "")
if(DEFINED NATIVE_LIBS AND NOT NATIVE_LIBS STREQUAL "")
    string(REPLACE "," ";" libs "${NATIVE_LIBS}")
    file(GLOB in_apk RELATIVE "${libx}/lib/${NATIVE_ABI}" "${libx}/lib/${NATIVE_ABI}/*")
    set(want_names "")
    foreach(lib IN LISTS libs)
        get_filename_component(lname "${lib}" NAME)
        list(APPEND want_names "${lname}")
        if(NOT EXISTS "${libx}/lib/${NATIVE_ABI}/${lname}")
            _fail("verify_signed_apk[${MODE}]: lib/${NATIVE_ABI}/${lname} missing")
        endif()
        file(SHA256 "${lib}" a)
        file(SHA256 "${libx}/lib/${NATIVE_ABI}/${lname}" b)
        if(NOT a STREQUAL b)
            _fail("verify_signed_apk[${MODE}]: lib/${NATIVE_ABI}/${lname} ${b} differs from the build ${a}")
        endif()
        string(APPEND lib_report "NATIVE_${lname}=${b}\n")
    endforeach()
    list(SORT in_apk)
    list(SORT want_names)
    if(NOT in_apk STREQUAL want_names)
        _fail("verify_signed_apk[${MODE}]: lib/${NATIVE_ABI}/ holds '${in_apk}', expected '${want_names}'")
    endif()
endif()
message(STATUS "verify_signed_apk[${MODE}]: native libraries: ABIs ${ABIS}; ${NATIVE_ABI} libraries match the build")

# 6. Payload against the unsigned build.
if(DEFINED UNSIGNED AND NOT UNSIGNED STREQUAL "")
    _run("payload comparison"
         "${CMAKE_COMMAND}" "-DSTOCK=${UNSIGNED}" "-DCAND=${APK}"
         "-DWORK=${vwork}/payload" "-DREF_NAME=unsigned" -P "${REF_SCRIPT}")
    string(REGEX MATCH "PAYLOAD-PRESERVING PASS \\(([0-9]+) entries" _ "${_out}")
    set(n_payload "${CMAKE_MATCH_1}")
    file(REMOVE_RECURSE "${vwork}/payload")
    message(STATUS "verify_signed_apk[${MODE}]: payload: ${n_payload} non-signature entries identical to the unsigned APK")
endif()
file(REMOVE_RECURSE "${libx}")

file(
    WRITE "${WORK}/verified.env"
    "APK=${APK}\n"
    "CERT_SHA256=${digests}\n"
    "CERT_DN=${cert_dn}\n"
    "PACKAGE=${PACKAGE}\n"
    "VERSION_CODE=${VERSION_CODE}\n"
    "VERSION_NAME=${VERSION_NAME}\n"
    "ABIS=${ABIS}\n"
    "PAYLOAD_ENTRIES=${n_payload}\n"
    "${lib_report}")
message(STATUS "verify_signed_apk[${MODE}]: PASS")
