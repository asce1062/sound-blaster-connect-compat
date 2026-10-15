/*
 * ctprotocol-core: portable SPP command encoder (implementation).
 *
 * Reproduces the stock Encode:: builders from the x86 decompilation, confirmed
 * byte-for-byte against oracle/vectors/enc_stock.txt. No JNI, no platform
 * headers: the same translation unit compiles for x86 (oracle differential)
 * and arm64-v8a (device). Scalars are written little-endian by hand so the
 * output does not depend on host endianness.
 */
#include "ctprotocol_encode.h"
#include <string.h>

/* Exact float constant from its IEEE-754 bit pattern (stock .rodata), so every
 * comparison matches the library regardless of compiler literal rounding. */
static float fb(uint32_t bits) {
    float f;
    memcpy(&f, &bits, sizeof f);
    return f;
}

/* ---- constant-frame getters ---- */

#define CONST_FRAME(fn, ...)                                                   \
    int fn(uint8_t *out) {                                                     \
        static const uint8_t b[] = {__VA_ARGS__};                             \
        memcpy(out, b, sizeof b);                                              \
        return (int)sizeof b;                                                  \
    }

CONST_FRAME(ctp_getMaxPayloadSize, 0x5a, 0x03, 0x00)
CONST_FRAME(ctp_getGeneralInfo, 0x5a, 0x07, 0x01, 0x00)
CONST_FRAME(ctp_getDeviceFwString, 0x5a, 0x07, 0x01, 0x02)
CONST_FRAME(ctp_releaseControl, 0x5a, 0x06, 0x01, 0x00)
CONST_FRAME(ctp_commitSettings, 0x5a, 0x08, 0x00)
CONST_FRAME(ctp_getHwBtn, 0x5a, 0x26, 0x01, 0x01)
CONST_FRAME(ctp_getHwBtnSupport, 0x5a, 0x26, 0x01, 0x02)
CONST_FRAME(ctp_getHwBtnStatusSupport, 0x5a, 0x26, 0x01, 0x03)
CONST_FRAME(ctp_hwBtnEnabled, 0x5a, 0x26, 0x01, 0x04)
CONST_FRAME(ctp_getBatteryLevel, 0x5a, 0x27, 0x01, 0x01)
CONST_FRAME(ctp_getBatteryLevelSupport, 0x5a, 0x27, 0x01, 0x02)
CONST_FRAME(ctp_getBatteryStatus, 0x5a, 0x28, 0x01, 0x01)
CONST_FRAME(ctp_getBatteryStatusSupport, 0x5a, 0x28, 0x01, 0x02)
CONST_FRAME(ctp_getBtAutoConnect, 0x5a, 0x31, 0x01, 0x01)
CONST_FRAME(ctp_getVoicePromptCtrl, 0x5a, 0x99, 0x01, 0x01)
CONST_FRAME(ctp_resetFactoryDefault, 0x5a, 0x9b, 0x01, 0x01)
CONST_FRAME(ctp_cancelFileTransfer, 0x5a, 0x98, 0x02, 0x82, 0x00)
CONST_FRAME(ctp_getProfileInfoRec, 0x5a, 0x19, 0x01, 0x01)
CONST_FRAME(ctp_getActiveProfileRec, 0x5a, 0x1a, 0x03, 0x01, 0x01, 0x00)
CONST_FRAME(ctp_getActiveProfileMega, 0x5a, 0x1a, 0x03, 0x01, 0x02, 0x00)

/* ---- one-argument builders ---- */

/* 0..255 domain: rejected when the value does not fit a byte. */
static int is_byte(int v) { return (unsigned)v <= 0xff; }

int ctp_getFwInfo(uint8_t *out, int n) {
    if (!is_byte(n)) return CTP_REJECT; /* 0x1e */
    out[0] = 0x5a; out[1] = 0x07; out[2] = 0x02; out[3] = 0x01;
    out[4] = (uint8_t)n;
    return 5;
}

int ctp_getAudioLvl(uint8_t *out, int n) {
    if (!is_byte(n)) return CTP_REJECT; /* 0x1e */
    out[0] = 0x5a; out[1] = 0x23; out[2] = 0x04; out[3] = 0x01;
    out[4] = (uint8_t)n; out[5] = 0x00; out[6] = 0x00;
    return 7;
}

