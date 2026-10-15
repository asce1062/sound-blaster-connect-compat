package com.creative.logic.sbxapplogic.vendor.sbx;

import java.io.BufferedReader;
import java.io.FileReader;
import java.util.ArrayList;
import java.util.List;

/**
 * Oracle / differential harness.
 *
 * Mirror of the stock SbxSppCommandManager with the EXACT fully-qualified name,
 * so the native lib's static Java_... exports bind to these declarations and
 * JNI_OnLoad's GetStaticMethodID finds these callback methods. It loads whichever
 * libsbxapplogic_ctprotocol_jni.so is passed (stock x86 or the reimplementation),
 * drives a fixed set of calls, and prints deterministic, diffable lines:
 *
 *   mode enc:  one "ENC <name> <argspec> = <hex>" per encode vector
 *   mode dec:  one "DEC <frameHex> ->" plus "  CB <name> <args>" per callback,
 *              in dispatch order, for each frame read from the corpus file
 *
 * Running the same vectors against the stock lib and the reimplementation and
 * diffing the output is the byte-for-byte differential check (Phases E and D).
 */
public class SbxSppCommandManager {

    // ---- 35 reachable native methods (exact signatures from the APK) ----
    private static native byte[] cancelFileTransfer();
    private static native byte[] commitSettings();
    private static native boolean decode(byte[] frame, int len);
    private static native byte[] getActiveProfileMega();
    private static native byte[] getActiveProfileRec();
    private static native byte[] getAudioLvl(int a);
    private static native byte[] getBatteryLevel();
    private static native byte[] getBatteryLevelSupport();
    private static native byte[] getBatteryStatus();
    private static native byte[] getBatteryStatusSupport();
    private static native byte[] getBtAutoConnect();
    private static native byte[] getDeviceFwString();
    private static native byte[] getFileDataBlk(byte[] a, int b, boolean c);
    private static native int    getFileTransferMaxDataSize();
    private static native byte[] getFwInfo(int a);
    private static native byte[] getGeneralInfo();
    private static native byte[] getHwBtn();
    private static native byte[] getHwBtnStatusSupport();
    private static native byte[] getHwBtnSupport();
    private static native byte[] getMaxPayloadSize();
    private static native byte[] getProfileInfoRec();
    private static native byte[] getVoicePromptCtrl();
    private static native byte[] hwBtnEnabled();
    private static native byte[] releaseControl();
    private static native byte[] resetFactoryDefault();
    private static native byte[] setActiveProfileMega(int a);
    private static native byte[] setActiveProfileMegaVoicePreview(int a);
    private static native byte[] setActiveProfileRec(int a);
    private static native byte[] setActiveProfileRecVoicePreview(int a);
    private static native byte[] setBtAutoConnect(int a);
    private static native byte[] setFileSize(int a, int b);
    private static native byte[] setHwBtn(int a, int b);
    private static native byte[] setMalcolmParam(int[] a, int[] b, float[] c, int d, int[] e);
    private static native byte[] setTime(int a);
    private static native byte[] setVoicePromptCtrl(int a);

    // ---- 28 inbound callbacks: record invocation name + args, in order ----
    private static final List<String> CB = new ArrayList<String>();
    private static void log(String s) { CB.add(s); }

