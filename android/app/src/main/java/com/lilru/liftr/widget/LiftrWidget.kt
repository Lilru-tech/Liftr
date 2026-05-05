package com.lilru.liftr.widget

import android.content.Context
import android.content.Intent
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.provideContent
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.action.clickable
import com.lilru.liftr.MainActivity
import com.lilru.liftr.R
import com.lilru.liftr.navigation.OpenWorkoutIntentStore
import com.lilru.liftr.ongoing.OngoingWorkoutWidgetPrefs

class LiftrWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent { WidgetContent(context) }
    }
}

@androidx.compose.runtime.Composable
private fun WidgetContent(context: Context) {
    val st = OngoingWorkoutWidgetPrefs.read(context)
    val open = Intent(context, MainActivity::class.java).apply {
        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        if (st != null) {
            putExtra(OpenWorkoutIntentStore.EXTRA_OPEN_WORKOUT_ID, st.workoutId)
        }
    }
    val openAction = actionStartActivity(open)
    val mins = if (st != null) {
        ((System.currentTimeMillis() - st.startedAtMs).coerceAtLeast(0L) / 60_000L).toInt()
    } else {
        0
    }
    val timeLine = if (st != null) {
        context.getString(R.string.widget_liftr_active_time, mins)
    } else {
        context.getString(R.string.widget_liftr_subtitle)
    }
    val line2 = when {
        st == null -> context.getString(R.string.widget_liftr_subtitle)
        st.statsLine.isNotBlank() -> st.statsLine
        else -> timeLine
    }
    val line3 = if (st != null && st.statsLine.isNotBlank()) {
        timeLine
    } else {
        null
    }
    val title = if (st != null) {
        st.subtitle.ifBlank { context.getString(R.string.widget_liftr_label) }
    } else {
        context.getString(R.string.widget_liftr_label)
    }
    GlanceTheme {
        Column(
            modifier = GlanceModifier
                .fillMaxSize()
                .padding(12.dp)
                .clickable { openAction },
            verticalAlignment = Alignment.Vertical.CenterVertically,
            horizontalAlignment = Alignment.Horizontal.CenterHorizontally
        ) {
            Text(
                text = title,
                style = TextStyle(fontWeight = FontWeight.Bold)
            )
            Spacer(GlanceModifier.height(4.dp))
            Text(
                text = line2,
                style = TextStyle(fontWeight = FontWeight.Normal)
            )
            if (line3 != null) {
                Spacer(GlanceModifier.height(2.dp))
                Text(
                    text = line3,
                    style = TextStyle(fontWeight = FontWeight.Normal)
                )
            }
        }
    }
}
