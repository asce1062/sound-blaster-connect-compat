/**
 * @file ctp_regress.c
 * Host regression driver for the portable CtProtocol core.
 *
 * Replays the frozen oracle vectors in oracle/vectors/ against ctprotocol-core
 * compiled for the host, and prints output in exactly the format of the Java
 * oracle harness (oracle/src/.../SbxSppCommandManager.java). The output of each
 * mode is compared line for line with the recorded stock capture:
 *
 *   ctp_regress enc                  -> oracle/vectors/enc_stock.txt
 *   ctp_regress dec <corpus.txt>     -> <corpus>.out.txt  (dec_entry, dec_valid)
 *   ctp_regress seq <corpus.txt>     -> <corpus>.out.txt  (dec_reject, dec_state,
 *                                                          dec_stream)
 *
 * The driver reproduces the JNI adapter's marshalling (jni/ctprotocol_jni.c,
 * jni/ctprotocol_jni_decode.c): a rejected builder yields an empty frame,
 * setMalcolmParam checks the three array lengths and writes e[] only on
 * success, and decode() copies min(len, array length) bytes into a zeroed
 * CTP_DECODE_MINBUF buffer and reports ret = (status != UNRECOGNIZED). It does
 * not exercise the JNI glue itself; the 32-bit x86 emulator differential in
 * oracle/ runs the real JNI library against the same vectors.
 *
 * Exit status: 0 on success, 2 on usage or I/O error. tests/ctprotocol/
 * compare.cmake runs each mode and compares the result with its vector file.
 */
#include <inttypes.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <stdarg.h>

#include "ctprotocol_decode.h"
#include "ctprotocol_encode.h"

/* ---- output: direct, or held while a decode() call runs -------------------- */

static char g_hold[1 << 16];
static size_t g_hold_len;
static int g_holding;
static int g_count; /* callbacks emitted by the current decode() call */

static void outf(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    if (!g_holding) {
        vprintf(fmt, ap);
    } else {
        int n = vsnprintf(g_hold + g_hold_len, sizeof g_hold - g_hold_len, fmt, ap);
        if (n < 0 || (size_t)n >= sizeof g_hold - g_hold_len) {
            fprintf(stderr, "callback output overflow\n");
            exit(2);
        }
        g_hold_len += (size_t)n;
    }
    va_end(ap);
}

static void hold_begin(void) { g_holding = 1; g_hold_len = 0; g_hold[0] = '\0'; }
static void hold_end(void) { g_holding = 0; }
static void hold_flush(void) { fputs(g_hold, stdout); g_hold_len = 0; g_hold[0] = '\0'; }

/* ---- output helpers (Java harness formats) ------------------------------- */

static void put_hex(const uint8_t *b, int n) {
    for (int i = 0; i < n; i++) outf("%02x", b[i]);
}

/* ENC <name> <argspec> = <hex>; a negative core result prints an empty frame. */
static void enc(const char *name, const char *argspec, const uint8_t *buf, int r) {
    outf("ENC %s %s = ", name, argspec);
    if (r > 0) put_hex(buf, r);
    outf("\n");
}

/* Java Float.toString for the values the decoder can emit: shortest decimal
 * that round-trips, plain notation for 1e-3 <= |v| < 1e7, else d.dddE<exp>. */
