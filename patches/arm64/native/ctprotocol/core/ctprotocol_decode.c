/*
 * ctprotocol-core: portable SPP inbound decoder (implementation).
 *
 * Reproduces the stock Decode::decode dispatcher. Validation, field extraction
 * and dispatch follow the stock logic; the Java argument order and the per-byte
 * field mapping of every reachable family match the stock library for the
 * vectors in oracle/vectors/dec_*.{txt,out.txt} (see docs/research/decoder/ and
 * docs/technical/CTPROTOCOL.md). Provenance: stock x86 library, dispatcher at
 * offset 0x1a520. No stream buffering, concatenation, resync, trailing-byte
 * tolerance or recovery: one frame per call, exact length.
 *
 * The caller must pass a buffer of at least CTP_DECODE_MINBUF bytes, with the
 * first `len` bytes holding the frame and the remainder zero. The dispatcher
 * reads some fixed positions before it checks that the frame is long enough to
 * contain them: a frame shorter than the fields its opcode reads sees zeros
 * from the zeroed tail of the buffer, for several opcodes including 0x02, 0x22,
 * 0x23, 0x26 and 0x27 with len 3, and for opcode 0x23 with plen < 3 (it reads
 * buf[3] to buf[5]). The zero tail reproduces the stock decoder's zeroed work
 * buffer without reading past the caller's allocation.
 */
#include "ctprotocol_decode.h"

static int32_t le16(const uint8_t *p) {
    return (int32_t)((uint32_t)p[0] | ((uint32_t)p[1] << 8));
}

static int32_t le32(const uint8_t *p) {
    return (int32_t)((uint32_t)p[0] | ((uint32_t)p[1] << 8) |
                     ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24));
}

/* op02 "code" (buf[3]) acknowledgement-type membership. Outside this set op02
 * is unrecognized (Java false), mirroring the stock membership test.
 * Provenance: stock x86 library, offset 0x1a5c7. */
static int op02_code_known(unsigned c) {
    return (c >= 1 && c <= 3) || (c >= 5 && c <= 8) ||
           (c >= 0x10 && c <= 0x16) || (c >= 0x20 && c <= 0x26) ||
           (c == 0x19 || c == 0x1a) || (c == 0x1c || c == 0x1e) ||
           (c >= 0x30 && c <= 0x3b) || (c >= 0x41 && c <= 0x4f) ||
           (c == 0x9b) || (c == 0x98 || c == 0x99);
}

/* op19 per-record validator: the record type (b0 bits 0..6) selects the largest
 * allowed field value (b1 bits 0..5). Record is b0=type|flag, b1=field|..,
 * b2=..; the caller rejects the whole frame if any record fails. Types not
 * listed below are invalid. 1 = valid, 0 = reject. Provenance: stock x86 library, validator at offset 0x149f5 plus
 * inline range checks in the dispatcher. */
static int op19_rec_valid(unsigned b0, unsigned b1) {
    unsigned type = b0 & 0x7f;
    unsigned field = b1 & 0x3f;
    switch (type) {
    case 0x00: return field <= 0xc;
    case 0x01:
    case 0x02:
    case 0x03:
    case 0x41: return field <= 4;
    case 0x40: return 1;
    default:   return 0;
    }
}