    private static void requestControlCallback(boolean a) { log("requestControlCallback " + b(a)); }
    private static void dataAckCallback(int a, int c, byte[] d) { log("dataAckCallback " + a + " " + c + " " + arr(d)); }
    private static void obsoleteAckCallback(int a, int c) { log("obsoleteAckCallback " + a + " " + c); }
    private static void pendingAckCallback(int a, int c, int d) { log("pendingAckCallback " + a + " " + c + " " + d); }
    private static void fileAckCallback(int a, int c, int d) { log("fileAckCallback " + a + " " + c + " " + d); }
    private static void deviceInfoCallback(int a, int c) { log("deviceInfoCallback " + a + " " + c); }
    private static void fwInfoCallback(int a, int c, int d, int e, int f) { log("fwInfoCallback " + a + " " + c + " " + d + " " + e + " " + f); }
    private static void maxPlsCallback(int a) { log("maxPlsCallback " + a); }
    private static void hwBtnCallback(int a, boolean c, boolean d, boolean e, boolean f, boolean g, boolean h, boolean i) { log("hwBtnCallback " + a + " " + b(c) + b(d) + b(e) + b(f) + b(g) + b(h) + b(i)); }
    private static void audioCtrlCallback(int a, boolean c) { log("audioCtrlCallback " + a + " " + b(c)); }
    private static void audioLvlCallback(int a, float c, int d) { log("audioLvlCallback " + a + " " + flt(c) + " " + d); }
    private static synchronized void audioLvlRangeCallback(int a, float c, float d, float e, int f, int g, int h) { log("audioLvlRangeCallback " + a + " " + flt(c) + " " + flt(d) + " " + flt(e) + " " + f + " " + g + " " + h); }
    private static void batteryLevelCallback(int a) { log("batteryLevelCallback " + a); }
    private static void batteryLevelSupportCallback(int a, int c, int d) { log("batteryLevelSupportCallback " + a + " " + c + " " + d); }
    private static void batteryStatusCallback(boolean a, boolean c) { log("batteryStatusCallback " + b(a) + " " + b(c)); }
    private static void batteryStatusSupportCallback(boolean a, boolean c) { log("batteryStatusSupportCallback " + b(a) + " " + b(c)); }
    private static void hwBtnSupportCallback(int a, boolean c, boolean d, boolean e, boolean f, boolean g, boolean h, boolean i) { log("hwBtnSupportCallback " + a + " " + b(c) + b(d) + b(e) + b(f) + b(g) + b(h) + b(i)); }
    private static void hwBtnStatusSupportCallback(int a, boolean c, boolean d, boolean e, boolean f, boolean g, boolean h, boolean i) { log("hwBtnStatusSupportCallback " + a + " " + b(c) + b(d) + b(e) + b(f) + b(g) + b(h) + b(i)); }
    private static void hwBtnEnabledCallback(int a, boolean c, boolean d, boolean e, boolean f, boolean g, boolean h, boolean i) { log("hwBtnEnabledCallback " + a + " " + b(c) + b(d) + b(e) + b(f) + b(g) + b(h) + b(i)); }
    private static void sbxProfileInfoCallback(int a, int c) { log("sbxProfileInfoCallback " + a + " " + c); }
    private static void sbxProfileDataCallback(int a) { log("sbxProfileDataCallback " + a); }
    private static void btAutoConnectCallback(int a) { log("btAutoConnectCallback " + a); }
    private static void devicefwStringCallback(int[] a) { log("devicefwStringCallback " + iarr(a)); }
    private static void profileInfoRecFirstCallback(int a, int c, int d, boolean e, int f, boolean g, boolean h, int i, boolean j) { log("profileInfoRecFirstCallback " + a + " " + c + " " + d + " " + b(e) + " " + f + " " + b(g) + " " + b(h) + " " + i + " " + b(j)); }
    private static void profileInfoRestCallback(int a, int c, boolean d, int e, boolean f, boolean g, int h, boolean i) { log("profileInfoRestCallback " + a + " " + c + " " + b(d) + " " + e + " " + b(f) + " " + b(g) + " " + h + " " + b(i)); }
    private static void activeProfileRecCallback(int a, boolean c) { log("activeProfileRecCallback " + a + " " + b(c)); }
    private static void activeProfileMegaCallback(int a, boolean c) { log("activeProfileMegaCallback " + a + " " + b(c)); }
    private static void voicePromptCtrlCallback(int a) { log("voicePromptCtrlCallback " + a); }

