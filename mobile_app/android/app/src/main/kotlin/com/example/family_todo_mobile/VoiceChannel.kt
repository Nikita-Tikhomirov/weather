@file:Suppress("DEPRECATION")

package com.example.family_todo_mobile

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

object VoiceChannel {
    fun register(flutterEngine: FlutterEngine) {
        var recorder: android.media.MediaRecorder? = null
        var player: android.media.MediaPlayer? = null

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "family_todo_mobile/voice"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startRecording" -> {
                    val path = call.argument<String>("path") ?: return@setMethodCallHandler result.error("NO_PATH", null, null)
                    try {
                        recorder = android.media.MediaRecorder().apply {
                            setAudioSource(android.media.MediaRecorder.AudioSource.MIC)
                            setOutputFormat(android.media.MediaRecorder.OutputFormat.MPEG_4)
                            setAudioEncoder(android.media.MediaRecorder.AudioEncoder.AAC)
                            setAudioSamplingRate(44100)
                            setAudioBitRate(96000)
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
                        player?.release()
                        player = android.media.MediaPlayer().apply {
                            setDataSource(url)
                            setOnPreparedListener { start() }
                            setOnCompletionListener { release(); player = null }
                            prepareAsync()
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("PLAY_ERR", e.message, null)
                    }
                }
                "stopVoice" -> {
                    try {
                        player?.apply { if (isPlaying) stop(); release() }
                        player = null
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("STOP_PLAY_ERR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
