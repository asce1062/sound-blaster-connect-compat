# modernize/patch.cmake: raise the target API level and apply the Android
# 12/13/14 behavior changes that follow.
#
# Runs with ${TREE} set to the staged (fresh) copy of the pristine decompiled/
# tree. Edits are in place (apktool.yml, AndroidManifest.xml, smali), and the
# overlay tree patches/modernize/overlay/ is copied onto the tree first by
# apply_patch.cmake. The overlay supplies the smali helper classes
# FgChannelCompat and RcvCompat; PermissionLifecycle is compiled from
# patches/modernize/java/ and copied onto the tree the same way.
#
# Method and field names in the smali anchors below (for example MainService.a(),
# MainActivity.D(), SbxConnectionManager.f() and the field j) are the obfuscated
# names of stock Sound Blaster Connect 1.04.02. The patch applies only to that
# exact release, and every anchor asserts its expected occurrence count.
#
# What the patch does, with the component inventory in
# docs/research/android/FINDINGS.md as the reference:
#
#   * targetSdkVersion: 26 -> 34 in apktool.yml.
#   * exported (>=31): explicit android:exported on every filtered component
#     that lacked it. Without it the package does not install on 31+.
#     MainActivity stays exported; MainReceiver, MainService,
#     MediaButtonReceiver, AppMeasurementReceiver, the bundled app-invite
#     PreviewActivity and LocalMusicRemoteControllerService are not exported
#     (docs/research/android/RECEIVER_AUDIT.md).
#   * LocalMusicRemoteControllerService is no longer a notification listener.
#   * uses-library (>=28): org.apache.http.legacy and android.test.base are
#     re-added as optional libraries (required=false) because the default
#     classpath no longer carries them.
#   * PendingIntent FLAG_IMMUTABLE (>=31): all 23 PendingIntent construction
#     sites. Without a mutability flag, getActivity/getService/getBroadcast/
#     getActivities throws IllegalArgumentException at runtime on 31+.
#   * Bluetooth permissions (>=31): BLUETOOTH_SCAN (neverForLocation) and
#     BLUETOOTH_CONNECT are declared; the legacy BLUETOOTH / BLUETOOTH_ADMIN
#     are capped at maxSdkVersion 30.
#   * POST_NOTIFICATIONS (>=33) is declared.
#   * Stock permissions with no first-party use are removed:
#     MEDIA_CONTENT_CONTROL, SYSTEM_ALERT_WINDOW, c2dm RECEIVE and
#     WRITE_EXTERNAL_STORAGE.
#   * foregroundServiceType + FOREGROUND_SERVICE* (>=34): MainService is a
#     connectedDevice foreground service (2-arg startForeground, so it adopts
#     the manifest type). Its prerequisite is met by normal permissions, so
#     the service starts before the Bluetooth runtime permissions are granted.
#   * Foreground-notification channel (>=26): FgChannelCompat.ensure() is
#     called after each channel-less NotificationCompat.Builder constructor in
#     MainService.
#   * Receiver registration (>=34): every two-arg registerReceiver call in the
#     smali tree is redirected to RcvCompat.register (96 sites).
#   * Runtime-permission lifecycle: PermissionLifecycle owns every request
#     (once-per-install launch sequence, feature-scoped prompts with
#     explanations and a settings path) and gates the Bluetooth entry points
#     until Nearby devices is granted. The stock request batch is replaced.
#   * Stock hidden-API calls: BluetoothHeadset.connect is skipped without
#     MODIFY_PHONE_STATE on 31+; the device name uses the public getAlias()
#     on 30+.
#   * Notification-listener prompt: removed.
#
# CtProtocol and the native libraries are untouched by this patch; the arm64
# variant adds its own libraries (patches/arm64/).

set(final_target "34")

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

# Count non-overlapping literal occurrences of <needle> in <haystack>.
function(_sbc_count haystack needle out)
    set(n 0)
    set(s "${haystack}")
    string(LENGTH "${needle}" nl)
    if(nl EQUAL 0)
        message(FATAL_ERROR "modernize: empty needle")
    endif()
    string(FIND "${s}" "${needle}" pos)
    while(NOT pos EQUAL -1)
        math(EXPR n "${n}+1")
        math(EXPR cut "${pos}+${nl}")
        string(SUBSTRING "${s}" ${cut} -1 s)
        string(FIND "${s}" "${needle}" pos)
    endwhile()
    set(${out}
        ${n}
        PARENT_SCOPE)
endfunction()

# Literal find-and-replace in <path>, asserting the needle occurs exactly
# <expected> times. Fails loudly if the stock text drifts.
function(_sbc_sub path needle replacement expected)
    if(NOT EXISTS "${path}")
        message(FATAL_ERROR "modernize: file missing: ${path}")
    endif()
    file(READ "${path}" c)
    _sbc_count("${c}" "${needle}" got)
    if(NOT got EQUAL expected)
        message(
            FATAL_ERROR
                "modernize: anchor found ${got} time(s), expected ${expected}, in ${path}\n"
                "  anchor: ${needle}")
    endif()
    string(
        REPLACE "${needle}"
                "${replacement}"
                c
                "${c}")
    file(WRITE "${path}" "${c}")
endfunction()