int ctp_setBtAutoConnect(uint8_t *out, int v) {
    if ((unsigned)v > 1) return CTP_REJECT; /* 0x69 */
    out[0] = 0x5a; out[1] = 0x31; out[2] = 0x02; out[3] = 0x00;
    out[4] = (uint8_t)v;
    return 5;
}

int ctp_setVoicePromptCtrl(uint8_t *out, int v) {
    if ((unsigned)v > 2) return CTP_REJECT; /* 0xa3 */
    out[0] = 0x5a; out[1] = 0x99; out[2] = 0x02; out[3] = 0x00;
    out[4] = (uint8_t)v;
    return 5;
}

int ctp_setTime(uint8_t *out, int32_t t) {
    uint32_t u = (uint32_t)t;
    out[0] = 0x5a; out[1] = 0x3b; out[2] = 0x04;
    out[3] = (uint8_t)(u & 0xff);
    out[4] = (uint8_t)((u >> 8) & 0xff);
    out[5] = (uint8_t)((u >> 16) & 0xff);
    out[6] = (uint8_t)((u >> 24) & 0xff);
    return 7;
}

/* ---- profile setters: 5a 1a 03 <mode> <sel> <value> ---- */

static int profile_set(uint8_t *out, int mode, int sel, int n) {
    if (!is_byte(n)) return CTP_REJECT; /* 0x1e */
    out[0] = 0x5a; out[1] = 0x1a; out[2] = 0x03;
    out[3] = (uint8_t)mode; out[4] = (uint8_t)sel; out[5] = (uint8_t)n;
    return 6;
}

int ctp_setActiveProfileRec(uint8_t *out, int n) { return profile_set(out, 0x00, 1, n); }
int ctp_setActiveProfileMega(uint8_t *out, int n) { return profile_set(out, 0x00, 2, n); }
int ctp_setActiveProfileRecVoicePreview(uint8_t *out, int n) { return profile_set(out, 0x02, 1, n); }
int ctp_setActiveProfileMegaVoicePreview(uint8_t *out, int n) { return profile_set(out, 0x02, 2, n); }

/* ---- two-argument builders ---- */

int ctp_setHwBtn(uint8_t *out, int id, int val) {
    if ((unsigned)(id - 1) >= 20) return CTP_REJECT; /* 0x5b: id in 1..20 */
    if ((unsigned)val >= 2) return CTP_REJECT;       /* 0x5c: val in {0,1} */
    out[0] = 0x5a; out[1] = 0x26; out[2] = 0x03; out[3] = 0x00;
    out[4] = (uint8_t)id; out[5] = (uint8_t)val;
    return 6;
}

int ctp_setFileSize(uint8_t *out, int a, int b) {
    if (a != 1) return CTP_REJECT; /* 0x9a: command type must be 1 (sendFile) */
    uint32_t u = (uint32_t)b;
    out[0] = 0x5a; out[1] = 0x98; out[2] = 0x05; out[3] = 0x01;
    out[4] = (uint8_t)(u & 0xff);
    out[5] = (uint8_t)((u >> 8) & 0xff);
    out[6] = (uint8_t)((u >> 16) & 0xff);
    out[7] = (uint8_t)((u >> 24) & 0xff);
    return 8;
}

/* ---- variable-length builder ---- */

int ctp_getFileDataBlk(uint8_t *out, const uint8_t *data, int datalen,
                       int len, int flag) {
    int off = flag ? 0x81 : 0x80;
    if (data == NULL) return CTP_REJECT;              /* 0x9b */
    if (len < 1 || len > 253) return CTP_REJECT;      /* 0x9c */
    if (off != 0x80 && off != 0x81 && off != 0x82) return CTP_REJECT; /* 0x9d */
    if (len > datalen) return CTP_REJECT;             /* source underrun guard */
    out[0] = 0x5a; out[1] = 0x98;
    out[2] = (uint8_t)(len + 2);
    out[3] = (uint8_t)off;
    out[4] = (uint8_t)len;
    memcpy(out + 5, data, (size_t)len);
    return len + 5;
}

/* ---- complex builder: setMalcolmParam ---- */

/* FUN_000159e0: per-param domain check. 0 = accept; non-zero rejects the call.
 * group ids 0x49/0x8f/0x95/0x96/0x97; everything else -> 0x18. Within a group,
 * a sub-index outside the defined cases -> 0x19; an out-of-range float -> 0x2f.
 */
