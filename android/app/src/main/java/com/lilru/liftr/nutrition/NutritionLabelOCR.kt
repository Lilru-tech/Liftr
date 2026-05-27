package com.lilru.liftr.nutrition

import android.graphics.Bitmap
import android.graphics.Rect
import android.util.Log
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.roundToInt

object NutritionLabelOCR {
    suspend fun recognize(bitmap: Bitmap): NutritionLabelRecognitionResult = withContext(Dispatchers.Default) {
        val prepared = downscaleIfNeeded(bitmap)
        val image = InputImage.fromBitmap(prepared, 0)
        val imageWidth = prepared.width.toFloat().coerceAtLeast(1f)
        val imageHeight = prepared.height.toFloat().coerceAtLeast(1f)
        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        suspendCancellableCoroutine { cont ->
            recognizer.process(image)
                .addOnSuccessListener { visionText ->
                    recognizer.close()
                    val elements = extractSpatialElements(visionText, imageWidth, imageHeight)
                    if (elements.size < 5) {
                        cont.resumeWithException(NutritionLabelOCRException.NoTextFound)
                        return@addOnSuccessListener
                    }
                    val merged = mergeTokensIntoLogicalRows(visionText, prepared.height)
                    if (merged.isNotEmpty()) {
                        Log.d("NutritionOCR", "--- [OCR RAW CORPUS START] ---")
                        merged.forEachIndexed { index, line ->
                            Log.d("NutritionOCR", "[$index] $line")
                        }
                        Log.d("NutritionOCR", "--- [OCR RAW CORPUS END] ---")
                    }
                    if (merged.isEmpty()) {
                        val fallback = visionText.text
                            .lines()
                            .map { it.trim() }
                            .filter { it.isNotEmpty() }
                        if (fallback.isEmpty()) {
                            cont.resumeWithException(NutritionLabelOCRException.NoTextFound)
                        } else {
                            cont.resume(NutritionLabelRecognitionResult(mergedLines = fallback, elements = elements))
                        }
                    } else {
                        cont.resume(NutritionLabelRecognitionResult(mergedLines = merged, elements = elements))
                    }
                }
                .addOnFailureListener { e ->
                    recognizer.close()
                    cont.resumeWithException(NutritionLabelOCRException.VisionFailed(e.message ?: "OCR failed"))
                }
            cont.invokeOnCancellation { recognizer.close() }
        }
    }

    suspend fun recognizeText(bitmap: Bitmap): List<String> = recognize(bitmap).mergedLines

    private fun extractSpatialElements(
        visionText: Text,
        imageWidth: Float,
        imageHeight: Float
    ): List<NutritionLabelSpatialElement> {
        val elements = mutableListOf<NutritionLabelSpatialElement>()
        for (block in visionText.textBlocks) {
            for (line in block.lines) {
                val lineElements = line.elements
                if (lineElements.isNotEmpty()) {
                    for (el in lineElements) {
                        val text = el.text.trim()
                        if (text.isEmpty()) continue
                        val box = el.boundingBox ?: continue
                        elements.add(normalizedElement(text, box, imageWidth, imageHeight))
                    }
                } else {
                    val text = line.text.trim()
                    if (text.isEmpty()) continue
                    val box = line.boundingBox ?: continue
                    elements.add(normalizedElement(text, box, imageWidth, imageHeight))
                }
            }
        }
        return elements
    }

    private fun normalizedElement(
        text: String,
        box: Rect,
        imageWidth: Float,
        imageHeight: Float
    ): NutritionLabelSpatialElement {
        val minX = box.left / imageWidth
        val maxX = box.right / imageWidth
        val minY = box.top / imageHeight
        val maxY = box.bottom / imageHeight
        return NutritionLabelSpatialElement(
            text = text,
            minX = minX.coerceIn(0f, 1f),
            minY = minY.coerceIn(0f, 1f),
            maxX = maxX.coerceIn(0f, 1f),
            maxY = maxY.coerceIn(0f, 1f)
        )
    }

    private data class TokenEntry(val text: String, val cx: Float, val cy: Float)

    private fun mergeTokensIntoLogicalRows(visionText: Text, imageHeight: Int): List<String> {
        val yTolerancePx = max(12f, imageHeight * 0.035f)
        val tokens: List<TokenEntry> = visionText.textBlocks.flatMap { block ->
            block.lines.flatMap { line ->
                val elements = line.elements
                if (elements.isNotEmpty()) {
                    elements.mapNotNull { el ->
                        val t = el.text.trim()
                        if (t.isEmpty()) return@mapNotNull null
                        val box: Rect = el.boundingBox ?: return@mapNotNull null
                        TokenEntry(t, (box.left + box.right) / 2f, (box.top + box.bottom) / 2f)
                    }
                } else {
                    val t = line.text.trim()
                    if (t.isEmpty()) emptyList() else {
                        val box: Rect? = line.boundingBox
                        if (box == null) emptyList() else listOf(
                            TokenEntry(t, (box.left + box.right) / 2f, (box.top + box.bottom) / 2f)
                        )
                    }
                }
            }
        }
        if (tokens.isEmpty()) return emptyList()
        val sorted = tokens.sortedWith { a, b ->
            if (abs(a.cy - b.cy) > yTolerancePx) a.cy.compareTo(b.cy) else a.cx.compareTo(b.cx)
        }
        data class Row(var cy: Float, val items: MutableList<TokenEntry>)
        val rows = mutableListOf<Row>()
        for (t in sorted) {
            val last = rows.lastOrNull()
            if (last != null && abs(t.cy - last.cy) <= yTolerancePx) {
                last.items.add(t)
                val n = last.items.size.toFloat()
                last.cy = (last.cy * (n - 1f) + t.cy) / n
            } else {
                rows.add(Row(t.cy, mutableListOf(t)))
            }
        }
        return rows.mapNotNull { row ->
            val line = row.items
                .sortedBy { it.cx }
                .joinToString(" ") { it.text }
                .trim()
            line.takeIf { it.isNotEmpty() }
        }
    }

    private fun downscaleIfNeeded(bitmap: Bitmap, maxDimension: Int = 2048): Bitmap {
        val w = bitmap.width
        val h = bitmap.height
        val maxSide = max(w, h)
        if (maxSide <= maxDimension) return bitmap
        val scale = maxDimension.toFloat() / maxSide
        val newW = (w * scale).roundToInt().coerceAtLeast(1)
        val newH = (h * scale).roundToInt().coerceAtLeast(1)
        return Bitmap.createScaledBitmap(bitmap, newW, newH, true)
    }
}

sealed class NutritionLabelOCRException(message: String) : Exception(message) {
    data object NoTextFound : NutritionLabelOCRException("no_text")
    class VisionFailed(detail: String) : NutritionLabelOCRException(detail)
}
