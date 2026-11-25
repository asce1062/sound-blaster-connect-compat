.class public Lcom/creative/apps/sbconnect/RcvCompat;
.super Ljava/lang/Object;

# Runtime-receiver export shim (modernize patch).
#
# Android 14 (API 34) requires Context.registerReceiver() to pass
# RECEIVER_EXPORTED or RECEIVER_NOT_EXPORTED whenever the receiver is not
# registered exclusively for protected system broadcasts. An app targeting
# API 34+ that calls the two-arg registerReceiver on a 34+ device gets
# SecurityException ("One of RECEIVER_EXPORTED or RECEIVER_NOT_EXPORTED should
# be specified ...") and the calling activity or service crashes. The stock app
# registers many receivers with the two-arg call. Platforms below API 34 do not
# perform this check.
#
# Every stock two-arg Context.registerReceiver call is redirected here. On
# API 34+ this passes RECEIVER_EXPORTED (0x2); below 34 it calls the original
# two-arg form unchanged. EXPORTED, not NOT_EXPORTED: before Android 13 every
# dynamically registered receiver was implicitly exported, so EXPORTED
# reproduces the stock app's exact exposure and cannot silently stop a receiver
# that depends on broadcasts from other apps (media/music metadata, system
# state). The three-arg registerReceiver(receiver, filter, int) overload exists
# only from API 26, so the pre-34 branch keeps the two-arg call for the full
# minSdk range.


# direct methods

# register(context, receiver, filter): drop-in replacement for the two-arg
# Context.registerReceiver. Returns the same sticky Intent (or null) that
# registerReceiver returns. 0x22 is API 34; the flag value 0x2 is
# RECEIVER_EXPORTED.
.method public static register(Landroid/content/Context;Landroid/content/BroadcastReceiver;Landroid/content/IntentFilter;)Landroid/content/Intent;
    .locals 2

    sget v0, Landroid/os/Build$VERSION;->SDK_INT:I

    const/16 v1, 0x22

    if-lt v0, v1, :cond_0

    const/4 v1, 0x2

    invoke-virtual {p0, p1, p2, v1}, Landroid/content/Context;->registerReceiver(Landroid/content/BroadcastReceiver;Landroid/content/IntentFilter;I)Landroid/content/Intent;

    move-result-object v0

    return-object v0

    :cond_0
    invoke-virtual {p0, p1, p2}, Landroid/content/Context;->registerReceiver(Landroid/content/BroadcastReceiver;Landroid/content/IntentFilter;)Landroid/content/Intent;

    move-result-object v0

    return-object v0
.end method
