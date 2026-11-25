package com.creative.apps.sbconnect;

import android.app.Activity;
import android.app.AlertDialog;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.content.Context;
import android.content.DialogInterface;
import android.content.Intent;
import android.content.SharedPreferences;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.provider.Settings;
import android.util.Log;
import android.widget.Toast;

/**
 * The runtime-permission lifecycle of the modernized app (modernize patch).
 *
 * <p>One owner for every runtime-permission request and every Bluetooth gate.
 * It replaces the stock request batch in {@code MainActivity.D()} (camera,
 * storage, microphone, location on every activity creation) and the earlier
 * {@code BtPermCompat} chain.
 *
 * <p>Launch sequence, once per install for each step and never on a recreated
 * activity:
 * <ol>
 *   <li>API 31+: Nearby devices ({@code BLUETOOTH_CONNECT}, {@code BLUETOOTH_SCAN}).
 *       API 23 to 30: location, which the platform requires there for Bluetooth
 *       discovery results.</li>
 *   <li>API 33+: notifications, independent of the Bluetooth result.</li>
 * </ol>
 * A step the user has answered is not requested again automatically. Later
 * requests come only from a feature the user opens: connecting to a device
 * (Nearby devices), room calibration (microphone) and Wi-Fi speaker setup
 * (location). Each shows an explanation first, with Allow while the system
 * can still show its dialog, or Open settings when it can no longer do so.
 *
 * <p>Gates: {@link #btOk()} and {@link #scanOk()} are consulted at the entry
 * of the Bluetooth utility and connection-manager methods, which return their
 * "no device" value instead of calling the platform without the grant.
 *
 * <p>When Nearby devices is granted after the activity was created without it
 * (from the dialog or from system settings), the activity is recreated once so
 * the stock initialization runs with the grant.
 */
public final class PermissionLifecycle {
    private static final String TAG = "SBConnect.Permissions";

    static final String CONNECT = "android.permission.BLUETOOTH_CONNECT";
    static final String SCAN = "android.permission.BLUETOOTH_SCAN";
    static final String NOTIFICATIONS = "android.permission.POST_NOTIFICATIONS";
    static final String FINE = "android.permission.ACCESS_FINE_LOCATION";
    static final String COARSE = "android.permission.ACCESS_COARSE_LOCATION";
    static final String MICROPHONE = "android.permission.RECORD_AUDIO";
    static final String MODIFY_PHONE_STATE = "android.permission.MODIFY_PHONE_STATE";

    static final int REQ_BLUETOOTH = 0x42c;
    static final int REQ_NOTIFICATIONS = 0x42d;
    static final int REQ_MICROPHONE = 0x42e;
    static final int REQ_LOCATION = 0x42f;

    private static final String PREFS = "sbc_permissions";
    private static final String ASKED_BLUETOOTH = "asked_bluetooth";
    private static final String ASKED_NOTIFICATIONS = "asked_notifications";
    private static final String ASKED_MICROPHONE = "asked_microphone";
    private static final String ASKED_LOCATION = "asked_location";

    private static Context app;
    /** The launch sequence is between steps. */
    private static boolean launching;
    /** One of this class's requests is on screen. */
    private static boolean pending;
    /** BLUETOOTH_CONNECT was held when the current activity was created. */
    private static boolean btAtCreate;
    /**
     * Identity of the fragment instance that last ran a feature prompt, per
     * feature, so a fragment resuming after the system dialog does not prompt
     * again. Held as a hash so no fragment is retained.
     */
    private static int btOwner;
    private static int micOwner;
    private static int locationOwner;

    private PermissionLifecycle() {}

    // --- state ------------------------------------------------------------

    /** From {@code SbxApplication.onCreate}, before any component runs. */
    public static void init(Context context) {
        app = context.getApplicationContext() != null ? context.getApplicationContext() : context;
    }

    private static boolean granted(Context c, String permission) {
        if (Build.VERSION.SDK_INT < 23) {
            return true;
        }
        return c != null && c.checkSelfPermission(permission) == 0;
    }

    /** Bluetooth use is permitted: below API 31, or BLUETOOTH_CONNECT held. */
    public static boolean btOk() {
        return Build.VERSION.SDK_INT < 31 || granted(app, CONNECT);
    }

    /** Discovery is permitted: below API 31, or both Nearby permissions held. */
    public static boolean scanOk() {
        return Build.VERSION.SDK_INT < 31 || (granted(app, CONNECT) && granted(app, SCAN));
    }

    /**
     * A Wi-Fi scan may run: precise location held. Without it the platform
     * refuses the scan and returns no results.
     */
    public static boolean wifiScanOk() {
        return granted(app, FINE);
    }