    // ---- helpers ----
    private static String b(boolean v) { return v ? "1" : "0"; }
    private static String hex(byte[] a) {
        if (a == null) return "null";
        StringBuilder sb = new StringBuilder();
        for (byte x : a) sb.append(String.format("%02x", x & 0xff));
        return sb.toString();
    }
    private static String ints(int[] a) {
        if (a == null) return "null";
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < a.length; i++) { if (i > 0) sb.append(','); sb.append(a[i]); }
        return sb.toString();
    }
    // ---- D5 typed-fidelity helpers (decode callbacks only) ----
    // Distinguish null vs empty, report length, and expose raw float bits so
    // signedness / width / NaN are unambiguous in the frozen capture.
    private static String flt(float v) {
        return v + "(bits=" + String.format("0x%08x", Float.floatToRawIntBits(v)) + ")";
    }
    private static String arr(byte[] a) {
        if (a == null) return "null";
        return "[len=" + a.length + "]" + hex(a);
    }
    private static String iarr(int[] a) {
        if (a == null) return "null";
        return "[len=" + a.length + "]" + ints(a);
    }
    private static byte[] unhex(String s) {
        s = s.trim();
        byte[] out = new byte[s.length() / 2];
        for (int i = 0; i < out.length; i++)
            out[i] = (byte) Integer.parseInt(s.substring(i * 2, i * 2 + 2), 16);
        return out;
    }
    private static void enc(String name, String argspec, byte[] out) {
        System.out.println("ENC " + name + " " + argspec + " = " + hex(out));
    }

    // setMalcolmParam with explicit arrays; prints frame bytes plus the two
    // output ints the stock wrapper writes back into e on success.
    private static void smp(String label, int[] a, int[] b, float[] c, int d) {
        int[] e = new int[] { 0, 0 };
        byte[] out = setMalcolmParam(a, b, c, d, e);
        System.out.println("ENC setMalcolmParam " + label + " = " + hex(out)
                           + " e=" + e[0] + "," + e[1]);
    }

    // n params all (group, sub, val); isolates the group-splitting math.
    private static void smpRep(String label, int group, int sub, float val, int n, int d) {
        int[] a = new int[n]; int[] b = new int[n]; float[] c = new float[n];
        for (int i = 0; i < n; i++) { a[i] = group; b[i] = sub; c[i] = val; }
        smp(label, a, b, c, d);
    }

    public static void main(String[] args) throws Exception {
        String lib = args[0];
        String mode = args.length > 1 ? args[1] : "enc";
        System.load(lib);

        if (mode.equals("enc")) {
            // ===== Canonical encode vectors =====
            // No-arg builders (constant frames):
            enc("cancelFileTransfer", "-", cancelFileTransfer());
            enc("commitSettings", "-", commitSettings());
            enc("getActiveProfileMega", "-", getActiveProfileMega());
            enc("getActiveProfileRec", "-", getActiveProfileRec());
            enc("getBatteryLevel", "-", getBatteryLevel());
            enc("getBatteryLevelSupport", "-", getBatteryLevelSupport());
            enc("getBatteryStatus", "-", getBatteryStatus());
            enc("getBatteryStatusSupport", "-", getBatteryStatusSupport());
            enc("getBtAutoConnect", "-", getBtAutoConnect());
            enc("getDeviceFwString", "-", getDeviceFwString());
            enc("getGeneralInfo", "-", getGeneralInfo());
            enc("getHwBtn", "-", getHwBtn());
            enc("getHwBtnStatusSupport", "-", getHwBtnStatusSupport());
            enc("getHwBtnSupport", "-", getHwBtnSupport());
            enc("getMaxPayloadSize", "-", getMaxPayloadSize());
            enc("getProfileInfoRec", "-", getProfileInfoRec());
            enc("getVoicePromptCtrl", "-", getVoicePromptCtrl());
            enc("hwBtnEnabled", "-", hwBtnEnabled());
            enc("releaseControl", "-", releaseControl());
            enc("resetFactoryDefault", "-", resetFactoryDefault());
            System.out.println("INT getFileTransferMaxDataSize - = " + getFileTransferMaxDataSize());

            // One-int builders with a 0..255 domain: min-1/min/min+1/rep/max-1/max/max+1.
            int[] byteDom = { -1, 0, 1, 0x40, 0xfe, 0xff, 0x100, 0x101 };
            for (int v : byteDom) enc("getAudioLvl", "" + v, getAudioLvl(v));
            for (int v : byteDom) enc("getFwInfo", "" + v, getFwInfo(v));
            for (int v : byteDom) enc("setActiveProfileMega", "" + v, setActiveProfileMega(v));
            for (int v : byteDom) enc("setActiveProfileMegaVoicePreview", "" + v, setActiveProfileMegaVoicePreview(v));
            for (int v : byteDom) enc("setActiveProfileRec", "" + v, setActiveProfileRec(v));
            for (int v : byteDom) enc("setActiveProfileRecVoicePreview", "" + v, setActiveProfileRecVoicePreview(v));

            // Enumerated small domains, with out-of-range neighbours.
            int[] btDom = { -1, 0, 1, 2 };
            for (int v : btDom) enc("setBtAutoConnect", "" + v, setBtAutoConnect(v));
            int[] vpDom = { -1, 0, 1, 2, 3 };
            for (int v : vpDom) enc("setVoicePromptCtrl", "" + v, setVoicePromptCtrl(v));

            // setTime: no validation; full int32 round-trip incl. sign boundaries.
            int[] times = { 0, 1, 0x100, 0x12345678, 0x7fffffff, 0x80000000, 0xffffffff };
            for (int v : times) enc("setTime", String.format("%08x", v), setTime(v));

            // setHwBtn(id,val): id in 1..20, val in {0,1}. Sweep each axis past its bound.
            int[] hwId = { 0, 1, 2, 19, 20, 21 };
            for (int id : hwId) enc("setHwBtn", id + ",1", setHwBtn(id, 1));
            int[] hwVal = { -1, 0, 1, 2 };
            for (int val : hwVal) enc("setHwBtn", "1," + val, setHwBtn(1, val));
            enc("setHwBtn", "10,0", setHwBtn(10, 0));

            // setFileSize(a,b): only a==1 emits; b is an LE32 size.
            int[] fsA = { 0, 1, 2 };
            for (int a : fsA) enc("setFileSize", a + ",2", setFileSize(a, 2));
            int[] fsB = { 0, 1, 0x100, 0x12345678, 0xffffffff };
            for (int b : fsB) enc("setFileSize", "1," + b, setFileSize(1, b));

            // getFileDataBlk(data,len,flag): len in 1..253, flag -> off 0x80/0x81.
            byte[] blk = new byte[0x100];
            for (int i = 0; i < blk.length; i++) blk[i] = (byte) i;
            int[] blkLen = { 0, 1, 2, 0x40, 0xfc, 0xfd, 0xfe };
            for (int L : blkLen) enc("getFileDataBlk", L + ",false", getFileDataBlk(blk, L, false));
            enc("getFileDataBlk", "0x40,true", getFileDataBlk(blk, 0x40, true));
            enc("getFileDataBlk", "0x01,true", getFileDataBlk(blk, 1, true));

            // ===== setMalcolmParam: marshalling, validator domain, grouping =====
            // Unconditionally-accepted param (group 0x97 sub 2 ignores the float):
            // group-splitting across count and the group-size divisor d.
            smpRep("grp_n0", 0x97, 2, 0.0f, 0, 0);     // count 0 -> empty via success path
            smpRep("grp_n1_d0", 0x97, 2, 0.0f, 1, 0);  // gs=2: one remainder group of 1
            smpRep("grp_n2_d0", 0x97, 2, 0.0f, 2, 0);  // gs=2: one full group of 2
            smpRep("grp_n3_d0", 0x97, 2, 0.0f, 3, 0);  // gs=2: full(2)+rem(1)
            smpRep("grp_n5_d0", 0x97, 2, 0.0f, 5, 0);  // gs=2: full,full,rem(1)
            smpRep("grp_n5_d16", 0x97, 2, 0.0f, 5, 16);// gs=(16-1)/6=2
            smpRep("grp_n7_d43", 0x97, 2, 0.0f, 7, 43);// gs=(43-1)/6=7: one full group of 7
            smpRep("grp_n8_d43", 0x97, 2, 0.0f, 8, 43);// gs=7: full(7)+rem(1)
            smpRep("grp_n1_d259", 0x97, 2, 0.0f, 1, 259); // gs clamps to 42

            // Group-ID membership boundary (validator param_1):
            smp("gid_0x48", new int[]{0x48}, new int[]{1}, new float[]{0.0f}, 0); // reject 0x18
            smp("gid_0x49", new int[]{0x49}, new int[]{1}, new float[]{10.0f}, 0);// accept [1,20]
            smp("gid_0x49_sub0", new int[]{0x49}, new int[]{0}, new float[]{10.0f}, 0); // 0x19
            smp("gid_0x4a", new int[]{0x4a}, new int[]{1}, new float[]{0.0f}, 0); // reject 0x18
            smp("gid_0x8f", new int[]{0x8f}, new int[]{0}, new float[]{1.0f}, 0); // accept {0,1}
            smp("gid_0x8f_sub1", new int[]{0x8f}, new int[]{1}, new float[]{1.0f}, 0); // 0x19
            smp("gid_0x95", new int[]{0x95}, new int[]{1}, new float[]{5.0f}, 0);  // accept [0,11.66]
            smp("gid_0x96", new int[]{0x96}, new int[]{0x1e}, new float[]{7.0f}, 0); // accept any
            smp("gid_0x97", new int[]{0x97}, new int[]{2}, new float[]{0.0f}, 0);  // accept any
            smp("gid_0x98", new int[]{0x98}, new int[]{0}, new float[]{0.0f}, 0);  // reject 0x18
            smp("gid_0x195", new int[]{0x195}, new int[]{1}, new float[]{0.0f}, 0);// full-int check -> 0x18

            // Sub-index boundary within group 0x97:
            int[] sub97 = { 0, 1, 2, 8, 9 };
            for (int s : sub97) smp("sub97_" + s, new int[]{0x97}, new int[]{s}, new float[]{0.0f}, 0);

            // Float-range boundary, continuous range (group 0x95 sub 1 -> [0, 11.66]):
            float[] rng = { -0.01f, 0.0f, 0.01f, 5.0f, 11.65f, 11.66f, 11.67f };
            for (int i = 0; i < rng.length; i++)
                smp("f95s1_" + i, new int[]{0x95}, new int[]{1}, new float[]{rng[i]}, 0);
            // Float-range boundary, boolean field (group 0x95 sub 0 -> {0.0,1.0}):
            float[] bl = { -1.0f, 0.0f, 0.5f, 1.0f, 2.0f };
            for (int i = 0; i < bl.length; i++)
                smp("f95s0_" + i, new int[]{0x95}, new int[]{0}, new float[]{bl[i]}, 0);

            // Mixed multi-param: valid + one invalid -> whole call rejected.
            smp("mix_reject", new int[]{0x97, 0x48}, new int[]{2, 0}, new float[]{0.0f, 0.0f}, 0);
            // Length mismatch between the three arrays -> empty (marshalling guard).
            smp("len_mismatch", new int[]{0x97, 0x97}, new int[]{2}, new float[]{0.0f}, 0);

            // ===== Statefulness controls =====
            // (1) same call repeated:
            for (int i = 0; i < 3; i++) enc("STATE_repeat_getGeneralInfo", "#" + i, getGeneralInfo());
            for (int i = 0; i < 3; i++) enc("STATE_repeat_setTime", "#" + i, setTime(0x12345678));
            for (int i = 0; i < 3; i++) smpRep("STATE_repeat_smp#" + i, 0x97, 2, 0.0f, 3, 0);
            // (2) unrelated calls interleaved around a fixed probe:
            enc("STATE_inter_probe", "a", getGeneralInfo());
            setTime(5);
            enc("STATE_inter_probe", "b", getGeneralInfo());
            smpRep("STATE_inter_smp", 0x97, 2, 0.0f, 3, 0);
            enc("STATE_inter_probe", "c", getGeneralInfo());
        } else if (mode.equals("dec")) {
            // Decode corpus: one hex frame per line in args[2].
            BufferedReader r = new BufferedReader(new FileReader(args[2]));
            String line;
            while ((line = r.readLine()) != null) {
                line = line.trim();
                if (line.isEmpty() || line.startsWith("#")) continue;
                // Optional "hex|N" overrides the length argument (N may differ from
                // the array length) to probe whether decode() uses the explicit len
                // parameter or the array's own length.
                int bar = line.indexOf('|');
                String hex = bar < 0 ? line : line.substring(0, bar);
                byte[] f = unhex(hex);
                int len = bar < 0 ? f.length : Integer.parseInt(line.substring(bar + 1).trim());
                CB.clear();
                boolean ret = decode(f, len);
                System.out.println("DEC " + line + " (arr=" + f.length + ",len=" + len
                                   + ") -> ret=" + b(ret));
                for (String c : CB) System.out.println("  CB " + c);
            }
            r.close();
        } else if (mode.equals("seq")) {
            // Stream/framing corpus: blank-line-separated GROUPS. Within a group
            // each non-comment line is one decode() call sharing a single callback
            // window (CB cleared only at group start), so cross-call buffering /
            // reassembly is directly observable. Callbacks are attributed to the
            // call that produced them.
            BufferedReader r = new BufferedReader(new FileReader(args[2]));
            String line;
            int grp = 0, call = 0;
            boolean open = false;
            while ((line = r.readLine()) != null) {
                line = line.trim();
                if (line.startsWith("#")) { System.out.println(line); continue; }
                if (line.isEmpty()) {
                    if (open) { System.out.println("--- end group " + grp); open = false; }
                    continue;
                }
                if (!open) { grp++; call = 0; CB.clear(); open = true;
                             System.out.println("=== group " + grp); }
                call++;
                byte[] f = unhex(line);
                int before = CB.size();
                boolean ret = decode(f, f.length);
                System.out.println("CALL " + grp + "." + call + " " + line
                                   + " (len=" + f.length + ") -> ret=" + b(ret));
                for (int i = before; i < CB.size(); i++)
                    System.out.println("    CB " + CB.get(i));
                if (CB.size() == before)
                    System.out.println("    (no callback)");
            }
            if (open) System.out.println("--- end group " + grp);
            r.close();
        }
        System.out.println("DONE");
    }
}
