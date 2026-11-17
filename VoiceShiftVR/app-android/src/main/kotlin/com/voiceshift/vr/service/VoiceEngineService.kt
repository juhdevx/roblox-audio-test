package com.voiceshift.vr.service

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import com.voiceshift.vr.MainActivity
import com.voiceshift.vr.R
import com.voiceshift.vr.di.AppScope
import com.voiceshift.vr.session.VoiceSession
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/**
 * Foreground service of type "microphone". It owns no audio itself: it keeps the process in the
 * foreground so Android does not cut microphone access while the user is in another app or in VR,
 * and offers a Stop action in the notification.
 */
@AndroidEntryPoint
class VoiceEngineService : Service() {

    @Inject lateinit var session: VoiceSession
    @Inject @AppScope lateinit var scope: CoroutineScope

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            scope.launch { session.stop() }
            stopSelf()
            return START_NOT_STICKY
        }
        createChannel()
        val openApp = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val stop = PendingIntent.getService(
            this, 1, Intent(this, VoiceEngineService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(getString(R.string.notification_title))
            .setContentText("Tap to open. Microphone in use.")
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(openApp)
            .addAction(0, getString(R.string.notification_stop), stop)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
        try {
            // The microphone service type exists from Android 11 (API 30); Android 10 needs no type.
            val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE else 0
            ServiceCompat.startForeground(this, NOTIFICATION_ID, notification, type)
        } catch (e: Exception) {
            // E.g. ForegroundServiceStartNotAllowedException: audio keeps running while the app is visible.
            session.log.w("Service", "Foreground service not allowed: ${e.message}")
            session.message("Background processing is unavailable right now; keep VoiceShift open.")
            stopSelf()
        }
        return START_NOT_STICKY
    }

    private fun createChannel() {
        val manager = getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) == null) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, getString(R.string.notification_channel_name), NotificationManager.IMPORTANCE_LOW)
                    .apply { description = getString(R.string.notification_channel_description) },
            )
        }
    }

    companion object {
        private const val CHANNEL_ID = "voice_engine"
        private const val NOTIFICATION_ID = 1001
        private const val ACTION_STOP = "com.voiceshift.vr.action.STOP"

        fun start(context: Context) {
            try {
                ContextCompat.startForegroundService(context, Intent(context, VoiceEngineService::class.java))
            } catch (_: Exception) {
                // Not fatal: the engine keeps running in the foreground activity.
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, VoiceEngineService::class.java))
        }
    }
}