    /**
     * The stock hidden-API call {@code BluetoothHeadset.connect} may run. From
     * API 31 the platform requires MODIFY_PHONE_STATE for it, a permission
     * granted only to privileged apps, so the call is skipped unless that
     * permission is held.
     */
    public static boolean headsetConnectOk() {
        if (!btOk()) {
            return false;
        }
        return Build.VERSION.SDK_INT < 31 || granted(app, MODIFY_PHONE_STATE);
    }

    /** API 30+: the stock name lookup uses the public alias instead of the hidden getAliasName. */
    public static boolean publicAlias() {
        return Build.VERSION.SDK_INT >= 30;
    }

    /** The device's user-visible name: its alias, otherwise its name. Null on failure. */
    public static String alias(BluetoothDevice device) {
        if (device == null || !btOk()) {
            return null;
        }
        try {
            String alias = device.getAlias();
            if (alias != null) {
                return alias;
            }
        } catch (RuntimeException e) {
            Log.w(TAG, "getAlias failed", e);
        }
        try {
            return device.getName();
        } catch (RuntimeException e) {
            Log.w(TAG, "getName failed", e);
            return null;
        }
    }

    /**
     * Replaces the stock {@code BluetoothAdapter.enable()} call. Runs it only
     * with the grant and below API 33, where the platform still honors it for
     * this app; otherwise the caller's next step (system Bluetooth settings)
     * lets the user turn Bluetooth on.
     */
    public static boolean enableAdapter(BluetoothAdapter adapter) {
        if (adapter == null || !btOk() || Build.VERSION.SDK_INT >= 33) {
            return false;
        }
        try {
            return adapter.enable();
        } catch (RuntimeException e) {
            Log.w(TAG, "enable failed", e);
            return false;
        }
    }

