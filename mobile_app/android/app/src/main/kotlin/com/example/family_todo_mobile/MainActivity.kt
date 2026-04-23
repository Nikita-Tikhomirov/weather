package com.example.family_todo_mobile

import com.google.firebase.installations.FirebaseInstallations
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "family_todo_mobile/firebase_installations"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "deleteInstallation" -> {
                    FirebaseInstallations.getInstance().delete()
                        .addOnSuccessListener { result.success(true) }
                        .addOnFailureListener { result.error("fis_delete_failed", it.message, null) }
                }
                else -> result.notImplemented()
            }
        }
    }
}
