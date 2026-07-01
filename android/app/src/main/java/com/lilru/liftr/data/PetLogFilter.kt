package com.lilru.liftr.data

enum class PetLogFilterCategory(val key: String, val label: String) {
    FEEDING("feeding", "Feeding & items"),
    LEVEL_UP("level_up", "Level up"),
    EGG_HATCH("egg_hatch", "Egg & hatch"),
    EVOLUTION("evolution", "Evolution"),
    RARITY_UPGRADE("rarity_upgrade", "Rarity upgrade"),
    PASSIVE_COINS("passive_coins", "Passive pet coins"),
    WORKOUT_BONUS("workout_bonus", "Workout bonus"),
    COMBAT("combat", "Combat");

    companion object {
        val all = entries.toList()

        fun categoryKey(eventType: String): String? = when (eventType.trim().lowercase()) {
            "fed", "item_used" -> FEEDING.key
            "level_up" -> LEVEL_UP.key
            "incubation_started", "hatched" -> EGG_HATCH.key
            "evolution" -> EVOLUTION.key
            "rarity_upgrade" -> RARITY_UPGRADE.key
            "coins_generated" -> PASSIVE_COINS.key
            "workout_pet_bonus" -> WORKOUT_BONUS.key
            "combat" -> COMBAT.key
            else -> null
        }

        fun isVisible(eventType: String, disabledKeys: Set<String>): Boolean {
            val key = categoryKey(eventType) ?: return true
            return key !in disabledKeys
        }

        fun filter(logs: List<PetLogWire>, disabledKeys: Set<String>): List<PetLogWire> =
            logs.filter { isVisible(it.eventType, disabledKeys) }
    }
}

enum class CoinLogFilterCategory(val key: String) {
    WORKOUTS("workouts"),
    PET_WORKOUT_BONUS("pet_workout_bonus"),
    PET_COINS("pet_coins"),
    SOCIAL("social"),
    NUTRITION("nutrition"),
    ACHIEVEMENTS("achievements"),
    GOALS_STREAKS("goals_streaks"),
    WEEKLY_TASKS("weekly_tasks"),
    COMPETITION("competition"),
    PET_COMBAT("pet_combat"),
    OTHER("other");

    val label: String get() = CoinManager.sourceCategoryLabel(key)

    companion object {
        val all = entries.toList()

        fun isVisible(actionType: String, disabledKeys: Set<String>): Boolean {
            val key = CoinManager.sourceKey(actionType)
            return key !in disabledKeys
        }
    }
}
