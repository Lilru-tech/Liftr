package com.lilru.liftr.ongoing

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import com.lilru.liftr.widget.LiftrAppWidgetReceiver

internal object OngoingWorkoutWidgetRefresh {
    fun requestUpdate(context: Context) {
        val mgr = AppWidgetManager.getInstance(context)
        val cn = ComponentName(context, LiftrAppWidgetReceiver::class.java)
        val ids = mgr.getAppWidgetIds(cn)
        if (ids.isEmpty()) return
        val i = Intent(context, LiftrAppWidgetReceiver::class.java).apply {
            action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
        }
        context.sendBroadcast(i)
    }
}
