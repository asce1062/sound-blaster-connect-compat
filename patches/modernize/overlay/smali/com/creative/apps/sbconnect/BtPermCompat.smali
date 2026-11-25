.class public Lcom/creative/apps/sbconnect/BtPermCompat;
.super Ljava/lang/Object;

# Android 12 (API 31) Nearby Devices runtime-permission shim (modernize patch).
#
# From API 31 the legacy install-time BLUETOOTH / BLUETOOTH_ADMIN permissions
# (capped at maxSdkVersion 30 in the manifest) no longer cover Bluetooth use.
# The app must hold the runtime BLUETOOTH_CONNECT (bonded-device enumeration and
# the SPP/RFCOMM connection) and BLUETOOTH_SCAN (device discovery) permissions,
# which the stock app predates and never requests, so on a fresh install every
# Bluetooth call throws SecurityException and no device is ever found. The old
# app ran before these existed, so below API 31 the legacy permissions apply and
# this shim stays out of the way.
#
# onResult(), from MainActivity.onRequestPermissionsResult, drives a sequential
# permission chain. The stock app's onCreate already requests its own runtime
# permissions (camera, mic, location) under request code 0x457, and Android drops a
# second requestPermissions while a dialog sequence is still pending, so each later
# request must wait for the previous result rather than fire from onCreate. The
# chain is:
#   0x457 (stock batch) returns -> ensure() requests BLUETOOTH_CONNECT/SCAN (0x42c)
#   0x42c (Bluetooth)   returns -> askNotif() requests POST_NOTIFICATIONS (0x42d)
#   0x42d (notifications) returns -> resume()
# so the user sees the dialogs back to back: location/mic, then Nearby devices, then
# notifications. ensure() is a no-op below API 31 and returns silently when
# BLUETOOTH_CONNECT is already held; askNotif() is a no-op below API 33 and when
# POST_NOTIFICATIONS is already held, and returns whether it fired a request so the
# chain either waits for 0x42d or falls straight through to resume(). resume() re-runs
# the normal initialization path once via Activity.recreate() when BLUETOOTH_CONNECT
# is granted (otherwise it leaves the app alive and idle rather than retrying into
# repeated SecurityExceptions). ok() is the gate the connection manager's discovery
# and bonded-enumeration entry points consult so they no-op instead of throwing until
# the permission is in hand. POST_NOTIFICATIONS only lets the app post its own
# notifications (foreground-service/media); it gates nothing. No CtProtocol or native
# code is touched; this is platform permission plumbing only.


# direct methods

