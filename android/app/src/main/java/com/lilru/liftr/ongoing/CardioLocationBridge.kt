package com.lilru.liftr.ongoing

/**
 * Enlace entre [OngoingWorkoutService] (Fused) y [com.lilru.liftr.ui.active.ActiveCardioWorkoutViewModel].
 */
object CardioLocationBridge {
    @Volatile
    var listener: ((Double, Double) -> Unit)? = null
        @Synchronized get
        @Synchronized set

    fun push(lat: Double, lon: Double) {
        listener?.invoke(lat, lon)
    }
}
