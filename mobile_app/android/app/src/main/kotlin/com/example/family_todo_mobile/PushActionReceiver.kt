package com.example.family_todo_mobile

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL

class PushActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != PUSH_ACTION_MARK_READ) return
        val data = intent.pushData()
        val conversationKey = data["conversation_key"]?.trim().orEmpty()
        val actor = data["recipient_profile"]?.trim().orEmpty()
        if (conversationKey.isEmpty() || actor.isEmpty()) return

        Thread {
            try {
                val connection = URL("$pushApiBaseUrl/chat/conversations/read").openConnection() as HttpURLConnection
                connection.requestMethod = "POST"
                connection.setRequestProperty("Content-Type", "application/json; charset=utf-8")
                connection.setRequestProperty("X-Api-Key", pushApiKey)
                connection.doOutput = true
                val body = "{\"actor_profile\":\"${jsonEscape(actor)}\",\"conversation_key\":\"${jsonEscape(conversationKey)}\"}"
                OutputStreamWriter(connection.outputStream, Charsets.UTF_8).use { it.write(body) }
                connection.inputStream.close()
                connection.disconnect()
            } catch (_: Exception) {
            }
        }.start()
    }

    private fun jsonEscape(value: String): String {
        return value.replace("\\", "\\\\").replace("\"", "\\\"")
    }
}