static int is01(float f) { return (f == 1.0f || f == 0.0f) ? 0 : 0x2f; }
static int rng(float f, float lo, float hi) { return (f < lo || f > hi) ? 0x2f : 0; }

int ctp_malcolm_validate(int group, int sub, float f) {
    if (group == 0x95) {
        switch (sub) {
        case 0x00: return is01(f);
        case 0x01: return rng(f, 0.0f, fb(0x413a8f5c));  /* [0, 11.66] */
        case 0x02: return rng(f, 0.0f, 256.0f);
        case 0x03: return is01(f);
        case 0x04: return is01(f);
        case 0x05: return rng(f, 0.0f, 1.0f);
        case 0x06: return is01(f);
        case 0x07: return rng(f, fb(0x3c23d70a), 0.25f); /* [0.01, 0.25] */
        case 0x08: return rng(f, 20.0f, 180.0f);
        case 0x09: return rng(f, 20.0f, 60.0f);
        case 0x0a: return is01(f);
        case 0x0b: return rng(f, 200.0f, 800.0f);
        case 0x0c: return rng(f, 800.0f, 1800.0f);
        case 0x0d: return rng(f, 1600.0f, 2750.0f);
        case 0x0e: if (f < 0.25f) return 0x2f; return (f > 4.0f) ? 0x2f : 0;
        case 0x0f: if (f < 0.5f) return 0x2f; return (f > 2.0f) ? 0x2f : 0;
        case 0x10: return rng(f, -1.0f, 5.0f);
        case 0x11: if (f < 0.0f) return 0x2f; return (f > 2.0f) ? 0x2f : 0;
        case 0x12: if (f < 0.0f) return 0x2f; return (f > 4.0f) ? 0x2f : 0;
        case 0x13: return is01(f);
        case 0x14: case 0x15: case 0x16: case 0x17:
        case 0x18: case 0x19: case 0x1a: case 0x1b:
            return rng(f, -24.0f, 24.0f);
        case 0x1c: case 0x1d: case 0x1e: case 0x1f:
        case 0x20: case 0x21: case 0x22: case 0x23:
            return rng(f, 20.0f, 8000.0f);
        case 0x24: case 0x25: case 0x26: case 0x27:
        case 0x28: case 0x29: case 0x2a: case 0x2b:
            return rng(f, 1.0f, 4000.0f);
        case 0x2c: return is01(f);
        case 0x2d: return rng(f, 0.0f, 1.0f);
        case 0x2e: return is01(f);
        case 0x2f: case 0x30: case 0x31: case 0x32:
        case 0x33: case 0x34: case 0x35:
            return 0;
        case 0x36: return is01(f);
        default: return 0x19;
        }
    }
    if (group < 0x96) {
        if (group == 0x49) {
            if (sub != 1) return 0x19;
            return rng(f, 1.0f, 20.0f);
        }
        if (group != 0x8f) return 0x18;
        if (sub != 0) return 0x19;
        return is01(f);
    }
    if (group != 0x96) {
        if (group != 0x97) return 0x18;
        switch (sub) {
        case 0x00: return is01(f);
        case 0x01: return is01(f);
        case 0x02: case 0x03: case 0x05:
        case 0x06: case 0x07: case 0x08:
            return 0;
        case 0x04: return is01(f);
        default: return 0x19;
        }
    }
    /* group == 0x96 */
    switch (sub) {
    case 0x00: return is01(f);
    case 0x01: if (f < 0.0f) return 0x2f; return (f > fb(0x3fd55326)) ? 0x2f : 0; /* [0, 1.6666] */
    case 0x02: return is01(f);
    case 0x03: case 0x05: case 0x08:
        if (f < 0.0f) return 0x2f; return (f > 1.0f) ? 0x2f : 0;
    case 0x04: return is01(f);
    case 0x06: return (f == 1.0f || f == 0.0f || f == 2.0f) ? 0 : 0x2f;
    case 0x07: return is01(f);
    case 0x09: return is01(f);
    case 0x0a: return rng(f, -12.0f, 12.0f);
    case 0x0b: case 0x0c: case 0x0d: case 0x0e:
    case 0x0f: case 0x10: case 0x11: case 0x12:
    case 0x13: case 0x14:
        return rng(f, -24.0f, 24.0f);
    case 0x15: return is01(f);
    case 0x16: case 0x17: return rng(f, 10.0f, 1000.0f);
    case 0x18: return is01(f);
    case 0x19: if (f < 0.0f) return 0x2f; return (f > 1.0f) ? 0x2f : 0;
    case 0x1a: case 0x1b: case 0x1c: case 0x1d:
        return is01(f);
    case 0x1e: return 0;
    case 0x1f: case 0x20: return is01(f);
    case 0x21: case 0x22: case 0x23: case 0x24:
    case 0x25: case 0x26: case 0x27: case 0x28:
        return rng(f, -20.0f, 20.0f);
    case 0x29: case 0x2a: case 0x2b: case 0x2c:
    case 0x2d: case 0x2e: case 0x2f: case 0x30:
        return is01(f);
    case 0x31: case 0x32: case 0x33: case 0x34:
    case 0x35: case 0x36: case 0x37: case 0x38:
        if (f < 0.0f) return 0x2f; return (f > fb(0x3c75c28f)) ? 0x2f : 0; /* [0, 0.015] */
    case 0x39: case 0x3a: case 0x3b: case 0x3c: case 0x3d:
        return 0;
    case 0x3e: return is01(f);
    case 0x70: return (f == 1.0f || f == 0.0f || f == 2.0f) ? 0 : 0x2f;
    case 0x71: case 0x72:
        return (f == 1.0f || f == 0.0f || f == 3.0f || f == 2.0f) ? 0 : 0x2f;
    default: return 0x19;
    }
}

