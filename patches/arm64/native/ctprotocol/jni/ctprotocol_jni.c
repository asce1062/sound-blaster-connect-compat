/**
 * @file ctprotocol_jni.c
 * @brief Thin JNI adapter for ctprotocol-core: the encode surface.
 *
 * Translates the Java native calls on
 * com.creative.logic.sbxapplogic.vendor.sbx.SbxSppCommandManager into
 * ctprotocol-core calls and nothing else: no protocol logic lives here. Bound
 * statically by export name, exactly like the stock library. The inbound side
 * (decode() and the 28 inbound callbacks) is exported from
 * ctprotocol_jni_decode.c, which is compiled into the same library.
 *
 * A builder that rejects its input (core returns < 0) yields an empty byte[],
 * matching the stock wrapper's rejection behavior. Java arguments are widened
 * or narrowed to the core's C types without range checks; every range check
 * lives in the core. See docs/technical/JNI_INTERFACE.md.
 */
#include <jni.h>
#include <stdlib.h>
#include <string.h>
#include "ctprotocol_encode.h"

/* Expands to the JNI export name of a static native method of
 * SbxSppCommandManager. */
#define JNM(name) \
    Java_com_creative_logic_sbxapplogic_vendor_sbx_SbxSppCommandManager_##name

/* byte[] from a core result; len < 0 (reject) -> empty array, like stock.
 * Returns NULL (with a Java exception pending) if the array cannot be
 * allocated. */
static jbyteArray mk(JNIEnv *env, const uint8_t *buf, int len) {
    if (len < 0) len = 0;
    jbyteArray arr = (*env)->NewByteArray(env, len);
    if (arr != NULL && len > 0)
        (*env)->SetByteArrayRegion(env, arr, 0, len, (const jbyte *)buf);
    return arr;
}

/* NOARG(name, core): defines the export `byte[] name()` that returns the
 * constant frame produced by core function `core`. The frame is never empty. */
#define NOARG(name, core)                                                      \
    JNIEXPORT jbyteArray JNICALL JNM(name)(JNIEnv *env, jclass cls) {          \
        (void)cls;                                                             \
        uint8_t buf[CTP_CAP];                                                  \
        return mk(env, buf, core(buf));                                        \
    }

/**
 * @name Fixed-frame exports
 *
 * Each generated export is `static native byte[] <name>()` on
 * SbxSppCommandManager: getMaxPayloadSize, getGeneralInfo, getDeviceFwString,
 * releaseControl, commitSettings, getHwBtn, getHwBtnSupport,
 * getHwBtnStatusSupport, hwBtnEnabled, getBatteryLevel, getBatteryLevelSupport,
 * getBatteryStatus, getBatteryStatusSupport, getBtAutoConnect,
 * getVoicePromptCtrl, resetFactoryDefault, cancelFileTransfer,
 * getProfileInfoRec, getActiveProfileRec and getActiveProfileMega.
 *
 * @param env  JNI environment.
 * @param cls  The SbxSppCommandManager class (unused).
 * @return     A new byte[] holding the frame of the matching ctp_* function
 *             (see ctprotocol_encode.h).
 * @{
 */
NOARG(getMaxPayloadSize, ctp_getMaxPayloadSize)
NOARG(getGeneralInfo, ctp_getGeneralInfo)
NOARG(getDeviceFwString, ctp_getDeviceFwString)
NOARG(releaseControl, ctp_releaseControl)
NOARG(commitSettings, ctp_commitSettings)
NOARG(getHwBtn, ctp_getHwBtn)
NOARG(getHwBtnSupport, ctp_getHwBtnSupport)
NOARG(getHwBtnStatusSupport, ctp_getHwBtnStatusSupport)
NOARG(hwBtnEnabled, ctp_hwBtnEnabled)
NOARG(getBatteryLevel, ctp_getBatteryLevel)
NOARG(getBatteryLevelSupport, ctp_getBatteryLevelSupport)
NOARG(getBatteryStatus, ctp_getBatteryStatus)
NOARG(getBatteryStatusSupport, ctp_getBatteryStatusSupport)
NOARG(getBtAutoConnect, ctp_getBtAutoConnect)
NOARG(getVoicePromptCtrl, ctp_getVoicePromptCtrl)
NOARG(resetFactoryDefault, ctp_resetFactoryDefault)
NOARG(cancelFileTransfer, ctp_cancelFileTransfer)
NOARG(getProfileInfoRec, ctp_getProfileInfoRec)
NOARG(getActiveProfileRec, ctp_getActiveProfileRec)
NOARG(getActiveProfileMega, ctp_getActiveProfileMega)
/** @} */

