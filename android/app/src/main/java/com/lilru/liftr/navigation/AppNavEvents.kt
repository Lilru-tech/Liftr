package com.lilru.liftr.navigation

import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.receiveAsFlow

/**
 * Eventos de navegación que pueden originarse en push, FCM o lista in-app.
 */
object AppNavEvents {
    private val ch = Channel<MainOverlay>(Channel.BUFFERED)

    val events: Flow<MainOverlay> = ch.receiveAsFlow()

    fun send(overlay: MainOverlay) {
        ch.trySend(overlay)
    }
}
