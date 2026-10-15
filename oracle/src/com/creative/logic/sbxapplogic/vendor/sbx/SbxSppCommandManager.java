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
    private static void dataAckCallback(int a, int c, byte[] d) { log("dataAckCallback " + a + " " + c + " " + hex(d)); }
    private static void obsoleteAckCallback(int a, int c) { log("obsoleteAckCallback " + a + " " + c); }
    private static void pendingAckCallback(int a, int c, int d) { log("pendingAckCallback " + a + " " + c + " " + d); }
    private static void fileAckCallback(int a, int c, int d) { log("fileAckCallback " + a + " " + c + " " + d); }
    private static void deviceInfoCallback(int a, int c) { log("deviceInfoCallback " + a + " " + c); }
    private static void fwInfoCallback(int a, int c, int d, int e, int f) { log("fwInfoCallback " + a + " " + c + " " + d + " " + e + " " + f); }
    private static void maxPlsCallback(int a) { log("maxPlsCallback " + a); }
    private static void hwBtnCallback(int a, boolean c, boolean d, boolean e, boolean f, boolean g, boolean h, boolean i) { log("hwBtnCallback " + a + " " + b(c) + b(d) + b(e) + b(f) + b(g) + b(h) + b(i)); }
    private static void audioCtrlCallback(int a, boolean c) { log("audioCtrlCallback " + a + " " + b(c)); }
    private static void audioLvlCallback(int a, float c, int d) { log("audioLvlCallback " + a + " " + c + " " + d); }
    private static synchronized void audioLvlRangeCallback(int a, float c, float d, float e, int f, int g, int h) { log("audioLvlRangeCallback " + a + " " + c + " " + d + " " + e + " " + f + " " + g + " " + h); }
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
    private static void devicefwStringCallback(int[] a) { log("devicefwStringCallback " + ints(a)); }
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

    public static void main(String[] args) throws Exception {
        String lib = args[0];
        String mode = args.length > 1 ? args[1] : "enc";
        System.load(lib);

        if (mode.equals("enc")) {
            // Deterministic encode vectors. No-arg builders:
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

            // Single-int builders, swept across representative values:
            int[] vals = { 0, 1, 2, 3, 0x7f, 0x80, 0xff };
            for (int v : vals) enc("getAudioLvl", "" + v, getAudioLvl(v));
            for (int v : vals) enc("getFwInfo", "" + v, getFwInfo(v));
            for (int v : vals) enc("setActiveProfileMega", "" + v, setActiveProfileMega(v));
            for (int v : vals) enc("setActiveProfileMegaVoicePreview", "" + v, setActiveProfileMegaVoicePreview(v));
            for (int v : vals) enc("setActiveProfileRec", "" + v, setActiveProfileRec(v));
            for (int v : vals) enc("setActiveProfileRecVoicePreview", "" + v, setActiveProfileRecVoicePreview(v));
            for (int v : vals) enc("setBtAutoConnect", "" + v, setBtAutoConnect(v));
            for (int v : vals) enc("setVoicePromptCtrl", "" + v, setVoicePromptCtrl(v));
            int[] times = { 0, 1, 0x100, 0x12345678, 0x7fffffff };
            for (int v : times) enc("setTime", String.format("%08x", v), setTime(v));

            // Two-int builders:
            int[][] pairs = { {0,0},{1,2},{0x80,3},{0xff,0xff},{0x1234,0x40} };
            for (int[] p : pairs) enc("setFileSize", p[0]+","+p[1], setFileSize(p[0], p[1]));
            for (int[] p : pairs) enc("setHwBtn", p[0]+","+p[1], setHwBtn(p[0], p[1]));

            // getFileDataBlk(data, len, bool): fixed data block.
            byte[] blk = new byte[0x40];
            for (int i = 0; i < blk.length; i++) blk[i] = (byte) i;
            enc("getFileDataBlk", "0x40,false", getFileDataBlk(blk, 0x40, false));
            enc("getFileDataBlk", "0x40,true", getFileDataBlk(blk, 0x40, true));
            enc("getFileDataBlk", "0x10,false", getFileDataBlk(blk, 0x10, false));

            // setMalcolmParam(int[] a, int[] b, float[] c, int d, int[] e): small fixed vectors.
            enc("setMalcolmParam", "v1",
                setMalcolmParam(new int[]{1,2}, new int[]{3,4}, new float[]{1.5f,-2.0f}, 2, new int[]{5,6}));
            enc("setMalcolmParam", "v2",
                setMalcolmParam(new int[]{0}, new int[]{0}, new float[]{0.0f}, 1, new int[]{0}));
        } else if (mode.equals("dec")) {
            // Decode corpus: one hex frame per line in args[2].
            BufferedReader r = new BufferedReader(new FileReader(args[2]));
            String line;
            while ((line = r.readLine()) != null) {
                line = line.trim();
                if (line.isEmpty() || line.startsWith("#")) continue;
                byte[] f = unhex(line);
                CB.clear();
                boolean ret = decode(f, f.length);
                System.out.println("DEC " + line + " -> ret=" + b(ret));
                for (String c : CB) System.out.println("  CB " + c);
            }
            r.close();
        }
        System.out.println("DONE");
    }
}
