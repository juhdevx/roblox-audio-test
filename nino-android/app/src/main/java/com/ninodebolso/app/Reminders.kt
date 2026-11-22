package com.ninodebolso.app

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings

/** Reminders become real alarms, so they show up even when the app is closed. */
object Reminders {
    const val ACTION_FIRE = "com.ninodebolso.app.REMIND"
    const val ACTION_DONE = "com.ninodebolso.app.REMIND_DONE"
    const val ACTION_SNOOZE = "com.ninodebolso.app.REMIND_SNOOZE"

    private fun pi(ctx: Context, id: String, action: String = ACTION_FIRE): PendingIntent =
        PendingIntent.getBroadcast(
            ctx, (action + id).hashCode(),
            Intent(ctx, ReminderReceiver::class.java).setAction(action).putExtra("id", id),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    fun canExact(ctx: Context): Boolean {
        if (Build.VERSION.SDK_INT < 31) return true
        return ctx.getSystemService(AlarmManager::class.java).canScheduleExactAlarms()
    }

    fun schedule(ctx: Context, t: Task) {
        val due = t.due ?: return
        if (t.done || due <= now()) return
        val am = ctx.getSystemService(AlarmManager::class.java)
        val p = pi(ctx, t.id)
        try {
            if (canExact(ctx)) am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, due, p)
            else am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, due, p)
        } catch (e: SecurityException) {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, due, p)
        }
    }

    fun cancel(ctx: Context, id: String) {
        ctx.getSystemService(AlarmManager::class.java).cancel(pi(ctx, id))
        ctx.getSystemService(NotificationManager::class.java).cancel(id.hashCode())
    }

    fun rescheduleAll(ctx: Context) {
        Store.tasks.filter { !it.done && (it.due ?: 0) > now() }.forEach { schedule(ctx, it) }
    }

    fun exactAlarmSettings(ctx: Context): Intent? =
        if (Build.VERSION.SDK_INT >= 31) Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).setData(android.net.Uri.parse("package:" + ctx.packageName)) else null

    fun notify(ctx: Context, t: Task) {
        val open = PendingIntent.getActivity(
            ctx, 1, Intent(ctx, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val n = Notification.Builder(ctx, Notifs.REMIND)
            .setSmallIcon(R.drawable.ic_stat)
            .setContentTitle("${Store.petName}: hora de ${t.title}")
            .setContentText("Você me pediu pra lembrar. Já fez?")
            .setCategory(Notification.CATEGORY_REMINDER)
            .setAutoCancel(true)
            .setContentIntent(open)
            .addAction(Notification.Action.Builder(null, "Feito", pi(ctx, t.id, ACTION_DONE)).build())
            .addAction(Notification.Action.Builder(null, "Mais 10 min", pi(ctx, t.id, ACTION_SNOOZE)).build())
            .build()
        try {
            ctx.getSystemService(NotificationManager::class.java).notify(t.id.hashCode(), n)
        } catch (e: SecurityException) {
            // Notifications are off; the pet still says it on screen.
        }
    }
}

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        Store.init(ctx)
        val id = intent.getStringExtra("id") ?: return
        val t = Store.task(id) ?: return
        when (intent.action) {
            Reminders.ACTION_DONE -> {
                Store.completeTask(id)
                ctx.getSystemService(NotificationManager::class.java).cancel(id.hashCode())
                PetService.instance?.cheer()
            }
            Reminders.ACTION_SNOOZE -> {
                Store.snooze(id, 10)
                ctx.getSystemService(NotificationManager::class.java).cancel(id.hashCode())
            }
            else -> {
                if (t.done) return
                t.notified = true
                Store.addChat(ChatMsg("s", "Lembrete: ${t.title}"))
                Reminders.notify(ctx, t)
                val svc = PetService.instance
                if (svc != null) svc.remind(id)
                else if (Store.petActive && Settings.canDrawOverlays(ctx)) {
                    try { PetService.start(ctx, PetService.ACT_REMIND) { it.putExtra("id", id) } } catch (e: Exception) { }
                }
            }
        }
    }
}

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        Store.init(ctx)
        Reminders.rescheduleAll(ctx)
        if (Store.petActive && Settings.canDrawOverlays(ctx)) {
            try { PetService.start(ctx) } catch (e: Exception) { }
        }
    }
}
