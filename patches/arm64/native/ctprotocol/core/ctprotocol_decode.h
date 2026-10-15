/*
 * ctprotocol-core: portable SPP inbound decoder.
 *
 * ONE implementation, no JNI and no platform headers, validated against the
 * frozen Phase 2 decode oracle (oracle/vectors/dec_*.{txt,out.txt}) and compiled
 * unchanged for arm64-v8a. ctp_decode() parses a single inbound frame and emits
 * zero or more typed events; it reproduces the stock Decode::decode dispatcher
 * byte for byte. The core knows nothing about JNI, Java, Android, Bluetooth or
 * callbacks: the thin JNI adapter maps each typed event onto a stock
 * SbxSppCommandManager static callback. See docs/arm64/decode/.
 *
 * Inbound frame grammar: 5A <op> <plen> <payload[plen]>, total length plen + 3,
 * little-endian scalars. The entry gate is len >= 3 && buf[0] == 0x5A &&
 * buf[2] == len - 3; dispatch is on buf[1], then on sub = buf[3] or plen.
 *
 * Field names are structural. Where the stock library exposes no meaning for a
 * position, the name records what the bytes are (an LE16, a masked field, a bit)
 * rather than an invented semantic. Event field order is the stock Java callback
 * argument order, captured from the oracle (it is not always the frame order).
 */
#ifndef CTPROTOCOL_DECODE_H
#define CTPROTOCOL_DECODE_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Top-level decode status. The stock wrapper hands Java `decode(...) != 0x0b`,
 * so the frame is reported unrecognized (Java `false`) only when ctp_decode
 * returns CTP_DECODE_UNRECOGNIZED: an unknown top-level opcode, or op02/op07
 * whose code/length matches no known form. Every other outcome (success,
 * entry-gate failure, per-family length/sub rejection) returns CTP_DECODE_OK and
 * yields Java `true`. Acceptance is signalled by event emission, never by this.
 */
#define CTP_DECODE_OK            0x00
#define CTP_DECODE_UNRECOGNIZED  0x0b

/*
 * ctp_decode parses the frame in place from the caller's buffer. For a few
 * degenerate short frames (op23 with plen < 3) the stock dispatcher reads up to
 * two bytes past the declared payload out of its zeroed work buffer; pass the
 * frame in a zero-initialized buffer of at least CTP_DECODE_MINBUF bytes so those
 * reads see zero rather than running past the allocation. Real device frames
 * (8-bit plen) never exceed this.
 */
#define CTP_DECODE_MINBUF        258

/* One event kind per reachable Java callback family (25 total). The three cached
 * callbacks with no dispatcher path (audioCtrl, sbxProfileInfo, sbxProfileData)
 * are UNREACHABLE-FROM-KNOWN-DISPATCH and have no event kind: the stock binary
 * never emits them, so neither does the core. */
typedef enum {
    CTP_EV_OBSOLETE_ACK,          /* obsoleteAckCallback            (II)V        */
    CTP_EV_PENDING_ACK,           /* pendingAckCallback             (III)V       */
    CTP_EV_FILE_ACK,              /* fileAckCallback                (III)V       */
    CTP_EV_DATA_ACK,              /* dataAckCallback                (II[B)V      */
    CTP_EV_MAX_PLS,               /* maxPlsCallback                 (I)V         */
    CTP_EV_REQUEST_CONTROL,       /* requestControlCallback         (Z)V         */
    CTP_EV_DEVICE_INFO,           /* deviceInfoCallback             (II)V        */
    CTP_EV_FW_INFO,               /* fwInfoCallback                 (IIIII)V     */
    CTP_EV_DEVICE_FW_STRING,      /* devicefwStringCallback         ([I)V        */
    CTP_EV_PROFILE_INFO_REC_FIRST,/* profileInfoRecFirstCallback    (IIIZIZZIZ)V */
    CTP_EV_PROFILE_INFO_REST,     /* profileInfoRestCallback        (IIZIZZIZ)V  */
    CTP_EV_ACTIVE_PROFILE_REC,    /* activeProfileRecCallback       (IZ)V        */
    CTP_EV_ACTIVE_PROFILE_MEGA,   /* activeProfileMegaCallback      (IZ)V        */
    CTP_EV_AUDIO_LVL_RANGE,       /* audioLvlRangeCallback          (IFFFIII)V   */
    CTP_EV_AUDIO_LVL,             /* audioLvlCallback               (IFI)V       */
    CTP_EV_HW_BTN,                /* hwBtnCallback                  (IZZZZZZZ)V  */
    CTP_EV_HW_BTN_SUPPORT,        /* hwBtnSupportCallback           (IZZZZZZZ)V  */
    CTP_EV_HW_BTN_STATUS_SUPPORT, /* hwBtnStatusSupportCallback     (IZZZZZZZ)V  */
    CTP_EV_HW_BTN_ENABLED,        /* hwBtnEnabledCallback           (IZZZZZZZ)V  */
    CTP_EV_BATTERY_LEVEL,         /* batteryLevelCallback           (I)V         */
    CTP_EV_BATTERY_LEVEL_SUPPORT, /* batteryLevelSupportCallback    (III)V       */
    CTP_EV_BATTERY_STATUS,        /* batteryStatusCallback          (ZZ)V        */
    CTP_EV_BATTERY_STATUS_SUPPORT,/* batteryStatusSupportCallback   (ZZ)V        */
    CTP_EV_BT_AUTO_CONNECT,       /* btAutoConnectCallback          (I)V         */
    CTP_EV_VOICE_PROMPT_CTRL      /* voicePromptCtrlCallback        (I)V         */
} ctp_event_kind;