# Force FLAG_IMMUTABLE (0x04000000) into the flags register of a PendingIntent
# factory call by loading the combined value immediately before the invoke.
# <value> is the stock flags OR 0x04000000 (0x4000000 when the stock flags
# were 0). <reg> is the last register operand of <invoke> (the flags arg).
function(_sbc_pi relfile invoke reg value count)
    _sbc_sub("${TREE}/${relfile}" "${invoke}"
             "const ${reg}, ${value}\n\n    ${invoke}" ${count})
endfunction()

# Redirect every two-arg registerReceiver invoke under the app's smali to the
# RcvCompat.register shim (API 34 receiver-export requirement). The call is made
# through four static types (Context, support FragmentActivity, MainActivity,
# MainService), all Context subtypes, so the match is any declaring class whose
# two-arg registerReceiver returns Intent. The register tuple is preserved
# verbatim (receiver target, receiver, filter map 1:1 onto the static params),
# only the opcode and method ref change. RcvCompat.smali itself is skipped so
# its own registerReceiver calls are not rewritten into self-recursion.
# <expected> is the total stock site count across the tree, asserted so drift
# fails loudly.
function(_sbc_receiver_export_tree expected)
    # Constant suffix shared by every two-arg site (the declaring class varies);
    # counted literally with _sbc_count so embedded ';' is not list-split.
    set(needle
        ";->registerReceiver(Landroid/content/BroadcastReceiver;Landroid/content/IntentFilter;)Landroid/content/Intent;"
    )
    set(ref_rx
        "L[^;]*;->registerReceiver\\(Landroid/content/BroadcastReceiver;Landroid/content/IntentFilter;\\)Landroid/content/Intent;"
    )
    # Whole app code, every dex (smali, smali_classes2, ...), every package: the
    # stock app and its bundled libraries (ibluz under smali/c, support classes)
    # all make the two-arg call, and every one that runs throws on 34+.
    file(GLOB_RECURSE smalis "${TREE}/*.smali")
    set(total 0)
    foreach(f ${smalis})
        get_filename_component(bn "${f}" NAME)
        if(bn STREQUAL "RcvCompat.smali")
            continue()
        endif()
        file(READ "${f}" c)
        _sbc_count("${c}" "${needle}" n)
        if(n GREATER 0)
            string(
                REGEX
                REPLACE
                    "invoke-virtual ({[^}]*}), ${ref_rx}"
                    "invoke-static \\1, Lcom/creative/apps/sbconnect/RcvCompat;->register(Landroid/content/Context;Landroid/content/BroadcastReceiver;Landroid/content/IntentFilter;)Landroid/content/Intent;"
                    c
                    "${c}")
            _sbc_count("${c}" "${needle}" left)
            if(NOT left EQUAL 0)
                message(
                    FATAL_ERROR
                        "modernize: ${left} registerReceiver site(s) survived rewrite in ${f}"
                )
            endif()
            file(WRITE "${f}" "${c}")
            math(EXPR total "${total}+${n}")
        endif()
    endforeach()
    if(NOT total EQUAL expected)
        message(
            FATAL_ERROR
                "modernize: rewrote ${total} registerReceiver site(s), expected ${expected}"
        )
    endif()
endfunction()

# ---------------------------------------------------------------------------
# targetSdkVersion 26 -> ${final_target} (apktool writes the yml value into
# the built manifest).
# ---------------------------------------------------------------------------

set(yml "${TREE}/apktool.yml")
_sbc_sub("${yml}" "targetSdkVersion: 26" "targetSdkVersion: ${final_target}" 1)
message(STATUS "modernize: targetSdkVersion 26 -> ${final_target}")

# ---------------------------------------------------------------------------
# AndroidManifest.xml
# ---------------------------------------------------------------------------

set(mf "${TREE}/AndroidManifest.xml")

# --- >=31: explicit android:exported on every filtered component -----------
# API 31+ requires an explicit android:exported on any filtered component.
# Only MainActivity (the launcher) needs outside access. MainReceiver,
# MainService, and the media-button receiver are reached only by protected
# system broadcasts, same-app intents, and the app's own PendingIntents, never
# by a third-party app, so they are not exported
# (docs/research/android/RECEIVER_AUDIT.md, findings R1-R3). AppMeasurementReceiver is fed only by
# in-package broadcasts, so false.
_sbc_sub("${mf}" "android:name=\"com.creative.apps.sbconnect.MainActivity\""
         "android:exported=\"true\" android:name=\"com.creative.apps.sbconnect.MainActivity\""
         1)
_sbc_sub("${mf}" "android:name=\"com.creative.apps.sbconnect.MainReceiver\""
         "android:exported=\"false\" android:name=\"com.creative.apps.sbconnect.MainReceiver\""
         1)
# LocalMusicRemoteControllerService: no longer a notification listener. The
# stock declaration makes it bindable by the system as a
# NotificationListenerService (BIND_NOTIFICATION_LISTENER_SERVICE, the
# NotificationListenerService action), which lets the user grant it access to
# every notification. The service's onNotificationPosted is empty; the access
# fed only the Now Playing metadata of other players through
# RemoteController, and the prompt for it is already suppressed below. The
# app binds the service itself with an explicit-package intent
# (LocalMusicManager.i(), action BIND_RC_CONTROL_SERVICE), which an
# unexported service still accepts, so that action stays and the listener
# action and permission go (docs/research/android/PERMISSION_LIFECYCLE.md).
_sbc_sub("${mf}"
         "<service android:label=\"@string/app_name\" android:name=\"com.creative.logic.sbxapplogic.LocalMusicRemoteControllerService\" android:permission=\"android.permission.BIND_NOTIFICATION_LISTENER_SERVICE\">\n            <intent-filter>\n                <action android:name=\"android.service.notification.NotificationListenerService\"/>\n                <action android:name=\"com.creative.logic.sbxapplogic.BIND_RC_CONTROL_SERVICE\"/>"
         "<service android:exported=\"false\" android:label=\"@string/app_name\" android:name=\"com.creative.logic.sbxapplogic.LocalMusicRemoteControllerService\">\n            <intent-filter>\n                <action android:name=\"com.creative.logic.sbxapplogic.BIND_RC_CONTROL_SERVICE\"/>"
         1)
