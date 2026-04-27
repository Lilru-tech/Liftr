package com.lilru.liftr.ui.home

import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow

/**
 * Paridad con iOS [NotificationCenter] y [.workoutDidChange]: notifica al [HomeViewModel] para
 * reflejar ediciones / borrados en el feed sin recargar a mano.
 */
object HomeFeedSync {
    private val _events = MutableSharedFlow<Int>(extraBufferCapacity = 16, replay = 0)
    val events: SharedFlow<Int> = _events.asSharedFlow()

    fun notifyWorkoutChanged(workoutId: Int) {
        _events.tryEmit(workoutId)
    }
}
