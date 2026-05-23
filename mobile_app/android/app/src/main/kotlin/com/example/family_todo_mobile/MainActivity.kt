package com.example.family_todo_mobile

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.firebase.installations.FirebaseInstallations
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var sharedText: String? = null
    private var sharedImageUris: ArrayList<String>? = null
    private var sharedVideoUris: ArrayList<String>? = null
    private var shareChannel: MethodChannel? = null
    private var pushChannel: MethodChannel? = null
    private var pendingSharePayload: Map<String, Any>? = null
    private var pendingPushPayload: Map<String, String>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "family_todo_mobile/firebase_installations"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInstallationId" -> {
                    FirebaseInstallations.getInstance().id
                        .addOnSuccessListener { result.success(it) }
                        .addOnFailureListener { result.error("fis_id_failed", it.message, null) }
                }
                "getPlayServicesStatus" -> {
                    val statusCode = GoogleApiAvailability.getInstance()
                        .isGooglePlayServicesAvailable(applicationContext)
                    val statusName = when (statusCode) {
                        ConnectionResult.SUCCESS -> "SUCCESS"
                        ConnectionResult.SERVICE_MISSING -> "SERVICE_MISSING"
                        ConnectionResult.SERVICE_UPDATING -> "SERVICE_UPDATING"
                        ConnectionResult.SERVICE_VERSION_UPDATE_REQUIRED -> "SERVICE_VERSION_UPDATE_REQUIRED"
                        ConnectionResult.SERVICE_DISABLED -> "SERVICE_DISABLED"
                        ConnectionResult.SERVICE_INVALID -> "SERVICE_INVALID"
                        else -> "CODE_$statusCode"
                    }
                    result.success(
                        mapOf(
                            "statusCode" to statusCode,
                            "statusName" to statusName,
                            "packageName" to applicationContext.packageName,
                        )
                    )
                }
                "deleteInstallation" -> {
                    FirebaseInstallations.getInstance().delete()
                        .addOnSuccessListener { result.success(true) }
                        .addOnFailureListener { result.error("fis_delete_failed", it.message, null) }
                }
                "scanFile" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        android.media.MediaScannerConnection.scanFile(
                            applicationContext,
                            arrayOf(path),
                            null
                        ) { _, _ -> }
                        result.success(true)
                    } else {
                        result.error("INVALID_PATH", "path is null", null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Voice recording + playback
        VoiceChannel.register(flutterEngine, this)

        pushChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "family_todo_mobile/push_intents"
        )
        pushChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "ready" -> {
                    val pending = pendingPushPayload
                    pendingPushPayload = null
                    if (pending != null) {
                        pushChannel?.invokeMethod("onPushOpened", pending)
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // Share intent receiver channel
        shareChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "family_todo_mobile/share"
        )
        shareChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "ready" -> {
                    // Flutter is ready to receive share data — deliver any pending share
                    val pending = pendingSharePayload
                    pendingSharePayload = null
                    if (pending != null) {
                        shareChannel?.invokeMethod("onShareReceived", pending)
                    }
                    result.success(true)
                }
                "saveImage" -> {
                    val url = call.argument<String>("url") ?: return@setMethodCallHandler result.error("NO_URL", null, null)
                    Thread {
                        try {
                            val bytes = java.net.URL(url).readBytes()
                            val filename = "FamilyTodo_${System.currentTimeMillis()}.jpg"
                            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                                val values = android.content.ContentValues().apply {
                                    put(android.provider.MediaStore.Images.Media.DISPLAY_NAME, filename)
                                    put(android.provider.MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
                                    put(android.provider.MediaStore.Images.Media.RELATIVE_PATH, android.os.Environment.DIRECTORY_PICTURES + "/FamilyTodo")
                                }
                                val uri = contentResolver.insert(android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                                uri?.let { contentResolver.openOutputStream(it)?.use { it.write(bytes) } }
                            } else {
                                val dir = java.io.File(android.os.Environment.getExternalStoragePublicDirectory(android.os.Environment.DIRECTORY_PICTURES), "FamilyTodo")
                                dir.mkdirs()
                                java.io.File(dir, filename).writeBytes(bytes)
                            }
                            runOnUiThread { result.success(true) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("SAVE_ERR", e.message, null) }
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
        handlePushIntent(intent)
        handleShareIntent(intent)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        VoiceChannel.onRequestPermissionsResult(requestCode, grantResults)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handlePushIntent(intent)
        handleShareIntent(intent)
    }

    private fun handlePushIntent(intent: Intent?) {
        if (intent == null) return
        if (intent.action != PUSH_ACTION_OPEN) return
        val payload = intent.pushData()
        if (payload.isEmpty()) return
        pendingPushPayload = payload
        pushChannel?.invokeMethod("onPushOpened", payload)
    }

    private fun handleShareIntent(intent: Intent?) {
        if (intent == null) return
        if (intent.action != Intent.ACTION_SEND && intent.action != Intent.ACTION_SEND_MULTIPLE) return

        val type = intent.type ?: return
        sharedText = null
        sharedImageUris = null
        sharedVideoUris = null

        if (type.startsWith("text/plain")) {
            sharedText = intent.getStringExtra(Intent.EXTRA_TEXT)
        } else if (type.startsWith("image/")) {
            sharedImageUris = extractUris(intent)
        } else if (type.startsWith("video/")) {
            sharedVideoUris = extractUris(intent)
        }

        val payload = mutableMapOf<String, Any>()
        if (sharedText != null) {
            payload["text"] = sharedText!!
        }
        if (sharedImageUris != null) {
            payload["imageUris"] = sharedImageUris!!
        }
        if (sharedVideoUris != null) {
            payload["videoUris"] = sharedVideoUris!!
        }
        if (payload.isNotEmpty()) {
            // Buffer if Flutter hasn't registered the share handler yet;
            // it will be delivered once the Flutter side sends the "ready" signal.
            pendingSharePayload = payload
            shareChannel?.invokeMethod("onShareReceived", payload)
        }
    }

    private fun extractUris(intent: Intent): ArrayList<String> {
        val uris = ArrayList<String>()
        if (intent.action == Intent.ACTION_SEND_MULTIPLE) {
            val list = intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
            if (list != null) {
                for (uri in list) {
                    uris.add(uri.toString())
                }
            }
        } else {
            val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            if (uri != null) {
                uris.add(uri.toString())
            }
        }
        return uris
    }
}
