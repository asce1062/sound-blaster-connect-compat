/*
 * ctprotocol-core: portable SPP command encoder.
 *
 * ONE implementation, no JNI and no platform headers, validated against the
 * frozen x86 oracle (oracle/vectors/enc_stock.txt) and compiled unchanged for
 * arm64-v8a. Every function reproduces a stock Encode:: builder: it writes an
 * outbound command frame into `out` (capacity CTP_CAP) and returns the frame
 * length, or a negative value when the stock builder rejects the input (the
 * JNI layer then hands Java an empty byte[], matching stock exactly).
 *
 * Frame grammar: 5A <op> <sub/len> [selector] [payload...], little-endian
 * scalars, no trailing checksum. See docs/arm64/encode/ENCODE_SPEC.md.
 */
#ifndef CTPROTOCOL_ENCODE_H
#define CTPROTOCOL_ENCODE_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Stock buffer capacity: Context->cap = 0x102. Callers pass a buffer >= this. */
#define CTP_CAP 258

/* Negative return = rejected (empty frame). The exact magnitude mirrors the
 * stock builder's error code for diagnostics; the JNI layer only tests < 0. */
#define CTP_REJECT (-1)

/* ---- fixed getters (constant frame, no args) ---- */
int ctp_getMaxPayloadSize(uint8_t *out);
int ctp_getGeneralInfo(uint8_t *out);
int ctp_getDeviceFwString(uint8_t *out);
int ctp_releaseControl(uint8_t *out);
int ctp_commitSettings(uint8_t *out);
int ctp_getHwBtn(uint8_t *out);
int ctp_getHwBtnSupport(uint8_t *out);
int ctp_getHwBtnStatusSupport(uint8_t *out);
int ctp_hwBtnEnabled(uint8_t *out);
int ctp_getBatteryLevel(uint8_t *out);
int ctp_getBatteryLevelSupport(uint8_t *out);
int ctp_getBatteryStatus(uint8_t *out);
int ctp_getBatteryStatusSupport(uint8_t *out);
int ctp_getBtAutoConnect(uint8_t *out);
int ctp_getVoicePromptCtrl(uint8_t *out);
int ctp_resetFactoryDefault(uint8_t *out);
int ctp_cancelFileTransfer(uint8_t *out);
int ctp_getProfileInfoRec(uint8_t *out);
int ctp_getActiveProfileRec(uint8_t *out);
int ctp_getActiveProfileMega(uint8_t *out);

/* ---- one-argument builders ---- */
int ctp_getFwInfo(uint8_t *out, int n);     /* 0..255 */
int ctp_getAudioLvl(uint8_t *out, int n);   /* 0..255 */
int ctp_setBtAutoConnect(uint8_t *out, int v);   /* {0,1} */
int ctp_setVoicePromptCtrl(uint8_t *out, int v); /* {0,1,2} */
int ctp_setTime(uint8_t *out, int32_t t);        /* no validation */

/* ---- profile setters (constant selector + value byte) ---- */
int ctp_setActiveProfileRec(uint8_t *out, int n);
int ctp_setActiveProfileMega(uint8_t *out, int n);
int ctp_setActiveProfileRecVoicePreview(uint8_t *out, int n);
int ctp_setActiveProfileMegaVoicePreview(uint8_t *out, int n);

/* ---- two-argument builders ---- */
int ctp_setHwBtn(uint8_t *out, int id, int val); /* id 1..20, val {0,1} */
int ctp_setFileSize(uint8_t *out, int a, int b); /* a==1 required */

/* ---- variable-length builder ---- */
/* data[0..len) copied into the frame; off = flag ? 0x81 : 0x80. len 1..253. */
int ctp_getFileDataBlk(uint8_t *out, const uint8_t *data, int datalen,
                       int len, int flag);

/* ---- complex builder ---- */
/* a/b/c are length-n arrays (group id, sub-index, float value); d is the
 * group-size seed. On success e0/e1 (if non-NULL) receive [lastGroupBytes,
 * groupCount], matching the stock out-array. Returns frame length (0 for
 * n==0, which stock treats as a valid empty frame) or CTP_REJECT. */
int ctp_setMalcolmParam(uint8_t *out, const int32_t *a, const int32_t *b,
                        const float *c, int n, int d, int *e0, int *e1);

/* Emitted frame length for (n, d), or CTP_REJECT when n < 0. The stock wrapper
 * grows its buffer to fit rather than capping, so the adapter sizes `out` from
 * this before calling ctp_setMalcolmParam. */
int ctp_malcolm_size(int n, int d);

/* Per-param validator (stock FUN_000159e0): 0 = accept, non-zero = reject. */
int ctp_malcolm_validate(int group, int sub, float f);

/* ---- scalar getter (not a frame) ---- */
int ctp_getFileTransferMaxDataSize(void); /* returns 253 */

#ifdef __cplusplus
}
#endif

#endif /* CTPROTOCOL_ENCODE_H */
