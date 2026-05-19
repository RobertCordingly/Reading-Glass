package com.readingglass.processing

import android.content.Context
import android.net.Uri
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.text.PDFTextStripper

/**
 * Extracts text from a PDF identified by [Uri], with `--SE_NEWLINE--PAGE n--SE_NEWLINE--`
 * markers between pages so the downstream [TextProcessor] can preserve page breaks.
 */
object PdfImporter {
    data class Imported(val pageCount: Int, val rawText: String)

    fun import(context: Context, uri: Uri): Imported? {
        val resolver = context.contentResolver
        val input = resolver.openInputStream(uri) ?: return null
        return input.use { stream ->
            PDDocument.load(stream).use { doc ->
                val pageCount = doc.numberOfPages
                val sb = StringBuilder()
                val stripper = PDFTextStripper()
                stripper.sortByPosition = true
                for (i in 0 until pageCount) {
                    stripper.startPage = i + 1
                    stripper.endPage = i + 1
                    sb.append("--SE_NEWLINE--PAGE ").append(i).append("--SE_NEWLINE--\n")
                    sb.append(stripper.getText(doc))
                    sb.append('\n')
                }
                Imported(pageCount, sb.toString())
            }
        }
    }
}
