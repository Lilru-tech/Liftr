package com.lilru.liftr.ui.home

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Typeface
import androidx.core.content.FileProvider
import com.lilru.liftr.R
import java.io.File
import java.io.FileOutputStream
import kotlin.math.max

object HomeMonthShareImage {
    fun sharePng(
        context: Context,
        summary: HomeMonthSummaryUi
    ) {
        val dir = File(context.cacheDir, "share").apply { mkdirs() }
        val f = File(dir, "liftr_month.png")
        val bitmap = renderBitmap(summary)
        FileOutputStream(f).use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        val uri = FileProvider.getUriForFile(
            context,
            "${context.packageName}.fileprovider",
            f
        )
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "image/png"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(send, context.getString(R.string.home_share_image_title)))
    }

    private fun renderBitmap(ms: HomeMonthSummaryUi): Bitmap {
        val w = 1080
        val h = 800
        val bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val c = Canvas(bitmap)
        c.drawColor(0xFF121212.toInt())
        val brandPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = 0xFFFFFFFF.toInt()
            textSize = 56f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        }
        val monthPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = 0xFFFFFFFF.toInt()
            textSize = 48f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        }
        val bodyPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = 0xFFCCCCCC.toInt()
            textSize = 38f
        }
        var y = 80f
        c.drawText("Liftr", 60f, y, brandPaint)
        y += 100f
        c.drawText(ms.label, 60f, y, monthPaint)
        y += 90f
        c.drawText(
            "Workouts: ${ms.workoutCount}  ·  Score: ${ms.scoreTotal}",
            60f,
            y,
            bodyPaint
        )
        ms.deltaPercent?.let { d ->
            y += 70f
            c.drawText(
                "vs last month: ${"%.0f%%".format(d)}",
                60f,
                y,
                bodyPaint
            )
        }
        val series = ms.series
        if (series.size > 1) {
            y += 100f
            val maxV = max(series.maxOf { it.value }, 1.0)
            val chartH = 280f
            val chartW = w - 120f
            val plotPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = 0xFF6750A4.toInt()
                strokeWidth = 6f
                style = Paint.Style.STROKE
            }
            val n = series.size
            for (i in 0 until n) {
                if (i == 0) continue
                val x0 = 60f + chartW * ((i - 1) / (n - 1f).coerceAtLeast(1f))
                val y0 = y + chartH - (chartH * (series[i - 1].value / maxV)).toFloat()
                val x1 = 60f + chartW * (i / (n - 1f).coerceAtLeast(1f))
                val y1 = y + chartH - (chartH * (series[i].value / maxV)).toFloat()
                c.drawLine(x0, y0, x1, y1, plotPaint)
            }
        }
        return bitmap
    }
}
