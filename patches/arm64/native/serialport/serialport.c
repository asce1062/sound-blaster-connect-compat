/**
 * @file serialport.c
 * @brief libserialport_jni.so: portable reimplementation of the stock serial
 *        port JNI library.
 *
 * Behaviour-faithful rebuild of the stock 32-bit libserialport_jni.so shipped
 * in SBConnect_v1.04.02.apk, for any ABI the project builds (see
 * docs/research/arm64/RE.md and docs/technical/NATIVE_LIBRARIES.md). It is a
 * thin JNI wrapper over a POSIX tty, the same contract as the public
 * android-serialport-api, bound to com.creative.serialport.SerialPort via
 * RegisterNatives:
 *
 *     private native FileDescriptor open(String path, int baudrate);
 *     public  native int            close();
 *
 * The stock lib keeps a single process-global fd: open() stores it and also
 * returns a java.io.FileDescriptor wrapping it; close() shuts that global fd.
 * Reproduced here so every ABI behaves as the 32-bit original does. Because the
 * descriptor is global, the library supports one open port at a time.
 */
#include <jni.h>
#include <android/log.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <termios.h>

#define TAG "serialport_jni"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

/* Single global descriptor, matching the stock lib: -1 when no port is open.
 * It is not synchronized, and open() overwrites it without closing a
 * descriptor from an earlier open(), as the stock library does. */
static int s_fd = -1;

/*
 * Map a decimal baud rate to its CBAUD encoding (low speed bits, plus the
 * CBAUDEX 0x1000 flag for the extended rates). Returns -1 for an unsupported
 * rate, which aborts the open exactly as the original did.
 */
static int baud_to_cbaud(int baud) {
    switch (baud) {
        case 0:       return 0x0;
        case 50:      return 0x1;
        case 75:      return 0x2;
        case 110:     return 0x3;
        case 134:     return 0x4;
        case 150:     return 0x5;
        case 200:     return 0x6;
        case 300:     return 0x7;
        case 600:     return 0x8;
        case 1200:    return 0x9;
        case 1800:    return 0xa;
        case 2400:    return 0xb;
        case 4800:    return 0xc;
        case 9600:    return 0xd;
        case 19200:   return 0xe;
        case 38400:   return 0xf;    /* B38400 */
        case 57600:   return 0x1001;
        case 115200:  return 0x1002;
        case 230400:  return 0x1003;
        case 460800:  return 0x1004;
        case 500000:  return 0x1005;
        case 576000:  return 0x1006;
        case 921600:  return 0x1007;
        case 1000000: return 0x1008;
        case 1152000: return 0x1009;
        case 1500000: return 0x100a;
        case 2000000: return 0x100b;
        case 2500000: return 0x100c;
        case 3000000: return 0x100d;
        case 3500000: return 0x100e;
        case 4000000: return 0x100f;
        default:      return -1;
    }
}

/**
 * @brief Java `private native FileDescriptor open(String path, int baudrate)`.
 *
 * Opens `path` read/write, switches the line to raw 8N1 at `baudrate`, stores
 * the descriptor in the process-global s_fd and returns a java.io.FileDescriptor
 * holding the same descriptor number. A previously open descriptor is not
 * closed first.
 *
 * @param env       JNI environment.
 * @param thiz      The SerialPort instance (unused).
 * @param path      Device path, for example a tty node. Must not be null.
 * @param baudrate  Decimal baud rate. Only the rates listed in baud_to_cbaud
 *                  are accepted.
 * @return          A new FileDescriptor, or null when the baud rate is not
 *                  supported, the device cannot be opened, or the termios get or
 *                  set fails. On a termios failure the descriptor is closed and
 *                  s_fd is reset to -1. Failures are logged with the
 *                  "serialport_jni" tag and raise no Java exception.
 */