# ensure(activity): requests BLUETOOTH_CONNECT and BLUETOOTH_SCAN under request
# code 0x42c. No-op below API 31 (0x1f) and when BLUETOOTH_CONNECT is held.
.method public static ensure(Landroid/app/Activity;)V
    .locals 3

    sget v0, Landroid/os/Build$VERSION;->SDK_INT:I

    const/16 v1, 0x1f

    if-ge v0, v1, :cond_0

    return-void

    :cond_0
    const-string v0, "android.permission.BLUETOOTH_CONNECT"

    invoke-virtual {p0, v0}, Landroid/content/Context;->checkSelfPermission(Ljava/lang/String;)I

    move-result v0

    if-nez v0, :cond_1

    return-void

    :cond_1
    const/4 v0, 0x2

    new-array v0, v0, [Ljava/lang/String;

    const/4 v1, 0x0

    const-string v2, "android.permission.BLUETOOTH_CONNECT"

    aput-object v2, v0, v1

    const/4 v1, 0x1

    const-string v2, "android.permission.BLUETOOTH_SCAN"

    aput-object v2, v0, v1

    const/16 v1, 0x42c

    invoke-virtual {p0, v0, v1}, Landroid/app/Activity;->requestPermissions([Ljava/lang/String;I)V

    return-void
.end method

# ok(context): true below API 31, otherwise true only while BLUETOOTH_CONNECT is
# granted. Only BLUETOOTH_CONNECT is consulted, not BLUETOOTH_SCAN.
.method public static ok(Landroid/content/Context;)Z
    .locals 2

    sget v0, Landroid/os/Build$VERSION;->SDK_INT:I

    const/16 v1, 0x1f

    if-ge v0, v1, :cond_0

    const/4 v0, 0x1

    return v0

    :cond_0
    const-string v0, "android.permission.BLUETOOTH_CONNECT"

    invoke-virtual {p0, v0}, Landroid/content/Context;->checkSelfPermission(Ljava/lang/String;)I

    move-result v0

    if-nez v0, :cond_1

    const/4 v0, 0x1

    return v0

    :cond_1
    const/4 v0, 0x0

    return v0
.end method

# onResult(activity, requestCode, permissions, grantResults): advances the chain
# described in the header. Request codes other than 0x457, 0x42c and 0x42d are
# ignored. The permissions and grantResults arguments are not read; the grants
# are re-checked with checkSelfPermission.
.method public static onResult(Landroid/app/Activity;I[Ljava/lang/String;[I)V
    .locals 1

    const/16 v0, 0x457

    if-ne p1, v0, :cond_bt

    # stock permission batch (camera/mic/location) finished; the request channel
    # is free, so request the Bluetooth permissions now.
    invoke-static {p0}, Lcom/creative/apps/sbconnect/BtPermCompat;->ensure(Landroid/app/Activity;)V

    return-void

    :cond_bt
    const/16 v0, 0x42c

    if-ne p1, v0, :cond_notif

    # Bluetooth result in; request notifications next (API 33+). If askNotif fired
    # a request, wait for its result; otherwise fall through and resume.
    invoke-static {p0}, Lcom/creative/apps/sbconnect/BtPermCompat;->askNotif(Landroid/app/Activity;)Z

    move-result v0

    if-eqz v0, :cond_fin

    return-void

    :cond_notif
    const/16 v0, 0x42d

    if-eq p1, v0, :cond_fin

    return-void

    :cond_fin
    invoke-static {p0}, Lcom/creative/apps/sbconnect/BtPermCompat;->resume(Landroid/app/Activity;)V

    return-void
.end method

# askNotif(activity): requests POST_NOTIFICATIONS under request code 0x42d and
# returns true if a request was fired. Returns false, without requesting, below
# API 33 (0x21) or when the permission is already held.
.method public static askNotif(Landroid/app/Activity;)Z
    .locals 3

    sget v0, Landroid/os/Build$VERSION;->SDK_INT:I

    const/16 v1, 0x21

    if-ge v0, v1, :cond_0

    const/4 v0, 0x0

    return v0

    :cond_0
    const-string v0, "android.permission.POST_NOTIFICATIONS"

    invoke-virtual {p0, v0}, Landroid/content/Context;->checkSelfPermission(Ljava/lang/String;)I

    move-result v0

    if-nez v0, :cond_1

    const/4 v0, 0x0

    return v0

    :cond_1
    const/4 v0, 0x1

    new-array v0, v0, [Ljava/lang/String;

    const/4 v1, 0x0

    const-string v2, "android.permission.POST_NOTIFICATIONS"

    aput-object v2, v0, v1

    const/16 v1, 0x42d

    invoke-virtual {p0, v0, v1}, Landroid/app/Activity;->requestPermissions([Ljava/lang/String;I)V

    const/4 v0, 0x1

    return v0
.end method

# resume(activity): recreates the activity when BLUETOOTH_CONNECT is held, so
# the stock initialization path runs again with the permission in place. Does
# nothing otherwise.
.method public static resume(Landroid/app/Activity;)V
    .locals 1

    const-string v0, "android.permission.BLUETOOTH_CONNECT"

    invoke-virtual {p0, v0}, Landroid/content/Context;->checkSelfPermission(Ljava/lang/String;)I

    move-result v0

    if-eqz v0, :cond_0

    return-void

    :cond_0
    invoke-virtual {p0}, Landroid/app/Activity;->recreate()V

    return-void
.end method
