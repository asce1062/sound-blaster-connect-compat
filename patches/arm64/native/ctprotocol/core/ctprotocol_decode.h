/**
 * @file ctprotocol_decode.h
 * @brief ctprotocol-core: portable SPP inbound decoder (public interface).
 *
 * One implementation, no JNI and no platform headers. It matches the stock
 * library for the vectors in oracle/vectors/dec_*.{txt,out.txt} and compiles
 * unchanged for every ABI the project builds. ctp_decode() parses a single
 * inbound frame and emits zero or more typed events; it reproduces the stock
 * Decode::decode dispatcher. The core knows nothing about JNI, Java, Android,
 * Bluetooth or callbacks: the thin JNI adapter maps each typed event onto a
 * stock SbxSppCommandManager static callback. See docs/technical/CTPROTOCOL.md
 * and docs/research/decoder/.
 *
 * Inbound frame grammar: 5A <op> <plen> <payload[plen]>, total length plen + 3,
 * little-endian scalars. The entry gate is len >= 3 && buf[0] == 0x5A &&
 * buf[2] == len - 3; dispatch is on buf[1], then on sub = buf[3] or the frame
 * length.
 *
 * Field names are structural. Where the stock library exposes no meaning for a
 * position, the name records what the bytes are (an LE16, a masked field, a bit)
 * rather than an invented semantic. Event field order is the stock Java callback
 * argument order, as recorded in the oracle vectors (it is not always the frame
 * order).
 *
 * The decoder keeps no state between calls: no stream buffering,
 * concatenation, resynchronization or de-duplication. One frame per call, exact
 * length.
 */
