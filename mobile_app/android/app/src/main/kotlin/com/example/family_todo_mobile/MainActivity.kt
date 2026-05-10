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
    private var shareChannel: MethodChannel? = null
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

        // Share intent receiver channel
        shareChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "family_todo_mobile/share"
        )
        handleShareIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleShareIntent(intent)
    }

    private fun handleShareIntent(intent: Intent?) {
        if (intent == null) return
        if (intent.action != Intent.ACTION_SEND && intent.action != Intent.ACTION_SEND_MULTIPLE) return

        val type = intent.type ?: return
        sharedText = null
        sharedImageUris = null

        if (type.startsWith("text/plain")) {
            sharedText = intent.getStringExtra(Intent.EXTRA_TEXT)
        } else if (type.startsWith("image/")) {
            if (intent.action == Intent.ACTION_SEND_MULTIPLE) {
                val uris = intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
                if (uris != null) {
                    sharedImageUris = ArrayList()
                    for (uri in uris) {
                        sharedImageUris!!.add(uri.toString())
                    }
                }
            } else {
                val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                if (uri != null) {
                    sharedImageUris = ArrayList()
                    sharedImageUris!!.add(uri.toString())
                }
            }
        }

        val payload = mutableMapOf<String, Any>()
        if (sharedText != null) {
            payload["text"] = sharedText!!
        }
        if (sharedImageUris != null) {
            payload["imageUris"] = sharedImageUris!!
        }
        if (payload.isNotEmpty()) {
            shareChannel?.invokeMethod("onShareReceived", payload)
        }
    }
}