# The bundled Google app-invite preview activity is exported with a filter,
# and no first-party code uses app invites. Not exported.
_sbc_sub("${mf}"
         "<activity android:exported=\"true\" android:name=\"com.google.android.gms.appinvite.PreviewActivity\""
         "<activity android:exported=\"false\" android:name=\"com.google.android.gms.appinvite.PreviewActivity\""
         1)
_sbc_sub("${mf}"
         "android:name=\"android.support.v4.media.session.MediaButtonReceiver\""
         "android:exported=\"false\" android:name=\"android.support.v4.media.session.MediaButtonReceiver\""
         1)
_sbc_sub("${mf}"
         "android:name=\"com.google.android.gms.measurement.AppMeasurementReceiver\""
         "android:exported=\"false\" android:name=\"com.google.android.gms.measurement.AppMeasurementReceiver\""
         1)
# MainService carries a stock android:exported="true"; it is started only by
# explicit in-package intents and the app's own notification PendingIntents, so
# flip it to false as well (docs/research/android/RECEIVER_AUDIT.md, R2). Anchored on the unique
# label="MainService".
_sbc_sub("${mf}"
         "android:exported=\"true\" android:label=\"MainService\""
         "android:exported=\"false\" android:label=\"MainService\""
         1)

# --- >=31 Bluetooth + >=33 notifications + >=34 foreground service perms ---
# Cap the legacy permissions at 30 and add the runtime-requested replacements.
_sbc_sub("${mf}" "<uses-permission android:name=\"android.permission.BLUETOOTH\"/>"
         "<uses-permission android:name=\"android.permission.BLUETOOTH\" android:maxSdkVersion=\"30\"/>"
         1)
# BLUETOOTH_SCAN carries neverForLocation: the app derives no physical
# location from Bluetooth scan results. Discovered devices fill the device
# list and the connection; the only Bluetooth-derived value found leaving the
# device is the connected model name as an analytics event label
# (docs/research/android/PERMISSION_LIFECYCLE.md). With the flag, discovery on
# API 31+ needs no location grant, and the platform withholds beacon-type
# results from the app. ACCESS_FINE_LOCATION stays for Wi-Fi speaker setup
# (Wi-Fi scan results and the current network) and for Bluetooth discovery
# on API 23 to 30, where the platform requires it.
_sbc_sub("${mf}"
         "<uses-permission android:name=\"android.permission.BLUETOOTH_ADMIN\"/>"
         "<uses-permission android:name=\"android.permission.BLUETOOTH_ADMIN\" android:maxSdkVersion=\"30\"/>\n    <uses-permission android:name=\"android.permission.BLUETOOTH_SCAN\" android:usesPermissionFlags=\"neverForLocation\"/>\n    <uses-permission android:name=\"android.permission.BLUETOOTH_CONNECT\"/>\n    <uses-permission android:name=\"android.permission.POST_NOTIFICATIONS\"/>\n    <uses-permission android:name=\"android.permission.FOREGROUND_SERVICE\"/>\n    <uses-permission android:name=\"android.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE\"/>"
         1)

# --- stock permissions with no first-party use -----------------------------
#   MEDIA_CONTENT_CONTROL   signature|privileged; never granted to this app.
#   SYSTEM_ALERT_WINDOW     no overlay window is created.
#   c2dm RECEIVE            no first-party code registers for GCM messages.
#   WRITE_EXTERNAL_STORAGE  no first-party code writes shared storage; on
#                           API 33+ the platform no longer grants it.
foreach(perm "android.permission.MEDIA_CONTENT_CONTROL"
             "android.permission.SYSTEM_ALERT_WINDOW"
             "com.google.android.c2dm.permission.RECEIVE"
             "android.permission.WRITE_EXTERNAL_STORAGE")
    _sbc_sub("${mf}" "    <uses-permission android:name=\"${perm}\"/>\n" "" 1)
endforeach()

# --- >=34: MainService foreground service type -----------------------------
# connectedDevice: the service holds the link to the speaker (the SPP
# session and its media session); it plays no audio. Its prerequisite is met
# by the normal CHANGE_NETWORK_STATE and NFC permissions, so the service can
# start before the Nearby devices grant, and the type may start from
# BOOT_COMPLETED on API 35+, where mediaPlayback may not.
_sbc_sub("${mf}" "android:name=\"com.creative.apps.sbconnect.MainService\">"
         "android:foregroundServiceType=\"connectedDevice\" android:name=\"com.creative.apps.sbconnect.MainService\">"
         1)

