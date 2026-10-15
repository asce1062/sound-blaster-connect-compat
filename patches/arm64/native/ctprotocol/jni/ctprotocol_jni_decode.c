/*
 * JNI decode adapter for ctprotocol-core.
 *
 * Exports the single inbound entry point decode([BI)Z and maps each typed event
 * ctprotocol-core emits onto the matching stock SbxSppCommandManager static
 * callback. No protocol logic lives here: ctp_decode does the parsing, this file
 * only marshals bytes in and typed events out. Bound statically by export name,
 * exactly like the stock library.
 *
 * JNI_OnLoad caches the 28 inbound callback method IDs all-or-nothing, mirroring
 * the stock loader: if any GetStaticMethodID fails the library fails to load
 * (returns -1), so the callback set is either entirely present or entirely
 * absent. Three of the 28 (audioCtrl, sbxProfileInfo, sbxProfileData) are cached
 * but never invoked; no dispatcher path reaches them, in stock or here.
 */
#include <jni.h>
#include <string.h>
#include "ctprotocol_decode.h"

#define JNM(name) \
    Java_com_creative_logic_sbxapplogic_vendor_sbx_SbxSppCommandManager_##name

/* Cached class and the 28 inbound callback method IDs (JNI_OnLoad). */
static jclass    g_cls;
static jmethodID m_requestControl;
static jmethodID m_dataAck;
static jmethodID m_obsoleteAck;
static jmethodID m_pendingAck;
static jmethodID m_fileAck;
static jmethodID m_deviceInfo;
static jmethodID m_fwInfo;
static jmethodID m_maxPls;
static jmethodID m_hwBtn;
static jmethodID m_audioCtrl;         /* cached, never dispatched */
static jmethodID m_audioLvl;
static jmethodID m_audioLvlRange;
static jmethodID m_batteryLevel;
static jmethodID m_batteryLevelSupport;
static jmethodID m_batteryStatus;
static jmethodID m_batteryStatusSupport;
static jmethodID m_hwBtnSupport;
static jmethodID m_hwBtnStatusSupport;
static jmethodID m_hwBtnEnabled;
static jmethodID m_sbxProfileInfo;    /* cached, never dispatched */
static jmethodID m_sbxProfileData;    /* cached, never dispatched */
static jmethodID m_btAutoConnect;
static jmethodID m_devicefwString;
static jmethodID m_profileInfoRecFirst;
static jmethodID m_profileInfoRest;
static jmethodID m_activeProfileRec;
static jmethodID m_activeProfileMega;
static jmethodID m_voicePromptCtrl;

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM *vm, void *reserved) {
    (void)reserved;
    JNIEnv *env;
    if ((*vm)->GetEnv(vm, (void **)&env, JNI_VERSION_1_6) != JNI_OK)
        return -1;

    jclass cls = (*env)->FindClass(
        env, "com/creative/logic/sbxapplogic/vendor/sbx/SbxSppCommandManager");
    if (cls == NULL)
        return -1;
    g_cls = (jclass)(*env)->NewGlobalRef(env, cls);
    if (g_cls == NULL)
        return -1;

#define GET(var, name, sig)                                        \
    var = (*env)->GetStaticMethodID(env, g_cls, name, sig);        \
    if (var == NULL)                                               \
        return -1;

    GET(m_requestControl,      "requestControlCallback",      "(Z)V")
    GET(m_dataAck,             "dataAckCallback",             "(II[B)V")
    GET(m_obsoleteAck,         "obsoleteAckCallback",         "(II)V")
    GET(m_pendingAck,          "pendingAckCallback",          "(III)V")
    GET(m_fileAck,             "fileAckCallback",             "(III)V")
    GET(m_deviceInfo,          "deviceInfoCallback",          "(II)V")
    GET(m_fwInfo,              "fwInfoCallback",              "(IIIII)V")
    GET(m_maxPls,              "maxPlsCallback",              "(I)V")
    GET(m_hwBtn,               "hwBtnCallback",               "(IZZZZZZZ)V")
    GET(m_audioCtrl,           "audioCtrlCallback",           "(IZ)V")
    GET(m_audioLvl,            "audioLvlCallback",            "(IFI)V")
    GET(m_audioLvlRange,       "audioLvlRangeCallback",       "(IFFFIII)V")
    GET(m_batteryLevel,        "batteryLevelCallback",        "(I)V")
    GET(m_batteryLevelSupport, "batteryLevelSupportCallback", "(III)V")
    GET(m_batteryStatus,       "batteryStatusCallback",       "(ZZ)V")
    GET(m_batteryStatusSupport,"batteryStatusSupportCallback","(ZZ)V")
    GET(m_hwBtnSupport,        "hwBtnSupportCallback",        "(IZZZZZZZ)V")
    GET(m_hwBtnStatusSupport,  "hwBtnStatusSupportCallback",  "(IZZZZZZZ)V")
    GET(m_hwBtnEnabled,        "hwBtnEnabledCallback",        "(IZZZZZZZ)V")
    GET(m_sbxProfileInfo,      "sbxProfileInfoCallback",      "(II)V")
    GET(m_sbxProfileData,      "sbxProfileDataCallback",      "(I)V")
    GET(m_btAutoConnect,       "btAutoConnectCallback",       "(I)V")
    GET(m_devicefwString,      "devicefwStringCallback",      "([I)V")
    GET(m_profileInfoRecFirst, "profileInfoRecFirstCallback", "(IIIZIZZIZ)V")
    GET(m_profileInfoRest,     "profileInfoRestCallback",     "(IIZIZZIZ)V")
    GET(m_activeProfileRec,    "activeProfileRecCallback",    "(IZ)V")
    GET(m_activeProfileMega,   "activeProfileMegaCallback",   "(IZ)V")
    GET(m_voicePromptCtrl,     "voicePromptCtrlCallback",     "(I)V")
#undef GET

    return JNI_VERSION_1_6;
}