/* ONEARG(name, core): defines the export `byte[] name(int a)` that calls
 * `core(buf, a)` and returns the frame, or an empty byte[] when the core
 * rejects `a`. */
#define ONEARG(name, core)                                                     \
    JNIEXPORT jbyteArray JNICALL JNM(name)(JNIEnv *env, jclass cls, jint a) {  \
        (void)cls;                                                             \
        uint8_t buf[CTP_CAP];                                                  \
        return mk(env, buf, core(buf, (int)a));                               \
    }

/**
 * @name One-int exports
 *
 * Each generated export is `static native byte[] <name>(int a)` on
 * SbxSppCommandManager: getFwInfo, getAudioLvl, setBtAutoConnect,
 * setVoicePromptCtrl, setActiveProfileRec, setActiveProfileMega,
 * setActiveProfileRecVoicePreview and setActiveProfileMegaVoicePreview.
 *
 * @param env  JNI environment.
 * @param cls  The SbxSppCommandManager class (unused).
 * @param a    The argument, passed to the matching ctp_* function as an int.
 * @return     A new byte[] holding the frame, or an empty byte[] when the core
 *             rejects `a` (see ctprotocol_encode.h for each accepted domain).
 * @{
 */
ONEARG(getFwInfo, ctp_getFwInfo)
ONEARG(getAudioLvl, ctp_getAudioLvl)
ONEARG(setBtAutoConnect, ctp_setBtAutoConnect)
ONEARG(setVoicePromptCtrl, ctp_setVoicePromptCtrl)
ONEARG(setActiveProfileRec, ctp_setActiveProfileRec)
ONEARG(setActiveProfileMega, ctp_setActiveProfileMega)
ONEARG(setActiveProfileRecVoicePreview, ctp_setActiveProfileRecVoicePreview)
ONEARG(setActiveProfileMegaVoicePreview, ctp_setActiveProfileMegaVoicePreview)
/** @} */

/**
 * @brief Java `static native byte[] setTime(int t)`.
 *
 * @param env  JNI environment.
 * @param cls  The SbxSppCommandManager class (unused).
 * @param t    Time value, written as 4 little-endian bytes.
 * @return     A new 7-byte byte[]; the core never rejects.
 */
JNIEXPORT jbyteArray JNICALL JNM(setTime)(JNIEnv *env, jclass cls, jint t) {
    (void)cls;
    uint8_t buf[CTP_CAP];
    return mk(env, buf, ctp_setTime(buf, (int32_t)t));
}

/**
 * @brief Java `static native byte[] setHwBtn(int id, int val)`.
 *
 * @param env  JNI environment.
 * @param cls  The SbxSppCommandManager class (unused).
 * @param id   Button identifier, accepted by the core when in 1..20.
 * @param val  Button state, accepted by the core when 0 or 1.
 * @return     A new 6-byte byte[], or an empty byte[] when the core rejects
 *             the arguments.
 */
JNIEXPORT jbyteArray JNICALL JNM(setHwBtn)(JNIEnv *env, jclass cls, jint id, jint val) {
    (void)cls;
    uint8_t buf[CTP_CAP];
    return mk(env, buf, ctp_setHwBtn(buf, (int)id, (int)val));
}

/**
 * @brief Java `static native byte[] setFileSize(int a, int b)`.
 *
 * @param env  JNI environment.
 * @param cls  The SbxSppCommandManager class (unused).
 * @param a    Command type; the core accepts only 1.
 * @param b    File size, written as 4 little-endian bytes.
 * @return     A new 8-byte byte[], or an empty byte[] when `a` is not 1.
 */
JNIEXPORT jbyteArray JNICALL JNM(setFileSize)(JNIEnv *env, jclass cls, jint a, jint b) {
    (void)cls;
    uint8_t buf[CTP_CAP];
    return mk(env, buf, ctp_setFileSize(buf, (int)a, (int)b));
}

/**
 * @brief Java `static native byte[] getFileDataBlk(byte[] data, int len, boolean flag)`.
 *
 * Copies at most 256 bytes of `data` into a local buffer and passes that count
 * as the readable length to ctp_getFileDataBlk, so a `len` above the readable
 * length (at most min(data.length, 256)) is rejected by the core.
 *
 * @param env   JNI environment.
 * @param cls   The SbxSppCommandManager class (unused).
 * @param data  Source bytes. A null array is passed to the core as NULL and
 *              rejected.
 * @param len   Number of bytes to copy, accepted by the core when in 1..253.
 * @param flag  True selects block marker 0x81, false selects 0x80.
 * @return      A new byte[] of `len + 5` bytes, or an empty byte[] when the
 *              core rejects the arguments.
 */