# --- >=28: classpath libraries removed from the default bootclasspath ------
# API 28 dropped two class families the app references at runtime from the
# default classpath; both survive on device as optional shared libraries, so
# re-add each as a uses-library (required=false so install still succeeds
# where it is absent) as the first children of <application>:
#   org.apache.http.legacy - JSONParser uses DefaultHttpClient, so
#     MainActivity$ParseJsonTask throws NoClassDefFoundError without the
#     library under the raised target.
#   android.test.base - holds junit.framework.* / junit.runner.*. Utils.b()
#     calls junit.framework.Assert as an inline runtime assertion, reached from
#     SbxModifiableProfileMainFragment$ProfileListAdapter.onBindViewHolder (the
#     "See All" / "Blaster Experience" preset lists), so binding a row throws
#     NoClassDefFoundError: junit.framework.Assert and kills the activity.
_sbc_sub("${mf}"
         "android:name=\"com.creative.apps.sbconnect.SbxApplication\" android:theme=\"@style/AppTheme\">"
         "android:name=\"com.creative.apps.sbconnect.SbxApplication\" android:theme=\"@style/AppTheme\">\n        <uses-library android:name=\"org.apache.http.legacy\" android:required=\"false\"/>\n        <uses-library android:name=\"android.test.base\" android:required=\"false\"/>"
         1)

message(STATUS "modernize: manifest exported + permissions + foregroundServiceType + apache-http-legacy + android-test-base")

# ---------------------------------------------------------------------------
# PendingIntent FLAG_IMMUTABLE (>=31), all 23 construction sites.
#
# <value> = stock flags | 0x04000000:
#   0x0        -> 0x4000000    0x08000000 (UPDATE_CURRENT) -> 0xc000000
#   0x10000000 (CANCEL_CURRENT) -> 0x14000000
#   0x40000000 (ONE_SHOT)       -> 0x44000000
# Loading the combined value into the flags register just before the call also
# supersedes any earlier const into that register. Where the flags register is
# the reused requestCode register (value 0), the requestCode becomes the same
# constant, which only affects PendingIntent dedup identity.
# ---------------------------------------------------------------------------

# app's own code
#
# MainService.a() cannot take the generic _sbc_pi const-into-flags-register
# treatment: both getActivity sites name v11 as the flags operand, and v11 is
# the method's shared 0 constant, reused after the calls as the int index into
# SbxProfileMainCards.a() (feeding ArrayList.get) and as the boolean for
# NotificationCompat.setAutoCancel(). A const v11, 0x4000000 corrupts those,
# and ArrayList.get() throws IndexOutOfBounds at index 0x4000000. The method
# already holds 0x04000000 in v14 (loaded for Intent.addFlags), so both sites
# take their flags from v14 and leave v11 = 0 intact. requestCode is unchanged.
_sbc_sub("${TREE}/smali/com/creative/apps/sbconnect/MainService.smali"
         "invoke-static {p0, v11, v1, v11}, Landroid/app/PendingIntent;->getActivity(Landroid/content/Context;ILandroid/content/Intent;I)Landroid/app/PendingIntent;"
         "invoke-static {p0, v11, v1, v14}, Landroid/app/PendingIntent;->getActivity(Landroid/content/Context;ILandroid/content/Intent;I)Landroid/app/PendingIntent;"
         1)
_sbc_sub("${TREE}/smali/com/creative/apps/sbconnect/MainService.smali"
         "invoke-static {p0, v12, v2, v11}, Landroid/app/PendingIntent;->getActivity(Landroid/content/Context;ILandroid/content/Intent;I)Landroid/app/PendingIntent;"
         "invoke-static {p0, v12, v2, v14}, Landroid/app/PendingIntent;->getActivity(Landroid/content/Context;ILandroid/content/Intent;I)Landroid/app/PendingIntent;"
         1)
_sbc_pi("smali/com/creative/apps/sbconnect/MainService.smali"
        "invoke-static {p0, v1, v0, v2}, Landroid/app/PendingIntent;->getService(Landroid/content/Context;ILandroid/content/Intent;I)Landroid/app/PendingIntent;"
        v2 0x4000000 1)
_sbc_pi("smali/com/creative/logic/sbxapplogic/LocalMusicManager.smali"
        "invoke-static {v1, v2, v0, v3}, Landroid/app/PendingIntent;->getBroadcast(Landroid/content/Context;ILandroid/content/Intent;I)Landroid/app/PendingIntent;"
        v3 0x4000000 1)

# bundled androidx / support libraries
_sbc_pi("smali/android/support/v4/app/TaskStackBuilder\$TaskStackBuilderApi16Impl.smali"
        "invoke-static {p1, p3, p2, p4, p5}, Landroid/app/PendingIntent;->getActivities(Landroid/content/Context;I[Landroid/content/Intent;ILandroid/os/Bundle;)Landroid/app/PendingIntent;"
        p4 0x4000000 1)
_sbc_pi("smali/android/support/v4/app/TaskStackBuilder\$TaskStackBuilderBaseImpl.smali"
        "invoke-static {p1, p3, p2, p4}, Landroid/app/PendingIntent;->getActivities(Landroid/content/Context;I[Landroid/content/Intent;I)Landroid/app/PendingIntent;"
        p4 0x4000000 1)
_sbc_pi("smali/android/support/v4/media/session/MediaButtonReceiver.smali"
        "invoke-static {p0, v1, v0, v4}, Landroid/app/PendingIntent;->getBroadcast(Landroid/content/Context;ILandroid/content/Intent;I)Landroid/app/PendingIntent;"
        v4 0x4000000 1)
_sbc_pi("smali/android/support/v4/media/session/MediaSessionCompat.smali"
        "invoke-static {p1, v2, v0, v2}, Landroid/app/PendingIntent;->getBroadcast(Landroid/content/Context;ILandroid/content/Intent;I)Landroid/app/PendingIntent;"
        v2 0x4000000 1)
