# resign_control.cmake: payload-preserving re-sign of the stock APK.
#
#   cmake -DINPUT=<stock.apk> -DSTAGED=<staged.apk> -DOUTDIR=<dir> \
#         -DJAVA=<java> -DSIGNER=<uber-apk-signer.jar> -DZIPALIGN=<zipalign> \
#         -P resign_control.cmake
#
# The `resign` control isolates signing/distribution from every other change:
# it does NOT go through apktool, so no resource, manifest, or dex bytes are
# re-encoded. It checks the stock APK's alignment; if already aligned it copies
# the archive verbatim, otherwise it aligns once (zipalign never recompresses).
# It then re-signs with uber-apk-signer's debug key, passing --skipZipAlign so
# the already-aligned entries are left where they are. apksigner preserves the
# alignment and the uncompressed bytes of every non-signature entry; only the
# META-INF signature files and the v2/v3 signing block change.
#
# Output: <OUTDIR>/<STAGED-basename>-debugSigned.apk. The caller names STAGED
# "sbc_<name>-aligned.apk" so the signed output lands at the canonical
# "sbc_<name>-aligned-debugSigned.apk". resign_verify.cmake then proves the
# payload is SHA-256 identical to stock.

foreach(v INPUT STAGED OUTDIR JAVA SIGNER ZIPALIGN)
    if(NOT DEFINED ${v})
        message(FATAL_ERROR "resign_control: ${v} not set")
    endif()
endforeach()

# Resolve the signed output path uber-apk-signer will write, from STAGED's name.
cmake_path(GET STAGED STEM staged_stem)
set(signed "${OUTDIR}/${staged_stem}-debugSigned.apk")

file(REMOVE "${STAGED}" "${signed}" "${signed}.idsig")

# 1. Alignment: check, then copy verbatim (aligned) or align once (not aligned).
execute_process(
    COMMAND "${ZIPALIGN}" -c -p 4 "${INPUT}"
    RESULT_VARIABLE aligned_rc
    OUTPUT_QUIET ERROR_QUIET)

if(aligned_rc EQUAL 0)
    message(STATUS "resign: stock APK is already 4-byte/page aligned; copying archive verbatim")
    file(COPY_FILE "${INPUT}" "${STAGED}")
else()
    message(STATUS "resign: stock APK not aligned (zipalign -c rc=${aligned_rc}); aligning once (no recompression)")
    execute_process(
        COMMAND "${ZIPALIGN}" -p -f 4 "${INPUT}" "${STAGED}"
        RESULT_VARIABLE za_rc)
    if(NOT za_rc EQUAL 0)
        message(FATAL_ERROR "resign: zipalign failed (rc=${za_rc})")
    endif()
endif()

# 2. Re-sign (debug key), skipping the signer's own realign: STAGED is aligned.
message(STATUS "resign: signing with uber-apk-signer (--skipZipAlign --allowResign)")
execute_process(
    COMMAND "${JAVA}" -jar "${SIGNER}" -a "${STAGED}" --out "${OUTDIR}"
            --skipZipAlign --allowResign
    RESULT_VARIABLE sign_rc)
if(NOT sign_rc EQUAL 0)
    message(FATAL_ERROR "resign: uber-apk-signer failed (rc=${sign_rc})")
endif()

if(NOT EXISTS "${signed}")
    message(FATAL_ERROR "resign: expected signed output not produced: ${signed}")
endif()

# 3. Sanity: the signed output must still be aligned (apksigner preserves it).
execute_process(
    COMMAND "${ZIPALIGN}" -c -p 4 "${signed}"
    RESULT_VARIABLE out_aligned_rc
    OUTPUT_QUIET ERROR_QUIET)
if(NOT out_aligned_rc EQUAL 0)
    message(FATAL_ERROR "resign: signed output is not aligned (zipalign -c rc=${out_aligned_rc})")
endif()

message(STATUS "resign: produced ${signed} (aligned, re-signed)")
