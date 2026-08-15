package com.carriez.flutter_hbb

import android.content.ContentValues
import android.content.Context
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

data class RecordingPublishResult(
    val status: String,
    val sourcePath: String = "",
    val galleryUri: String = "",
    val errorCode: String = "",
) {
    fun toMap(): Map<String, String> = mapOf(
        "status" to status,
        "sourcePath" to sourcePath,
        "galleryUri" to galleryUri,
        "errorCode" to errorCode,
    )

    companion object {
        fun success(uri: String) = RecordingPublishResult(
            status = "success",
            galleryUri = uri,
        )

        fun cleanupWarning(source: File, uri: String) = RecordingPublishResult(
            status = "cleanup_warning",
            sourcePath = source.absolutePath,
            galleryUri = uri,
            errorCode = "source_delete_failed",
        )

        fun failure(source: File, errorCode: String) = RecordingPublishResult(
            status = "failure",
            sourcePath = source.absolutePath,
            errorCode = errorCode,
        )
    }
}

class RecordingMediaStorePublisher(private val context: Context) {
    fun publish(sourcePath: String, callback: (RecordingPublishResult) -> Unit) {
        val source = File(sourcePath)
        val validationError = validate(source)
        if (validationError != null) {
            callback(RecordingPublishResult.failure(source, validationError))
            return
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                callback(publishScoped(source))
            } else {
                publishLegacy(source, callback)
            }
        } catch (_: SecurityException) {
            callback(RecordingPublishResult.failure(source, "permission_denied"))
        } catch (_: Exception) {
            callback(RecordingPublishResult.failure(source, "publish_failed"))
        }
    }

    private fun validate(source: File): String? {
        if (!source.isFile) return "source_not_found"
        if (!source.canRead()) return "source_not_readable"
        if (source.length() <= 0L) return "source_empty"
        if (mimeTypeFor(source.name) == null) return "unsupported_format"
        return null
    }

    private fun publishScoped(source: File): RecordingPublishResult {
        val resolver = context.contentResolver
        val collection = MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        val relativePath = "$ALBUM_RELATIVE_PATH/"
        val displayName = collisionSafeName(source.name) { candidate ->
            resolver.query(
                collection,
                arrayOf(MediaStore.Video.Media._ID),
                "${MediaStore.Video.Media.DISPLAY_NAME} = ? AND ${MediaStore.Video.Media.RELATIVE_PATH} = ?",
                arrayOf(candidate, relativePath),
                null,
            )?.use { it.moveToFirst() } ?: false
        }
        val values = ContentValues().apply {
            put(MediaStore.Video.Media.DISPLAY_NAME, displayName)
            put(MediaStore.Video.Media.MIME_TYPE, mimeTypeFor(source.name))
            put(MediaStore.Video.Media.RELATIVE_PATH, relativePath)
            put(MediaStore.Video.Media.IS_PENDING, 1)
        }

        var uri: Uri? = null
        var committed = false
        var stage = "insert_failed"
        return try {
            uri = resolver.insert(collection, values)
                ?: return RecordingPublishResult.failure(source, stage)
            stage = "open_destination_failed"
            val output = resolver.openOutputStream(uri, "w")
                ?: return cleanupFailedRow(uri, source, stage)
            stage = "copy_failed"
            FileInputStream(source).use { input ->
                output.use { destination ->
                    input.copyTo(destination)
                    destination.flush()
                }
            }
            stage = "commit_failed"
            val committedRows = resolver.update(
                uri,
                ContentValues().apply { put(MediaStore.Video.Media.IS_PENDING, 0) },
                null,
                null,
            )
            if (committedRows <= 0) {
                return cleanupFailedRow(uri, source, stage)
            }
            committed = true
            if (source.delete()) {
                RecordingPublishResult.success(uri.toString())
            } else {
                RecordingPublishResult.cleanupWarning(source, uri.toString())
            }
        } catch (_: SecurityException) {
            if (uri != null && !committed) deleteQuietly(uri)
            RecordingPublishResult.failure(source, "permission_denied")
        } catch (_: Exception) {
            if (uri != null && !committed) deleteQuietly(uri)
            RecordingPublishResult.failure(source, stage)
        }
    }

    private fun cleanupFailedRow(
        uri: Uri,
        source: File,
        errorCode: String,
    ): RecordingPublishResult {
        deleteQuietly(uri)
        return RecordingPublishResult.failure(source, errorCode)
    }

    private fun deleteQuietly(uri: Uri) {
        try {
            context.contentResolver.delete(uri, null, null)
        } catch (_: Exception) {
            // The source remains intact even if an incomplete MediaStore row cannot be removed.
        }
    }

    @Suppress("DEPRECATION")
    private fun publishLegacy(
        source: File,
        callback: (RecordingPublishResult) -> Unit,
    ) {
        val album = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DCIM),
            ALBUM_NAME,
        )
        if (!album.exists() && !album.mkdirs()) {
            callback(RecordingPublishResult.failure(source, "create_album_failed"))
            return
        }
        val displayName = collisionSafeName(source.name) { File(album, it).exists() }
        val target = File(album, displayName)
        val pending = File(album, ".$displayName.pending-${System.nanoTime()}")
        try {
            FileInputStream(source).use { input ->
                FileOutputStream(pending).use { output ->
                    input.copyTo(output)
                    output.fd.sync()
                }
            }
            if (!pending.renameTo(target)) {
                pending.delete()
                callback(RecordingPublishResult.failure(source, "commit_failed"))
                return
            }
        } catch (_: SecurityException) {
            pending.delete()
            callback(RecordingPublishResult.failure(source, "permission_denied"))
            return
        } catch (_: Exception) {
            pending.delete()
            callback(RecordingPublishResult.failure(source, "copy_failed"))
            return
        }

        MediaScannerConnection.scanFile(
            context,
            arrayOf(target.absolutePath),
            arrayOf(mimeTypeFor(source.name)),
        ) { _, uri ->
            if (uri == null) {
                target.delete()
                callback(RecordingPublishResult.failure(source, "media_scan_failed"))
            } else if (source.delete()) {
                callback(RecordingPublishResult.success(uri.toString()))
            } else {
                callback(RecordingPublishResult.cleanupWarning(source, uri.toString()))
            }
        }
    }

    companion object {
        const val ALBUM_NAME = "鲲穹远程桌面"
        const val ALBUM_RELATIVE_PATH = "DCIM/$ALBUM_NAME"

        fun mimeTypeFor(filename: String): String? = when {
            filename.endsWith(".mp4", ignoreCase = true) -> "video/mp4"
            filename.endsWith(".webm", ignoreCase = true) -> "video/webm"
            else -> null
        }

        fun collisionSafeName(
            requestedName: String,
            exists: (String) -> Boolean,
        ): String {
            if (!exists(requestedName)) return requestedName
            val extensionIndex = requestedName.lastIndexOf('.')
            val base = if (extensionIndex > 0) {
                requestedName.substring(0, extensionIndex)
            } else {
                requestedName
            }
            val extension = if (extensionIndex > 0) {
                requestedName.substring(extensionIndex)
            } else {
                ""
            }
            var suffix = 1
            while (exists("$base ($suffix)$extension")) suffix += 1
            return "$base ($suffix)$extension"
        }
    }
}
