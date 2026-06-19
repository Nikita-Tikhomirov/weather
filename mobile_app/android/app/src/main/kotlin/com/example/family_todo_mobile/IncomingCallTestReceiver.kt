package com.example.family_todo_mobile

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class IncomingCallTestReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != PUSH_ACTION_TEST_INCOMING_CALL) return
        val data = incomingCallData(intent)
        TelecomCallManager.registerPhoneAccounts(context)
        if (!TelecomCallManager.reportIncomingCall(context, data)) {
            TelecomCallManager.showIncomingCallFallback(context, data)
        }
    }

    private fun incomingCallData(intent: Intent): Map<String, String> {
        val sessionId = stringExtra(
            intent,
            "session_id",
            "qa_${System.currentTimeMillis()}"
        )
        val rawCallType = stringExtra(intent, "call_type", "audio")
        val callType = if (rawCallType.equals("video", ignoreCase = true)) {
            "video"
        } else {
            "audio"
        }
        val callerName = stringExtra(
            intent,
            "caller_display_name",
            if (callType == "video") "QA Video Call" else "QA Audio Call"
        )
        val calleeProfile = stringExtra(
            intent,
            "callee_profile",
            stringExtra(intent, "recipient_profile", "qa_callee")
        )
        val recipientProfile = stringExtra(intent, "recipient_profile", calleeProfile)
        val callTitle = if (callType == "video") "Видеозвонок" else "Аудиозвонок"
        return linkedMapOf(
            "entity" to "call_incoming",
            "type" to "call_incoming",
            "session_id" to sessionId,
            "event_id" to stringExtra(intent, "event_id", "qa_event_$sessionId"),
            "conversation_key" to stringExtra(intent, "conversation_key", "qa_call"),
            "caller_profile" to stringExtra(intent, "caller_profile", "qa_caller"),
            "caller_display_name" to callerName,
            "caller_name" to callerName,
            "callee_profile" to calleeProfile,
            "recipient_profile" to recipientProfile,
            "call_type" to callType,
            "title" to callTitle,
            "body" to "Входящий звонок от $callerName",
        )
    }

    private fun stringExtra(intent: Intent, key: String, defaultValue: String): String {
        return intent.getStringExtra(key)?.trim()?.takeIf { it.isNotEmpty() }
            ?: defaultValue
    }
}
