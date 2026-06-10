package com.lilru.liftr.ui.pets

import com.lilru.liftr.data.PetEnergyPricing
import com.lilru.liftr.data.PetFullDataWire
import com.lilru.liftr.data.PetInventoryWire
import com.lilru.liftr.data.PetMarketItemWire

private val FOOD_TYPES = setOf("food_baby", "food_kid", "food_teen", "food_adult", "food_elder")

object PetMarketVisibility {
    fun inventoryQuantity(inventory: List<PetInventoryWire>, itemType: String): Int =
        inventory.firstOrNull { it.itemType == itemType }?.quantity ?: 0

    fun shouldShowMarketItem(item: PetMarketItemWire, petData: PetFullDataWire?): Boolean {
        val hasPet = petData?.pet != null
        val inventory = petData?.inventory.orEmpty()
        return when (item.itemType) {
            "pet_egg" -> !hasPet && inventoryQuantity(inventory, "pet_egg") == 0
            "incubator" -> !hasPet && inventoryQuantity(inventory, "incubator") == 0
            "pet_rarity_upgrade" -> {
                val rarity = petData?.pet?.rarity ?: return false
                PetRarityUpgrade.nextTier(rarity) != null
            }
            "pet_energy_capacity" -> (petData?.energy?.max ?: 5) < PetEnergyPricing.MAX_CAPACITY
            in FOOD_TYPES -> hasPet
            else -> true
        }
    }

    fun inventoryCategory(itemType: String): String = when (itemType) {
        "pet_egg", "incubator" -> "eggs_devices"
        else -> "pet_food"
    }

    fun categoryTitle(category: String): String = when (category) {
        "eggs_devices" -> "Eggs & Devices"
        "pet_food" -> "Pet Food"
        "pet_upgrades" -> "Pet Upgrades"
        else -> category.replaceFirstChar { it.uppercase() }
    }

    fun hasIncubator(inventory: List<PetInventoryWire>): Boolean =
        inventoryQuantity(inventory, "incubator") > 0

    fun canIncubate(petData: PetFullDataWire?): Boolean {
        if (petData?.pet != null) return false
        val inventory = petData?.inventory.orEmpty()
        return inventoryQuantity(inventory, "pet_egg") > 0 &&
            inventoryQuantity(inventory, "incubator") > 0
    }
}
