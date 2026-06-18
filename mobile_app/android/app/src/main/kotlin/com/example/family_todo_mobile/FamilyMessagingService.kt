package com.example.family_todo_mobile

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.Person
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import kotlin.math.abs

class FamilyMessagingService : FirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
        val data = message.data
        when {
            isIncomingCallPush(data) -> {
                TelecomCallManager.registerPhoneAccounts(this)
                if (!TelecomCallManager.reportIncomingCall(this, data)) {
                    showIncomingCallNotification(this, data)
                }
            }
            isChatPush(data) -> showChatNotification(data)
        }
    }

    private fun showChatNotification(data: Map<String, String>) {
        ensureChannels(this)
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

    companion object {
        fun showIncomingCallNotification(context: Context, data: Map<String, String>) {
            ensureChannels(context)
            val notificationId = callNotificationId(data)
            val callType = data["call_type"]?.trim()?.lowercase() ?: "audio"
            val isVideo = callType == "video"
            val caller = data["caller_display_name"]
                ?: data["caller_name"]
                ?: data["title"]
                ?: data["caller_profile"]
                ?: "Контакт"
            val title = if (isVideo) "Видеозвонок" else "Звонок"
            val body = "$caller звонит"
            val ringtoneUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)

            val openPendingIntent = callActivityPendingIntent(
                context = context,
                requestCode = notificationId,
                data = data,
                callAction = "show"
            )
            val acceptPendingIntent = callActivityPendingIntent(
                context = context,
                requestCode = notificationId + 10,
                data = data,
                callAction = "accept"
            )
            val declineIntent = Intent(context, PushActionReceiver::class.java)
                .setAction(PUSH_ACTION_CALL_DECLINE)
                .putPushData(data)
            val declinePendingIntent = PendingIntent.getBroadcast(
                context,
                notificationId + 20,
                declineIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val callerPerson = Person.Builder()
                .setName(caller)
                .setImportant(true)
                .build()
            val callStyle = NotificationCompat.CallStyle.forIncomingCall(
                callerPerson,
                declinePendingIntent,
                acceptPendingIntent
            )

            val notification = NotificationCompat.Builder(context, PUSH_CALL_CHANNEL_ID)
                .setSmallIcon(context.applicationInfo.icon)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(callStyle)
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_CALL)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setOngoing(true)
                .setAutoCancel(false)
                .setSound(ringtoneUri)
                .setDefaults(NotificationCompat.DEFAULT_VIBRATE or NotificationCompat.DEFAULT_LIGHTS)
                .setVibrate(longArrayOf(0, 900, 300, 900, 300, 900))
                .setOnlyAlertOnce(false)
                .setColorized(true)
                .setTimeoutAfter(60_000)
                .setContentIntent(openPendingIntent)
                .setFullScreenIntent(openPendingIntent, true)
                .addAction(context.applicationInfo.icon, "Отклонить", declinePendingIntent)
                .addAction(context.applicationInfo.icon, "Принять", acceptPendingIntent)
                .build()

            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.notify(notificationId, notification)
        }

        private fun callActivityPendingIntent(
            context: Context,
            requestCode: Int,
            data: Map<String, String>,
            callAction: String
        ): PendingIntent {
            val callData = data.toMutableMap()
            callData["call_action"] = callAction
            val intent = Intent(context, MainActivity::class.java)
                .setAction(PUSH_ACTION_OPEN)
                .putPushData(callData)
                .addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                )
            return PendingIntent.getActivity(
                context,
                requestCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        private fun ensureChannels(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channel = NotificationChannel(
                PUSH_CHANNEL_ID,
                "Семейные уведомления",
                NotificationManager.IMPORTANCE_HIGH
            )
            channel.description = "Пуш-уведомления о задачах и сообщениях"
            manager.createNotificationChannel(channel)

            val ringtoneUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            val callAudioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            val callChannel = NotificationChannel(
                PUSH_CALL_CHANNEL_ID,
                "Семейные звонки",
                NotificationManager.IMPORTANCE_HIGH
            )
            callChannel.description = "Входящие аудио- и видеозвонки"
            callChannel.setSound(ringtoneUri, callAudioAttributes)
            callChannel.enableVibration(true)
            manager.createNotificationChannel(callChannel)
        }
    }
}
