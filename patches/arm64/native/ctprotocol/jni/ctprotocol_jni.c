/*
 * Thin JNI adapter for ctprotocol-core (encode surface, Phase 1).
 *
 * Translates the Java native calls on
 * com.creative.logic.sbxapplogic.vendor.sbx.SbxSppCommandManager into
 * ctprotocol-core calls and nothing else: no protocol logic lives here. Bound
 * statically by export name, exactly like the stock library. decode() and the
 * 28 inbound callbacks are the decoder phase and are intentionally absent.
 *
 * A builder that rejects its input (core returns < 0) yields an empty byte[],
 * matching the stock wrapper's rejection behavior.
 */
#include <jni.h>
#include <stdlib.h>
#include <string.h>
#include "ctprotocol_encode.h"

#define JNM(name) \
    Java_com_creative_logic_sbxapplogic_vendor_sbx_SbxSppCommandManager_##name

/* byte[] from a core result; len < 0 (reject) -> empty array, like stock. */
static jbyteArray mk(JNIEnv *env, const uint8_t *buf, int len) {
    if (len < 0) len = 0;
    jbyteArray arr = (*env)->NewByteArray(env, len);
    if (arr != NULL && len > 0)
        (*env)->SetByteArrayRegion(env, arr, 0, len, (const jbyte *)buf);
    return arr;
}

#define NOARG(name, core)                                                      \
    JNIEXPORT jbyteArray JNICALL JNM(name)(JNIEnv *env, jclass cls) {          \
        (void)cls;                                                             \
        uint8_t buf[CTP_CAP];                                                  \
        return mk(env, buf, core(buf));                                        \
    }

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

#define ONEARG(name, core)                                                     \
    JNIEXPORT jbyteArray JNICALL JNM(name)(JNIEnv *env, jclass cls, jint a) {  \
        (void)cls;                                                             \
        uint8_t buf[CTP_CAP];                                                  \
        return mk(env, buf, core(buf, (int)a));                               \
    }

ONEARG(getFwInfo, ctp_getFwInfo)
ONEARG(getAudioLvl, ctp_getAudioLvl)
ONEARG(setBtAutoConnect, ctp_setBtAutoConnect)
ONEARG(setVoicePromptCtrl, ctp_setVoicePromptCtrl)
ONEARG(setActiveProfileRec, ctp_setActiveProfileRec)
ONEARG(setActiveProfileMega, ctp_setActiveProfileMega)
ONEARG(setActiveProfileRecVoicePreview, ctp_setActiveProfileRecVoicePreview)
ONEARG(setActiveProfileMegaVoicePreview, ctp_setActiveProfileMegaVoicePreview)

JNIEXPORT jbyteArray JNICALL JNM(setTime)(JNIEnv *env, jclass cls, jint t) {
    (void)cls;
    uint8_t buf[CTP_CAP];
    return mk(env, buf, ctp_setTime(buf, (int32_t)t));
}

JNIEXPORT jbyteArray JNICALL JNM(setHwBtn)(JNIEnv *env, jclass cls, jint id, jint val) {
    (void)cls;
    uint8_t buf[CTP_CAP];
    return mk(env, buf, ctp_setHwBtn(buf, (int)id, (int)val));
}

JNIEXPORT jbyteArray JNICALL JNM(setFileSize)(JNIEnv *env, jclass cls, jint a, jint b) {
    (void)cls;
    uint8_t buf[CTP_CAP];
    return mk(env, buf, ctp_setFileSize(buf, (int)a, (int)b));
}

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

JNIEXPORT jint JNICALL JNM(getFileTransferMaxDataSize)(JNIEnv *env, jclass cls) {
    (void)env; (void)cls;
    return (jint)ctp_getFileTransferMaxDataSize();
}
