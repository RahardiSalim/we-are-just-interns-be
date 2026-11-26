package com.gosafe.gosafe

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.IBinder

/**
 * Keeps the app alive with the microphone allowed while the ride is on, so recording and listening
 * continue with the screen locked or another app open. Android shows its notification for as long as it runs.
 */
class RideService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val n = Alerts.builder(this, Alerts.LISTENING)
            .setContentTitle(intent?.getStringExtra("title"))
            .setContentText(intent?.getStringExtra("body"))
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(Alerts.LISTENING_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
        } else {
            startForeground(Alerts.LISTENING_ID, n)
        }
        return START_NOT_STICKY // if Android kills it, don't restart a recording nobody started
    }
}

/** Notification channels: the quiet "listening" one, and the "Are you okay?" alerts. */
object Alerts {
    const val LISTENING = "listening"
    private const val CHECKIN = "checkin"
    private const val ALARM = "alarm"
    const val LISTENING_ID = 1
    private const val ALERT_ID = 2

    fun builder(ctx: Context, channel: String): Notification.Builder {
        channels(ctx)
        val open = PendingIntent.getActivity(
            ctx, 0,
            Intent(ctx, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE,
        )
        return Notification.Builder(ctx, channel).setSmallIcon(R.drawable.ic_stat_gosafe).setContentIntent(open)
    }

    /** loud: alarm sound on the alarm stream (plays in silent mode), repeating until answered. */
    fun show(ctx: Context, title: String, body: String, loud: Boolean) {
        val n = builder(ctx, if (loud) ALARM else CHECKIN)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setCategory(if (loud) Notification.CATEGORY_ALARM else Notification.CATEGORY_REMINDER)
            .setAutoCancel(true)
            .build()
        if (loud) n.flags = n.flags or Notification.FLAG_INSISTENT
        ctx.getSystemService(NotificationManager::class.java).notify(ALERT_ID, n)
    }

    fun clear(ctx: Context) = ctx.getSystemService(NotificationManager::class.java).cancel(ALERT_ID)

    // A channel's sound can't change after it's created, so each kind of alert has its own.
    private fun channels(ctx: Context) {
        val nm = ctx.getSystemService(NotificationManager::class.java)
        if (nm.getNotificationChannel(ALARM) != null) return
        nm.createNotificationChannel(NotificationChannel(LISTENING, "Ride listening", NotificationManager.IMPORTANCE_LOW))
        nm.createNotificationChannel(NotificationChannel(CHECKIN, "Are you okay?", NotificationManager.IMPORTANCE_HIGH))
        nm.createNotificationChannel(
            NotificationChannel(ALARM, "Danger alarm", NotificationManager.IMPORTANCE_HIGH).apply {
                setSound(
                    RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM),
                    AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build(),
                )
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 800, 400, 800, 400, 800)
            },
        )
    }
}
