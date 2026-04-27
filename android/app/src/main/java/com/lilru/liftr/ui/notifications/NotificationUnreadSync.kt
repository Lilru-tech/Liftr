package com.lilru.liftr.ui.notifications

import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow

/**
 * Señal global para refrescar badges de notificaciones en tiempo real.
 */
object NotificationUnreadSync {
    private val _events = MutableSharedFlow<Unit>(extraBufferCapacity = 16, replay = 0)
    val events: SharedFlow<Unit> = _events.asSharedFlow()

    fun notifyChanged() {
        _events.tryEmit(Unit)
    }
}