_sbc_pi("smali/android/support/v7/media/RemotePlaybackClient.smali"
        "invoke-static {p1, v3, v0, v3}, Landroid/app/PendingIntent;->getBroadcast(Landroid/content/Context;ILandroid/content/Intent;I)Landroid/app/PendingIntent;"
        v3 0x4000000 2)
_sbc_pi("smali/android/support/v7/widget/SearchView.smali"
        "invoke-static {v1, v3, v0, v4}, Landroid/app/PendingIntent;->getActivity(Landroid/content/Context;ILandroid/content/Intent;I)Landroid/app/PendingIntent;"
        v4 0x44000000 1)

# bundled Google Play services
_sbc_pi("smali/com/google/android/gms/analytics/internal/zzv.smali"
        "invoke-static {v1, v3, v0, v3}, Landroid/app/PendingIntent;->getBroadcast(Landroid/content/Context;ILandroid/content/Intent;I)Landroid/app/PendingIntent;"
        v3 0x4000000 1)
_sbc_pi("smali/com/google/android/gms/auth/api/credentials/internal/zzd.smali"
        "invoke-static {v1, v2, v0, v3}, Landroid/app/PendingIntent;->getActivity(Landroid/content/Context;ILandroid/content/Intent;I)Landroid/app/PendingIntent;"
        v3 0x14000000 1)
_sbc_pi("smali/com/google/android/gms/cast/CastRemoteDisplayLocalService.smali"
        "invoke-static {p0, v1, v0, v2}, Landroid/app/PendingIntent;->getBroadcast(Landroid/content/Context;ILandroid/content/Intent;I)Landroid/app/PendingIntent;"
        v2 0x14000000 1)
_sbc_pi("smali/com/google/android/gms/common/api/internal/zzd.smali"
        "invoke-static {v0, v1, v2, v3}, Landroid/app/PendingIntent;->getActivity(Landroid/content/Context;ILandroid/content/Intent;I)Landroid/app/PendingIntent;"
        v3 0xc000000 1)
_sbc_pi("smali/com/google/android/gms/common/zzc.smali"
        "invoke-static {p1, p3, v0, v1}, Landroid/app/PendingIntent;->getActivity(Landroid/content/Context;ILandroid/content/Intent;I)Landroid/app/PendingIntent;"
        v1 0x14000000 1)
_sbc_pi("smali/com/google/android/gms/gcm/GoogleCloudMessaging.smali"
        "invoke-static {v1, v2, v0, v3}, Landroid/app/PendingIntent;->getBroadcast(Landroid/content/Context;ILandroid/content/Intent;I)Landroid/app/PendingIntent;"
        v3 0x4000000 1)
_sbc_pi("smali_classes2/com/google/android/gms/gcm/GcmNetworkManager.smali"
        "invoke-static {v0, v2, v1, v2}, Landroid/app/PendingIntent;->getBroadcast(Landroid/content/Context;ILandroid/content/Intent;I)Landroid/app/PendingIntent;"
        v2 0x4000000 1)
_sbc_pi("smali_classes2/com/google/android/gms/gcm/zzb.smali"
        "invoke-static {v0, v2, v1, v3}, Landroid/app/PendingIntent;->getActivity(Landroid/content/Context;ILandroid/content/Intent;I)Landroid/app/PendingIntent;"
        v3 0x44000000 1)
_sbc_pi("smali_classes2/com/google/android/gms/gcm/zzb.smali"
        "invoke-static {v1, v2, v0, v3}, Landroid/app/PendingIntent;->getService(Landroid/content/Context;ILandroid/content/Intent;I)Landroid/app/PendingIntent;"
        v3 0x44000000 2)
_sbc_pi("smali_classes2/com/google/android/gms/iid/zzc.smali"
        "invoke-static {v1, v2, v0, v3}, Landroid/app/PendingIntent;->getBroadcast(Landroid/content/Context;ILandroid/content/Intent;I)Landroid/app/PendingIntent;"
        v3 0x4000000 1)
_sbc_pi("smali_classes2/com/google/android/gms/measurement/internal/zzag.smali"
        "invoke-static {v1, v3, v0, v3}, Landroid/app/PendingIntent;->getBroadcast(Landroid/content/Context;ILandroid/content/Intent;I)Landroid/app/PendingIntent;"
        v3 0x4000000 1)

message(STATUS "modernize: PendingIntent FLAG_IMMUTABLE applied (23 sites)")

# ---------------------------------------------------------------------------
# >=26 foreground-service notification channel. MainService.a() builds its
# notification with the channel-less NotificationCompat.Builder(Context) ctor
# (two sites) and the app creates no channel, so startForeground() posts a
# channel=null notification. On API 33+ that throws
# CannotPostForegroundServiceNotificationException and kills the process.
# FgChannelCompat.ensure() (modernize overlay) stamps the builder with a
# channel id and registers the channel; call it right after each ctor. p0 is
# the MainService (Context); the builder is v3 at the first site, v5 at the
# second.
# ---------------------------------------------------------------------------

_sbc_sub("${TREE}/smali/com/creative/apps/sbconnect/MainService.smali"
         "invoke-direct {v3, p0}, Landroid/support/v4/app/NotificationCompat\$Builder;-><init>(Landroid/content/Context;)V"
         "invoke-direct {v3, p0}, Landroid/support/v4/app/NotificationCompat\$Builder;-><init>(Landroid/content/Context;)V\n\n    invoke-static {p0, v3}, Lcom/creative/apps/sbconnect/FgChannelCompat;->ensure(Landroid/content/Context;Landroid/support/v4/app/NotificationCompat\$Builder;)V"
         1)
