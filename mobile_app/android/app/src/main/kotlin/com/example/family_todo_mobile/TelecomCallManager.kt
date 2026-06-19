package com.example.family_todo_mobile

import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.telecom.PhoneAccount
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import android.telecom.VideoProfile

private const val MANAGED_PHONE_ACCOUNT_ID = "family_todo_managed_calls"
private const val SELF_MANAGED_PHONE_ACCOUNT_ID = "family_todo_self_managed_calls"
private const val TELECOM_EXTRA_PREFIX = "family_todo_mobile.push."

object TelecomCallManager {
    fun registerPhoneAccounts(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val telecom = context.getSystemService(TelecomManager::class.java) ?: return
        registerManagedPhoneAccount(context, telecom)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            registerSelfManagedPhoneAccount(context, telecom)
        }
    }

    fun reportIncomingCall(context: Context, data: Map<String, String>): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        val telecom = context.getSystemService(TelecomManager::class.java) ?: return false
        registerPhoneAccounts(context)
        val extras = incomingCallExtras(data)

        if (isManagedPhoneAccountEnabled(context, telecom) &&
            tryAddIncomingCall(telecom, managedPhoneAccountHandle(context), extras)
        ) {
            return true
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            return tryAddIncomingCall(telecom, selfManagedPhoneAccountHandle(context), extras)
        }
        return false
    }

    fun isManagedPhoneAccountEnabled(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        val telecom = context.getSystemService(TelecomManager::class.java) ?: return false
        registerPhoneAccounts(context)
        return isManagedPhoneAccountEnabled(context, telecom)
    }

    fun isSelfManagedPhoneAccount(handle: PhoneAccountHandle): Boolean {
        return handle.id == SELF_MANAGED_PHONE_ACCOUNT_ID
    }

    fun canUseFullScreenIntent(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return true
        val manager = context.getSystemService(NotificationManager::class.java) ?: return true
        return try {
            manager.canUseFullScreenIntent()
        } catch (_: Exception) {
            false
        }
    }

    fun fullScreenIntentSettingsIntent(context: Context): Intent {
        val action = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT
        } else {
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS
        }
        return Intent(action)
            .setData(Uri.parse("package:${context.packageName}"))
            .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }

    fun callDataFromRequest(request: android.telecom.ConnectionRequest): Map<String, String> {
        val out = linkedMapOf<String, String>()
        collectPushExtras(request.extras, out)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            collectPushExtras(
                request.extras.getBundle(TelecomManager.EXTRA_INCOMING_CALL_EXTRAS),
                out
            )
        }
        return out
    }

    fun openCallActivity(
        context: Context,
        data: Map<String, String>,
        callAction: String,
    ) {
        if (callAction == "accept") {
            cancelIncomingCallNotification(context, data)
        }
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
        context.startActivity(intent)
    }

    fun openIncomingCallActivity(context: Context, data: Map<String, String>) {
        val callData = data.toMutableMap()
        callData["call_action"] = "show"
        val intent = Intent(context, IncomingCallActivity::class.java)
            .setAction(PUSH_ACTION_OPEN)
            .putPushData(callData)
            .addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            )
        try {
            context.startActivity(intent)
        } catch (_: Exception) {
        }
    }

    fun rejectIncomingCall(context: Context, data: Map<String, String>) {
        val intent = Intent(context, PushActionReceiver::class.java)
            .setAction(PUSH_ACTION_CALL_DECLINE)
            .putPushData(data)
        context.sendBroadcast(intent)
    }

    fun cancelIncomingCallNotification(context: Context, data: Map<String, String>) {
        try {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.cancel(callNotificationId(data))
        } catch (_: Exception) {
        }
    }

    fun phoneAccountSettingsIntent(): Intent {
        return Intent(TelecomManager.ACTION_CHANGE_PHONE_ACCOUNTS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }

    fun callerDisplayName(data: Map<String, String>): String {
        return data["caller_display_name"]
            ?: data["caller_name"]
            ?: data["title"]
            ?: data["caller_profile"]
            ?: "Контакт"
    }

    fun isVideoCall(data: Map<String, String>): Boolean {
        return data["call_type"]?.trim()?.lowercase() == "video"
    }

    fun callAddress(data: Map<String, String>): Uri {
        val raw = data["caller_phone"]
            ?: data["phone"]
            ?: data["caller_profile"]
            ?: data["session_id"]
            ?: "unknown"
        val phone = raw.filter { it.isDigit() || it == '+' || it == '*' || it == '#' }
        if (phone.isNotBlank()) {
            return Uri.fromParts(PhoneAccount.SCHEME_TEL, phone, null)
        }
        val sipName = raw
            .trim()
            .replace(Regex("[^A-Za-z0-9_.@-]"), "_")
            .ifBlank { "unknown" }
        return Uri.fromParts(PhoneAccount.SCHEME_SIP, sipName, null)
    }

    private fun registerManagedPhoneAccount(context: Context, telecom: TelecomManager) {
        try {
            val account = PhoneAccount.Builder(
                managedPhoneAccountHandle(context),
                "Family Todo"
            )
                .setCapabilities(PhoneAccount.CAPABILITY_CALL_PROVIDER)
                .setSupportedUriSchemes(listOf(PhoneAccount.SCHEME_TEL, PhoneAccount.SCHEME_SIP))
                .setShortDescription("Family Todo")
                .setIcon(Icon.createWithResource(context, context.applicationInfo.icon))
                .build()
            telecom.registerPhoneAccount(account)
        } catch (_: Exception) {
        }
    }

    private fun registerSelfManagedPhoneAccount(context: Context, telecom: TelecomManager) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            val account = PhoneAccount.Builder(
                selfManagedPhoneAccountHandle(context),
                "Family Todo"
            )
                .setCapabilities(PhoneAccount.CAPABILITY_SELF_MANAGED)
                .setSupportedUriSchemes(listOf(PhoneAccount.SCHEME_TEL, PhoneAccount.SCHEME_SIP))
                .setShortDescription("Family Todo")
                .setIcon(Icon.createWithResource(context, context.applicationInfo.icon))
                .build()
            telecom.registerPhoneAccount(account)
        } catch (_: Exception) {
        }
    }

    private fun isManagedPhoneAccountEnabled(
        context: Context,
        telecom: TelecomManager,
    ): Boolean {
        return try {
            telecom.getPhoneAccount(managedPhoneAccountHandle(context))?.isEnabled == true
        } catch (_: Exception) {
            false
        }
    }

    private fun tryAddIncomingCall(
        telecom: TelecomManager,
        handle: PhoneAccountHandle,
        extras: Bundle,
    ): Boolean {
        return try {
            telecom.addNewIncomingCall(handle, extras)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun incomingCallExtras(data: Map<String, String>): Bundle {
        val pushExtras = Bundle()
        data.forEach { (key, value) ->
            pushExtras.putString("$TELECOM_EXTRA_PREFIX$key", value)
        }

        return Bundle(pushExtras).apply {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                putParcelable(TelecomManager.EXTRA_INCOMING_CALL_ADDRESS, callAddress(data))
                putInt(
                    TelecomManager.EXTRA_INCOMING_VIDEO_STATE,
                    if (isVideoCall(data)) {
                        VideoProfile.STATE_BIDIRECTIONAL
                    } else {
                        VideoProfile.STATE_AUDIO_ONLY
                    }
                )
                putBundle(TelecomManager.EXTRA_INCOMING_CALL_EXTRAS, pushExtras)
            }
        }
    }

    private fun collectPushExtras(bundle: Bundle?, out: MutableMap<String, String>) {
        if (bundle == null) return
        for (key in bundle.keySet()) {
            if (key.startsWith(TELECOM_EXTRA_PREFIX)) {
                out[key.removePrefix(TELECOM_EXTRA_PREFIX)] =
                    bundle.get(key)?.toString().orEmpty()
            }
        }
    }

    private fun managedPhoneAccountHandle(context: Context): PhoneAccountHandle {
        return PhoneAccountHandle(connectionServiceName(context), MANAGED_PHONE_ACCOUNT_ID)
    }

    private fun selfManagedPhoneAccountHandle(context: Context): PhoneAccountHandle {
        return PhoneAccountHandle(connectionServiceName(context), SELF_MANAGED_PHONE_ACCOUNT_ID)
    }

    private fun connectionServiceName(context: Context): ComponentName {
        return ComponentName(context, FamilyConnectionService::class.java)
    }
}
