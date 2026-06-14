package com.lilru.liftr.ui.pets

import android.content.Context
import com.lilru.liftr.data.PetRefreshBus
import com.lilru.liftr.navigation.AppNavEvents
import com.lilru.liftr.navigation.MainOverlay

object PetHatchEventHandler {
    fun handleHatchEvent(
        context: Context? = null,
        navigateToProfile: Boolean = true
    ) {
        context?.let { PetHatchLocalNotificationScheduler.cancel(it) }
        PetRefreshBus.notifyPetStateDidChange()
        if (navigateToProfile) {
            AppNavEvents.send(MainOverlay.PetHatched)
        }
    }
}