static void java_float(char *out, size_t cap, float v) {
    if (isnan(v)) { snprintf(out, cap, "NaN"); return; }
    if (isinf(v)) { snprintf(out, cap, v < 0 ? "-Infinity" : "Infinity"); return; }
    if (v == 0.0f) { snprintf(out, cap, signbit(v) ? "-0.0" : "0.0"); return; }

    char e[48];
    int prec = 0;
    for (; prec < 9; prec++) {
        snprintf(e, sizeof e, "%.*e", prec, (double)v);
        if (strtof(e, NULL) == v) break;
    }
    /* e = [-]d[.ddd]e[+-]XX : split into sign, digits, exponent. */
    int neg = e[0] == '-';
    const char *p = e + neg;
    char digits[16];
    int nd = 0;
    for (; *p && *p != 'e'; p++)
        if (*p != '.') digits[nd++] = *p;
    digits[nd] = '\0';
    int exp10 = atoi(p + 1);
    while (nd > 1 && digits[nd - 1] == '0') digits[--nd] = '\0';

    char body[64];
    double a = fabs((double)v);
    if (a >= 1e-3 && a < 1e7) {
        if (exp10 >= 0) {
            char ip[32], fp[32];
            int k = 0, f = 0;
            for (int i = 0; i <= exp10; i++) ip[k++] = i < nd ? digits[i] : '0';
            ip[k] = '\0';
            for (int i = exp10 + 1; i < nd; i++) fp[f++] = digits[i];
            if (f == 0) fp[f++] = '0';
            fp[f] = '\0';
            snprintf(body, sizeof body, "%s.%s", ip, fp);
        } else {
            char fp[48];
            int f = 0;
            for (int i = 0; i < -exp10 - 1; i++) fp[f++] = '0';
            for (int i = 0; i < nd; i++) fp[f++] = digits[i];
            fp[f] = '\0';
            snprintf(body, sizeof body, "0.%s", fp);
        }
    } else {
        snprintf(body, sizeof body, "%c.%sE%d", digits[0], nd > 1 ? digits + 1 : "0", exp10);
    }
    snprintf(out, cap, "%s%s", neg ? "-" : "", body);
}

/* flt(): value plus raw IEEE-754 bits, as the harness prints it. */
static void put_flt(float v) {
    char s[80];
    uint32_t bits;
    memcpy(&bits, &v, sizeof bits);
    java_float(s, sizeof s, v);
    outf("%s(bits=0x%08" PRIx32 ")", s, bits);
}

#define ZB(x) ((x) ? "1" : "0")

/* ---- decode event -> callback line ---------------------------------------- */

