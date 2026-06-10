package com.lilru.liftr.ui.pets

import com.lilru.liftr.ui.AppSnackbar
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

object PetMarketPurchaseFeedback {
    private val _unseenMyItemsCount = MutableStateFlow(0)
    val unseenMyItemsCount: StateFlow<Int> = _unseenMyItemsCount.asStateFlow()

    fun recordPurchase(itemType: String) {
        if (itemType != "pet_egg" && itemType != "incubator") return
        _unseenMyItemsCount.update { it + 1 }
        val message = when (itemType) {
            "pet_egg" -> "Mysterious Egg added to My Items"
            else -> "Egg Incubator added to My Items"
        }
        AppSnackbar.showSuccess(message)
    }

    fun clearBadge() {
        _unseenMyItemsCount.value = 0
    }
}
