package com.lilru.liftr.auth

/**
 * Mensaje breve para mostrar en [com.lilru.liftr.ui.main.MainShellScreen] tras un login correcto
 * (paridad con el banner "Welcome back" de [Liftr.LoginView] en iOS).
 * El flujo pasa a la shell antes de que el canal de [com.lilru.liftr.ui.AppSnackbar] haya reaccionado.
 */
object PostLoginShellMessage {
    @Volatile
    var pending: String? = null

    fun take(): String? = synchronized(this) {
        val t = pending
        pending = null
        t
    }
}
