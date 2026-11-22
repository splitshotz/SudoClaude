package io.github.splitshotz.sudoclaude.phone;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.graphics.PixelFormat;
import android.graphics.Point;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.view.WindowManager;

import java.io.File;
import java.io.FileOutputStream;

/**
 * Draws Claude's presence on the phone while the computer drives it: a glow around
 * the screen edge, Claude's cursor moving to each tap, and a notification with Stop.
 * Commands arrive as intents from adb (cmd activity start-foreground-service).
 */
public class OverlayService extends Service {
    private static final String CHANNEL = "claude";
    private static final long IDLE_MS = 8000;

    private final Handler main = new Handler(Looper.getMainLooper());
    private WindowManager wm;
    private OverlayView view;
    private boolean foreground;
    private final Runnable idle = this::dismiss;

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (!foreground) goForeground();
        String op = intent != null && intent.getAction() != null ? intent.getAction() : "show";
        if (op.equals("stop")) {
            writeStop();
            dismiss();
            return START_NOT_STICKY;
        }
        if (op.equals("hide")) {
            dismiss();
            return START_NOT_STICKY;
        }
        ensureView();
        String label = intent != null ? intent.getStringExtra("label") : null;
        int x = intent != null ? intent.getIntExtra("x", -1) : -1;
        int y = intent != null ? intent.getIntExtra("y", -1) : -1;
        switch (op) {
            case "tap":
                view.tap(x, y, label != null ? label : "Tap", intent.getIntExtra("ms", 0));
                break;
            case "swipe":
                view.swipe(x, y, intent.getIntExtra("x2", x), intent.getIntExtra("y2", y),
                        intent.getIntExtra("ms", 300), label != null ? label : "Swipe");
                break;
            case "peek":
                view.peek(true);
                break;
            case "unpeek":
                view.peek(false);
                break;
            default:
                view.show(label);
        }
        main.removeCallbacks(idle);
        main.postDelayed(idle, IDLE_MS);
        return START_NOT_STICKY;
    }

    private void ensureView() {
        if (view != null) return;
        wm = (WindowManager) getSystemService(WINDOW_SERVICE);
        view = new OverlayView(this);
        WindowManager.LayoutParams p = new WindowManager.LayoutParams(
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                        | WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
                        | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
                        | WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
                        | WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
                PixelFormat.TRANSLUCENT);
        Point size = new Point();
        wm.getDefaultDisplay().getRealSize(size);
        p.width = size.x;
        p.height = size.y;
        p.x = 0;
        p.y = 0;
        p.gravity = android.view.Gravity.TOP | android.view.Gravity.START;
        // Android lets touches through an untouchable overlay only at 80% opacity or less.
        p.alpha = 0.8f;
        if (Build.VERSION.SDK_INT >= 28) {
            p.layoutInDisplayCutoutMode = Build.VERSION.SDK_INT >= 30
                    ? WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
                    : WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES;
        }
        if (Build.VERSION.SDK_INT >= 30) p.setFitInsetsTypes(0);
        p.setTitle("SudoClaude");
        wm.addView(view, p);
    }

    private void dismiss() {
        main.removeCallbacks(idle);
        if (view != null) {
            final OverlayView v = view;
            view = null;
            v.hide(() -> {
                try {
                    wm.removeView(v);
                } catch (Exception ignored) {
                }
                finish();
            });
        } else {
            finish();
        }
    }

    private void finish() {
        if (view != null) return;
        if (Build.VERSION.SDK_INT >= 24) stopForeground(STOP_FOREGROUND_REMOVE);
        else stopForeground(true);
        foreground = false;
        stopSelf();
    }

    private void writeStop() {
        try {
            File dir = getExternalFilesDir(null);
            if (dir == null) return;
            try (FileOutputStream out = new FileOutputStream(new File(dir, "stop"))) {
                out.write(Long.toString(System.currentTimeMillis()).getBytes());
            }
        } catch (Exception ignored) {
        }
    }

    private void goForeground() {
        NotificationManager nm = getSystemService(NotificationManager.class);
        NotificationChannel ch = new NotificationChannel(CHANNEL, "Claude at work",
                NotificationManager.IMPORTANCE_LOW);
        ch.setDescription("Shown while Claude is using your phone");
        ch.setShowBadge(false);
        nm.createNotificationChannel(ch);

        Intent stop = new Intent(this, OverlayService.class).setAction("stop");
        PendingIntent pi = PendingIntent.getService(this, 1, stop,
                PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        Notification n = new Notification.Builder(this, CHANNEL)
                .setSmallIcon(R.drawable.ic_stat)
                .setColor(0xFFD97757)
                .setContentTitle("Claude is using your phone")
                .setContentText("Tap Stop to take it back")
                .setOngoing(true)
                .setCategory(Notification.CATEGORY_SERVICE)
                .addAction(new Notification.Action.Builder(null, "Stop", pi).build())
                .build();
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(1, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE);
        } else {
            startForeground(1, n);
        }
        foreground = true;
    }
}