/* Per-family payloads. Every member is already in Java callback argument order
 * and in the Java argument width (int32 for I/Z, float for F, byte[]/int[] for
 * arrays). Booleans are carried as int32 0/1. */

typedef struct { int32_t code; int32_t v1; } ctp_ev_two;          /* obsoleteAck, deviceInfo */
typedef struct { int32_t a0, a1, a2; } ctp_ev_three;              /* pendingAck, fileAck, batteryLevelSupport */
typedef struct { int32_t code, v1; uint8_t data[8]; } ctp_ev_data_ack; /* dataAck */
typedef struct { int32_t value; } ctp_ev_one;                     /* maxPls, requestControl(Z), batteryLevel, btAutoConnect, voicePromptCtrl */
typedef struct { int32_t a0, a1, a2, a3, a4; } ctp_ev_five;       /* fwInfo */
typedef struct { int32_t vals[64]; } ctp_ev_int_array;            /* devicefwString, always 64 */
typedef struct { int32_t value; int32_t flag; } ctp_ev_int_bool;  /* activeProfileRec/Mega */
typedef struct { int32_t b0, b1; } ctp_ev_two_bool;               /* batteryStatus, batteryStatusSupport */
typedef struct { int32_t value; int32_t bit[7]; } ctp_ev_hwbtn;   /* hwBtn family: value + 7 bools */
typedef struct { int32_t a0; float f0, f1, f2; int32_t i0, i1, i2; } ctp_ev_audio_range; /* audioLvlRange */
typedef struct { int32_t a0; float f; int32_t i0; } ctp_ev_audio_lvl;                    /* audioLvl */
/* profileInfoRecFirst (IIIZIZZIZ): x index type bit0hi f_lo f_b6 f_hi_n s_lo s_hi_n.
 * x = payload byte b[5]; index = 0-based record ordinal within the frame. */
typedef struct {
    int32_t x, index, type, b0_hi, b1_lo, b1_b6, b1_hi_n, b2_lo, b2_hi_n;
} ctp_ev_profile_rec_first;
/* profileInfoRest (IIZIZZIZ): x_plus_index type bit0hi f_lo f_b6 f_hi_n s_lo s_hi_n.
 * x_plus_index = payload byte b[5] + the 0-based record ordinal (stock folds the
 * header byte and the record index into one running arg; recFirst keeps them split). */
typedef struct {
    int32_t x_plus_index, type, b0_hi, b1_lo, b1_b6, b1_hi_n, b2_lo, b2_hi_n;
} ctp_ev_profile_rest;

typedef struct {
    ctp_event_kind kind;
    union {
        ctp_ev_two                two;
        ctp_ev_three              three;
        ctp_ev_data_ack           data_ack;
        ctp_ev_one                one;
        ctp_ev_five               five;
        ctp_ev_int_array          int_array;
        ctp_ev_int_bool           int_bool;
        ctp_ev_two_bool           two_bool;
        ctp_ev_hwbtn              hwbtn;
        ctp_ev_audio_range        audio_range;
        ctp_ev_audio_lvl          audio_lvl;
        ctp_ev_profile_rec_first  rec_first;
        ctp_ev_profile_rest       rest;
    } u;
} ctp_event;

/* Called once per emitted event, in dispatch order (for op19/op22 multi-record
 * frames, once per record in record order). The event pointer is valid only for
 * the duration of the call. */
typedef void (*ctp_emit_fn)(void *user, const ctp_event *ev);

/*
 * Decode exactly `len` bytes of `frame` from offset 0 (any bytes past `len` are
 * ignored, matching the stock explicit-length contract). Emits each event via
 * `emit`. Holds no state across calls, buffers nothing, de-duplicates nothing.
 * Returns CTP_DECODE_OK or CTP_DECODE_UNRECOGNIZED (see above).
 */
int ctp_decode(const uint8_t *frame, int len, ctp_emit_fn emit, void *user);

#ifdef __cplusplus
}
#endif

#endif /* CTPROTOCOL_DECODE_H */
