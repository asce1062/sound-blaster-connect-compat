/**
 * @file ctprotocol_encode.h
 * @brief ctprotocol-core: portable SPP command encoder (public interface).
 *
 * One implementation, no JNI and no platform headers. It matches the stock
 * library for the vectors in oracle/vectors/enc_stock.txt and compiles
 * unchanged for every ABI the project builds. Every function reproduces a stock
 * Encode:: builder: it writes an outbound command frame into the caller's
 * buffer `out` and returns the frame length, or CTP_REJECT when the stock
 * builder rejects the input (the JNI layer then hands Java an empty byte[],
 * matching stock).
 *
 * Frame grammar: 5A <op> <sub/len> [selector] [payload...], little-endian
 * scalars, no trailing checksum. See docs/technical/CTPROTOCOL.md and
 * docs/research/encoder/ENCODE_SPEC.md.
 *
 * Buffer contract: unless a function says otherwise, `out` must point to at
 * least CTP_CAP writable bytes. ctp_setMalcolmParam is the exception and needs
 * ctp_malcolm_size(n, d) bytes. No builder reads or writes outside the frame it
 * returns, and no builder keeps state between calls.
 */
#ifndef CTPROTOCOL_ENCODE_H
#define CTPROTOCOL_ENCODE_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Output buffer capacity, in bytes, for every builder except
 *        ctp_setMalcolmParam.
 *
 * The value (258, 0x102) is the capacity of the stock encoder's output buffer.
 * The largest frame these builders emit is 258 bytes (ctp_getFileDataBlk with
 * len 253). Callers pass a buffer of at least this size.
 */
#define CTP_CAP 258

/**
 * @brief Return value of every builder that rejects its input.
 *
 * Every builder returns exactly -1 on rejection, never another negative value.
 * Callers may test for any negative value; the JNI layer tests `< 0`. The
 * stock library's internal error codes are not reproduced in return values.
 * They appear only as "stock error code" comments in ctprotocol_encode.c.
 * ctp_malcolm_validate does not use this constant; it has its own return codes.
 */
#define CTP_REJECT (-1)

/**
 * @name Fixed-frame getters
 *
 * Twenty builders that take no argument and always emit the same constant
 * frame. Each one:
 *  - @param out  Output buffer of at least CTP_CAP bytes (at most 6 are written).
 *  - @return     The frame length in bytes; never CTP_REJECT.
 *
 * The frame emitted by each function is given after its declaration.
 * @{
 */
int ctp_getMaxPayloadSize(uint8_t *out);        /**< 5A 03 00 (3 bytes) */
int ctp_getGeneralInfo(uint8_t *out);           /**< 5A 07 01 00 (4 bytes) */
int ctp_getDeviceFwString(uint8_t *out);        /**< 5A 07 01 02 (4 bytes) */
int ctp_releaseControl(uint8_t *out);           /**< 5A 06 01 00 (4 bytes) */
int ctp_commitSettings(uint8_t *out);           /**< 5A 08 00 (3 bytes) */
int ctp_getHwBtn(uint8_t *out);                 /**< 5A 26 01 01 (4 bytes) */
int ctp_getHwBtnSupport(uint8_t *out);          /**< 5A 26 01 02 (4 bytes) */
int ctp_getHwBtnStatusSupport(uint8_t *out);    /**< 5A 26 01 03 (4 bytes) */
int ctp_hwBtnEnabled(uint8_t *out);             /**< 5A 26 01 04 (4 bytes) */
int ctp_getBatteryLevel(uint8_t *out);          /**< 5A 27 01 01 (4 bytes) */
int ctp_getBatteryLevelSupport(uint8_t *out);   /**< 5A 27 01 02 (4 bytes) */
int ctp_getBatteryStatus(uint8_t *out);         /**< 5A 28 01 01 (4 bytes) */
int ctp_getBatteryStatusSupport(uint8_t *out);  /**< 5A 28 01 02 (4 bytes) */
int ctp_getBtAutoConnect(uint8_t *out);         /**< 5A 31 01 01 (4 bytes) */
int ctp_getVoicePromptCtrl(uint8_t *out);       /**< 5A 99 01 01 (4 bytes) */
int ctp_resetFactoryDefault(uint8_t *out);      /**< 5A 9B 01 01 (4 bytes) */
int ctp_cancelFileTransfer(uint8_t *out);       /**< 5A 98 02 82 00 (5 bytes) */
int ctp_getProfileInfoRec(uint8_t *out);        /**< 5A 19 01 01 (4 bytes) */
int ctp_getActiveProfileRec(uint8_t *out);      /**< 5A 1A 03 01 01 00 (6 bytes) */
int ctp_getActiveProfileMega(uint8_t *out);     /**< 5A 1A 03 01 02 00 (6 bytes) */
/** @} */

