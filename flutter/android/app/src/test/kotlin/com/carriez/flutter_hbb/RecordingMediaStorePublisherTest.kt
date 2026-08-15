package com.carriez.flutter_hbb

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.io.File

class RecordingMediaStorePublisherTest {
    @Test
    fun `maps supported recording extensions to video mime types`() {
        assertEquals("video/mp4", RecordingMediaStorePublisher.mimeTypeFor("clip.MP4"))
        assertEquals("video/webm", RecordingMediaStorePublisher.mimeTypeFor("clip.webm"))
        assertNull(RecordingMediaStorePublisher.mimeTypeFor("clip.mov"))
    }

    @Test
    fun `chooses a collision safe legacy filename`() {
        val existing = setOf("clip.mp4", "clip (1).mp4")

        val selected = RecordingMediaStorePublisher.collisionSafeName(
            "clip.mp4",
            existing::contains,
        )

        assertEquals("clip (2).mp4", selected)
    }

    @Test
    fun `preserves extension when filename has multiple dots`() {
        val selected = RecordingMediaStorePublisher.collisionSafeName(
            "remote.session.webm",
        ) { it == "remote.session.webm" }

        assertEquals("remote.session (1).webm", selected)
    }

    @Test
    fun `failure result retains source path and stable error code`() {
        val result = RecordingPublishResult.failure(
            File("/private/clip.mp4"),
            "copy_failed",
        ).toMap()

        assertEquals("failure", result["status"])
        assertEquals("/private/clip.mp4", result["sourcePath"])
        assertEquals("copy_failed", result["errorCode"])
    }

    @Test
    fun `cleanup warning reports gallery uri and retained source`() {
        val result = RecordingPublishResult.cleanupWarning(
            File("/private/clip.mp4"),
            "content://media/video/1",
        ).toMap()

        assertEquals("cleanup_warning", result["status"])
        assertEquals("content://media/video/1", result["galleryUri"])
        assertEquals("/private/clip.mp4", result["sourcePath"])
    }
}