/* One emitted event -> one static callback, args in Java order. */
static void emit_cb(void *user, const ctp_event *ev) {
    JNIEnv *env = (JNIEnv *)user;
    const int Z = JNI_TRUE, z = JNI_FALSE;
#define B(x) ((x) ? Z : z)

    switch (ev->kind) {
    case CTP_EV_OBSOLETE_ACK:
        (*env)->CallStaticVoidMethod(env, g_cls, m_obsoleteAck,
            (jint)ev->u.two.code, (jint)ev->u.two.v1);
        break;
    case CTP_EV_PENDING_ACK:
        (*env)->CallStaticVoidMethod(env, g_cls, m_pendingAck,
            (jint)ev->u.three.a0, (jint)ev->u.three.a1, (jint)ev->u.three.a2);
        break;
    case CTP_EV_FILE_ACK:
        (*env)->CallStaticVoidMethod(env, g_cls, m_fileAck,
            (jint)ev->u.three.a0, (jint)ev->u.three.a1, (jint)ev->u.three.a2);
        break;
    case CTP_EV_DATA_ACK: {
        jbyteArray d = (*env)->NewByteArray(env, 8);
        if (d != NULL) {
            (*env)->SetByteArrayRegion(env, d, 0, 8,
                (const jbyte *)ev->u.data_ack.data);
            (*env)->CallStaticVoidMethod(env, g_cls, m_dataAck,
                (jint)ev->u.data_ack.code, (jint)ev->u.data_ack.v1, d);
            (*env)->DeleteLocalRef(env, d);
        }
        break;
    }
    case CTP_EV_MAX_PLS:
        (*env)->CallStaticVoidMethod(env, g_cls, m_maxPls, (jint)ev->u.one.value);
        break;
    case CTP_EV_REQUEST_CONTROL:
        (*env)->CallStaticVoidMethod(env, g_cls, m_requestControl, B(ev->u.one.value));
        break;
    case CTP_EV_DEVICE_INFO:
        (*env)->CallStaticVoidMethod(env, g_cls, m_deviceInfo,
            (jint)ev->u.two.code, (jint)ev->u.two.v1);
        break;
    case CTP_EV_FW_INFO:
        (*env)->CallStaticVoidMethod(env, g_cls, m_fwInfo,
            (jint)ev->u.five.a0, (jint)ev->u.five.a1, (jint)ev->u.five.a2,
            (jint)ev->u.five.a3, (jint)ev->u.five.a4);
        break;
    case CTP_EV_DEVICE_FW_STRING: {
        jintArray a = (*env)->NewIntArray(env, 64);
        if (a != NULL) {
            (*env)->SetIntArrayRegion(env, a, 0, 64, (const jint *)ev->u.int_array.vals);
            (*env)->CallStaticVoidMethod(env, g_cls, m_devicefwString, a);
            (*env)->DeleteLocalRef(env, a);
        }
        break;
    }
    case CTP_EV_PROFILE_INFO_REC_FIRST:
        (*env)->CallStaticVoidMethod(env, g_cls, m_profileInfoRecFirst,
            (jint)ev->u.rec_first.x, (jint)ev->u.rec_first.index,
            (jint)ev->u.rec_first.type, B(ev->u.rec_first.b0_hi),
            (jint)ev->u.rec_first.b1_lo, B(ev->u.rec_first.b1_b6),
            B(ev->u.rec_first.b1_hi_n), (jint)ev->u.rec_first.b2_lo,
            B(ev->u.rec_first.b2_hi_n));
        break;
    case CTP_EV_PROFILE_INFO_REST:
        (*env)->CallStaticVoidMethod(env, g_cls, m_profileInfoRest,
            (jint)ev->u.rest.x_plus_index, (jint)ev->u.rest.type, B(ev->u.rest.b0_hi),
            (jint)ev->u.rest.b1_lo, B(ev->u.rest.b1_b6), B(ev->u.rest.b1_hi_n),
            (jint)ev->u.rest.b2_lo, B(ev->u.rest.b2_hi_n));
        break;
    case CTP_EV_ACTIVE_PROFILE_REC:
        (*env)->CallStaticVoidMethod(env, g_cls, m_activeProfileRec,
            (jint)ev->u.int_bool.value, B(ev->u.int_bool.flag));
        break;
    case CTP_EV_ACTIVE_PROFILE_MEGA:
        (*env)->CallStaticVoidMethod(env, g_cls, m_activeProfileMega,
            (jint)ev->u.int_bool.value, B(ev->u.int_bool.flag));
        break;
    case CTP_EV_AUDIO_LVL_RANGE:
        (*env)->CallStaticVoidMethod(env, g_cls, m_audioLvlRange,
            (jint)ev->u.audio_range.a0, (jfloat)ev->u.audio_range.f0,
            (jfloat)ev->u.audio_range.f1, (jfloat)ev->u.audio_range.f2,
            (jint)ev->u.audio_range.i0, (jint)ev->u.audio_range.i1,
            (jint)ev->u.audio_range.i2);
        break;
    case CTP_EV_AUDIO_LVL:
        (*env)->CallStaticVoidMethod(env, g_cls, m_audioLvl,
            (jint)ev->u.audio_lvl.a0, (jfloat)ev->u.audio_lvl.f,
            (jint)ev->u.audio_lvl.i0);
        break;
    case CTP_EV_HW_BTN:
        (*env)->CallStaticVoidMethod(env, g_cls, m_hwBtn, (jint)ev->u.hwbtn.value,
            B(ev->u.hwbtn.bit[0]), B(ev->u.hwbtn.bit[1]), B(ev->u.hwbtn.bit[2]),
            B(ev->u.hwbtn.bit[3]), B(ev->u.hwbtn.bit[4]), B(ev->u.hwbtn.bit[5]),
            B(ev->u.hwbtn.bit[6]));
        break;
    case CTP_EV_HW_BTN_SUPPORT:
        (*env)->CallStaticVoidMethod(env, g_cls, m_hwBtnSupport, (jint)ev->u.hwbtn.value,
            B(ev->u.hwbtn.bit[0]), B(ev->u.hwbtn.bit[1]), B(ev->u.hwbtn.bit[2]),
            B(ev->u.hwbtn.bit[3]), B(ev->u.hwbtn.bit[4]), B(ev->u.hwbtn.bit[5]),
            B(ev->u.hwbtn.bit[6]));
        break;
    case CTP_EV_HW_BTN_STATUS_SUPPORT:
        (*env)->CallStaticVoidMethod(env, g_cls, m_hwBtnStatusSupport, (jint)ev->u.hwbtn.value,
            B(ev->u.hwbtn.bit[0]), B(ev->u.hwbtn.bit[1]), B(ev->u.hwbtn.bit[2]),
            B(ev->u.hwbtn.bit[3]), B(ev->u.hwbtn.bit[4]), B(ev->u.hwbtn.bit[5]),
            B(ev->u.hwbtn.bit[6]));
        break;
    case CTP_EV_HW_BTN_ENABLED:
        (*env)->CallStaticVoidMethod(env, g_cls, m_hwBtnEnabled, (jint)ev->u.hwbtn.value,
            B(ev->u.hwbtn.bit[0]), B(ev->u.hwbtn.bit[1]), B(ev->u.hwbtn.bit[2]),
            B(ev->u.hwbtn.bit[3]), B(ev->u.hwbtn.bit[4]), B(ev->u.hwbtn.bit[5]),
            B(ev->u.hwbtn.bit[6]));
        break;
    case CTP_EV_BATTERY_LEVEL:
        (*env)->CallStaticVoidMethod(env, g_cls, m_batteryLevel, (jint)ev->u.one.value);
        break;
    case CTP_EV_BATTERY_LEVEL_SUPPORT:
        (*env)->CallStaticVoidMethod(env, g_cls, m_batteryLevelSupport,
            (jint)ev->u.three.a0, (jint)ev->u.three.a1, (jint)ev->u.three.a2);
        break;
    case CTP_EV_BATTERY_STATUS:
        (*env)->CallStaticVoidMethod(env, g_cls, m_batteryStatus,
            B(ev->u.two_bool.b0), B(ev->u.two_bool.b1));
        break;
    case CTP_EV_BATTERY_STATUS_SUPPORT:
        (*env)->CallStaticVoidMethod(env, g_cls, m_batteryStatusSupport,
            B(ev->u.two_bool.b0), B(ev->u.two_bool.b1));
        break;
    case CTP_EV_BT_AUTO_CONNECT:
        (*env)->CallStaticVoidMethod(env, g_cls, m_btAutoConnect, (jint)ev->u.one.value);
        break;
    case CTP_EV_VOICE_PROMPT_CTRL:
        (*env)->CallStaticVoidMethod(env, g_cls, m_voicePromptCtrl, (jint)ev->u.one.value);
        break;
    }
#undef B
}

/*
 * decode([BI)Z. Reads exactly `len` bytes from offset 0 of `frame` into a zeroed
 * work buffer, runs ctp_decode (which fires emit_cb per event), and hands Java
 * the stock predicate: true unless the frame was unrecognizable. Lengths are
 * clamped to the work buffer; real device frames are far smaller.
 */
JNIEXPORT jboolean JNICALL JNM(decode)(JNIEnv *env, jclass cls,
                                       jbyteArray frame, jint len) {
    (void)cls;
    uint8_t buf[CTP_DECODE_MINBUF];
    memset(buf, 0, sizeof buf);

    int declen = (int)len;
    if (declen < 0) declen = 0;
    if (declen > (int)sizeof buf) declen = (int)sizeof buf;

    if (frame != NULL) {
        jsize n = (*env)->GetArrayLength(env, frame);
        int copylen = declen;
        if (copylen > (int)n) copylen = (int)n;
        if (copylen > 0)
            (*env)->GetByteArrayRegion(env, frame, 0, copylen, (jbyte *)buf);
    }

    int ret = ctp_decode(buf, declen, emit_cb, env);
    return (ret != CTP_DECODE_UNRECOGNIZED) ? JNI_TRUE : JNI_FALSE;
}