/**
 * @brief Request firmware information for index `n`.
 *
 * Emits `5A 07 02 01 <n>`.
 *
 * @param out  Output buffer of at least CTP_CAP bytes.
 * @param n    Index, accepted when in 0..255.
 * @return     5, or CTP_REJECT when `n` is outside 0..255.
 */
int ctp_getFwInfo(uint8_t *out, int n);

/**
 * @brief Request the audio level for index `n`.
 *
 * Emits `5A 23 04 01 <n> 00 00`.
 *
 * @param out  Output buffer of at least CTP_CAP bytes.
 * @param n    Index, accepted when in 0..255.
 * @return     7, or CTP_REJECT when `n` is outside 0..255.
 */
int ctp_getAudioLvl(uint8_t *out, int n);

/**
 * @brief Set the Bluetooth auto-connect flag.
 *
 * Emits `5A 31 02 00 <v>`.
 *
 * @param out  Output buffer of at least CTP_CAP bytes.
 * @param v    Flag value, accepted when 0 or 1.
 * @return     5, or CTP_REJECT when `v` is not 0 or 1.
 */
int ctp_setBtAutoConnect(uint8_t *out, int v);

/**
 * @brief Set the voice-prompt control mode.
 *
 * Emits `5A 99 02 00 <v>`.
 *
 * @param out  Output buffer of at least CTP_CAP bytes.
 * @param v    Mode, accepted when 0, 1 or 2.
 * @return     5, or CTP_REJECT when `v` is outside 0..2.
 */
int ctp_setVoicePromptCtrl(uint8_t *out, int v);

/**
 * @brief Set the device clock.
 *
 * Emits `5A 3B 04 <t as little-endian 32-bit>`. Every 32-bit value is
 * accepted, including negative values; the unsigned bit pattern is written.
 *
 * @param out  Output buffer of at least CTP_CAP bytes.
 * @param t    Time value, written as 4 little-endian bytes.
 * @return     7. This builder never rejects.
 */
int ctp_setTime(uint8_t *out, int32_t t);

/**
 * @name Profile setters
 *
 * Four builders that select a profile slot. Each emits
 * `5A 1A 03 <mode> <sel> <n>`:
 *  - `<mode>` is 00 for the plain setters and 02 for the voice-preview setters.
 *  - `<sel>` is 01 for the Rec profile and 02 for the Mega profile.
 *
 * Each one:
 *  - @param out  Output buffer of at least CTP_CAP bytes.
 *  - @param n    Profile number, accepted when in 0..255.
 *  - @return     6, or CTP_REJECT when `n` is outside 0..255.
 * @{
 */
int ctp_setActiveProfileRec(uint8_t *out, int n);                /**< mode 00, sel 01 */
int ctp_setActiveProfileMega(uint8_t *out, int n);               /**< mode 00, sel 02 */
int ctp_setActiveProfileRecVoicePreview(uint8_t *out, int n);    /**< mode 02, sel 01 */
int ctp_setActiveProfileMegaVoicePreview(uint8_t *out, int n);   /**< mode 02, sel 02 */
/** @} */

/**
 * @brief Enable or disable one hardware button.
 *
 * Emits `5A 26 03 00 <id> <val>`.
 *
 * @param out  Output buffer of at least CTP_CAP bytes.
 * @param id   Button identifier, accepted when in 1..20.
 * @param val  Button state, accepted when 0 or 1.
 * @return     6, or CTP_REJECT when `id` is outside 1..20 or `val` is not 0 or 1.
 */
int ctp_setHwBtn(uint8_t *out, int id, int val);

/**
 * @brief Announce the size of a file about to be sent.
 *
 * Emits `5A 98 05 01 <b as little-endian 32-bit>`.
 *
 * @param out  Output buffer of at least CTP_CAP bytes.
 * @param a    Command type; only 1 (send file) is accepted.
 * @param b    File size, written as 4 little-endian bytes with no range check.
 * @return     8, or CTP_REJECT when `a` is not 1.
 */
int ctp_setFileSize(uint8_t *out, int a, int b);

/**
 * @brief Build one file-data block frame.
 *
 * Emits `5A 98 <len+2> <off> <len> <data[0..len)>` where `off` is 0x81 when
 * `flag` is non-zero and 0x80 otherwise. Exactly `len` bytes of `data` are
 * copied; bytes of `data` beyond `len` are ignored.
 *
 * @param out      Output buffer of at least CTP_CAP bytes.
 * @param data     Source bytes; must not be NULL.
 * @param datalen  Number of readable bytes at `data`.
 * @param len      Number of bytes to copy, accepted when in 1..253 and not
 *                 greater than `datalen`.
 * @param flag     Non-zero selects `off` 0x81, zero selects 0x80.
 * @return         `len + 5`, or CTP_REJECT when `data` is NULL, `len` is outside
 *                 1..253, or `len` exceeds `datalen`.
 */