_sbc_sub("${TREE}/smali/com/creative/apps/sbconnect/MainService.smali"
         "invoke-direct {v5, p0}, Landroid/support/v4/app/NotificationCompat\$Builder;-><init>(Landroid/content/Context;)V"
         "invoke-direct {v5, p0}, Landroid/support/v4/app/NotificationCompat\$Builder;-><init>(Landroid/content/Context;)V\n\n    invoke-static {p0, v5}, Lcom/creative/apps/sbconnect/FgChannelCompat;->ensure(Landroid/content/Context;Landroid/support/v4/app/NotificationCompat\$Builder;)V"
         1)

message(STATUS "modernize: foreground-service notification channel shim wired (2 sites)")

# ---------------------------------------------------------------------------
# >=34 runtime receiver export. registerReceiver() for a non-system broadcast
# must pass RECEIVER_EXPORTED/RECEIVER_NOT_EXPORTED under target 34+; the
# two-arg call throws SecurityException on a 34+ device. Call sites exist in
# the app's activities and fragments and inside the bundled ibluz Bluetooth
# library (smali/c), so every one must be redirected. Redirect every two-arg
# registerReceiver call, in every dex and package (the stock app, the ibluz
# library, and support classes), to the RcvCompat.register shim (modernize
# overlay), which passes RECEIVER_EXPORTED on 34+ and calls the two-arg form
# below 34. 96 sites across the whole smali tree.
# ---------------------------------------------------------------------------

_sbc_receiver_export_tree(96)

message(STATUS "modernize: registerReceiver export shim wired (96 sites, whole smali tree)")

# ---------------------------------------------------------------------------
# Runtime-permission lifecycle (PermissionLifecycle, compiled from
# patches/modernize/java/). docs/research/android/PERMISSION_LIFECYCLE.md has
# the inventory this wiring follows.
#
#   * SbxApplication.onCreate: PermissionLifecycle.init(context).
#   * MainActivity.onCreate: the stock request batch D() (camera, storage,
#     microphone, location, on every creation) is replaced by onLaunch, which
#     asks once per install for Nearby devices (API 31+) or location (API 23
#     to 30, required there for Bluetooth discovery), then notifications
#     (API 33+), and never on a recreated activity.
#   * MainActivity.onRequestPermissionsResult: every result goes to onResult.
#   * MainActivity.onResume: onResume recreates the activity once when
#     Nearby devices was granted after creation (dialog or system settings).
#   * Feature prompts: tapping a device in the Connect list (Nearby devices),
#     opening room calibration (microphone) and opening Wi-Fi speaker setup
#     (location). Each explains first and offers the request, or system
#     settings once the system no longer shows its dialog.
#   * Entry gates on the Bluetooth utility and connection-manager methods:
#     without the grant they return their "no device" value (null, false or
#     nothing) instead of calling the platform.
# ---------------------------------------------------------------------------
set(pl "Lcom/creative/apps/sbconnect/PermissionLifecycle;")
set(ma "${TREE}/smali/com/creative/apps/sbconnect/MainActivity.smali")
set(cm "${TREE}/smali/com/creative/logic/sbxapplogic/SbxConnectionManager.smali")
set(bu "${TREE}/smali/com/creative/logic/sbxapplogic/BluetoothUtils.smali")

# Insert a gate at the entry of <method> (its full .method line) in <path>,
# right after ".locals <n>" and before any monitor-enter. <check> is a
# PermissionLifecycle predicate (btOk, scanOk, headsetConnectOk); <ret> is
# the value returned when it fails: void, false or null. Uses v0, so <n> >= 1.
function(_sbc_gate path method n check ret)
    if(n LESS 1)
        message(FATAL_ERROR "modernize: gate needs a local register: ${method}")
    endif()
    if(ret STREQUAL "void")
        set(r "return-void")
    elseif(ret STREQUAL "false")
        set(r "const/4 v0, 0x0\n\n    return v0")
    elseif(ret STREQUAL "null")
        set(r "const/4 v0, 0x0\n\n    return-object v0")
    else()
        message(FATAL_ERROR "modernize: unknown gate return '${ret}'")
    endif()
    _sbc_sub("${path}" "${method}\n    .locals ${n}\n"
             "${method}\n    .locals ${n}\n\n    invoke-static {}, ${pl}->${check}()Z\n\n    move-result v0\n\n    if-nez v0, :sbc_gate_ok\n\n    ${r}\n\n    :sbc_gate_ok\n"
             1)
endfunction()

# --- application and activity lifecycle ------------------------------------
_sbc_sub("${TREE}/smali/com/creative/apps/sbconnect/SbxApplication.smali"
         "invoke-super {p0}, Landroid/support/multidex/MultiDexApplication;->onCreate()V"
         "invoke-super {p0}, Landroid/support/multidex/MultiDexApplication;->onCreate()V\n\n    invoke-static {p0}, ${pl}->init(Landroid/content/Context;)V"
         1)
_sbc_sub("${ma}"
         "invoke-direct {p0}, Lcom/creative/apps/sbconnect/MainActivity;->D()V"
         "invoke-static {p0, p1}, ${pl}->onLaunch(Landroid/app/Activity;Landroid/os/Bundle;)V"
         1)
