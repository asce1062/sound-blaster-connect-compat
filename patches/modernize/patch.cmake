# modernize/patch.cmake — raise the target API level and apply the Android
# 12/13/14 behavior changes that follow.
#
# Runs with ${TREE} set to the staged (fresh) copy of the pristine decompiled/
# tree. Edits are in-place (apktool.yml, AndroidManifest.xml, smali); this
# patch ships no overlay/ tree.
#
# Target: raise targetSdkVersion 26 -> 34. Every change below is required by,
# and verified against, the component inventory in docs/FINDINGS.md:
#
#   * exported (>=31): the 5 filtered components that lacked an explicit
#     android:exported. Without this the package will not install on 31+.
#   * PendingIntent FLAG_IMMUTABLE (>=31): all 23 PendingIntent construction
#     sites. Without a mutability flag, getActivity/getService/getBroadcast/
#     getActivities throws IllegalArgumentException at runtime on 31+.
#   * Bluetooth runtime permissions (>=31): BLUETOOTH_SCAN / BLUETOOTH_CONNECT;
#     the legacy BLUETOOTH / BLUETOOTH_ADMIN are capped at maxSdkVersion 30.
#   * POST_NOTIFICATIONS (>=33): runtime notification permission.
#   * foregroundServiceType + FOREGROUND_SERVICE* (>=34): MainService is a
#     foreground service (2-arg startForeground, so it adopts the manifest
#     type). mediaPlayback has no dangerous-permission prerequisite, so the
#     service still starts before the BT runtime permissions are granted.
#
# What is NOT done here (needs a device): the runtime *request* UI for
# BLUETOOTH_SCAN/CONNECT and POST_NOTIFICATIONS. Declaring them lets the user
# grant them in Settings; wiring requestPermissions() into the app's flow is
# the device-gated follow-up. See README.md.

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
# Launcher, the BT/system receiver, the notification-listener service and the
# media-button receiver are driven by the system, so they stay exported.
# AppMeasurementReceiver is fed only by in-package broadcasts, so false.
_sbc_sub("${mf}" "android:name=\"com.creative.apps.sbconnect.MainActivity\""
         "android:exported=\"true\" android:name=\"com.creative.apps.sbconnect.MainActivity\""
         1)
_sbc_sub("${mf}" "android:name=\"com.creative.apps.sbconnect.MainReceiver\""
         "android:exported=\"true\" android:name=\"com.creative.apps.sbconnect.MainReceiver\""
         1)
_sbc_sub("${mf}"
         "android:name=\"com.creative.logic.sbxapplogic.LocalMusicRemoteControllerService\""
         "android:exported=\"true\" android:name=\"com.creative.logic.sbxapplogic.LocalMusicRemoteControllerService\""
         1)
_sbc_sub("${mf}"
         "android:name=\"android.support.v4.media.session.MediaButtonReceiver\""
         "android:exported=\"true\" android:name=\"android.support.v4.media.session.MediaButtonReceiver\""
         1)
_sbc_sub("${mf}"
         "android:name=\"com.google.android.gms.measurement.AppMeasurementReceiver\""
         "android:exported=\"false\" android:name=\"com.google.android.gms.measurement.AppMeasurementReceiver\""
         1)

# --- >=31 Bluetooth + >=33 notifications + >=34 foreground service perms ---
# Cap the legacy permissions at 30 and add the runtime-requested replacements.
_sbc_sub("${mf}" "<uses-permission android:name=\"android.permission.BLUETOOTH\"/>"
         "<uses-permission android:name=\"android.permission.BLUETOOTH\" android:maxSdkVersion=\"30\"/>"
         1)
_sbc_sub("${mf}"
         "<uses-permission android:name=\"android.permission.BLUETOOTH_ADMIN\"/>"
         "<uses-permission android:name=\"android.permission.BLUETOOTH_ADMIN\" android:maxSdkVersion=\"30\"/>\n    <uses-permission android:name=\"android.permission.BLUETOOTH_SCAN\"/>\n    <uses-permission android:name=\"android.permission.BLUETOOTH_CONNECT\"/>\n    <uses-permission android:name=\"android.permission.POST_NOTIFICATIONS\"/>\n    <uses-permission android:name=\"android.permission.FOREGROUND_SERVICE\"/>\n    <uses-permission android:name=\"android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK\"/>"
         1)
