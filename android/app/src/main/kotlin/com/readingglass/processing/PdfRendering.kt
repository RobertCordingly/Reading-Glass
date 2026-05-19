package com.readingglass.processing

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.ParcelFileDescriptor
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import java.io.File
import java.io.FileOutputStream

/**
 * Loads PDF pages as bitmaps using Android's built-in [PdfRenderer].
 *
 * Holds the document open for the lifetime of the [PdfBitmapSource]; call
 * [close] when you're done with it.
 */
class PdfBitmapSource private constructor(
    private val fd: ParcelFileDescriptor,
    private val renderer: PdfRenderer,
) : AutoCloseable {

    val pageCount: Int get() = renderer.pageCount

    @Synchronized
    fun renderPage(index: Int, targetWidthPx: Int): ImageBitmap? {
        if (index < 0 || index >= renderer.pageCount) return null
        renderer.openPage(index).use { page ->
            val ratio = page.height.toFloat() / page.width.toFloat()
            val w = targetWidthPx.coerceAtLeast(64)
            val h = (w * ratio).toInt().coerceAtLeast(64)
            val bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888).apply {
                eraseColor(Color.WHITE)
            }
            page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
            return bitmap.asImageBitmap()
        }
    }

    override fun close() {
        renderer.close()
        fd.close()
    }

    companion object {
        fun fromUri(context: Context, uri: Uri): PdfBitmapSource? {
            // PdfRenderer requires a seekable FD. Content URIs (e.g. SAF) often
            // need to be copied to a local cache file first.
            val local = ensureLocalCopy(context, uri) ?: return null
            val fd = ParcelFileDescriptor.open(local, ParcelFileDescriptor.MODE_READ_ONLY)
            return PdfBitmapSource(fd, PdfRenderer(fd))
        }

        private fun ensureLocalCopy(context: Context, uri: Uri): File? {
            val scheme = uri.scheme
            if (scheme == "file") return uri.path?.let(::File)
            val resolver = context.contentResolver
            val cache = File(context.cacheDir, "imported.pdf")
            return try {
                resolver.openInputStream(uri)?.use { input ->
                    FileOutputStream(cache).use { output -> input.copyTo(output) }
                }
                cache
            } catch (_: Exception) {
                null
            }
        }
    }
}