static jobject native_open(JNIEnv *env, jobject thiz, jstring path, jint baudrate) {
    (void) thiz;

    int speed = baud_to_cbaud(baudrate);
    if (speed < 0) {
        LOGE("Invalid baudrate");
        return NULL;
    }

    const char *file = (*env)->GetStringUTFChars(env, path, NULL);
    LOGD("open: %s", file);
    /* Flag word 0x1102 as in the stock lib: O_RDWR (0x2) | O_NOCTTY (0x100) |
     * 0x1000 (O_DSYNC in the Linux generic ABI). The raw value is kept; it is
     * the same on arm and arm64 bionic. */
    s_fd = open(file, 0x1102);
    LOGD("open fd = %d", s_fd);
    (*env)->ReleaseStringUTFChars(env, path, file);

    if (s_fd == -1) {
        LOGE("Cannot open port, baud %d", baudrate);
        return NULL;
    }

    struct termios cfg;
    if (ioctl(s_fd, TCGETS, &cfg) != 0) {
        LOGE("TCGETS failed");
        close(s_fd);
        s_fd = -1;
        return NULL;
    }

    /* Raw 8N1 mode. The masks are the stock library's raw values, kept as
     * literals. In Linux termios terms:
     *   c_iflag &= ~(IGNBRK | BRKINT | PARMRK | ISTRIP | INLCR | IGNCR | ICRNL | IXON)
     *   c_oflag &= ~OPOST
     *   c_lflag &= ~(ECHO | ECHONL | ICANON | ISIG | IEXTEN)
     *   c_cflag  = (c_cflag & ~(CBAUD | CBAUDEX | CSIZE | CSTOPB | PARENB))
     *              | CS8 | <speed from baud_to_cbaud>
     * This is the same flag set as cfmakeraw() clears; c_cc is not modified.
     * c_cflag keeps CREAD, PARODD, HUPCL and CLOCAL as read from the device. */
    cfg.c_iflag &= 0xfffffa14u;
    cfg.c_oflag &= 0xfffffffeu;
    cfg.c_lflag &= 0xffff7fb4u;
    cfg.c_cflag  = (cfg.c_cflag & 0xffffeec0u) | 0x30u | (unsigned) speed;

    if (ioctl(s_fd, TCSETS, &cfg) != 0) {
        LOGE("TCSETS failed");
        close(s_fd);
        s_fd = -1;
        return NULL;
    }

    jclass fdClass = (*env)->FindClass(env, "java/io/FileDescriptor");
    jmethodID ctor = (*env)->GetMethodID(env, fdClass, "<init>", "()V");
    jfieldID descField = (*env)->GetFieldID(env, fdClass, "descriptor", "I");
    jobject fdObj = (*env)->NewObject(env, fdClass, ctor);
    (*env)->SetIntField(env, fdObj, descField, s_fd);
    return fdObj;
}

/**
 * @brief Java `public native int close()`.
 *
 * Closes the process-global descriptor if one is open and resets it to -1.
 * Preserved from stock: the return value is always 1, whether or not a port was
 * open and whether or not close(2) succeeded, and the Java FileDescriptor
 * returned by open() is not invalidated.
 *
 * @param env   JNI environment (unused).
 * @param thiz  The SerialPort instance (unused).
 * @return      Always 1.
 */
static jint native_close(JNIEnv *env, jobject thiz) {
    (void) env;
    (void) thiz;
    if (s_fd >= 0) {
        close(s_fd);
        s_fd = -1;
    }
    return 1;
}

/* Methods registered on com.creative.serialport.SerialPort by JNI_OnLoad. */
static const JNINativeMethod kMethods[] = {
    { "open",  "(Ljava/lang/String;I)Ljava/io/FileDescriptor;", (void *) native_open },
    { "close", "()I",                                           (void *) native_close },
};

/**
 * @brief Library load hook: registers open() and close() on
 *        com.creative.serialport.SerialPort.
 *
 * @param vm        The Java VM.
 * @param reserved  Unused.
 * @return          JNI_VERSION_1_6 on success, or -1 when GetEnv, FindClass or
 *                  RegisterNatives fails.
 */
JNIEXPORT jint JNI_OnLoad(JavaVM *vm, void *reserved) {
    (void) reserved;
    JNIEnv *env = NULL;
    if ((*vm)->GetEnv(vm, (void **) &env, JNI_VERSION_1_6) != JNI_OK) {
        return -1;
    }
    jclass cls = (*env)->FindClass(env, "com/creative/serialport/SerialPort");
    if (cls == NULL) {
        return -1;
    }
    if ((*env)->RegisterNatives(env, cls, kMethods,
                                sizeof(kMethods) / sizeof(kMethods[0])) < 0) {
        return -1;
    }
    return JNI_VERSION_1_6;
}
