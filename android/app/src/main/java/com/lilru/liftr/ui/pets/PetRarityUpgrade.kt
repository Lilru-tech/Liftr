package com.lilru.liftr.ui.pets

import kotlin.math.pow

object PetRarityUpgrade {
    private val tierOrder = listOf("common", "uncommon", "rare", "epic", "legendary", "mythic")

    fun sortOrder(rarity: String): Int =
        tierOrder.indexOf(rarity.lowercase()).let { if (it < 0) 0 else it + 1 }

    fun nextTier(rarity: String): String? {
        val idx = tierOrder.indexOf(rarity.lowercase())
        if (idx < 0 || idx >= tierOrder.lastIndex) return null
        return tierOrder[idx + 1]
    }

    fun upgradeCost(rarity: String): Int? {
        val order = sortOrder(rarity)
        if (nextTier(rarity) == null) return null
        return (1000 * 2.0.pow((order - 1).toDouble())).toInt()
    }

    fun upgradeMarketImagePath(rarity: String): String? {
        val next = nextTier(rarity) ?: return null
        return "market/rarity_upgrade_${rarity.lowercase()}_to_${next.lowercase()}.png"
    }

    fun statMultiplier(rarity: String): Double = when (rarity.lowercase()) {
        "uncommon" -> 1.05
        "rare" -> 1.10
        "epic" -> 1.20
        "legendary" -> 1.35
        "mythic" -> 1.50
        else -> 1.00
    }

    fun coinMultiplier(rarity: String): Double = when (rarity.lowercase()) {
        "uncommon" -> 1.10
        "rare" -> 1.25
        "epic" -> 1.50
        "legendary" -> 2.00
        "mythic" -> 3.00
        else -> 1.00
    }

    fun formattedMultiplier(value: Double): String = "%.2f".format(value)
}
