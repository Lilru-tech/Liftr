package com.lilru.liftr.util

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import java.io.ByteArrayOutputStream
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * Redimensiona y comprime como en [ProfileView.swift] `resizedJPEG` (lado máx. 1024, calidad 0,85).
 */
object AvatarImageUtils {
    private const val MAX_SIDE = 1024
    private const val JPEG_QUALITY = 85

    fun rawToAvatarJpeg(raw: ByteArray): ByteArray? {
        val src = BitmapFactory.decodeByteArray(raw, 0, raw.size) ?: return null
        val scaled = scaleMaxSide(src, MAX_SIDE)
        if (scaled != src) {
            src.recycle()
        }
        return try {
            ByteArrayOutputStream().use { out ->
                scaled.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, out)
                out.toByteArray()
            }
        } finally {
            scaled.recycle()
        }
    }

    private fun scaleMaxSide(src: Bitmap, maxSide: Int): Bitmap {
        val w = src.width
        val h = src.height
        val longest = max(w, h)
        if (longest <= maxSide) {
            return src
        }
        val scale = maxSide.toFloat() / longest
        val nw = (w * scale).roundToInt().coerceAtLeast(1)
        val nh = (h * scale).roundToInt().coerceAtLeast(1)
        return Bitmap.createScaledBitmap(src, nw, nh, true)
    }
}
