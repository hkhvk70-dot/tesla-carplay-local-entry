// SPDX-License-Identifier: GPL-3.0-only
package local.carplay.localentry;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.net.VpnService;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.ParcelFileDescriptor;
import android.system.OsConstants;
import java.io.IOException;

/** Local-only entry verified on the development phone; other OS versions need testing. */
public final class LocalEntryService extends VpnService {
    public static volatile String status = "尚未启动";
    private ParcelFileDescriptor entryDescriptor;
    private ParcelFileDescriptor activeDescriptor;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final Runnable autoStop = () -> finishTest("计时诊断已结束，入口已停止");

    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent != null && "STOP".equals(intent.getAction())) {
            finishTest("入口已停止");
            return START_NOT_STICKY;
        }
        // A second tap cannot accumulate descriptors or create extra interfaces.
        if (activeDescriptor != null) return START_NOT_STICKY;
        try {
            NotificationManager notifications = getSystemService(NotificationManager.class);
            notifications.createNotificationChannel(new NotificationChannel("local-entry", "CarPlay 本地入口", NotificationManager.IMPORTANCE_LOW));
            PendingIntent open = PendingIntent.getActivity(this, 0,
                new Intent(this, MainActivity.class), PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
            PendingIntent stop = PendingIntent.getService(this, 1,
                new Intent(this, LocalEntryService.class).setAction("STOP"), PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
            Notification notification = new Notification.Builder(this, "local-entry")
                .setSmallIcon(android.R.drawable.ic_dialog_info).setContentTitle("CarPlay 本地入口")
                .setContentText("局域网入口运行中，可随时停止")
                .setContentIntent(open).addAction(android.R.drawable.ic_delete, "停止", stop)
                .setOngoing(true).build();
            if (Build.VERSION.SDK_INT >= 34) {
                startForeground(1, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE);
            } else {
                startForeground(1, notification);
            }
            // Normal use has no timer. The explicit diagnostic action still exercises
            // the common cleanup path in 15 seconds without changing normal behavior.
            if (intent != null && "VERIFY_TIMEOUT".equals(intent.getAction())) {
                handler.postDelayed(autoStop, 15000L);
            }

            entryDescriptor = new Builder().setSession("CarPlay local entry stage 1")
                .setMtu(1500).addAddress("7.7.7.1", 32).addRoute("7.7.7.1", 32)
                .addAllowedApplication(getPackageName()).allowFamily(OsConstants.AF_INET6)
                .establish();
            if (entryDescriptor == null) throw new IOException("VPN permission unavailable at stage 1");

            // Different addresses force a distinct interface configuration. Holding the
            // first descriptor retains the address on the verified development device.
            // Neither stage configures a default route, DNS, or a remote server.
            activeDescriptor = new Builder().setSession("CarPlay local entry stage 2")
                .setMtu(1500).addAddress("198.18.7.1", 32).addRoute("198.18.7.1", 32)
                .addAllowedApplication(getPackageName()).allowFamily(OsConstants.AF_INET6)
                .establish();
            if (activeDescriptor == null) throw new IOException("VPN permission unavailable at stage 2");
            status = "入口运行中\nhttp://7.7.7.1:8080/\n请用已连接 Android 个人热点的设备打开。";
        } catch (Exception error) {
            finishTest("入口启动失败：" + error.getClass().getSimpleName());
        }
        return START_NOT_STICKY;
    }

    private void closeInterfaces() {
        handler.removeCallbacks(autoStop);
        ParcelFileDescriptor entry = entryDescriptor;
        ParcelFileDescriptor active = activeDescriptor;
        entryDescriptor = null;
        activeDescriptor = null;
        // Attempt both closes even if the first descriptor has already become invalid.
        if (entry != null) { try { entry.close(); } catch (IOException ignored) { } }
        if (active != null) { try { active.close(); } catch (IOException ignored) { } }
    }

    private void finishTest(String reason) {
        // VpnService is also bound by Android. stopSelf alone does not destroy a
        // bound service, so close descriptors before requesting service shutdown.
        closeInterfaces();
        status = reason;
        stopForeground(STOP_FOREGROUND_REMOVE);
        stopSelf();
    }

    @Override public void onRevoke() {
        finishTest("VPN 授权已撤销，入口已停止");
    }

    @Override public void onDestroy() {
        boolean running = entryDescriptor != null || activeDescriptor != null;
        closeInterfaces();
        if (running) status = "入口已停止";
        stopForeground(STOP_FOREGROUND_REMOVE);
        super.onDestroy();
    }
}