static void emit(void *user, const ctp_event *ev) {
    const char *indent = (const char *)user;
    g_count++;
    outf("%sCB ", indent);
    switch (ev->kind) {
    case CTP_EV_OBSOLETE_ACK:
        outf("obsoleteAckCallback %" PRId32 " %" PRId32, ev->u.two.code, ev->u.two.v1);
        break;
    case CTP_EV_PENDING_ACK:
        outf("pendingAckCallback %" PRId32 " %" PRId32 " %" PRId32,
               ev->u.three.a0, ev->u.three.a1, ev->u.three.a2);
        break;
    case CTP_EV_FILE_ACK:
        outf("fileAckCallback %" PRId32 " %" PRId32 " %" PRId32,
               ev->u.three.a0, ev->u.three.a1, ev->u.three.a2);
        break;
    case CTP_EV_DATA_ACK:
        outf("dataAckCallback %" PRId32 " %" PRId32 " [len=8]",
               ev->u.data_ack.code, ev->u.data_ack.v1);
        put_hex(ev->u.data_ack.data, 8);
        break;
    case CTP_EV_MAX_PLS:
        outf("maxPlsCallback %" PRId32, ev->u.one.value);
        break;
    case CTP_EV_REQUEST_CONTROL:
        outf("requestControlCallback %s", ZB(ev->u.one.value));
        break;
    case CTP_EV_DEVICE_INFO:
        outf("deviceInfoCallback %" PRId32 " %" PRId32, ev->u.two.code, ev->u.two.v1);
        break;
    case CTP_EV_FW_INFO:
        outf("fwInfoCallback %" PRId32 " %" PRId32 " %" PRId32 " %" PRId32 " %" PRId32,
               ev->u.five.a0, ev->u.five.a1, ev->u.five.a2, ev->u.five.a3, ev->u.five.a4);
        break;
    case CTP_EV_DEVICE_FW_STRING:
        outf("devicefwStringCallback [len=64]");
        for (int i = 0; i < 64; i++)
            outf(i ? ",%" PRId32 : "%" PRId32, ev->u.int_array.vals[i]);
        break;
    case CTP_EV_PROFILE_INFO_REC_FIRST: {
        const ctp_ev_profile_rec_first *r = &ev->u.rec_first;
        outf("profileInfoRecFirstCallback %" PRId32 " %" PRId32 " %" PRId32
               " %s %" PRId32 " %s %s %" PRId32 " %s",
               r->x, r->index, r->type, ZB(r->b0_hi), r->b1_lo, ZB(r->b1_b6),
               ZB(r->b1_hi_n), r->b2_lo, ZB(r->b2_hi_n));
        break;
    }
    case CTP_EV_PROFILE_INFO_REST: {
        const ctp_ev_profile_rest *r = &ev->u.rest;
        outf("profileInfoRestCallback %" PRId32 " %" PRId32 " %s %" PRId32
               " %s %s %" PRId32 " %s",
               r->x_plus_index, r->type, ZB(r->b0_hi), r->b1_lo, ZB(r->b1_b6),
               ZB(r->b1_hi_n), r->b2_lo, ZB(r->b2_hi_n));
        break;
    }
    case CTP_EV_ACTIVE_PROFILE_REC:
        outf("activeProfileRecCallback %" PRId32 " %s",
               ev->u.int_bool.value, ZB(ev->u.int_bool.flag));
        break;
    case CTP_EV_ACTIVE_PROFILE_MEGA:
        outf("activeProfileMegaCallback %" PRId32 " %s",
               ev->u.int_bool.value, ZB(ev->u.int_bool.flag));
        break;
    case CTP_EV_AUDIO_LVL_RANGE: {
        const ctp_ev_audio_range *r = &ev->u.audio_range;
        outf("audioLvlRangeCallback %" PRId32 " ", r->a0);
        put_flt(r->f0); outf(" ");
        put_flt(r->f1); outf(" ");
        put_flt(r->f2);
        outf(" %" PRId32 " %" PRId32 " %" PRId32, r->i0, r->i1, r->i2);
        break;
    }
    case CTP_EV_AUDIO_LVL:
        outf("audioLvlCallback %" PRId32 " ", ev->u.audio_lvl.a0);
        put_flt(ev->u.audio_lvl.f);
        outf(" %" PRId32, ev->u.audio_lvl.i0);
        break;
    case CTP_EV_HW_BTN:
    case CTP_EV_HW_BTN_SUPPORT:
    case CTP_EV_HW_BTN_STATUS_SUPPORT:
    case CTP_EV_HW_BTN_ENABLED: {
        static const char *const names[] = {
            "hwBtnCallback", "hwBtnSupportCallback",
            "hwBtnStatusSupportCallback", "hwBtnEnabledCallback"};
        outf("%s %" PRId32 " ", names[ev->kind - CTP_EV_HW_BTN], ev->u.hwbtn.value);
        for (int i = 0; i < 7; i++) outf("%s", ZB(ev->u.hwbtn.bit[i]));
        break;
    }
    case CTP_EV_BATTERY_LEVEL:
        outf("batteryLevelCallback %" PRId32, ev->u.one.value);
        break;
    case CTP_EV_BATTERY_LEVEL_SUPPORT:
        outf("batteryLevelSupportCallback %" PRId32 " %" PRId32 " %" PRId32,
               ev->u.three.a0, ev->u.three.a1, ev->u.three.a2);
        break;
    case CTP_EV_BATTERY_STATUS:
        outf("batteryStatusCallback %s %s", ZB(ev->u.two_bool.b0), ZB(ev->u.two_bool.b1));
        break;
    case CTP_EV_BATTERY_STATUS_SUPPORT:
        outf("batteryStatusSupportCallback %s %s",
               ZB(ev->u.two_bool.b0), ZB(ev->u.two_bool.b1));
        break;
    case CTP_EV_BT_AUTO_CONNECT:
        outf("btAutoConnectCallback %" PRId32, ev->u.one.value);
        break;
    case CTP_EV_VOICE_PROMPT_CTRL:
        outf("voicePromptCtrlCallback %" PRId32, ev->u.one.value);
        break;
    }
    outf("\n");
}

