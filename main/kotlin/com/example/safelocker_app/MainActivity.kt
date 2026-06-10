package com.example.safelocker_app

import android.app.Activity
import android.content.ContentUris
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.safelocker_app/media"
    private var pendingResult: MethodChannel.Result? = null
    private val DELETE_REQUEST_CODE = 1001

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {

                "openFileInGallery" -> {
                    val fileName = call.argument<String>("fileName")
                    if (fileName != null) {
                        openFileInGallery(fileName, result)
                    } else {
                        result.error("INVALID", "No fileName", null)
                    }
                }

                "openFileWithPath" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath != null) {
                        openFileWithPath(filePath, result)
                    } else {
                        result.error("INVALID", "No filePath", null)
                    }
                }

                "deleteFile" -> {
                    val filePath = call.argument<String>("filePath")  // ✅ FIXED: Changed to filePath
                    if (filePath != null) {
                        requestDeleteFile(filePath, result)
                    } else {
                        result.error("INVALID", "No filePath", null)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    // ── Open file in gallery/viewer using filename ───────────
    private fun openFileInGallery(
        fileName: String,
        result: MethodChannel.Result
    ) {
        try {
            val uri = findMediaUri(fileName)

            val mimeType = when {
                fileName.endsWith(".jpg", true) ||
                        fileName.endsWith(".jpeg", true) ||
                        fileName.endsWith(".png", true) ||
                        fileName.endsWith(".gif", true) ||
                        fileName.endsWith(".webp", true) -> "image/*"

                fileName.endsWith(".mp4", true) ||
                        fileName.endsWith(".mkv", true) ||
                        fileName.endsWith(".avi", true) ||
                        fileName.endsWith(".mov", true) ||
                        fileName.endsWith(".webm", true) -> "video/*"

                fileName.endsWith(".mp3", true) ||
                        fileName.endsWith(".wav", true) ||
                        fileName.endsWith(".aac", true) ||
                        fileName.endsWith(".flac", true) ||
                        fileName.endsWith(".m4a", true) ||
                        fileName.endsWith(".ogg", true) -> "audio/*"

                fileName.endsWith(".pdf", true) -> "application/pdf"

                else -> "*/*"
            }

            if (uri != null) {
                val intent = Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, mimeType)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                try {
                    startActivity(intent)
                    result.success("opened")
                    return
                } catch (e: Exception) {
                    val fallback = Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(uri, "*/*")
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    startActivity(fallback)
                    result.success("opened")
                }
            } else {
                val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
                    type = mimeType
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                try {
                    startActivity(intent)
                    result.success("opened_files")
                } catch (e: Exception) {
                    result.error("ERROR", "Cannot open file manager", null)
                }
            }
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    // ── Open file using FULL PATH ──
    private fun openFileWithPath(
        filePath: String,
        result: MethodChannel.Result
    ) {
        try {
            val uri = Uri.parse(filePath)

            val mimeType = when {
                filePath.endsWith(".jpg", true) ||
                        filePath.endsWith(".jpeg", true) ||
                        filePath.endsWith(".png", true) ||
                        filePath.endsWith(".gif", true) ||
                        filePath.endsWith(".webp", true) -> "image/*"

                filePath.endsWith(".mp4", true) ||
                        filePath.endsWith(".mkv", true) ||
                        filePath.endsWith(".avi", true) ||
                        filePath.endsWith(".mov", true) ||
                        filePath.endsWith(".webm", true) -> "video/*"

                filePath.endsWith(".mp3", true) ||
                        filePath.endsWith(".wav", true) ||
                        filePath.endsWith(".aac", true) ||
                        filePath.endsWith(".flac", true) ||
                        filePath.endsWith(".m4a", true) ||
                        filePath.endsWith(".ogg", true) -> "audio/*"

                filePath.endsWith(".pdf", true) -> "application/pdf"

                else -> "*/*"
            }

            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, mimeType)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }

            startActivity(intent)
            result.success("opened")
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    // ── Request delete via Android system dialog (FIXED for filePath) ─────────────
    private fun requestDeleteFile(
        filePath: String,  // ✅ FIXED: Changed parameter name and usage
        result: MethodChannel.Result
    ) {
        try {
            // First, try direct file deletion for files outside MediaStore
            val file = File(filePath)
            if (file.exists()) {
                // Try direct deletion first
                if (file.delete()) {
                    result.success("deleted")
                    return
                }
            }

            // If direct deletion fails, try MediaStore (for gallery files)
            val fileName = file.name
            val uri = findMediaUri(fileName)
            
            if (uri == null) {
                result.success("not_found")
                return
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val pendingIntent = MediaStore.createDeleteRequest(
                    contentResolver,
                    listOf(uri)
                )
                pendingResult = result
                startIntentSenderForResult(
                    pendingIntent.intentSender,
                    DELETE_REQUEST_CODE,
                    null, 0, 0, 0
                )
            } else {
                try {
                    val rows = contentResolver.delete(
                        uri, null, null
                    )
                    result.success(
                        if (rows > 0) "deleted" else "failed"
                    )
                } catch (e: Exception) {
                    result.success("failed")
                }
            }
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    // ── Find media URI by filename in MediaStore ─────────────
    private fun findMediaUri(fileName: String): Uri? {
        data class Col(val uri: Uri, val idCol: String)

        val collections = if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
        ) {
            listOf(
                Col(
                    MediaStore.Images.Media.getContentUri(
                        MediaStore.VOLUME_EXTERNAL
                    ),
                    MediaStore.Images.Media._ID
                ),
                Col(
                    MediaStore.Video.Media.getContentUri(
                        MediaStore.VOLUME_EXTERNAL
                    ),
                    MediaStore.Video.Media._ID
                ),
                Col(
                    MediaStore.Audio.Media.getContentUri(
                        MediaStore.VOLUME_EXTERNAL
                    ),
                    MediaStore.Audio.Media._ID
                ),
                Col(
                    MediaStore.Downloads.getContentUri(
                        MediaStore.VOLUME_EXTERNAL
                    ),
                    MediaStore.Downloads._ID
                )
            )
        } else {
            listOf(
                Col(
                    MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                    MediaStore.Images.Media._ID
                ),
                Col(
                    MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                    MediaStore.Video.Media._ID
                ),
                Col(
                    MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                    MediaStore.Audio.Media._ID
                )
            )
        }

        for (col in collections) {
            contentResolver.query(
                col.uri,
                arrayOf(col.idCol),
                MediaStore.MediaColumns.DISPLAY_NAME + " = ?",
                arrayOf(fileName),
                null
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val id = cursor.getLong(
                        cursor.getColumnIndexOrThrow(col.idCol)
                    )
                    return ContentUris.withAppendedId(
                        col.uri, id
                    )
                }
            }
        }
        return null
    }

    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?
    ) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == DELETE_REQUEST_CODE) {
            pendingResult?.success(
                if (resultCode == Activity.RESULT_OK)
                    "deleted"
                else
                    "cancelled"
            )
            pendingResult = null
        }
    }
}