# Note: android:usesPermissionFlags="neverForLocation" on BLUETOOTH_SCAN is
# omitted. apktool's pinned framework (api 23 attr table) predates that API-31
# attribute, so aapt2 rejects it. The app already declares ACCESS_FINE_LOCATION,
# so scanning works with location granted; neverForLocation would only let the
# app skip the location grant, which is not required here.

# --- >=34: MainService foreground service type -----------------------------
_sbc_sub("${mf}" "android:name=\"com.creative.apps.sbconnect.MainService\">"
         "android:foregroundServiceType=\"mediaPlayback\" android:name=\"com.creative.apps.sbconnect.MainService\">"
         1)

# --- >=28: classpath libraries removed from the default bootclasspath ------
# API 28 dropped two class families the app references at runtime from the
# default classpath; both survive on device as optional shared libraries, so
# re-add each as a uses-library (required=false so install still succeeds
# where it is absent) as the first children of <application>:
#   org.apache.http.legacy - JSONParser uses DefaultHttpClient, so
#     MainActivity$ParseJsonTask throws NoClassDefFoundError under the raised
#     target.
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
# two-arg call throws SecurityException on a 34+ device. The first site runs in
# MainActivity.onCreate (LocalMusicManager) and more run in onStart (fragments
# via FragmentActivity), so the app crashes on launch on Android 14+. A further
# site runs inside the bundled ibluz Bluetooth library (smali/c, obfuscated c.d)
# during BluzDeviceFactory.getDevice when the SPP control channel opens; its
# SecurityException is swallowed, so the app survives but the device connection
# silently fails and the "device in use" state never clears. Redirect every
# two-arg registerReceiver call, in every dex and package (the stock app, the
# ibluz library, and support classes), to the RcvCompat.register shim (modernize
# overlay), which passes RECEIVER_EXPORTED on 34+ and is unchanged below.
# 96 sites across the whole smali tree.
# ---------------------------------------------------------------------------

_sbc_receiver_export_tree(96)

message(STATUS "modernize: registerReceiver export shim wired (96 sites, whole smali tree)")

# ---------------------------------------------------------------------------
# >=31 Nearby Devices runtime permission request flow. Device-gated follow-up
# to the BLUETOOTH_SCAN/CONNECT manifest declarations above (the request UI the
# header notes was left for a device). The stock app predates the API 31
# Bluetooth permission split and never calls requestPermissions, so on 31+ the
# runtime permissions sit denied, every Bluetooth call throws SecurityException,
# and bonded-device enumeration and the SPP connection fail silently - no device
# is ever found. BtPermCompat (modernize overlay) requests BLUETOOTH_CONNECT and
# BLUETOOTH_SCAN (the connect and discovery paths use both), resumes the normal
# init path via Activity.recreate() on grant, and gates the connection manager's
# discovery (startDiscovery) and bonded-enumeration (getBondedDevices) entry
# points so they no-op instead of throwing until the grant lands. Below 31 the
# legacy install-time permissions apply and the shim is inert. CtProtocol and the
# native libraries are untouched.
#
# The requests are chained off each preceding result rather than fired together
# from onCreate: onCreate's D() already calls requestPermissions (code 0x457) for
# the stock runtime permissions (camera/mic/location), and Android drops a second
# requestPermissions while a dialog sequence is still pending - firing the BT
# request from onCreate therefore never shows its dialog. onResult instead walks a
# sequential chain, each link firing when the previous result returns:
#   0x457 (stock) -> ensure() requests BLUETOOTH_CONNECT/SCAN (0x42c)
#   0x42c (BT)    -> askNotif() requests POST_NOTIFICATIONS (0x42d, API 33+)
#   0x42d (notif) -> resume() recreates on BT grant
# so the dialogs appear back to back (location/mic, Nearby devices, notifications).
# POST_NOTIFICATIONS is already declared in the manifest block above; without the
# runtime request it stays denied and the app cannot post its foreground-service or
# media notifications. D()'s request is unconditional, so the chain fires on every
# launch and is a no-op once the grants are held.
# ---------------------------------------------------------------------------
set(ma "${TREE}/smali/com/creative/apps/sbconnect/MainActivity.smali")
set(cm "${TREE}/smali/com/creative/logic/sbxapplogic/SbxConnectionManager.smali")