/* Group size (params/group) and full-group byte size for the seed d. */
static void malcolm_group(int d, int *gs, int *gb) {
    if (d < 16) { *gs = 2; *gb = 16; return; }
    int g = (d - 1) / 6;
    if (g < 43) { *gs = g; *gb = g * 6 + 4; }
    else { *gs = 42; *gb = 256; }
}

int ctp_malcolm_size(int n, int d) {
    if (n < 0) return CTP_REJECT;
    int gs, gb;
    malcolm_group(d, &gs, &gb);
    int full = n / gs;
    int rem = n % gs;
    return full * gb + (rem ? rem * 6 + 4 : 0);
}

/* One group sub-frame: 5a 12 <cnt*6+1> <cnt> then cnt * (a&ff, b&ff, float LE). */
static int malcolm_group_frame(uint8_t *out, int cnt, const int32_t *a,
                               const int32_t *b, const float *c) {
    out[0] = 0x5a; out[1] = 0x12;
    out[2] = (uint8_t)(cnt * 6 + 1);
    out[3] = (uint8_t)cnt;
    for (int i = 0; i < cnt; i++) {
        uint8_t *p = out + 4 + i * 6;
        uint32_t bits;
        memcpy(&bits, &c[i], sizeof bits);
        p[0] = (uint8_t)a[i];
        p[1] = (uint8_t)b[i];
        p[2] = (uint8_t)(bits & 0xff);
        p[3] = (uint8_t)((bits >> 8) & 0xff);
        p[4] = (uint8_t)((bits >> 16) & 0xff);
        p[5] = (uint8_t)((bits >> 24) & 0xff);
    }
    return 4 + cnt * 6;
}

int ctp_setMalcolmParam(uint8_t *out, const int32_t *a, const int32_t *b,
                        const float *c, int n, int d, int *e0, int *e1) {
    if (n < 0) return CTP_REJECT; /* 0x1b */
    int gs, gb;
    malcolm_group(d, &gs, &gb);
    int full = n / gs;
    int rem = n % gs;

    /* Any invalid param aborts the whole call (stock returns non-zero, wrapper
     * emits an empty byte[]); validate before emitting. */
    for (int i = 0; i < n; i++)
        if (ctp_malcolm_validate(a[i], b[i], c[i]) != 0) return CTP_REJECT;

    int pos = 0, idx = 0;
    for (int g = 0; g < full; g++) {
        pos += malcolm_group_frame(out + pos, gs, a + idx, b + idx, c + idx);
        idx += gs;
    }
    if (rem) {
        pos += malcolm_group_frame(out + pos, rem, a + idx, b + idx, c + idx);
        idx += rem;
    }
    if (e0) *e0 = rem ? (rem * 6 + 4) : gb;
    if (e1) *e1 = full + (rem ? 1 : 0);
    return pos;
}

/* ---- scalar getter ---- */

int ctp_getFileTransferMaxDataSize(void) { return 253; }
