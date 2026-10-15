/*
 * libserialport_jni.so - arm64-v8a reimplementation.
 *
 * Behaviour-faithful rebuild of the stock 32-bit libserialport_jni.so shipped
 * in SBConnect_v1.04.02.apk, recovered by decompiling native_open/native_close/
 * JNI_OnLoad (docs/arm64/RE.md). It is a thin JNI wrapper over a POSIX tty, the
 * same contract as the public android-serialport-api, bound to
 * com.creative.serialport.SerialPort via RegisterNatives:
 *
 *     private native FileDescriptor open(String path, int baudrate);
 *     public  native int            close();
 *
 * The stock lib keeps a single process-global fd: open() stores it and also
 * returns a java.io.FileDescriptor wrapping it; close() shuts that global fd.
 * Reproduced here so arm64 behaves exactly as the 32-bit original.
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

/* Single global descriptor, matching the stock lib. */
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
        case 38400:   return 0xf;    /* the Katana's rate (0x9600) */
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

static jobject native_open(JNIEnv *env, jobject thiz, jstring path, jint baudrate) {
    (void) thiz;

    int speed = baud_to_cbaud(baudrate);
    if (speed < 0) {
        LOGE("Invalid baudrate");
        return NULL;
    }

    const char *file = (*env)->GetStringUTFChars(env, path, NULL);
    LOGD("open: %s", file);
    /* O_RDWR | O_NOCTTY | 0x1000 - stock flag word 0x1102, identical on arm/arm64 bionic. */
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

    /* Raw-mode flag masks, exactly as the stock lib set them. */
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

static jint native_close(JNIEnv *env, jobject thiz) {
    (void) env;
    (void) thiz;
    if (s_fd >= 0) {
        close(s_fd);
        s_fd = -1;
    }
    return 1;
}

static const JNINativeMethod kMethods[] = {
    { "open",  "(Ljava/lang/String;I)Ljava/io/FileDescriptor;", (void *) native_open },
    { "close", "()I",                                           (void *) native_close },
};

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