# chain the BT request off the stock permission result, and resume the normal init
# path on grant: hand every permission result to BtPermCompat after super.
_sbc_sub("${ma}"
         "invoke-super {p0, p1, p2, p3}, Landroid/support/v7/app/AppCompatActivity;->onRequestPermissionsResult(I[Ljava/lang/String;[I)V"
         "invoke-super {p0, p1, p2, p3}, Landroid/support/v7/app/AppCompatActivity;->onRequestPermissionsResult(I[Ljava/lang/String;[I)V\n\n    invoke-static {p0, p1, p2, p3}, Lcom/creative/apps/sbconnect/BtPermCompat;->onResult(Landroid/app/Activity;I[Ljava/lang/String;[I)V"
         1)

# gate discovery (startDiscovery, BLUETOOTH_SCAN) before the method monitor.
_sbc_sub("${cm}"
         ".method public declared-synchronized a()V\n    .locals 3\n\n    monitor-enter p0"
         ".method public declared-synchronized a()V\n    .locals 3\n\n    iget-object v0, p0, Lcom/creative/logic/sbxapplogic/SbxConnectionManager;->j:Landroid/content/Context;\n\n    invoke-static {v0}, Lcom/creative/apps/sbconnect/BtPermCompat;->ok(Landroid/content/Context;)Z\n\n    move-result v0\n\n    if-nez v0, :sbc_bt_gate\n\n    return-void\n\n    :sbc_bt_gate\n    monitor-enter p0"
         1)

# gate bonded-device enumeration (getBondedDevices, BLUETOOTH_CONNECT) at the top.
_sbc_sub("${cm}"
         ".method public f()V\n    .locals 5\n\n    :try_start_0"
         ".method public f()V\n    .locals 5\n\n    iget-object v0, p0, Lcom/creative/logic/sbxapplogic/SbxConnectionManager;->j:Landroid/content/Context;\n\n    invoke-static {v0}, Lcom/creative/apps/sbconnect/BtPermCompat;->ok(Landroid/content/Context;)Z\n\n    move-result v0\n\n    if-nez v0, :sbc_bt_gate\n\n    return-void\n\n    :sbc_bt_gate\n    :try_start_0"
         1)

message(STATUS "modernize: runtime permission chain wired (BtPermCompat: stock -> Nearby Devices -> notifications, + discovery/bonded gates)")

# ---------------------------------------------------------------------------
# Notification-listener access prompt: suppressed. MainActivity.v() prompts
# (MainActivity.w) for notification-listener access to feed the now-playing
# metadata feature (LocalMusicRemoteControllerService), which drives the removed
# android.media.RemoteController API and is inert on modern Android. The grant is
# a system-level "read all notifications" permission that buys no working feature
# here, and the system pane cannot be reduced to a single focused toggle on Samsung
# (OneUI renders the per-app deep-link as the full listener list) nor made to return
# to the app afterward (API 34+ background-activity-launch forbids a listener service
# from foregrounding an activity). Drop the call to w() so the dialog never fires;
# the Bluetooth/notification runtime-permission chain above is unaffected.
# ---------------------------------------------------------------------------
set(ma "${TREE}/smali/com/creative/apps/sbconnect/MainActivity.smali")

# v(): keep the accessibility check/logging, drop the w() prompt invocation.
_sbc_sub("${ma}"
         "    if-nez v0, :cond_0\n\n    invoke-direct {p0}, Lcom/creative/apps/sbconnect/MainActivity;->w()V\n\n    goto :goto_0"
         "    if-nez v0, :cond_0\n\n    goto :goto_0"
         1)

message(STATUS "modernize: notification-listener access prompt suppressed (inert RemoteController feature)")
