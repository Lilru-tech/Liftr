package com.lilru.liftr.ui

import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow

/**
 * Snackbars / banners a nivel de shell: [com.lilru.liftr.ui.main.MainShellScreen] recoge el flujo
 * (tipos alineados con [Liftr.BannerType] / BannerPresenter en iOS).
 */
sealed class AppBannerEvent {
    abstract val message: String

    data class Success(override val message: String) : AppBannerEvent()
    data class Error(override val message: String) : AppBannerEvent()
    data class Info(override val message: String) : AppBannerEvent()
}

object AppSnackbar {
    private val _events = MutableSharedFlow<AppBannerEvent>(extraBufferCapacity = 8, replay = 0)
    val events: SharedFlow<AppBannerEvent> = _events.asSharedFlow()

    fun showSuccess(message: String) {
        _events.tryEmit(AppBannerEvent.Success(message))
    }

    fun showError(message: String) {
        _events.tryEmit(AppBannerEvent.Error(message))
    }

    fun showInfo(message: String) {
        _events.tryEmit(AppBannerEvent.Info(message))
    }

    /** Compat: trata el mensaje como informativo (o neutro). */
    fun show(message: String) {
        _events.tryEmit(AppBannerEvent.Info(message))
    }
}