int ctp_decode(const uint8_t *frame, int len, ctp_emit_fn emit, void *user) {
    /* Entry gate: len >= 3, magic 0x5A, declared plen == len-3. Any failure
     * returns Java true (ret != 0x0b) with no event. */
    if (len < 3 || frame[0] != 0x5a || frame[2] != (uint8_t)(len - 3))
        return CTP_DECODE_OK;

    const uint8_t *b = frame;
    const int plen = len - 3;
    ctp_event ev;

    switch (b[1]) {

    case 0x02: {  /* ack family; op02 and op07 are the only unrecognizable opcodes */
        unsigned code = b[3];
        if (!op02_code_known(code))
            return CTP_DECODE_UNRECOGNIZED;
        if (len == 5) {
            if ((b[4] & 0x7f) < 2) {
                ev.kind = CTP_EV_OBSOLETE_ACK;
                ev.u.two.code = (int32_t)code;
                ev.u.two.v1 = b[4];
                emit(user, &ev);
            }
            return CTP_DECODE_OK;
        }
        if (len == 7) {
            if (b[4] == 1) {
                int32_t p = le16(b + 5);
                if (p < 2) p = 2; else if (p > 600) p = 600;
                ev.kind = CTP_EV_PENDING_ACK;
                ev.u.three.a0 = (int32_t)code;
                ev.u.three.a1 = 1;
                ev.u.three.a2 = p;
                emit(user, &ev);
            }
            return CTP_DECODE_OK;
        }
        if (len == 0xd) {
            if (code == 0x3a)
                return CTP_DECODE_OK;  /* stock routes code 0x3a, len 13 to an internal
                                        * listener, not to Java: no callback is raised */
            /* Admits b[4] in {0x00, 0x80, 0x81}: the low 7 bits are < 2 and b[4]
             * itself is not 1. Preserved from stock; 0x80 and 0x81 are passed
             * through to the callback unchanged in v1. */
            if ((b[4] & 0x7f) < 2 && b[4] != 1) {
                ev.kind = CTP_EV_DATA_ACK;
                ev.u.data_ack.code = (int32_t)code;
                ev.u.data_ack.v1 = b[4];
                for (int i = 0; i < 8; i++)
                    ev.u.data_ack.data[i] = b[5 + i];
                emit(user, &ev);
            }
            return CTP_DECODE_OK;
        }
        if (len == 6 && b[4] == 1) {
            if (b[5] < 4) {
                ev.kind = CTP_EV_FILE_ACK;
                ev.u.three.a0 = (int32_t)code;
                ev.u.three.a1 = b[5];
                ev.u.three.a2 = 1;
                emit(user, &ev);
            }
            return CTP_DECODE_OK;
        }
        return CTP_DECODE_UNRECOGNIZED;  /* len not a known op02 form */
    }

    case 0x03:  /* maxPls */
        if (len == 5) {
            ev.kind = CTP_EV_MAX_PLS;
            ev.u.one.value = le16(b + 3);
            emit(user, &ev);
        }
        return CTP_DECODE_OK;

    case 0x06:  /* requestControl */
        if (len == 4) {
            ev.kind = CTP_EV_REQUEST_CONTROL;
            ev.u.one.value = (b[3] == 1);
            emit(user, &ev);
        }
        return CTP_DECODE_OK;

    case 0x07:  /* deviceInfo / fwInfo / devicefwString; unrecognized on bad length */
        if (len == 0x13 || len == 7) {
            ev.kind = CTP_EV_DEVICE_INFO;
            ev.u.two.code = le16(b + 3);
            ev.u.two.v1 = b[6];
            emit(user, &ev);
            return CTP_DECODE_OK;
        }
        if (len == 9) {
            ev.kind = CTP_EV_FW_INFO;
            ev.u.five.a0 = b[3];
            ev.u.five.a1 = b[4];
            ev.u.five.a2 = b[5];
            ev.u.five.a3 = le16(b + 6);
            ev.u.five.a4 = b[8];
            emit(user, &ev);
            return CTP_DECODE_OK;
        }
        if (len == 0x43) {
            ev.kind = CTP_EV_DEVICE_FW_STRING;
            for (int i = 0; i < 64; i++)
                ev.u.int_array.vals[i] = b[3 + i];
            emit(user, &ev);
            return CTP_DECODE_OK;
        }
        return CTP_DECODE_UNRECOGNIZED;

    case 0x19: {  /* profileInfoRecFirst (sub&0x7f==0, mode==1) / profileInfoRest */
        if (len <= 4)
            return CTP_DECODE_OK;
        unsigned sub = b[3];
        if ((sub & 0x7f) == 0) {
            if (b[4] == 1) {               /* mode: only 1 reaches the Java callback */
                unsigned count = b[6];
                if (plen == (int)count * 3 + 4) {
                    /* Two passes, preserved from stock: every record is
                     * validated first, and one invalid record suppresses the
                     * events of every record in the frame, including records
                     * that precede it. */
                    for (unsigned i = 0; i < count; i++) {
                        const uint8_t *r = b + 7 + i * 3;
                        if (!op19_rec_valid(r[0], r[1]))
                            return CTP_DECODE_OK;   /* whole frame: no callback */
                    }
                    for (unsigned i = 0; i < count; i++) {
                        const uint8_t *r = b + 7 + i * 3;
                        ev.kind = CTP_EV_PROFILE_INFO_REC_FIRST;
                        ev.u.rec_first.x = b[5];
                        ev.u.rec_first.index = (int32_t)i;
                        ev.u.rec_first.type = r[0] & 0x7f;
                        ev.u.rec_first.b0_hi = r[0] >> 7;
                        ev.u.rec_first.b1_lo = r[1] & 0x3f;
                        ev.u.rec_first.b1_b6 = (r[1] >> 6) & 1;
                        ev.u.rec_first.b1_hi_n = ((r[1] >> 7) & 1) ^ 1;
                        ev.u.rec_first.b2_lo = r[2] & 0x7f;
                        ev.u.rec_first.b2_hi_n = ((r[2] >> 7) & 1) ^ 1;
                        emit(user, &ev);
                    }
                }
            }
            return CTP_DECODE_OK;
        } else {
            unsigned count = b[4];
            if (plen == ((int)count + 1) * 3) {
                /* Same two-pass validation as the first-frame form above. */
                for (unsigned i = 0; i < count; i++) {
                    const uint8_t *r = b + 6 + i * 3;
                    if (!op19_rec_valid(r[0], r[1]))
                        return CTP_DECODE_OK;
                }
                for (unsigned i = 0; i < count; i++) {
                    const uint8_t *r = b + 6 + i * 3;
                    ev.kind = CTP_EV_PROFILE_INFO_REST;
                    ev.u.rest.x_plus_index = b[5] + (int32_t)i;
                    ev.u.rest.type = r[0] & 0x7f;
                    ev.u.rest.b0_hi = r[0] >> 7;
                    ev.u.rest.b1_lo = r[1] & 0x3f;
                    ev.u.rest.b1_b6 = (r[1] >> 6) & 1;
                    ev.u.rest.b1_hi_n = ((r[1] >> 7) & 1) ^ 1;
                    ev.u.rest.b2_lo = r[2] & 0x7f;
                    ev.u.rest.b2_hi_n = ((r[2] >> 7) & 1) ^ 1;
                    emit(user, &ev);
                }
            }
            return CTP_DECODE_OK;
        }
    }

    case 0x1a:  /* activeProfileRec (sub==1) / activeProfileMega (sub==2) */
        if (len == 5 && b[3] < 4) {
            if (b[3] == 1 || b[3] == 2) {
                ev.kind = (b[3] == 1) ? CTP_EV_ACTIVE_PROFILE_REC
                                      : CTP_EV_ACTIVE_PROFILE_MEGA;
                ev.u.int_bool.value = b[4] & 0x7f;
                ev.u.int_bool.flag = b[4] >> 7;
                emit(user, &ev);
            }
        }
        return CTP_DECODE_OK;

    case 0x22: {  /* audioLvlRange: count = buf[3], one event per 7-byte record */
        /* Preserved from stock: buf[4] is not examined, whatever its value, and
         * the three float arguments of every event are always 0.0f. */
        unsigned count = b[3];
        if (plen >= 2 && plen == (int)count * 7 + 2) {
            for (unsigned i = 0; i < count; i++) {
                const uint8_t *r = b + 5 + i * 7;
                ev.kind = CTP_EV_AUDIO_LVL_RANGE;
                ev.u.audio_range.a0 = r[0];
                ev.u.audio_range.f0 = 0.0f;
                ev.u.audio_range.f1 = 0.0f;
                ev.u.audio_range.f2 = 0.0f;
                ev.u.audio_range.i0 = le16(r + 1);
                ev.u.audio_range.i1 = le16(r + 3);
                ev.u.audio_range.i2 = le16(r + 5);
                emit(user, &ev);
            }
        }
        return CTP_DECODE_OK;
    }

    case 0x23:  /* audioLvl: int, reserved float (always 0.0), LE16 */
        if (plen < 5) {
            ev.kind = CTP_EV_AUDIO_LVL;
            ev.u.audio_lvl.a0 = b[3];
            ev.u.audio_lvl.f = 0.0f;
            ev.u.audio_lvl.i0 = le16(b + 4);
            emit(user, &ev);
        }
        return CTP_DECODE_OK;

    case 0x26: {  /* hwBtn family: sub selects the callback, plen must be 5 */
        unsigned sub = b[3];
        if (plen == 5 && sub >= 1 && sub <= 4) {
            unsigned f4 = b[4], f6 = b[6];
            ev.kind = (sub == 1) ? CTP_EV_HW_BTN :
                      (sub == 2) ? CTP_EV_HW_BTN_SUPPORT :
                      (sub == 3) ? CTP_EV_HW_BTN_STATUS_SUPPORT :
                                   CTP_EV_HW_BTN_ENABLED;
            ev.u.hwbtn.value = le32(b + 4);
            /* Bit mapping preserved from stock: the seven booleans are drawn
             * from bytes 4 and 6 in a permuted order (see ctp_ev_hwbtn). The
             * status-support callback (sub 3) inverts positions 0, 1, 4, 5 and
             * 6 and leaves 2 and 3 as they are; this asymmetry is stock
             * behavior, not a transcription error. */
            if (sub == 3) {  /* status-support inverts positions 0,1,4,5,6 */
                ev.u.hwbtn.bit[0] = ((f4 >> 0) & 1) ^ 1;
                ev.u.hwbtn.bit[1] = ((f4 >> 3) & 1) ^ 1;
                ev.u.hwbtn.bit[2] = (f6 >> 2) & 1;
                ev.u.hwbtn.bit[3] = (f6 >> 3) & 1;
                ev.u.hwbtn.bit[4] = ((f6 >> 1) & 1) ^ 1;
                ev.u.hwbtn.bit[5] = ((f4 >> 4) & 1) ^ 1;
                ev.u.hwbtn.bit[6] = ((f4 >> 7) & 1) ^ 1;
            } else {
                ev.u.hwbtn.bit[0] = (f4 >> 0) & 1;
                ev.u.hwbtn.bit[1] = (f4 >> 3) & 1;
                ev.u.hwbtn.bit[2] = (f6 >> 2) & 1;
                ev.u.hwbtn.bit[3] = (f6 >> 3) & 1;
                ev.u.hwbtn.bit[4] = (f6 >> 1) & 1;
                ev.u.hwbtn.bit[5] = (f4 >> 4) & 1;
                ev.u.hwbtn.bit[6] = (f4 >> 7) & 1;
            }
            emit(user, &ev);
        }
        return CTP_DECODE_OK;
    }

    case 0x27:  /* batteryLevel (sub1,len5) / batteryLevelSupport (sub2,len7) */
        if (b[3] == 1 && len == 5) {
            ev.kind = CTP_EV_BATTERY_LEVEL;
            ev.u.one.value = b[4];
            emit(user, &ev);
        } else if (b[3] == 2 && len == 7) {
            ev.kind = CTP_EV_BATTERY_LEVEL_SUPPORT;
            ev.u.three.a0 = b[4];
            ev.u.three.a1 = b[5];
            ev.u.three.a2 = b[6];
            emit(user, &ev);
        }
        return CTP_DECODE_OK;

    case 0x28:  /* batteryStatus (sub1) / batteryStatusSupport (sub2), len8 */
        if (len == 8 && (b[3] == 1 || b[3] == 2)) {
            ev.kind = (b[3] == 1) ? CTP_EV_BATTERY_STATUS
                                  : CTP_EV_BATTERY_STATUS_SUPPORT;
            ev.u.two_bool.b0 = b[4] & 1;
            ev.u.two_bool.b1 = (b[4] >> 1) & 1;
            emit(user, &ev);
        }
        return CTP_DECODE_OK;

    case 0x31:  /* btAutoConnect */
        if (len == 4 && b[3] < 2) {
            ev.kind = CTP_EV_BT_AUTO_CONNECT;
            ev.u.one.value = b[3];
            emit(user, &ev);
        }
        return CTP_DECODE_OK;

    case 0x99:  /* voicePromptCtrl */
        if (len == 4 && b[3] < 3) {
            ev.kind = CTP_EV_VOICE_PROMPT_CTRL;
            ev.u.one.value = b[3];
            emit(user, &ev);
        }
        return CTP_DECODE_OK;

    /* Recognized but silent, preserved from stock: these opcodes have no
     * reachable Java callback (internal listener slots or record-store forms).
     * They are accepted (ret != 0x0b, so Java sees `true`) and emit nothing.
     * Removing one from this list would change the Java result to `false`. */
    case 0x01: case 0x05: case 0x10: case 0x11: case 0x13: case 0x14:
    case 0x15: case 0x16: case 0x1e: case 0x20: case 0x21: case 0x24:
    case 0x25: case 0x30: case 0x32: case 0x33: case 0x34: case 0x35:
    case 0x36: case 0x38: case 0x39: case 0x3a:
        return CTP_DECODE_OK;

    default:  /* unknown top-level opcode: Java false */
        return CTP_DECODE_UNRECOGNIZED;
    }
}
