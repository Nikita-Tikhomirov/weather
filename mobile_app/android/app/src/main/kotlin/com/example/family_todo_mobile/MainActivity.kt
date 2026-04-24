package com.example.family_todo_mobile

import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
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
                else -> result.notImplemented()
            }
        }
    }
}