_sbc_sub("${ma}"
         "invoke-super {p0, p1, p2, p3}, Landroid/support/v7/app/AppCompatActivity;->onRequestPermissionsResult(I[Ljava/lang/String;[I)V"
         "invoke-super {p0, p1, p2, p3}, Landroid/support/v7/app/AppCompatActivity;->onRequestPermissionsResult(I[Ljava/lang/String;[I)V\n\n    invoke-static {p0, p1, p2, p3}, ${pl}->onResult(Landroid/app/Activity;I[Ljava/lang/String;[I)V"
         1)
_sbc_sub("${ma}"
         ".method protected onResume()V\n    .locals 7\n"
         ".method protected onResume()V\n    .locals 7\n\n    invoke-static {p0}, ${pl}->onResume(Landroid/app/Activity;)V\n"
         1)

# --- feature prompts ---------------------------------------------------------
# Connect list, Bluetooth partition (0): explain and stop when Nearby devices
# is missing. v0 is reloaded by the stock code right after.
_sbc_sub("${TREE}/smali/com/creative/apps/sbconnect/ConnectionFragment.smali"
         "    if-nez v0, :cond_6\n\n    :try_start_0\n    iget-object v0, p0, Lcom/creative/apps/sbconnect/ConnectionFragment;->k:Ljava/util/ArrayList;"
         "    if-nez v0, :cond_6\n\n    invoke-virtual {p0}, Landroid/support/v4/app/Fragment;->getActivity()Landroid/support/v4/app/FragmentActivity;\n\n    move-result-object v0\n\n    invoke-static {v0}, ${pl}->requireBluetooth(Landroid/app/Activity;)Z\n\n    move-result v0\n\n    if-nez v0, :sbc_bt_ok\n\n    return-void\n\n    :sbc_bt_ok\n    :try_start_0\n    iget-object v0, p0, Lcom/creative/apps/sbconnect/ConnectionFragment;->k:Ljava/util/ArrayList;"
         1)
# Connect screen, room calibration and Wi-Fi speaker setup: at the entry of
# onResume. With Nearby devices denied the connect screen's list is empty, so
# its tap check above is unreachable; opening the screen offers the retry.
_sbc_sub("${TREE}/smali/com/creative/apps/sbconnect/ConnectionFragment.smali"
         ".method public onResume()V\n    .locals 10\n"
         ".method public onResume()V\n    .locals 10\n\n    invoke-virtual {p0}, Landroid/support/v4/app/Fragment;->getActivity()Landroid/support/v4/app/FragmentActivity;\n\n    move-result-object v0\n\n    invoke-static {p0, v0}, ${pl}->requireBluetoothScreen(Ljava/lang/Object;Landroid/app/Activity;)V\n"
         1)
_sbc_sub("${TREE}/smali/com/creative/apps/sbconnect/CalibrationFragment.smali"
         ".method public onResume()V\n    .locals 2\n"
         ".method public onResume()V\n    .locals 2\n\n    invoke-virtual {p0}, Landroid/support/v4/app/Fragment;->getActivity()Landroid/support/v4/app/FragmentActivity;\n\n    move-result-object v0\n\n    invoke-static {p0, v0}, ${pl}->requireMicrophone(Ljava/lang/Object;Landroid/app/Activity;)V\n"
         1)
_sbc_sub("${TREE}/smali/com/creative/apps/sbconnect/WifiSetupFragment.smali"
         ".method public onResume()V\n    .locals 5\n"
         ".method public onResume()V\n    .locals 5\n\n    invoke-virtual {p0}, Landroid/support/v4/app/Fragment;->getActivity()Landroid/support/v4/app/FragmentActivity;\n\n    move-result-object v0\n\n    invoke-static {p0, v0}, ${pl}->requireLocation(Ljava/lang/Object;Landroid/app/Activity;)V\n"
         1)
# Add-speaker button: the stock BluetoothAdapter.enable() runs only with the
# grant and below API 33; the button then opens system Bluetooth settings as
# before, where pairing needs no app permission.
_sbc_sub("${TREE}/smali/com/creative/apps/sbconnect/AddBluetoothSpeakerFragment\$3.smali"
         "invoke-virtual {v0}, Landroid/bluetooth/BluetoothAdapter;->enable()Z"
         "invoke-static {v0}, ${pl}->enableAdapter(Landroid/bluetooth/BluetoothAdapter;)Z"
         1)