int ctp_getFileDataBlk(uint8_t *out, const uint8_t *data, int datalen,
                       int len, int flag);

/**
 * @brief Build the parameter-update frames for a list of Malcolm parameters.
 *
 * Parameters `a[i]` (group id), `b[i]` (sub-index) and `c[i]` (float value)
 * are first validated one by one with ctp_malcolm_validate. If any parameter is
 * invalid the whole call is rejected and nothing is written to `out`. Otherwise
 * the parameters are emitted as consecutive group sub-frames, each
 * `5A 12 <cnt*6+1> <cnt>` followed by `cnt` six-byte records
 * `<a&FF> <b&FF> <c as little-endian IEEE-754 bits>`. Full groups hold the group
 * size derived from `d` (see ctp_malcolm_size); a final shorter group holds the
 * remainder.
 *
 * Group id and sub-index are validated as full ints and then truncated to 8
 * bits when written, so values such as 0x195 are rejected by the validator
 * rather than aliased to 0x95.
 *
 * @param out  Output buffer of at least ctp_malcolm_size(n, d) bytes. Unlike
 *             the other builders, CTP_CAP is not sufficient.
 * @param a    Array of `n` group ids. Not read when `n` is 0.
 * @param b    Array of `n` sub-indexes. Not read when `n` is 0.
 * @param c    Array of `n` float values. Not read when `n` is 0.
 * @param n    Number of parameters; 0 is accepted.
 * @param d    Group-size seed. Values below 16 select groups of 2 parameters;
 *             larger values select (d-1)/6 parameters per group, capped at 42.
 * @param e0   Optional. On success receives the byte length of the last group
 *             frame emitted: the remainder group's length when a remainder
 *             exists, else the length of a full group.
 * @param e1   Optional. On success receives the number of group frames emitted.
 *             Neither e0 nor e1 is written on rejection.
 * @return     The total frame length. 0 for `n == 0`, which is a valid empty
 *             frame; with `n == 0`, `*e0` is the full-group length for `d` and
 *             `*e1` is 0. CTP_REJECT when `n < 0` or any parameter fails
 *             ctp_malcolm_validate.
 */
int ctp_setMalcolmParam(uint8_t *out, const int32_t *a, const int32_t *b,
                        const float *c, int n, int d, int *e0, int *e1);

/**
 * @brief Compute the frame length ctp_setMalcolmParam emits for `(n, d)`.
 *
 * The stock wrapper grows its buffer to fit rather than capping, so the adapter
 * sizes `out` from this value before calling ctp_setMalcolmParam. The result
 * depends only on `n` and `d`, not on parameter values.
 *
 * @param n  Number of parameters.
 * @param d  Group-size seed, as for ctp_setMalcolmParam.
 * @return   The emitted frame length in bytes (0 when `n` is 0), or CTP_REJECT
 *           when `n < 0`.
 */
int ctp_malcolm_size(int n, int d);

/**
 * @brief Validate one Malcolm parameter.
 *
 * Known groups are 0x49, 0x8F, 0x95, 0x96 and 0x97. Within a group the
 * sub-index selects the rule: a boolean (value must equal 0.0 or 1.0), a closed
 * range, a small set of allowed values, or no restriction.
 *
 * Comparison semantics are preserved from the stock library. A NaN value fails
 * every boolean and set-membership rule, but passes every closed-range rule
 * because those reject only values that compare below the lower bound or above
 * the upper bound. Some sub-indexes accept any float value, including NaN and
 * infinities.
 *
 * @param group  Group id, as a full int.
 * @param sub    Sub-index within the group, as a full int.
 * @param f      Parameter value.
 * @return       0 when the parameter is accepted. 0x18 when `group` is not a
 *               known group. 0x19 when `sub` is not defined for a known group.
 *               0x2F when `f` is outside the allowed values for that sub-index.
 */
int ctp_malcolm_validate(int group, int sub, float f);

/**
 * @brief Maximum payload size of one file-data block (not a frame).
 *
 * This is the upper bound on the `len` argument of ctp_getFileDataBlk.
 *
 * @return  253.
 */
int ctp_getFileTransferMaxDataSize(void);

#ifdef __cplusplus
}
#endif

#endif /* CTPROTOCOL_ENCODE_H */
