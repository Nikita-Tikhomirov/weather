package com.example.family_todo_mobile

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import kotlin.math.abs

class FamilyMessagingService : FirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
        val data = message.data
        if (!isChatPush(data)) return
        showChatNotification(data)
    }

    private fun showChatNotification(data: Map<String, String>) {
        ensureChannel()
        val title = data["title"] ?: "Сообщение"
        val body = data["body"] ?: "Новое сообщение"
        val notificationId = abs((data["event_id"] ?: data["message_id"] ?: body).hashCode())

        val openIntent = Intent(this, MainActivity::class.java)
            .setAction(PUSH_ACTION_OPEN)
            .putPushData(data)
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val openPendingIntent = PendingIntent.getActivity(
            this,
            notificationId,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val markReadIntent = Intent(this, PushActionReceiver::class.java)
            .setAction(PUSH_ACTION_MARK_READ)
            .putPushData(data)
        val markReadPendingIntent = PendingIntent.getBroadcast(
            this,
            notificationId + 1,
            markReadIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, PUSH_CHANNEL_ID)
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setAutoCancel(true)
            .setContentIntent(openPendingIntent)
            .addAction(0, "Перейти", openPendingIntent)
            .addAction(0, "Пометить прочитанным", markReadPendingIntent)
            .build()

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(notificationId, notification)
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            PUSH_CHANNEL_ID,
            "Семейные уведомления",
            NotificationManager.IMPORTANCE_HIGH
        )
        channel.description = "Пуш-уведомления о задачах и сообщениях"
        manager.createNotificationChannel(channel)
    }
}