JNIEXPORT jbyteArray JNICALL JNM(getFileDataBlk)(JNIEnv *env, jclass cls,
                                                 jbyteArray data, jint len, jboolean flag) {
    (void)cls;
    uint8_t buf[CTP_CAP];
    uint8_t src[256];
    int datalen = 0;
    if (data != NULL) {
        jsize n = (*env)->GetArrayLength(env, data);
        datalen = (int)n;
        if (datalen > (int)sizeof src) datalen = (int)sizeof src;
        (*env)->GetByteArrayRegion(env, data, 0, datalen, (jbyte *)src);
    }
    int r = ctp_getFileDataBlk(buf, data != NULL ? src : NULL, datalen,
                               (int)len, flag != JNI_FALSE);
    return mk(env, buf, r);
}

/**
 * @brief Java `static native byte[] setMalcolmParam(int[] a, int[] b, float[] c, int d, int[] e)`.
 *
 * Marshals the three parameter arrays into native buffers, sizes the output
 * with ctp_malcolm_size and calls ctp_setMalcolmParam. The arrays `a`, `b` and
 * `c` must not be null.
 *
 * @param env  JNI environment.
 * @param cls  The SbxSppCommandManager class (unused).
 * @param a    Group ids.
 * @param b    Sub-indexes.
 * @param c    Float values.
 * @param d    Group-size seed (see ctp_setMalcolmParam).
 * @param e    Optional out-array. On success, when non-null and at least 2
 *             elements long, e[0] and e[1] receive the core's e0 and e1.
 *             Otherwise it is left untouched.
 * @return     A new byte[] holding the frames, or an empty byte[] when the
 *             arrays differ in length, any parameter is invalid, or memory
 *             cannot be allocated. A zero-length parameter list also yields an
 *             empty byte[], and still fills `e`.
 */
JNIEXPORT jbyteArray JNICALL JNM(setMalcolmParam)(JNIEnv *env, jclass cls,
                                                  jintArray a, jintArray b,
                                                  jfloatArray c, jint d, jintArray e) {
    (void)cls;
    /* Marshalling guard: stock requires a.length == b.length == c.length. */
    jsize na = (*env)->GetArrayLength(env, a);
    jsize nb = (*env)->GetArrayLength(env, b);
    jsize nc = (*env)->GetArrayLength(env, c);
    if (na != nb || na != nc) return mk(env, NULL, 0);

    int n = (int)na;
    int32_t *ai = NULL, *bi = NULL;
    float *cf = NULL;
    uint8_t *out = NULL;
    jbyteArray result;

    if (n > 0) {
        ai = (int32_t *)malloc((size_t)n * sizeof(int32_t));
        bi = (int32_t *)malloc((size_t)n * sizeof(int32_t));
        cf = (float *)malloc((size_t)n * sizeof(float));
        if (ai == NULL || bi == NULL || cf == NULL) { result = mk(env, NULL, 0); goto done; }
        (*env)->GetIntArrayRegion(env, a, 0, n, (jint *)ai);
        (*env)->GetIntArrayRegion(env, b, 0, n, (jint *)bi);
        (*env)->GetFloatArrayRegion(env, c, 0, n, (jfloat *)cf);
    }

    int size = ctp_malcolm_size(n, (int)d);   /* n >= 0, so >= 0 */
    out = (uint8_t *)malloc((size_t)(size > 0 ? size : 1));
    if (out == NULL) { result = mk(env, NULL, 0); goto done; }

    int e0 = 0, e1 = 0;
    int r = ctp_setMalcolmParam(out, ai, bi, cf, n, (int)d, &e0, &e1);
    result = mk(env, out, r);
    if (r >= 0 && e != NULL && (*env)->GetArrayLength(env, e) >= 2) {
        jint eo[2] = { (jint)e0, (jint)e1 };
        (*env)->SetIntArrayRegion(env, e, 0, 2, eo);
    }

done:
    free(ai); free(bi); free(cf); free(out);
    return result;
}

/**
 * @brief Java `static native int getFileTransferMaxDataSize()`.
 *
 * @param env  JNI environment (unused).
 * @param cls  The SbxSppCommandManager class (unused).
 * @return     253, the largest `len` accepted by getFileDataBlk.
 */
JNIEXPORT jint JNICALL JNM(getFileTransferMaxDataSize)(JNIEnv *env, jclass cls) {
    (void)env; (void)cls;
    return (jint)ctp_getFileTransferMaxDataSize();
}
