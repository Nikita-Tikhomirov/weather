package com.example.family_todo_mobile

import android.content.Context
import android.os.Build
import android.telecom.CallAudioState
import android.telecom.Connection
import android.telecom.DisconnectCause
import android.telecom.TelecomManager
import android.telecom.VideoProfile

class FamilyCallConnection(
    private val appContext: Context,
    private val data: Map<String, String>,
    private val isSelfManaged: Boolean,
) : Connection() {
    @Volatile
    private var incomingUiShown = false

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
        setVideoState(videoStateForCall())
        setConnectionCapabilities(connectionCapabilities(data))
        setRinging()
        TelecomCallManager.trackIncomingConnection(data, this)
    }

    override fun onShowIncomingCallUi() {
        incomingUiShown = true
        FamilyMessagingService.showIncomingCallNotification(appContext, data)
        TelecomCallManager.openIncomingCallActivity(appContext, data)
    }

    override fun onAnswer() {
        onAnswer(videoStateForCall())
    }

    override fun onAnswer(videoState: Int) {
        activate(videoState)
        TelecomCallManager.openCallActivity(appContext, data, "accept")
    }

    @Suppress("DEPRECATION", "OVERRIDE_DEPRECATION")
    override fun onCallAudioStateChanged(state: CallAudioState) {
        super.onCallAudioStateChanged(state)
        if (!isVideoCall()) return
        if (state.route == CallAudioState.ROUTE_SPEAKER) return
        if (state.supportedRouteMask and CallAudioState.ROUTE_SPEAKER == 0) {
            return
        }
        forceVideoSpeakerRoute()
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
        activate(videoStateForCall())
    }

    fun rejectFromNative() {
        disconnectAndDestroy(DisconnectCause.REJECTED)
    }

    fun endFromNative() {
        disconnectAndDestroy(DisconnectCause.LOCAL)
    }

    fun hasShownIncomingUi(): Boolean {
        return incomingUiShown
    }

    private fun connectionCapabilities(data: Map<String, String>): Int {
        var capabilities = CAPABILITY_MUTE or CAPABILITY_SUPPORT_HOLD
        if (TelecomCallManager.isVideoCall(data)) {
            capabilities = capabilities or
                CAPABILITY_SUPPORTS_VT_LOCAL_BIDIRECTIONAL or
                CAPABILITY_SUPPORTS_VT_REMOTE_BIDIRECTIONAL
        }
        return capabilities
    }

    private fun videoStateForCall(): Int {
        return if (isVideoCall()) {
            VideoProfile.STATE_BIDIRECTIONAL
        } else {
            VideoProfile.STATE_AUDIO_ONLY
        }
    }

    private fun activate(videoState: Int) {
        setVideoState(videoState)
        setActive()
        forceVideoSpeakerRoute()
    }

    private fun isVideoCall(): Boolean {
        return TelecomCallManager.isVideoCall(data)
    }

    @Suppress("DEPRECATION")
    private fun forceVideoSpeakerRoute() {
        if (!isVideoCall()) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                setAudioRoute(CallAudioState.ROUTE_SPEAKER)
            } catch (_: Exception) {
            }
        }
        CallAudioRouteManager.setSpeakerOn(appContext, true)
    }

    private fun disconnectAndDestroy(causeCode: Int) {
        setDisconnected(DisconnectCause(causeCode))
        TelecomCallManager.untrackIncomingConnection(data, this)
        destroy()
    }
}
