package com.lilru.liftr.auth

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

object PasswordRecoveryGate {
    private val _pending = MutableStateFlow(false)
    val pending: StateFlow<Boolean> = _pending.asStateFlow()

    fun markPending() {
        _pending.value = true
    }

    fun clear() {
        _pending.value = false
    }
}