    private static SharedPreferences prefs(Context c) {
        return c.getApplicationContext().getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    private static boolean asked(Context c, String key) {
        return prefs(c).getBoolean(key, false);
    }

    private static void markAsked(Context c, String key) {
        prefs(c).edit().putBoolean(key, true).apply();
    }

    private static String text(Context c, String name) {
        int id = c.getResources().getIdentifier(name, "string", c.getPackageName());
        return id != 0 ? c.getString(id) : name;
    }

    private static void request(Activity a, String[] permissions, int code) {
        pending = true;
        a.requestPermissions(permissions, code);
    }

    // --- activity lifecycle -------------------------------------------------

    /**
     * From {@code MainActivity.onCreate}, in place of the stock request batch.
     * A recreated activity (saved state present) does not start the sequence
     * again; a sequence already under way continues from its pending result.
     */
    public static void onLaunch(Activity a, Bundle savedState) {
        btAtCreate = btOk();
        if (Build.VERSION.SDK_INT < 23 || savedState != null) {
            return;
        }
        pending = false;
        launching = true;
        nextLaunchStep(a);
    }

    private static void nextLaunchStep(Activity a) {
        if (Build.VERSION.SDK_INT >= 31) {
            if (!btOk() && !asked(a, ASKED_BLUETOOTH)) {
                markAsked(a, ASKED_BLUETOOTH);
                request(a, new String[] {CONNECT, SCAN}, REQ_BLUETOOTH);
                return;
            }
        } else if (!granted(a, FINE) && !asked(a, ASKED_LOCATION)) {
            markAsked(a, ASKED_LOCATION);
            request(a, new String[] {FINE, COARSE}, REQ_LOCATION);
            return;
        }
        if (Build.VERSION.SDK_INT >= 33
                && !granted(a, NOTIFICATIONS)
                && !asked(a, ASKED_NOTIFICATIONS)) {
            markAsked(a, ASKED_NOTIFICATIONS);
            request(a, new String[] {NOTIFICATIONS}, REQ_NOTIFICATIONS);
            return;
        }
        launching = false;
        recreateIfBluetoothArrived(a);
    }

    /** From {@code MainActivity.onRequestPermissionsResult}, after super. */
    public static void onResult(Activity a, int code, String[] permissions, int[] results) {
        if (code != REQ_BLUETOOTH
                && code != REQ_NOTIFICATIONS
                && code != REQ_MICROPHONE
                && code != REQ_LOCATION) {
            return;
        }
        pending = false;
        if (launching) {
            nextLaunchStep(a);
            return;
        }
        switch (code) {
            case REQ_BLUETOOTH:
                if (btOk()) {
                    recreateIfBluetoothArrived(a);
                } else {
                    toast(a, "sbc_perm_bluetooth_denied");
                }
                break;
            case REQ_MICROPHONE:
                if (!granted(a, MICROPHONE)) {
                    toast(a, "sbc_perm_microphone_denied");
                }
                break;
            case REQ_LOCATION:
                if (!granted(a, FINE)) {
                    toast(a, Build.VERSION.SDK_INT < 31
                            ? "sbc_perm_location_denied_legacy" : "sbc_perm_location_denied");
                }
                break;
            default:
                break;
        }
    }

    /** From {@code MainActivity.onResume}: picks up a grant made in system settings. */
    public static void onResume(Activity a) {
        if (!pending && !launching) {
            recreateIfBluetoothArrived(a);
        }
    }

    private static void recreateIfBluetoothArrived(Activity a) {
        if (!btAtCreate && btOk()) {
            btAtCreate = true;
            Log.i(TAG, "Nearby devices granted; recreating the activity");
            a.recreate();
        }
    }

    // --- feature prompts ----------------------------------------------------

    /**
     * Before a user-initiated Bluetooth action (tapping a device). Returns true
     * when the action may proceed; otherwise explains and offers the request or
     * system settings, and returns false.
     */
    public static boolean requireBluetooth(Activity a) {
        if (btOk()) {
            return true;
        }
        if (a == null || a.isFinishing()) {
            return false;
        }
        explain(a, "sbc_perm_bluetooth_title", "sbc_perm_bluetooth_message",
                new String[] {CONNECT, SCAN}, REQ_BLUETOOTH, ASKED_BLUETOOTH);
        return false;
    }

    /**
     * From {@code ConnectionFragment.onResume}: the connect screen lists and
     * connects devices over Bluetooth. Without Nearby devices its list is
     * empty, so opening it is where a denied user can retry. On API 23 to 30
     * discovery of unpaired devices needs location instead; paired devices
     * are listed without it.
     */
    public static void requireBluetoothScreen(Object owner, Activity a) {
        int id = System.identityHashCode(owner);
        if (a == null || id == btOwner || pending || launching) {
            return;
        }
        if (!btOk()) {
            btOwner = id;
            requireBluetooth(a);
        } else if (Build.VERSION.SDK_INT >= 23 && Build.VERSION.SDK_INT < 31 && !granted(a, FINE)) {
            btOwner = id;
            explain(a, "sbc_perm_location_title", "sbc_perm_location_discovery_message",
                    new String[] {FINE, COARSE}, REQ_LOCATION, ASKED_LOCATION);
        }
    }

    /** From {@code CalibrationFragment.onResume}: calibration records through the microphone. */
    public static void requireMicrophone(Object owner, Activity a) {
        int id = System.identityHashCode(owner);
        if (granted(a, MICROPHONE) || a == null || id == micOwner || pending) {
            return;
        }
        micOwner = id;
        explain(a, "sbc_perm_microphone_title", "sbc_perm_microphone_message",
                new String[] {MICROPHONE}, REQ_MICROPHONE, ASKED_MICROPHONE);
    }

    /**
     * From {@code WifiSetupFragment.onResume}: Wi-Fi speaker setup reads Wi-Fi
     * scan results and the current network, which the platform releases only
     * with location. Below API 31 the launch sequence already asked.
     */
    public static void requireLocation(Object owner, Activity a) {
        int id = System.identityHashCode(owner);
        if (granted(a, FINE) || a == null || id == locationOwner || pending || launching) {
            return;
        }
        locationOwner = id;
        explain(a, "sbc_perm_location_title", "sbc_perm_location_message",
                new String[] {FINE, COARSE}, REQ_LOCATION, ASKED_LOCATION);
    }

    private static void explain(final Activity a, String title, String message,
            final String[] permissions, final int code, final String key) {
        if (Build.VERSION.SDK_INT < 23) {
            return;
        }
        // The system dialog can still be shown when the permission was never
        // requested, or when it was declined once (rationale true). Otherwise
        // only system settings can grant it.
        boolean canRequest = !asked(a, key);
        for (String p : permissions) {
            if (a.shouldShowRequestPermissionRationale(p)) {
                canRequest = true;
            }
        }
        AlertDialog.Builder b = new AlertDialog.Builder(a)
                .setTitle(text(a, title))
                .setMessage(text(a, message))
                .setNegativeButton(text(a, "sbc_perm_not_now"), null);
        if (canRequest) {
            b.setPositiveButton(text(a, "sbc_perm_allow"), new DialogInterface.OnClickListener() {
                @Override
                public void onClick(DialogInterface d, int which) {
                    markAsked(a, key);
                    request(a, permissions, code);
                }
            });
        } else {
            b.setPositiveButton(text(a, "sbc_perm_open_settings"), new DialogInterface.OnClickListener() {
                @Override
                public void onClick(DialogInterface d, int which) {
                    openSettings(a);
                }
            });
        }
        try {
            b.show();
        } catch (RuntimeException e) {
            Log.w(TAG, "explanation dialog not shown", e);
        }
    }

    private static void openSettings(Activity a) {
        Intent i = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.fromParts("package", a.getPackageName(), null));
        try {
            a.startActivity(i);
        } catch (RuntimeException e) {
            Log.w(TAG, "app settings not opened", e);
        }
    }

    private static void toast(Activity a, String name) {
        Toast.makeText(a, text(a, name), Toast.LENGTH_LONG).show();
    }
}