# --- entry gates ---------------------------------------------------------------
# BluetoothUtils (static). Profile-proxy setup a(Context), isEnabled a() and
# the proxy checks b()/c() need no runtime permission and stay ungated.
set(bd "Landroid/bluetooth/BluetoothDevice;")
_sbc_gate("${bu}" ".method public static declared-synchronized a(Ljava/lang/String;)${bd}" 6 btOk null)
_sbc_gate("${bu}" ".method public static declared-synchronized b(Landroid/content/Context;)${bd}" 7 btOk null)
_sbc_gate("${bu}" ".method public static declared-synchronized b(${bd})V" 4 btOk void)
_sbc_gate("${bu}" ".method public static declared-synchronized c(Landroid/content/Context;)${bd}" 7 btOk null)
_sbc_gate("${bu}" ".method public static declared-synchronized c(${bd})V" 6 btOk void)
_sbc_gate("${bu}" ".method public static declared-synchronized d(${bd})V" 6 btOk void)
_sbc_gate("${bu}" ".method public static declared-synchronized f(${bd})V" 6 btOk void)
_sbc_gate("${bu}" ".method public static declared-synchronized g(${bd})Z" 4 btOk false)
# e(device): BluetoothHeadset.connect by reflection. On API 31+ the platform
# requires MODIFY_PHONE_STATE, which only privileged apps hold; the call
# threw SecurityException on every connect (PERMISSION_FINDINGS.md, PF7).
_sbc_gate("${bu}" ".method public static declared-synchronized e(${bd})V" 6 headsetConnectOk void)
# a(device): the device name. Stock tries the hidden getAliasName first, which
# API 30+ does not have (NoSuchMethodException, PF7); there the public
# getAlias() replaces the whole lookup.
_sbc_sub("${bu}"
         ".method public static declared-synchronized a(${bd})Ljava/lang/String;\n    .locals 6\n"
         ".method public static declared-synchronized a(${bd})Ljava/lang/String;\n    .locals 6\n\n    invoke-static {}, ${pl}->btOk()Z\n\n    move-result v0\n\n    if-nez v0, :sbc_gate_ok\n\n    const/4 v0, 0x0\n\n    return-object v0\n\n    :sbc_gate_ok\n    invoke-static {}, ${pl}->publicAlias()Z\n\n    move-result v0\n\n    if-eqz v0, :sbc_stock_alias\n\n    invoke-static {p0}, ${pl}->alias(${bd})Ljava/lang/String;\n\n    move-result-object v0\n\n    return-object v0\n\n    :sbc_stock_alias\n"
         1)

# SbxConnectionManager: discovery start/cancel need BLUETOOTH_SCAN as well.
_sbc_gate("${cm}" ".method public declared-synchronized a()V" 3 scanOk void)
_sbc_gate("${cm}" ".method public declared-synchronized b()V" 2 scanOk void)
_sbc_gate("${cm}" ".method public a(${bd})Z" 2 btOk false)
_sbc_gate("${cm}" ".method public declared-synchronized b(${bd})V" 2 btOk void)
_sbc_gate("${cm}" ".method public declared-synchronized c(${bd})V" 2 btOk void)
_sbc_gate("${cm}" ".method public f()V" 5 btOk void)
# c(): Wi-Fi discovery of speakers in setup mode (their access points). Wi-Fi
# scans need precise location, which the connect screen does not request.
_sbc_gate("${cm}" ".method public declared-synchronized c()V" 3 wifiScanOk void)

# BLE scan start.
_sbc_gate("${TREE}/smali/com/creative/logic/sbxapplogic/BluetoothLE/BLEManager.smali"
          ".method private e()Z" 6 scanOk false)

# --- explanation strings (English) ----------------------------------------------
_sbc_sub("${TREE}/res/values/strings.xml" "</resources>"
         "    <string name=\"sbc_perm_allow\">Allow</string>
    <string name=\"sbc_perm_not_now\">Not now</string>
    <string name=\"sbc_perm_open_settings\">Open settings</string>
    <string name=\"sbc_perm_bluetooth_title\">Nearby devices</string>
    <string name=\"sbc_perm_bluetooth_message\">Finding and controlling a Sound Blaster device uses Bluetooth, which needs the Nearby devices permission. Without it the app opens, but cannot connect to a device.</string>
    <string name=\"sbc_perm_bluetooth_denied\">Nearby devices is not allowed. Connecting to a device is unavailable.</string>
    <string name=\"sbc_perm_microphone_title\">Microphone</string>
    <string name=\"sbc_perm_microphone_message\">Room calibration measures test tones through the microphone. No other feature uses it.</string>
    <string name=\"sbc_perm_microphone_denied\">Microphone is not allowed. Room calibration is unavailable.</string>
    <string name=\"sbc_perm_location_title\">Location</string>
    <string name=\"sbc_perm_location_message\">Wi-Fi speaker setup lists nearby Wi-Fi networks, which Android provides only with location access.</string>
    <string name=\"sbc_perm_location_denied\">Location is not allowed. Wi-Fi speaker setup cannot list networks.</string>
    <string name=\"sbc_perm_location_discovery_message\">On this Android version, finding Bluetooth devices that are not yet paired needs location access. Paired devices are listed without it.</string>
    <string name=\"sbc_perm_location_denied_legacy\">Location is not allowed. Finding unpaired devices and Wi-Fi speaker setup are unavailable.</string>
</resources>"
         1)

message(STATUS "modernize: permission lifecycle wired (PermissionLifecycle: launch sequence, feature prompts, 18 entry gates)")

# ---------------------------------------------------------------------------
# Notification-listener access prompt: suppressed. MainActivity.v() prompts
# (MainActivity.w) for notification-listener access, which fed the Now Playing
# metadata of other players through LocalMusicRemoteControllerService and the
# deprecated android.media.RemoteController. The service is no longer declared
# as a notification listener (manifest block above), so the access could not
# be granted; the call to w() is removed so the prompt is never shown.
# ---------------------------------------------------------------------------

# v(): keep the accessibility check/logging, drop the w() prompt invocation.
_sbc_sub("${ma}"
         "    if-nez v0, :cond_0\n\n    invoke-direct {p0}, Lcom/creative/apps/sbconnect/MainActivity;->w()V\n\n    goto :goto_0"
         "    if-nez v0, :cond_0\n\n    goto :goto_0"
         1)

message(STATUS "modernize: notification-listener access prompt removed")