/* ---- encode mode ----------------------------------------------------------- */

/* setMalcolmParam as marshalled by the JNI adapter. na/nb/nc are the three
 * Java array lengths; e[] stays {0,0} unless the builder succeeds. */
static void smp(const char *label, const int32_t *a, int na, const int32_t *b, int nb,
                const float *c, int nc, int d) {
    int e0 = 0, e1 = 0, r = -1;
    uint8_t *out = NULL;
    if (na == nb && na == nc) {
        int size = ctp_malcolm_size(na, d);
        out = malloc((size_t)(size > 0 ? size : 1));
        if (!out) { perror("malloc"); exit(2); }
        int t0 = 0, t1 = 0;
        r = ctp_setMalcolmParam(out, a, b, c, na, d, &t0, &t1);
        if (r >= 0) { e0 = t0; e1 = t1; }
    }
    outf("ENC setMalcolmParam %s = ", label);
    if (r > 0) put_hex(out, r);
    outf(" e=%d,%d\n", e0, e1);
    free(out);
}

static void smp1(const char *label, int32_t a, int32_t b, float c, int d) {
    smp(label, &a, 1, &b, 1, &c, 1, d);
}

static void smp_rep(const char *label, int32_t group, int32_t sub, float val, int n, int d) {
    int32_t a[16], b[16];
    float c[16];
    for (int i = 0; i < n; i++) { a[i] = group; b[i] = sub; c[i] = val; }
    smp(label, a, n, b, n, c, n, d);
}

