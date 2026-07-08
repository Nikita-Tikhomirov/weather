package com.example.family_todo_mobile

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL

class PushActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            PUSH_ACTION_MARK_READ -> markConversationRead(intent.pushData())
            PUSH_ACTION_CALL_DECLINE -> declineIncomingCall(context, intent.pushData())
        }
    }

    private fun markConversationRead(data: Map<String, String>) {
        val conversationKey = data["conversation_key"]?.trim().orEmpty()
        val actor = data["recipient_profile"]?.trim().orEmpty()
        if (conversationKey.isEmpty() || actor.isEmpty()) return

        Thread {
            try {
                postJson(
                    path = "/chat/conversations/read",
                    body = "{\"actor_profile\":\"${jsonEscape(actor)}\",\"conversation_key\":\"${jsonEscape(conversationKey)}\"}"
                )
            } catch (_: Exception) {
            }
        }.start()
    }

    private fun declineIncomingCall(context: Context, data: Map<String, String>) {
        TelecomCallManager.rejectIncomingConnection(data)
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(callNotificationId(data))

        val sessionId = data["session_id"]?.trim().orEmpty()
        val actor = (
            data["recipient_profile"]
                ?: data["callee_profile"]
                ?: data["actor_profile"]
                ?: ""
            ).trim()
        if (sessionId.isEmpty() || actor.isEmpty()) return

        Thread {
            try {
                postJson(
                    path = "/call/reject",
                    body = "{\"actor_profile\":\"${jsonEscape(actor)}\",\"session_id\":\"${jsonEscape(sessionId)}\"}"
                )
            } catch (_: Exception) {
            }
        }.start()
    }

    private fun postJson(path: String, body: String) {
        val connection = URL("$pushApiBaseUrl$path").openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "POST"
            connection.setRequestProperty("Content-Type", "application/json; charset=utf-8")
            connection.setRequestProperty("X-Api-Key", pushApiKey)
            connection.doOutput = true
            OutputStreamWriter(connection.outputStream, Charsets.UTF_8).use { it.write(body) }
            connection.inputStream.close()
        } finally {
            connection.disconnect()
        }
    }

    private fun jsonEscape(value: String): String {
        return value.replace("\\", "\\\\").replace("\"", "\\\"")
    }
}
