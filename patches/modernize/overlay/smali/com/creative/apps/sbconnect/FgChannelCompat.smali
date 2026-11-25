.class public Lcom/creative/apps/sbconnect/FgChannelCompat;
.super Ljava/lang/Object;

# Foreground-service notification channel shim (modernize patch).
#
# The stock app builds its MainService notification with the channel-less
# NotificationCompat.Builder(Context) constructor and never creates a channel.
# On API 26+ a channel-less notification is invalid, and on API 33+ posting it
# through startForeground() throws
# RemoteServiceException$CannotPostForegroundServiceNotificationException
# ("invalid channel for service notification: Notification(channel=null ...)"),
# which kills the process.
#
# ensure() is called right after each MainService Builder is constructed: it
# stamps the builder with a fixed channel id (the bundled support
# NotificationCompat.Builder.setChannelId mutates in place) and, on API 26+,
# registers that channel with the framework NotificationManager. Channel
# creation is idempotent.


# direct methods

# ensure(context, builder): sets the channel id "sbconnect_fg" on the builder
# on every API level. On API 26 (0x1a) and above it also creates the channel
# named "Sound Blaster Connect" with importance 2 (IMPORTANCE_LOW). The builder
# is mutated in place and nothing is returned.
.method public static ensure(Landroid/content/Context;Landroid/support/v4/app/NotificationCompat$Builder;)V
    .locals 5

    const-string v0, "sbconnect_fg"

    invoke-virtual {p1, v0}, Landroid/support/v4/app/NotificationCompat$Builder;->setChannelId(Ljava/lang/String;)Landroid/support/v4/app/NotificationCompat$Builder;

    sget v1, Landroid/os/Build$VERSION;->SDK_INT:I

    const/16 v2, 0x1a

    if-lt v1, v2, :cond_0

    const-string v1, "notification"

    invoke-virtual {p0, v1}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;

    move-result-object v1

    check-cast v1, Landroid/app/NotificationManager;

    new-instance v2, Landroid/app/NotificationChannel;

    const-string v3, "Sound Blaster Connect"

    const/4 v4, 0x2

    invoke-direct {v2, v0, v3, v4}, Landroid/app/NotificationChannel;-><init>(Ljava/lang/String;Ljava/lang/CharSequence;I)V

    invoke-virtual {v1, v2}, Landroid/app/NotificationManager;->createNotificationChannel(Landroid/app/NotificationChannel;)V

    :cond_0
    return-void
.end method
