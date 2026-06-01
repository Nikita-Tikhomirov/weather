package com.example.family_todo_mobile

import android.content.Intent

const val PUSH_ACTION_OPEN = "com.example.family_todo_mobile.action.OPEN_PUSH"
const val PUSH_ACTION_MARK_READ = "com.example.family_todo_mobile.action.MARK_READ"
const val PUSH_CHANNEL_ID = "family_updates"
const val PUSH_PREFS = "FlutterSharedPreferences"

val pushApiBaseUrl: String get() = BuildConfig.PUSH_API_BASE_URL
val pushApiKey: String get() = BuildConfig.PUSH_API_KEY

fun isChatPush(data: Map<String, String>): Boolean {
    val kind = data["entity"] ?: data["type"] ?: ""
    return kind == "chat_message" && !data["conversation_key"].isNullOrBlank()
}

fun Intent.putPushData(data: Map<String, String>): Intent {
    data.forEach { (key, value) -> putExtra("push_$key", value) }
    return this
}

fun Intent.pushData(): Map<String, String> {
    val out = linkedMapOf<String, String>()
    extras?.keySet()?.forEach { key ->
        if (key.startsWith("push_")) {
            out[key.removePrefix("push_")] = extras?.get(key)?.toString() ?: ""
        }
    }
    return out
}
