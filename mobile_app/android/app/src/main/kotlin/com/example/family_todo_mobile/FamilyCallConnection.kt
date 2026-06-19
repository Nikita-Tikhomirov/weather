package com.example.family_todo_mobile

import android.content.Context
import android.telecom.Connection
import android.telecom.DisconnectCause
import android.telecom.TelecomManager
import android.telecom.VideoProfile

class FamilyCallConnection(
    private val appContext: Context,
    private val data: Map<String, String>,
    private val isSelfManaged: Boolean,
) : Connection() {
    init {
        if (isSelfManaged) {
            setConnectionProperties(PROPERTY_SELF_MANAGED)
        }
        setAddress(TelecomCallManager.callAddress(data), TelecomManager.PRESENTATION_ALLOWED)
        setCallerDisplayName(
            TelecomCallManager.callerDisplayName(data),
            TelecomManager.PRESENTATION_ALLOWED
        )
        setAudioModeIsVoip(true)
        setVideoState(
            if (TelecomCallManager.isVideoCall(data)) {
                VideoProfile.STATE_BIDIRECTIONAL
            } else {
                VideoProfile.STATE_AUDIO_ONLY
            }
        )
        setConnectionCapabilities(CAPABILITY_MUTE or CAPABILITY_SUPPORT_HOLD)
        setRinging()
        TelecomCallManager.trackIncomingConnection(data, this)
    }

    override fun onShowIncomingCallUi() {
        FamilyMessagingService.showIncomingCallNotification(appContext, data)
        TelecomCallManager.openIncomingCallActivity(appContext, data)
    }

    override fun onAnswer() {
        onAnswer(VideoProfile.STATE_AUDIO_ONLY)
    }

    override fun onAnswer(videoState: Int) {
        activate(videoState)
        TelecomCallManager.openCallActivity(appContext, data, "accept")
    }

    override fun onReject() {
        rejectFromNative()
        TelecomCallManager.rejectIncomingCall(appContext, data)
    }

    override fun onDisconnect() {
        disconnectAndDestroy(DisconnectCause.LOCAL)
    }

    override fun onAbort() {
        disconnectAndDestroy(DisconnectCause.CANCELED)
    }

    fun answerFromNative() {
        activate(
            if (TelecomCallManager.isVideoCall(data)) {
                VideoProfile.STATE_BIDIRECTIONAL
            } else {
                VideoProfile.STATE_AUDIO_ONLY
            }
        )
    }

    fun rejectFromNative() {
        disconnectAndDestroy(DisconnectCause.REJECTED)
    }

    fun endFromNative() {
        disconnectAndDestroy(DisconnectCause.LOCAL)
    }

    private fun activate(videoState: Int) {
        IncomingCallAlertManager.stop()
        setVideoState(videoState)
        setActive()
    }

    private fun disconnectAndDestroy(causeCode: Int) {
        IncomingCallAlertManager.stop()
        setDisconnected(DisconnectCause(causeCode))
        TelecomCallManager.untrackIncomingConnection(data, this)
        destroy()
    }
}
