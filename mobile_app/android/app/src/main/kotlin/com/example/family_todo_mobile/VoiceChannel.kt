@file:Suppress("DEPRECATION")

package com.example.family_todo_mobile

import android.Manifest
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

object VoiceChannel {
    private const val PERMISSION_CODE = 1001
    private var pendingResult: MethodChannel.Result? = null

    fun register(flutterEngine: FlutterEngine, activity: android.app.Activity? = null) {
        var recorder: android.media.MediaRecorder? = null
        var player: android.media.MediaPlayer? = null
        var currentVoiceUrl: String? = null

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "family_todo_mobile/voice"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPermission" -> {
                    val act = activity
                    if (act == null) {
                        result.success(true) // Can't check, assume granted
                        return@setMethodCallHandler
                    }
                    if (ContextCompat.checkSelfPermission(act, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
                        result.success(true)
                    } else {
                        pendingResult = result
                        ActivityCompat.requestPermissions(act, arrayOf(Manifest.permission.RECORD_AUDIO), PERMISSION_CODE)
                    }
                }
                "startRecording" -> {
                    val path = call.argument<String>("path") ?: return@setMethodCallHandler result.error("NO_PATH", null, null)
                    try {
                        recorder = android.media.MediaRecorder().apply {
                            setAudioSource(android.media.MediaRecorder.AudioSource.MIC)
                            setOutputFormat(android.media.MediaRecorder.OutputFormat.MPEG_4)
                            setAudioEncoder(android.media.MediaRecorder.AudioEncoder.AAC)
                            setAudioSamplingRate(44100)
                            setAudioEncodingBitRate(96000)
                            setOutputFile(path)
                            prepare()
                            start()
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("RECORD_ERR", e.message, null)
                    }
                }
                "stopRecording" -> {
                    try {
                        recorder?.apply { stop(); release() }
                        recorder = null
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("STOP_ERR", e.message, null)
                    }
                }
                "playVoice" -> {
                    val url = call.argument<String>("url") ?: return@setMethodCallHandler result.error("NO_URL", null, null)
                    try {
                        val existing = player
                        if (existing != null && currentVoiceUrl == url) {
                            existing.start()
                            result.success(true)
                            return@setMethodCallHandler
                        }
                        player?.release()
                        currentVoiceUrl = url
                        player = android.media.MediaPlayer().apply {
                            setDataSource(url)
                            setOnPreparedListener { start() }
                            setOnCompletionListener { release(); player = null; currentVoiceUrl = null }
                            setOnErrorListener { _, what, extra ->
                                android.util.Log.e("VoiceChannel", "MediaPlayer error what=$what extra=$extra url=$url")
                                release()
                                player = null
                                currentVoiceUrl = null
                                false
                            }
                            prepareAsync()
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("PLAY_ERR", e.message, null)
                    }
                }
                "pauseVoice" -> {
                    try {
                        player?.apply { if (isPlaying) pause() }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("PAUSE_PLAY_ERR", e.message, null)
                    }
                }
                "stopVoice" -> {
                    try {
                        player?.apply { if (isPlaying) stop(); release() }
                        player = null
                        currentVoiceUrl = null
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("STOP_PLAY_ERR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode == PERMISSION_CODE && pendingResult != null) {
            pendingResult!!.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
            pendingResult = null
        }
    }
}
