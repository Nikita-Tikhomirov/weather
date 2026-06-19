package com.example.family_todo_mobile

import android.app.KeyguardManager
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.view.WindowManager
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.firebase.installations.FirebaseInstallations
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

class MainActivity : FlutterActivity() {
    private var sharedText: String? = null
    private var sharedImageUris: ArrayList<String>? = null
    private var sharedVideoUris: ArrayList<String>? = null
    private var shareChannel: MethodChannel? = null
    private var pushChannel: MethodChannel? = null
    private var pendingSharePayload: Map<String, Any>? = null
    private var pendingPushPayload: Map<String, String>? = null
    private var isPushChannelReady = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        TelecomCallManager.registerPhoneAccounts(this)
        applyCallWindowFlags(intent)
    }

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

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "family_todo_mobile/telecom"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "registerPhoneAccounts" -> {
                    TelecomCallManager.registerPhoneAccounts(this)
                    result.success(true)
                }
                "isManagedPhoneAccountEnabled" -> {
                    result.success(TelecomCallManager.isManagedPhoneAccountEnabled(this))
                }
                "openPhoneAccountSettings" -> {
                    try {
                        TelecomCallManager.registerPhoneAccounts(this)
                        startActivity(TelecomCallManager.phoneAccountSettingsIntent())
                        result.success(true)
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
                "canUseFullScreenIntent" -> {
                    result.success(TelecomCallManager.canUseFullScreenIntent(this))
                }
                "openFullScreenIntentSettings" -> {
                    try {
                        startActivity(TelecomCallManager.fullScreenIntentSettingsIntent(this))
                        result.success(true)
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
                "canPostNotifications" -> {
                    result.success(TelecomCallManager.canPostNotifications(this))
                }
                "openNotificationSettings" -> {
                    try {
                        startActivity(TelecomCallManager.notificationSettingsIntent(this))
                        result.success(true)
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
                "answerIncomingConnection" -> {
                    val sessionId = call.argument<String>("sessionId").orEmpty()
                    TelecomCallManager.answerIncomingConnection(mapOf("session_id" to sessionId))
                    result.success(sessionId.isNotBlank())
                }
                "rejectIncomingConnection" -> {
                    val sessionId = call.argument<String>("sessionId").orEmpty()
                    TelecomCallManager.rejectIncomingConnection(mapOf("session_id" to sessionId))
                    result.success(sessionId.isNotBlank())
                }
                "endIncomingConnection" -> {
                    val sessionId = call.argument<String>("sessionId").orEmpty()
                    TelecomCallManager.endIncomingConnection(mapOf("session_id" to sessionId))
                    result.success(sessionId.isNotBlank())
                }
                else -> result.notImplemented()
            }
        }

        pushChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "family_todo_mobile/push_intents"
        )
        pushChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "ready" -> {
                    isPushChannelReady = true
                    deliverPendingPushPayload()
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
                    val apiKey = call.argument<String>("apiKey").orEmpty()
                    val apiBaseUrl = call.argument<String>("apiBaseUrl").orEmpty()
                    Thread {
                        try {
                            saveImageToGallery(url, apiKey, apiBaseUrl)
                            runOnUiThread { result.success(true) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("SAVE_ERR", e.message, null) }
                        }
                    }.start()
                }
                "saveImageBytes" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                        ?: return@setMethodCallHandler result.error("NO_BYTES", null, null)
                    val contentType = call.argument<String>("contentType")
                    Thread {
                        try {
                            saveImageBytesToGallery(bytes, contentType)
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
        applyCallWindowFlags(intent)
        handlePushIntent(intent)
        handleShareIntent(intent)
    }

    private fun applyCallWindowFlags(intent: Intent?) {
        val isIncomingCallIntent = intent?.action == PUSH_ACTION_OPEN &&
            isIncomingCallPush(intent.pushData())
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(isIncomingCallIntent)
            setTurnScreenOn(isIncomingCallIntent)
            if (isIncomingCallIntent) {
                val keyguard = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
                keyguard.requestDismissKeyguard(this, null)
            }
            return
        }

        @Suppress("DEPRECATION")
        val callFlags = WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
            WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
            WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
        if (isIncomingCallIntent) {
            @Suppress("DEPRECATION")
            window.addFlags(callFlags)
        } else {
            @Suppress("DEPRECATION")
            window.clearFlags(callFlags)
        }
    }

    private fun handlePushIntent(intent: Intent?) {
        if (intent == null) return
        if (intent.action != PUSH_ACTION_OPEN) return
        val payload = intent.pushData()
        if (payload.isEmpty()) return
        if (isIncomingCallPush(payload) && payload["call_action"] == "accept") {
            TelecomCallManager.cancelIncomingCallNotification(this, payload)
        }
        pendingPushPayload = payload
        deliverPendingPushPayload()
    }

    private fun deliverPendingPushPayload() {
        val channel = pushChannel ?: return
        val pending = pendingPushPayload ?: return
        if (!isPushChannelReady) return

        channel.invokeMethod(
            "onPushOpened",
            pending,
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    if (pendingPushPayload == pending) {
                        pendingPushPayload = null
                    }
                }

                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                    // Keep payload buffered; the next ready/new-intent cycle can retry it.
                }

                override fun notImplemented() {
                    // Flutter side is not attached yet; keep payload buffered.
                }
            }
        )
    }

    private fun saveImageToGallery(url: String, apiKey: String, apiBaseUrl: String) {
        val download = downloadImage(url, apiKey, apiBaseUrl)
        saveImageBytesToGallery(download.bytes, download.contentType)
    }

    private fun saveImageBytesToGallery(bytes: ByteArray, contentType: String?) {
        if (bytes.isEmpty()) {
            throw IOException("Image download returned empty body")
        }
        val galleryImage = prepareGalleryImage(bytes, contentType)
        writeGalleryImage(galleryImage)
    }

    private fun writeGalleryImage(galleryImage: GalleryImage) {
        if (galleryImage.width <= 0 || galleryImage.height <= 0) {
            throw IOException("Gallery image has invalid dimensions")
        }
        val filename = "FamilyTodo_${System.currentTimeMillis()}.${galleryImage.format.extension}"

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, filename)
                put(MediaStore.Images.Media.MIME_TYPE, galleryImage.format.mimeType)
                put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/FamilyTodo")
                put(MediaStore.Images.Media.IS_PENDING, 1)
            }
            val uri = contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                ?: throw IOException("Cannot create gallery image")
            try {
                contentResolver.openOutputStream(uri, "w")?.use { stream ->
                    stream.write(galleryImage.bytes)
                    stream.flush()
                } ?: throw IOException("Cannot open gallery image")

                values.clear()
                values.put(MediaStore.Images.Media.IS_PENDING, 0)
                contentResolver.update(uri, values, null, null)
            } catch (e: Exception) {
                contentResolver.delete(uri, null, null)
                throw e
            }
            return
        }

        @Suppress("DEPRECATION")
        val dir = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES),
            "FamilyTodo"
        )
        if (!dir.exists() && !dir.mkdirs()) {
            throw IOException("Cannot create gallery directory")
        }
        val file = File(dir, filename)
        file.writeBytes(galleryImage.bytes)
        android.media.MediaScannerConnection.scanFile(
            applicationContext,
            arrayOf(file.absolutePath),
            arrayOf(galleryImage.format.mimeType)
        ) { _, _ -> }
    }

    private fun downloadImage(url: String, apiKey: String, apiBaseUrl: String): ImageDownload {
        val downloadUrl = URL(url)
        val connection = (downloadUrl.openConnection() as HttpURLConnection).apply {
            instanceFollowRedirects = true
            connectTimeout = 15_000
            readTimeout = 30_000
            setRequestProperty("Accept", "image/*")
            if (apiKey.trim().isNotEmpty() && shouldAttachApiKey(downloadUrl, apiBaseUrl)) {
                setRequestProperty("X-Api-Key", apiKey)
            }
        }
        try {
            val status = connection.responseCode
            if (status !in 200..299) {
                throw IOException("Image download failed: HTTP $status")
            }
            val bytes = connection.inputStream.use { it.readBytes() }
            if (bytes.isEmpty()) {
                throw IOException("Image download returned empty body")
            }
            return ImageDownload(bytes, connection.contentType)
        } finally {
            connection.disconnect()
        }
    }

    private fun shouldAttachApiKey(imageUrl: URL, apiBaseUrl: String): Boolean {
        val trimmedBaseUrl = apiBaseUrl.trim()
        if (trimmedBaseUrl.isEmpty()) return false
        return try {
            val apiUrl = URL(trimmedBaseUrl)
            imageUrl.protocol.equals(apiUrl.protocol, ignoreCase = true) &&
                imageUrl.host.equals(apiUrl.host, ignoreCase = true) &&
                effectivePort(imageUrl) == effectivePort(apiUrl)
        } catch (_: Exception) {
            false
        }
    }

    private fun effectivePort(url: URL): Int {
        return if (url.port >= 0) url.port else url.defaultPort
    }

    private fun prepareGalleryImage(bytes: ByteArray, contentType: String?): GalleryImage {
        val options = BitmapFactory.Options().apply {
            inJustDecodeBounds = true
        }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
        val decodedMime = options.outMimeType?.trim()?.lowercase().orEmpty()
        if (decodedMime.isEmpty()) {
            val headerMime = contentType?.substringBefore(';')?.trim().orEmpty()
            throw IOException("Decoded gallery image has no MIME type; Content-Type was $headerMime")
        }
        if (options.outWidth <= 0 || options.outHeight <= 0) {
            throw IOException("Downloaded file is not a supported image")
        }

        val imageFormat = imageFormatForDecodedMime(decodedMime)
        val normalised = normaliseGalleryImageBytes(bytes, imageFormat)
        val galleryBytes = normalised.bytes
        return GalleryImage(
            galleryBytes,
            normalised.format,
            normalised.width,
            normalised.height
        )
    }

    private fun normaliseGalleryImageBytes(
        bytes: ByteArray,
        sourceFormat: GalleryImageFormat
    ): NormalisedGalleryImage {
        val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            ?: throw IOException("Downloaded file cannot be decoded")
        try {
            val targetFormat = if (sourceFormat.mimeType == "image/png" || bitmap.hasAlpha()) {
                GalleryImageFormat("image/png", "png")
            } else {
                GalleryImageFormat("image/jpeg", "jpg")
            }
            val compressFormat = if (targetFormat.mimeType == "image/png") {
                Bitmap.CompressFormat.PNG
            } else {
                Bitmap.CompressFormat.JPEG
            }
            val quality = if (compressFormat == Bitmap.CompressFormat.PNG) 100 else 95
            val galleryBytes = ByteArrayOutputStream().use { output ->
                if (!bitmap.compress(compressFormat, quality, output)) {
                    throw IOException("Cannot encode gallery image")
                }
                output.toByteArray()
            }
            if (galleryBytes.isEmpty()) {
                throw IOException("Encoded gallery image is empty")
            }
            return NormalisedGalleryImage(
                bytes = galleryBytes,
                format = targetFormat,
                width = bitmap.width,
                height = bitmap.height
            )
        } finally {
            bitmap.recycle()
        }
    }

    private fun imageFormatForDecodedMime(decodedMime: String): GalleryImageFormat {
        return when (decodedMime) {
            "image/jpeg", "image/jpg" -> GalleryImageFormat("image/jpeg", "jpg")
            "image/png" -> GalleryImageFormat("image/png", "png")
            "image/webp" -> GalleryImageFormat("image/webp", "webp")
            "image/gif" -> GalleryImageFormat("image/gif", "gif")
            "image/bmp", "image/x-ms-bmp" -> GalleryImageFormat("image/bmp", "bmp")
            "image/heic" -> GalleryImageFormat("image/heic", "heic")
            "image/heif" -> GalleryImageFormat("image/heif", "heif")
            "image/avif" -> GalleryImageFormat("image/avif", "avif")
            else -> {
                val extension = decodedMime
                    .substringAfter('/', "img")
                    .substringBefore('+')
                    .replace(Regex("[^a-z0-9]"), "")
                    .ifEmpty { "img" }
                GalleryImageFormat(decodedMime, extension)
            }
        }
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

private data class ImageDownload(
    val bytes: ByteArray,
    val contentType: String?
)

private data class GalleryImage(
    val bytes: ByteArray,
    val format: GalleryImageFormat,
    val width: Int,
    val height: Int
)

private data class GalleryImageFormat(
    val mimeType: String,
    val extension: String
)

private data class NormalisedGalleryImage(
    val bytes: ByteArray,
    val format: GalleryImageFormat,
    val width: Int,
    val height: Int
)