#ifndef CTPROTOCOL_DECODE_H
#define CTPROTOCOL_DECODE_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @name Top-level decode status
 *
 * The stock wrapper hands Java `decode(...) != 0x0b`, so the frame is reported
 * unrecognized (Java `false`) only when ctp_decode returns
 * CTP_DECODE_UNRECOGNIZED: an unknown top-level opcode, or op02/op07 whose
 * code or length matches no known form. Every other outcome (success,
 * entry-gate failure, per-family length or sub-code rejection) returns
 * CTP_DECODE_OK and yields Java `true`. Acceptance of a frame is signalled by
 * event emission, never by the return value.
 * @{
 */
#define CTP_DECODE_OK            0x00 /**< Frame handled, or silently dropped; Java `true`. */
#define CTP_DECODE_UNRECOGNIZED  0x0b /**< Opcode or op02/op07 form not recognized; Java `false`. */
/** @} */

/**
 * @brief Minimum size, in bytes, of the buffer passed to ctp_decode.
 *
 * The dispatcher reads some fixed header positions before it checks that the
 * frame is long enough to contain them. A frame shorter than the fields its
 * opcode reads sees those positions as zero, which reproduces the stock
 * decoder's zeroed work buffer. Examples: for opcodes 0x02, 0x22, 0x23, 0x26
 * and 0x27 a frame of length 3 reads buf[3] as 0; opcode 0x23 reads buf[3] to
 * buf[5], so a frame with plen < 3 reads zeros for the missing bytes (and still
 * emits an event); opcode 0x19 in its first-frame form reads buf[6] for a frame
 * of length 5 or 6.
 *
 * The caller must therefore pass a buffer of at least this size in which the
 * first `len` bytes hold the frame and every remaining byte is zero. Real
 * device frames (8-bit plen) never exceed this size.
 */
#define CTP_DECODE_MINBUF        258

/**
 * @brief Event kind: one per reachable Java callback family (25 in total).
 *
 * Each value names the stock static callback it maps to and gives the Java
 * method signature. Three callbacks cached by the stock loader (audioCtrl,
 * sbxProfileInfo, sbxProfileData) have no dispatcher path that invokes them, in
 * stock or here, so they have no event kind.
 *
 * The union member of ctp_event that carries each kind's payload is given in
 * the member comment.
 */
typedef enum {
    CTP_EV_OBSOLETE_ACK,          /**< obsoleteAckCallback (II)V; payload `two` */
    CTP_EV_PENDING_ACK,           /**< pendingAckCallback (III)V; payload `three` */
    CTP_EV_FILE_ACK,              /**< fileAckCallback (III)V; payload `three` */
    CTP_EV_DATA_ACK,              /**< dataAckCallback (II[B)V; payload `data_ack` */
    CTP_EV_MAX_PLS,               /**< maxPlsCallback (I)V; payload `one` */
    CTP_EV_REQUEST_CONTROL,       /**< requestControlCallback (Z)V; payload `one` (0 or 1) */
    CTP_EV_DEVICE_INFO,           /**< deviceInfoCallback (II)V; payload `two` */
    CTP_EV_FW_INFO,               /**< fwInfoCallback (IIIII)V; payload `five` */
    CTP_EV_DEVICE_FW_STRING,      /**< devicefwStringCallback ([I)V; payload `int_array` */
    CTP_EV_PROFILE_INFO_REC_FIRST,/**< profileInfoRecFirstCallback (IIIZIZZIZ)V; payload `rec_first` */
    CTP_EV_PROFILE_INFO_REST,     /**< profileInfoRestCallback (IIZIZZIZ)V; payload `rest` */
    CTP_EV_ACTIVE_PROFILE_REC,    /**< activeProfileRecCallback (IZ)V; payload `int_bool` */
    CTP_EV_ACTIVE_PROFILE_MEGA,   /**< activeProfileMegaCallback (IZ)V; payload `int_bool` */
    CTP_EV_AUDIO_LVL_RANGE,       /**< audioLvlRangeCallback (IFFFIII)V; payload `audio_range` */
    CTP_EV_AUDIO_LVL,             /**< audioLvlCallback (IFI)V; payload `audio_lvl` */
    CTP_EV_HW_BTN,                /**< hwBtnCallback (IZZZZZZZ)V; payload `hwbtn` */
    CTP_EV_HW_BTN_SUPPORT,        /**< hwBtnSupportCallback (IZZZZZZZ)V; payload `hwbtn` */
    CTP_EV_HW_BTN_STATUS_SUPPORT, /**< hwBtnStatusSupportCallback (IZZZZZZZ)V; payload `hwbtn` */
    CTP_EV_HW_BTN_ENABLED,        /**< hwBtnEnabledCallback (IZZZZZZZ)V; payload `hwbtn` */
    CTP_EV_BATTERY_LEVEL,         /**< batteryLevelCallback (I)V; payload `one` */
    CTP_EV_BATTERY_LEVEL_SUPPORT, /**< batteryLevelSupportCallback (III)V; payload `three` */
    CTP_EV_BATTERY_STATUS,        /**< batteryStatusCallback (ZZ)V; payload `two_bool` */
    CTP_EV_BATTERY_STATUS_SUPPORT,/**< batteryStatusSupportCallback (ZZ)V; payload `two_bool` */
    CTP_EV_BT_AUTO_CONNECT,       /**< btAutoConnectCallback (I)V; payload `one` */
    CTP_EV_VOICE_PROMPT_CTRL      /**< voicePromptCtrlCallback (I)V; payload `one` */
} ctp_event_kind;

/*
 * Per-family payloads. Every member is already in Java callback argument order
 * and in the Java argument width (int32 for I/Z, float for F, byte[]/int[] for
 * arrays). Booleans are carried as int32 0/1.
 */

/**
 * @brief Two-int payload.
 *
 * Used by obsoleteAck (code, status byte) and deviceInfo (LE16 device code,
 * byte at frame offset 6).
 */
typedef struct {
    int32_t code; /**< First callback argument. */
    int32_t v1;   /**< Second callback argument. */
} ctp_ev_two;

/**
 * @brief Three-int payload.
 *
 * Used by pendingAck (code, 1, delay clamped to 2..600), fileAck (code, status
 * byte, 1) and batteryLevelSupport (three consecutive frame bytes).
 */
typedef struct {
    int32_t a0, a1, a2; /**< The three callback arguments, in order. */
} ctp_ev_three;

/**
 * @brief dataAck payload: an acknowledgement code, a status byte and 8 data bytes.
 */
typedef struct {
    int32_t code, v1;  /**< Acknowledgement code (frame offset 3) and status
                        *   byte (frame offset 4: 0, 0x80 or 0x81). */
    uint8_t data[8];   /**< Frame offsets 5 to 12. */
} ctp_ev_data_ack;

/**
 * @brief Single-int payload.
 *
 * Used by maxPls (LE16), requestControl (0 or 1), batteryLevel, btAutoConnect
 * and voicePromptCtrl.
 */
typedef struct {
    int32_t value; /**< The callback's only argument. */
} ctp_ev_one;

/**
 * @brief fwInfo payload: bytes at frame offsets 3, 4, 5, an LE16 at 6 and a
 *        byte at 8, in callback argument order.
 */
typedef struct {
    int32_t a0, a1, a2, a3, a4; /**< Frame offsets 3, 4, 5, then the LE16 at
                                 *   6 and 7 (a3), then offset 8 (a4). */
} ctp_ev_five;

/**
 * @brief devicefwString payload: always 64 values, one per frame byte at
 *        offsets 3 to 66.
 */
typedef struct {
    int32_t vals[64]; /**< Each element is 0..255. */
} ctp_ev_int_array;

/**
 * @brief activeProfileRec / activeProfileMega payload.
 *
 * Both fields come from one frame byte.
 */
typedef struct {
    int32_t value; /**< Low 7 bits of the byte (the profile number). */
    int32_t flag;  /**< Bit 7 of the byte, as 0 or 1. */
} ctp_ev_int_bool;

/**
 * @brief batteryStatus / batteryStatusSupport payload: bit 0 and bit 1 of one
 *        frame byte.
 */
typedef struct {
    int32_t b0, b1; /**< Bit 0 and bit 1, each as 0 or 1. */
} ctp_ev_two_bool;

/**
 * @brief hwBtn / hwBtnSupport / hwBtnStatusSupport / hwBtnEnabled payload.
 *
 * `value` is the LE32 at frame offsets 4 to 7. The seven booleans are single
 * bits of the frame bytes at offsets 4 and 6, in callback argument order. The
 * mapping is a permutation, not the natural bit order:
 *
 *   bit[0] = byte4 bit 0    bit[1] = byte4 bit 3    bit[2] = byte6 bit 2
 *   bit[3] = byte6 bit 3    bit[4] = byte6 bit 1    bit[5] = byte4 bit 4
 *   bit[6] = byte4 bit 7
 *
 * For hwBtnStatusSupport (frame sub-code 3) the stock library inverts
 * positions 0, 1, 4, 5 and 6, so those booleans carry the complement of the
 * bit; positions 2 and 3 are not inverted. The other three kinds are not
 * inverted.
 */
typedef struct {
    int32_t value;   /**< LE32 at frame offsets 4 to 7. */
    int32_t bit[7];  /**< Seven booleans, each 0 or 1, as described above. */
} ctp_ev_hwbtn;

/**
 * @brief audioLvlRange payload: one 7-byte record of a multi-record frame.
 *
 * The three float arguments are always 0.0f. Preserved from stock: the stock
 * callback receives floats but the decoder never derives them from the frame.
 */
typedef struct {
    int32_t a0;      /**< First byte of the record. */
    float f0, f1, f2; /**< Always 0.0f. */
    int32_t i0, i1, i2; /**< LE16 values at record offsets 1, 3 and 5. */
} ctp_ev_audio_range;

/**
 * @brief audioLvl payload: a frame byte, a reserved float and an LE16.
 */
typedef struct {
    int32_t a0;  /**< Frame offset 3. */
    float   f;   /**< Always 0.0f (reserved). */
    int32_t i0;  /**< LE16 at frame offsets 4 and 5. */
} ctp_ev_audio_lvl;

/**
 * @brief profileInfoRecFirst payload (callback signature IIIZIZZIZ): one
 *        3-byte record of an op19 "first" frame.
 *
 * The record bytes are r0, r1, r2. Booleans named `*_n` carry the complement of
 * the bit they come from.
 */
typedef struct {
    /**
     * x: header byte at frame offset 5, shared by all records.
     * index: 0-based record ordinal within the frame.
     * type: r0 bits 0..6.      b0_hi: r0 bit 7.
     * b1_lo: r1 bits 0..5.     b1_b6: r1 bit 6.
     * b1_hi_n: complement of r1 bit 7.
     * b2_lo: r2 bits 0..6.     b2_hi_n: complement of r2 bit 7.
     */
    int32_t x, index, type, b0_hi, b1_lo, b1_b6, b1_hi_n, b2_lo, b2_hi_n;
} ctp_ev_profile_rec_first;

/**
 * @brief profileInfoRest payload (callback signature IIZIZZIZ): one 3-byte
 *        record of an op19 "rest" frame.
 *
 * Field meanings match ctp_ev_profile_rec_first, except that the header byte
 * and the record ordinal are folded into one running value. The stock "first"
 * callback keeps them split.
 */
typedef struct {
    /**
     * x_plus_index: header byte at frame offset 5 plus the 0-based record
     * ordinal.
     * type: r0 bits 0..6.      b0_hi: r0 bit 7.
     * b1_lo: r1 bits 0..5.     b1_b6: r1 bit 6.
     * b1_hi_n: complement of r1 bit 7.
     * b2_lo: r2 bits 0..6.     b2_hi_n: complement of r2 bit 7.
     */
    int32_t x_plus_index, type, b0_hi, b1_lo, b1_b6, b1_hi_n, b2_lo, b2_hi_n;
} ctp_ev_profile_rest;

/**
 * @brief One decoded event: a kind tag and the payload member that kind uses.
 *
 * Only the union member named in the ctp_event_kind documentation is
 * meaningful for a given `kind`; the other members are unspecified.
 */
typedef struct {
    ctp_event_kind kind;               /**< Selects the active member of `u`. */
    union {
        ctp_ev_two                two;       /**< obsoleteAck, deviceInfo */
        ctp_ev_three              three;     /**< pendingAck, fileAck, batteryLevelSupport */
        ctp_ev_data_ack           data_ack;  /**< dataAck */
        ctp_ev_one                one;       /**< maxPls, requestControl, batteryLevel, btAutoConnect, voicePromptCtrl */
        ctp_ev_five               five;      /**< fwInfo */
        ctp_ev_int_array          int_array; /**< devicefwString */
        ctp_ev_int_bool           int_bool;  /**< activeProfileRec, activeProfileMega */
        ctp_ev_two_bool           two_bool;  /**< batteryStatus, batteryStatusSupport */
        ctp_ev_hwbtn              hwbtn;     /**< hwBtn, hwBtnSupport, hwBtnStatusSupport, hwBtnEnabled */
        ctp_ev_audio_range        audio_range; /**< audioLvlRange */
        ctp_ev_audio_lvl          audio_lvl; /**< audioLvl */
        ctp_ev_profile_rec_first  rec_first; /**< profileInfoRecFirst */
        ctp_ev_profile_rest       rest;      /**< profileInfoRest */
    } u;                               /**< Payload; see ctp_event_kind. */
} ctp_event;

/**
 * @brief Event sink called by ctp_decode.
 *
 * Called once per emitted event, in dispatch order (for multi-record frames,
 * opcodes 0x19 and 0x22, once per record in record order). The event pointer
 * is valid only for the duration of the call.
 *
 * @param user  The `user` pointer passed to ctp_decode, unchanged.
 * @param ev    The event; must not be retained after the call returns.
 */
typedef void (*ctp_emit_fn)(void *user, const ctp_event *ev);

/**
 * @brief Decode one inbound frame.
 *
 * Decodes exactly `len` bytes of `frame` from offset 0; any bytes past `len`
 * are ignored, matching the stock explicit-length contract. Emits each event
 * through `emit`. Holds no state across calls, buffers nothing and
 * de-duplicates nothing.
 *
 * Frames that fail the entry gate, and frames of a recognized opcode whose
 * length or sub-code is not valid for it, produce no event and return
 * CTP_DECODE_OK.
 *
 * Two behaviors are preserved from stock and are part of the contract:
 *  - For opcode 0x19, if any record in the frame is invalid, no event is
 *    emitted for any record of that frame (all records are validated before
 *    the first event is emitted).
 *  - Opcodes 0x01, 0x05, 0x10, 0x11, 0x13, 0x14, 0x15, 0x16, 0x1E, 0x20, 0x21,
 *    0x24, 0x25, 0x30, 0x32 to 0x36, 0x38, 0x39 and 0x3A are recognized but
 *    silent: they return CTP_DECODE_OK and emit nothing.
 *
 * @param frame  Buffer holding the frame at offset 0. It must be at least
 *               CTP_DECODE_MINBUF bytes long, with every byte at or beyond
 *               `len` set to zero (see CTP_DECODE_MINBUF). Must not be NULL.
 * @param len    Frame length in bytes, 3 to CTP_DECODE_MINBUF. A smaller value
 *               fails the entry gate and returns CTP_DECODE_OK with no event.
 * @param emit   Event sink; must not be NULL. It is not checked.
 * @param user   Opaque pointer passed through to `emit`.
 * @return       CTP_DECODE_OK, or CTP_DECODE_UNRECOGNIZED for an unknown
 *               top-level opcode or an op02/op07 frame of no known form.
 */
int ctp_decode(const uint8_t *frame, int len, ctp_emit_fn emit, void *user);

#ifdef __cplusplus
}
#endif

#endif /* CTPROTOCOL_DECODE_H */
