package com.vezaro.downloader

import android.Manifest
import android.content.ContentValues
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.vezaro.downloader/storage"
        private const val PUBLIC_FOLDER = "Vezaro"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        val storageQueue = messenger.makeBackgroundTaskQueue()
        MethodChannel(messenger, CHANNEL, StandardMethodCodec.INSTANCE, storageQueue)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "sdkInt" -> result.success(Build.VERSION.SDK_INT)
                        "saveToDownloads" -> {
                            val sourcePath = call.argument<String>("sourcePath")
                            val displayName = call.argument<String>("displayName")
                            val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
                            if (sourcePath.isNullOrBlank() || displayName.isNullOrBlank()) {
                                result.error("invalid_arguments", "Missing source path or file name", null)
                            } else {
                                result.success(saveToDownloads(File(sourcePath), displayName, mimeType))
                            }
                        }
                        "downloadExists" -> {
                            val rawUri = call.argument<String>("uri")
                            result.success(rawUri != null && contentUriExists(Uri.parse(rawUri)))
                        }
                        "openDownload" -> {
                            val rawUri = call.argument<String>("uri")
                            val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
                            if (rawUri.isNullOrBlank()) {
                                result.error("invalid_arguments", "Missing file URI", null)
                            } else {
                                runOnUiThread {
                                    try {
                                        val uri = if (rawUri.startsWith("content://")) {
                                            Uri.parse(rawUri)
                                        } else {
                                            FileProvider.getUriForFile(
                                                this,
                                                "$packageName.fileprovider",
                                                File(rawUri)
                                            )
                                        }
                                        val intent = Intent(Intent.ACTION_VIEW).apply {
                                            setDataAndType(uri, mimeType)
                                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                        }
                                        startActivity(intent)
                                        result.success(true)
                                    } catch (_: ActivityNotFoundException) {
                                        result.success(false)
                                    } catch (error: Exception) {
                                        result.error("open_failed", error.message ?: "Could not open file", null)
                                    }
                                }
                            }
                        }
                        "deleteDownload" -> {
                            val rawUri = call.argument<String>("uri")
                            if (rawUri.isNullOrBlank()) {
                                result.error("invalid_arguments", "Missing file URI", null)
                            } else {
                                result.success(deleteDownload(rawUri))
                            }
                        }
                        else -> result.notImplemented()
                    }
                } catch (security: SecurityException) {
                    result.error("permission_required", security.message, null)
                } catch (error: Exception) {
                    result.error("storage_error", error.message ?: "Storage operation failed", null)
                }
            }
    }

    private fun saveToDownloads(source: File, requestedName: String, mimeType: String): Map<String, String> {
        if (!source.exists() || !source.isFile || source.length() <= 0L) {
            throw IllegalArgumentException("The temporary download is missing or empty")
        }
        val safeName = sanitizeName(requestedName)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            saveWithMediaStore(source, safeName, mimeType)
        } else {
            saveLegacyPublicFile(source, safeName)
        }
    }

    private fun saveWithMediaStore(source: File, name: String, mimeType: String): Map<String, String> {
        val resolver = contentResolver
        val relativePath = Environment.DIRECTORY_DOWNLOADS + "/" + PUBLIC_FOLDER + "/"
        val displayName = uniqueMediaStoreName(name, relativePath)
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, displayName)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType.ifBlank { "application/octet-stream" })
            put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
        val destination = resolver.insert(collection, values)
            ?: throw IllegalStateException("Android could not create the Downloads entry")

        try {
            val output = resolver.openOutputStream(destination, "w")
                ?: throw IllegalStateException("Android could not open the Downloads file")
            output.use { stream -> FileInputStream(source).use { input -> input.copyTo(stream) } }
            val completed = ContentValues().apply {
                put(MediaStore.MediaColumns.IS_PENDING, 0)
            }
            if (resolver.update(destination, completed, null, null) <= 0) {
                throw IllegalStateException("Android could not finalize the Downloads file")
            }
            return mapOf("uri" to destination.toString(), "displayName" to displayName)
        } catch (error: Exception) {
            resolver.delete(destination, null, null)
            throw error
        }
    }

    @Suppress("DEPRECATION")
    private fun saveLegacyPublicFile(source: File, name: String): Map<String, String> {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.WRITE_EXTERNAL_STORAGE) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            throw SecurityException("Legacy Android requires storage permission")
        }
        val base = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        val folder = File(base, PUBLIC_FOLDER)
        if (!folder.exists() && !folder.mkdirs()) {
            throw IllegalStateException("Could not create the Downloads folder")
        }
        var target = File(folder, name)
        if (target.exists()) {
            val dot = name.lastIndexOf('.')
            val stem = if (dot > 0) name.substring(0, dot) else name
            val ext = if (dot > 0) name.substring(dot) else ""
            var index = 1
            do {
                target = File(folder, "${stem}_${System.currentTimeMillis()}_${index++}$ext")
            } while (target.exists())
        }
        FileInputStream(source).use { input -> FileOutputStream(target).use { output -> input.copyTo(output) } }
        if (!target.exists() || target.length() != source.length()) {
            target.delete()
            throw IllegalStateException("The public file copy was incomplete")
        }
        return mapOf("uri" to target.absolutePath, "displayName" to target.name)
    }

    private fun uniqueMediaStoreName(name: String, relativePath: String): String {
        val projection = arrayOf(MediaStore.MediaColumns.DISPLAY_NAME)
        val selection = "${MediaStore.MediaColumns.RELATIVE_PATH} = ? AND ${MediaStore.MediaColumns.DISPLAY_NAME} = ?"
        var candidate = name
        var index = 1
        while (true) {
            val cursor = contentResolver.query(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                projection,
                selection,
                arrayOf(relativePath, candidate),
                null
            )
            val exists = cursor?.use { it.moveToFirst() } ?: false
            if (!exists) return candidate
            val dot = name.lastIndexOf('.')
            val stem = if (dot > 0) name.substring(0, dot) else name
            val extension = if (dot > 0) name.substring(dot) else ""
            candidate = "${stem}_${index++}$extension"
        }
    }

    private fun contentUriExists(uri: Uri): Boolean {
        if (uri.scheme != "content") return File(uri.toString()).exists()
        return contentResolver.query(uri, arrayOf(MediaStore.MediaColumns._ID), null, null, null)
            ?.use { it.moveToFirst() } ?: false
    }

    private fun deleteDownload(rawUri: String): Boolean {
        if (rawUri.startsWith("content://")) {
            return contentResolver.delete(Uri.parse(rawUri), null, null) > 0
        }
        val file = File(rawUri)
        return !file.exists() || file.delete()
    }

    private fun sanitizeName(value: String): String {
        val cleaned = value
            .replace(Regex("""[\x00-\x1F\x7F<>:"/\\|?*]"""), "_")
            .trim()
            .trim('.')
        return cleaned.take(160).ifBlank { "download_${System.currentTimeMillis()}.bin" }
    }
}
