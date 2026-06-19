package com.example.family_todo_mobile

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper

private val REAPPLY_ROUTE_DELAYS_MS = longArrayOf(200L, 700L, 1_500L)

object CallAudioRouteManager {
    private enum class Route {
        Speaker,
        ExternalOrEarpiece,
        ExternalOrSpeaker,
    }

    private val handler = Handler(Looper.getMainLooper())
    private var savedMode: Int? = null
    private var savedSpeakerphoneOn: Boolean? = null
    private var lastRoute: Route? = null

    fun configureForCall(context: Context) {
        val audio = audioManager(context) ?: return
        saveAudioState(audio)
        try {
            audio.mode = AudioManager.MODE_IN_COMMUNICATION
        } catch (_: Exception) {
        }
    }

    fun setSpeakerOn(context: Context, enabled: Boolean) {
        applyRoute(
            context.applicationContext,
            if (enabled) Route.Speaker else Route.ExternalOrEarpiece,
            scheduleReapply = true
        )
    }

    fun preferHeadsetOrBluetooth(context: Context) {
        applyRoute(
            context.applicationContext,
            Route.ExternalOrSpeaker,
            scheduleReapply = true
        )
    }

    fun clearCommunicationDevice(context: Context) {
        handler.removeCallbacksAndMessages(null)
        lastRoute = null
        val audio = audioManager(context) ?: return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                audio.clearCommunicationDevice()
            }
        } catch (_: Exception) {
        }
        stopBluetoothSco(audio)
        setSpeakerphone(audio, savedSpeakerphoneOn ?: false)
        try {
            audio.mode = savedMode ?: AudioManager.MODE_NORMAL
        } catch (_: Exception) {
        }
        savedMode = null
        savedSpeakerphoneOn = null
    }

    private fun applyRoute(
        context: Context,
        route: Route,
        scheduleReapply: Boolean,
    ) {
        val audio = audioManager(context) ?: return
        configureForCall(context)
        when (route) {
            Route.Speaker -> routeToSpeaker(audio)
            Route.ExternalOrEarpiece -> routeToExternalOrBuiltIn(
                audio,
                fallbackToSpeaker = false
            )
            Route.ExternalOrSpeaker -> routeToExternalOrBuiltIn(
                audio,
                fallbackToSpeaker = true
            )
        }
        if (scheduleReapply) {
            scheduleRouteReapply(context.applicationContext, route)
        }
    }

    private fun scheduleRouteReapply(context: Context, route: Route) {
        handler.removeCallbacksAndMessages(null)
        lastRoute = route
        for (delayMs in REAPPLY_ROUTE_DELAYS_MS) {
            handler.postDelayed({
                if (lastRoute == route) {
                    applyRoute(context, route, scheduleReapply = false)
                }
            }, delayMs)
        }
    }

    private fun routeToSpeaker(audio: AudioManager) {
        stopBluetoothSco(audio)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val speaker = audio.availableCommunicationDevices.firstOrNull {
                it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER
            }
            if (speaker != null) {
                try {
                    audio.setCommunicationDevice(speaker)
                } catch (_: Exception) {
                }
            }
        }
        setSpeakerphone(audio, true)
    }

    private fun routeToExternalOrBuiltIn(
        audio: AudioManager,
        fallbackToSpeaker: Boolean,
    ) {
        setSpeakerphone(audio, false)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val device = preferredCommunicationDevice(audio, fallbackToSpeaker)
            if (device != null) {
                try {
                    if (audio.setCommunicationDevice(device)) {
                        return
                    }
                } catch (_: Exception) {
                }
            }
            if (fallbackToSpeaker) {
                routeToSpeaker(audio)
            } else {
                try {
                    audio.clearCommunicationDevice()
                } catch (_: Exception) {
                }
            }
            return
        }

        if (routeLegacyBluetoothIfConnected(audio)) return
        if (legacyOutputDevices(audio).any { isWiredDevice(it) }) return
        if (fallbackToSpeaker) {
            routeToSpeaker(audio)
        } else {
            setSpeakerphone(audio, false)
        }
    }

    private fun preferredCommunicationDevice(
        audio: AudioManager,
        fallbackToSpeaker: Boolean,
    ): AudioDeviceInfo? {
        val priorities = audio.availableCommunicationDevices
            .mapNotNull { device ->
                communicationPriority(device, fallbackToSpeaker)?.let { priority ->
                    priority to device
                }
            }
            .sortedBy { it.first }
        return priorities.firstOrNull()?.second
    }

    private fun communicationPriority(
        device: AudioDeviceInfo,
        fallbackToSpeaker: Boolean,
    ): Int? {
        return when {
            isBluetoothDevice(device) -> 0
            isWiredDevice(device) -> 1
            device.type == AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> 2
            fallbackToSpeaker &&
                device.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> 3
            else -> null
        }
    }

    private fun routeLegacyBluetoothIfConnected(audio: AudioManager): Boolean {
        if (!legacyOutputDevices(audio).any { isBluetoothDevice(it) }) {
            return false
        }
        return try {
            setSpeakerphone(audio, false)
            @Suppress("DEPRECATION")
            audio.startBluetoothSco()
            @Suppress("DEPRECATION")
            audio.isBluetoothScoOn = true
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun legacyOutputDevices(audio: AudioManager): List<AudioDeviceInfo> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return emptyList()
        return try {
            audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS).toList()
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun isBluetoothDevice(device: AudioDeviceInfo): Boolean {
        return device.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
            (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                device.type == AudioDeviceInfo.TYPE_BLE_HEADSET)
    }

    private fun isWiredDevice(device: AudioDeviceInfo): Boolean {
        return device.type == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
            device.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES ||
            device.type == AudioDeviceInfo.TYPE_USB_HEADSET
    }

    private fun saveAudioState(audio: AudioManager) {
        if (savedMode != null) return
        savedMode = audio.mode
        @Suppress("DEPRECATION")
        savedSpeakerphoneOn = audio.isSpeakerphoneOn
    }

    private fun setSpeakerphone(audio: AudioManager, enabled: Boolean) {
        try {
            @Suppress("DEPRECATION")
            audio.isSpeakerphoneOn = enabled
        } catch (_: Exception) {
        }
    }

    private fun stopBluetoothSco(audio: AudioManager) {
        try {
            @Suppress("DEPRECATION")
            audio.stopBluetoothSco()
            @Suppress("DEPRECATION")
            audio.isBluetoothScoOn = false
        } catch (_: Exception) {
        }
    }

    private fun audioManager(context: Context): AudioManager? {
        return context.applicationContext
            .getSystemService(Context.AUDIO_SERVICE) as? AudioManager
    }
}