#define ENC0(name)                                                            \
    do { uint8_t buf_[CTP_CAP]; enc(#name, "-", buf_, ctp_##name(buf_)); } while (0)

static void run_enc(void) {
    uint8_t buf[CTP_CAP];
    char spec[64];

    ENC0(cancelFileTransfer);
    ENC0(commitSettings);
    ENC0(getActiveProfileMega);
    ENC0(getActiveProfileRec);
    ENC0(getBatteryLevel);
    ENC0(getBatteryLevelSupport);
    ENC0(getBatteryStatus);
    ENC0(getBatteryStatusSupport);
    ENC0(getBtAutoConnect);
    ENC0(getDeviceFwString);
    ENC0(getGeneralInfo);
    ENC0(getHwBtn);
    ENC0(getHwBtnStatusSupport);
    ENC0(getHwBtnSupport);
    ENC0(getMaxPayloadSize);
    ENC0(getProfileInfoRec);
    ENC0(getVoicePromptCtrl);
    ENC0(hwBtnEnabled);
    ENC0(releaseControl);
    ENC0(resetFactoryDefault);
    outf("INT getFileTransferMaxDataSize - = %d\n", ctp_getFileTransferMaxDataSize());

    static const int byte_dom[] = {-1, 0, 1, 0x40, 0xfe, 0xff, 0x100, 0x101};
    static const struct { const char *name; int (*fn)(uint8_t *, int); } one[] = {
        {"getAudioLvl", ctp_getAudioLvl},
        {"getFwInfo", ctp_getFwInfo},
        {"setActiveProfileMega", ctp_setActiveProfileMega},
        {"setActiveProfileMegaVoicePreview", ctp_setActiveProfileMegaVoicePreview},
        {"setActiveProfileRec", ctp_setActiveProfileRec},
        {"setActiveProfileRecVoicePreview", ctp_setActiveProfileRecVoicePreview},
    };
    for (size_t f = 0; f < sizeof one / sizeof one[0]; f++)
        for (size_t i = 0; i < sizeof byte_dom / sizeof byte_dom[0]; i++) {
            snprintf(spec, sizeof spec, "%d", byte_dom[i]);
            enc(one[f].name, spec, buf, one[f].fn(buf, byte_dom[i]));
        }

    static const int bt_dom[] = {-1, 0, 1, 2};
    for (size_t i = 0; i < 4; i++) {
        snprintf(spec, sizeof spec, "%d", bt_dom[i]);
        enc("setBtAutoConnect", spec, buf, ctp_setBtAutoConnect(buf, bt_dom[i]));
    }
    static const int vp_dom[] = {-1, 0, 1, 2, 3};
    for (size_t i = 0; i < 5; i++) {
        snprintf(spec, sizeof spec, "%d", vp_dom[i]);
        enc("setVoicePromptCtrl", spec, buf, ctp_setVoicePromptCtrl(buf, vp_dom[i]));
    }

    static const uint32_t times[] = {0, 1, 0x100, 0x12345678, 0x7fffffff, 0x80000000u, 0xffffffffu};
    for (size_t i = 0; i < 7; i++) {
        snprintf(spec, sizeof spec, "%08" PRIx32, times[i]);
        enc("setTime", spec, buf, ctp_setTime(buf, (int32_t)times[i]));
    }

    static const int hw_id[] = {0, 1, 2, 19, 20, 21};
    for (size_t i = 0; i < 6; i++) {
        snprintf(spec, sizeof spec, "%d,1", hw_id[i]);
        enc("setHwBtn", spec, buf, ctp_setHwBtn(buf, hw_id[i], 1));
    }
    static const int hw_val[] = {-1, 0, 1, 2};
    for (size_t i = 0; i < 4; i++) {
        snprintf(spec, sizeof spec, "1,%d", hw_val[i]);
        enc("setHwBtn", spec, buf, ctp_setHwBtn(buf, 1, hw_val[i]));
    }
    enc("setHwBtn", "10,0", buf, ctp_setHwBtn(buf, 10, 0));

    static const int fs_a[] = {0, 1, 2};
    for (size_t i = 0; i < 3; i++) {
        snprintf(spec, sizeof spec, "%d,2", fs_a[i]);
        enc("setFileSize", spec, buf, ctp_setFileSize(buf, fs_a[i], 2));
    }
    static const uint32_t fs_b[] = {0, 1, 0x100, 0x12345678, 0xffffffffu};
    for (size_t i = 0; i < 5; i++) {
        snprintf(spec, sizeof spec, "1,%" PRId32, (int32_t)fs_b[i]);
        enc("setFileSize", spec, buf, ctp_setFileSize(buf, 1, (int)(int32_t)fs_b[i]));
    }

    uint8_t blk[0x100];
    for (int i = 0; i < 0x100; i++) blk[i] = (uint8_t)i;
    static const int blk_len[] = {0, 1, 2, 0x40, 0xfc, 0xfd, 0xfe};
    for (size_t i = 0; i < 7; i++) {
        snprintf(spec, sizeof spec, "%d,false", blk_len[i]);
        enc("getFileDataBlk", spec, buf, ctp_getFileDataBlk(buf, blk, 0x100, blk_len[i], 0));
    }
    enc("getFileDataBlk", "0x40,true", buf, ctp_getFileDataBlk(buf, blk, 0x100, 0x40, 1));
    enc("getFileDataBlk", "0x01,true", buf, ctp_getFileDataBlk(buf, blk, 0x100, 1, 1));

    smp_rep("grp_n0", 0x97, 2, 0.0f, 0, 0);
    smp_rep("grp_n1_d0", 0x97, 2, 0.0f, 1, 0);
    smp_rep("grp_n2_d0", 0x97, 2, 0.0f, 2, 0);
    smp_rep("grp_n3_d0", 0x97, 2, 0.0f, 3, 0);
    smp_rep("grp_n5_d0", 0x97, 2, 0.0f, 5, 0);
    smp_rep("grp_n5_d16", 0x97, 2, 0.0f, 5, 16);
    smp_rep("grp_n7_d43", 0x97, 2, 0.0f, 7, 43);
    smp_rep("grp_n8_d43", 0x97, 2, 0.0f, 8, 43);
    smp_rep("grp_n1_d259", 0x97, 2, 0.0f, 1, 259);

    smp1("gid_0x48", 0x48, 1, 0.0f, 0);
    smp1("gid_0x49", 0x49, 1, 10.0f, 0);
    smp1("gid_0x49_sub0", 0x49, 0, 10.0f, 0);
    smp1("gid_0x4a", 0x4a, 1, 0.0f, 0);
    smp1("gid_0x8f", 0x8f, 0, 1.0f, 0);
    smp1("gid_0x8f_sub1", 0x8f, 1, 1.0f, 0);
    smp1("gid_0x95", 0x95, 1, 5.0f, 0);
    smp1("gid_0x96", 0x96, 0x1e, 7.0f, 0);
    smp1("gid_0x97", 0x97, 2, 0.0f, 0);
    smp1("gid_0x98", 0x98, 0, 0.0f, 0);
    smp1("gid_0x195", 0x195, 1, 0.0f, 0);

    static const int sub97[] = {0, 1, 2, 8, 9};
    for (size_t i = 0; i < 5; i++) {
        snprintf(spec, sizeof spec, "sub97_%d", sub97[i]);
        smp1(spec, 0x97, sub97[i], 0.0f, 0);
    }
    static const float rng[] = {-0.01f, 0.0f, 0.01f, 5.0f, 11.65f, 11.66f, 11.67f};
    for (int i = 0; i < 7; i++) {
        snprintf(spec, sizeof spec, "f95s1_%d", i);
        smp1(spec, 0x95, 1, rng[i], 0);
    }
    static const float bl[] = {-1.0f, 0.0f, 0.5f, 1.0f, 2.0f};
    for (int i = 0; i < 5; i++) {
        snprintf(spec, sizeof spec, "f95s0_%d", i);
        smp1(spec, 0x95, 0, bl[i], 0);
    }
    {
        int32_t a[] = {0x97, 0x48}, b[] = {2, 0};
        float c[] = {0.0f, 0.0f};
        smp("mix_reject", a, 2, b, 2, c, 2, 0);
    }
    {
        int32_t a[] = {0x97, 0x97}, b[] = {2};
        float c[] = {0.0f};
        smp("len_mismatch", a, 2, b, 1, c, 1, 0);
    }

    for (int i = 0; i < 3; i++) {
        snprintf(spec, sizeof spec, "#%d", i);
        enc("STATE_repeat_getGeneralInfo", spec, buf, ctp_getGeneralInfo(buf));
    }
    for (int i = 0; i < 3; i++) {
        snprintf(spec, sizeof spec, "#%d", i);
        enc("STATE_repeat_setTime", spec, buf, ctp_setTime(buf, 0x12345678));
    }
    for (int i = 0; i < 3; i++) {
        snprintf(spec, sizeof spec, "STATE_repeat_smp#%d", i);
        smp_rep(spec, 0x97, 2, 0.0f, 3, 0);
    }
    enc("STATE_inter_probe", "a", buf, ctp_getGeneralInfo(buf));
    ctp_setTime(buf, 5);
    enc("STATE_inter_probe", "b", buf, ctp_getGeneralInfo(buf));
    smp_rep("STATE_inter_smp", 0x97, 2, 0.0f, 3, 0);
    enc("STATE_inter_probe", "c", buf, ctp_getGeneralInfo(buf));
}

/* ---- decode modes ------------------------------------------------------------ */

/* Java String.trim(): strip leading/trailing chars <= ' ' (also drops CR/LF). */
static char *trim(char *s) {
    while (*s && (unsigned char)*s <= ' ') s++;
    size_t n = strlen(s);
    while (n && (unsigned char)s[n - 1] <= ' ') s[--n] = '\0';
    return s;
}

static int unhex(const char *s, size_t n, uint8_t *out, size_t cap) {
    size_t bytes = n / 2;
    if (bytes > cap) return -1;
    for (size_t i = 0; i < bytes; i++) {
        unsigned v;
        if (sscanf(s + 2 * i, "%2x", &v) != 1) return -1;
        out[i] = (uint8_t)v;
    }
    return (int)bytes;
}

/* decode() as marshalled by the JNI adapter: the frame is copied into a zeroed
 * CTP_DECODE_MINBUF buffer, len is clamped to [0, CTP_DECODE_MINBUF], at most
 * min(len, array length) bytes are copied, and the Java boolean is
 * (status != CTP_DECODE_UNRECOGNIZED). Callback lines are held, because the
 * harness prints the result line before the callbacks it produced. Returns the
 * boolean; *ncb receives the number of callbacks. */
static int jni_decode(const uint8_t *arr, int arrlen, int len, const char *indent, int *ncb) {
    uint8_t buf[CTP_DECODE_MINBUF];
    memset(buf, 0, sizeof buf);
    int declen = len < 0 ? 0 : len;
    if (declen > (int)sizeof buf) declen = (int)sizeof buf;
    int copylen = declen < arrlen ? declen : arrlen;
    if (copylen > 0) memcpy(buf, arr, (size_t)copylen);
    g_count = 0;
    hold_begin();
    int ret = ctp_decode(buf, declen, emit, (void *)indent) != CTP_DECODE_UNRECOGNIZED;
    hold_end();
    *ncb = g_count;
    return ret;
}

static int run_corpus(const char *mode, const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) { perror(path); return 2; }
    char raw[4096];
    uint8_t frame[2048];
    int seq = strcmp(mode, "seq") == 0;
    int grp = 0, call = 0, open = 0, ncb = 0;

    while (fgets(raw, sizeof raw, f)) {
        char *line = trim(raw);
        if (!seq) {
            /* dec: one decode() per line; "<hex>|<N>" passes N as the length. */
            if (!*line || *line == '#') continue;
            char *bar = strchr(line, '|');
            size_t hexlen = bar ? (size_t)(bar - line) : strlen(line);
            int n = unhex(line, hexlen, frame, sizeof frame);
            if (n < 0) { fprintf(stderr, "bad hex: %s\n", line); fclose(f); return 2; }
            int len = bar ? atoi(trim(bar + 1)) : n;
            int ret = jni_decode(frame, n, len, "  ", &ncb);
            printf("DEC %s (arr=%d,len=%d) -> ret=%d\n", line, n, len, ret);
            hold_flush();
        } else {
            /* seq: blank lines delimit groups; comment lines are echoed. */
            if (*line == '#') { printf("%s\n", line); continue; }
            if (!*line) {
                if (open) { printf("--- end group %d\n", grp); open = 0; }
                continue;
            }
            if (!open) { grp++; call = 0; open = 1; printf("=== group %d\n", grp); }
            call++;
            int n = unhex(line, strlen(line), frame, sizeof frame);
            if (n < 0) { fprintf(stderr, "bad hex: %s\n", line); fclose(f); return 2; }
            int ret = jni_decode(frame, n, n, "    ", &ncb);
            printf("CALL %d.%d %s (len=%d) -> ret=%d\n", grp, call, line, n, ret);
            hold_flush();
            if (ncb == 0) printf("    (no callback)\n");
        }
    }
    if (seq && open) printf("--- end group %d\n", grp);
    fclose(f);
    return 0;
}

int main(int argc, char **argv) {
    const char *mode = argc > 1 ? argv[1] : "enc";
    int rc = 0;
    if (strcmp(mode, "enc") == 0) {
        run_enc();
    } else if ((strcmp(mode, "dec") == 0 || strcmp(mode, "seq") == 0) && argc > 2) {
        rc = run_corpus(mode, argv[2]);
    } else {
        fprintf(stderr, "usage: ctp_regress enc | dec <corpus> | seq <corpus>\n");
        return 2;
    }
    if (rc == 0) outf("DONE\n");
    return rc;
}
