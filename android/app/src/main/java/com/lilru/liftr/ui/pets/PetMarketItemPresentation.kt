package com.lilru.liftr.ui.pets

import com.lilru.liftr.data.PetEnergyPricing
import com.lilru.liftr.data.PetFullDataWire
import com.lilru.liftr.data.PetMarketItemWire

data class PetMarketItemPresentation(
    val effectivePrice: Int,
    val subtitle: String?,
    val imagePath: String?
)

object PetMarketItemPresentationFactory {
    fun make(item: PetMarketItemWire, petData: PetFullDataWire?): PetMarketItemPresentation {
        if (item.itemType == "pet_energy_capacity") {
            val currentMax = petData?.energy?.max ?: 5
            val nextMax = minOf(currentMax + 1, PetEnergyPricing.MAX_CAPACITY)
            return PetMarketItemPresentation(
                effectivePrice = PetEnergyPricing.upgradeCost(currentMax),
                subtitle = "$currentMax → $nextMax daily energy",
                imagePath = item.imagePath
            )
        }
        if (item.itemType != "pet_rarity_upgrade") {
            return PetMarketItemPresentation(effectivePrice = item.price, subtitle = null, imagePath = item.imagePath)
        }
        val rarity = petData?.pet?.rarity ?: return PetMarketItemPresentation(item.price, null, item.imagePath)
        val next = PetRarityUpgrade.nextTier(rarity) ?: return PetMarketItemPresentation(item.price, null, item.imagePath)
        val cost = PetRarityUpgrade.upgradeCost(rarity) ?: return PetMarketItemPresentation(item.price, null, item.imagePath)
        return PetMarketItemPresentation(
            effectivePrice = cost,
            subtitle = "${petRarityLabel(rarity)} → ${petRarityLabel(next)}",
            imagePath = PetRarityUpgrade.upgradeMarketImagePath(rarity) ?: item.imagePath
        )
    }

    fun modalTitle(item: PetMarketItemWire, petData: PetFullDataWire?): String {
        if (item.itemType == "pet_energy_capacity") {
            val currentMax = petData?.energy?.max ?: 5
            val nextMax = minOf(currentMax + 1, PetEnergyPricing.MAX_CAPACITY)
            return "Expand energy capacity from $currentMax to $nextMax"
        }
        if (item.itemType != "pet_rarity_upgrade") return item.displayName
        val rarity = petData?.pet?.rarity ?: return item.displayName
        val next = PetRarityUpgrade.nextTier(rarity) ?: return item.displayName
        return "Upgrade your pet from ${petRarityLabel(rarity)} to ${petRarityLabel(next)}"
    }
}
