package com.example.family_todo_mobile

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager

private const val CALL_RING_TIMEOUT_MS = 60_000L

object IncomingCallAlertManager {
    private val handler = Handler(Looper.getMainLooper())
    private val stopRunnable = Runnable { stop() }
    private var player: MediaPlayer? = null
    private var vibrator: Vibrator? = null

    @Synchronized
    fun start(context: Context) {
        stop()
        val appContext = context.applicationContext
        val mode = ringerMode(appContext)
        if (mode == AudioManager.RINGER_MODE_NORMAL) {
            player = createRingtonePlayer(appContext)
        }
        if (mode != AudioManager.RINGER_MODE_SILENT) {
            vibrator = startVibration(appContext)
        }
        handler.postDelayed(stopRunnable, CALL_RING_TIMEOUT_MS)
    }

    @Synchronized
    fun stop() {
        handler.removeCallbacks(stopRunnable)
        player?.let { current ->
            runCatching {
                if (current.isPlaying) {
                    current.stop()
                }
            }
            runCatching { current.release() }
        }
        player = null
        vibrator?.let { current ->
            runCatching { current.cancel() }
        }
        vibrator = null
    }

    private fun createRingtonePlayer(context: Context): MediaPlayer? {
        val ringtoneUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            ?: return null
        val nextPlayer = MediaPlayer()
        return try {
            nextPlayer.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            nextPlayer.setDataSource(context, ringtoneUri)
            nextPlayer.isLooping = true
            nextPlayer.prepare()
            nextPlayer.start()
            nextPlayer
        } catch (_: Exception) {
            runCatching { nextPlayer.release() }
            null
        }
    }

    private fun startVibration(context: Context): Vibrator? {
        val current = vibrator(context) ?: return null
        val pattern = longArrayOf(0, 850, 350, 850)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                current.vibrate(
                    VibrationEffect.createWaveform(pattern, 1)
                )
            } else {
                @Suppress("DEPRECATION")
                current.vibrate(pattern, 1)
            }
        } catch (_: Exception) {
            return null
        }
        return current
    }

    private fun vibrator(context: Context): Vibrator? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            return context.getSystemService(VibratorManager::class.java)
                ?.defaultVibrator
        }
        @Suppress("DEPRECATION")
        return context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
    }

    private fun ringerMode(context: Context): Int {
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        return audio?.ringerMode ?: AudioManager.RINGER_MODE_NORMAL
    }
}
