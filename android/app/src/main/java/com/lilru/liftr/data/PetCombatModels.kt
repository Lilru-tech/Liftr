package com.lilru.liftr.data

import kotlin.math.pow
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class ProfileEnergyWire(
    val current: Int = 0,
    val max: Int = 5,
    @SerialName("last_refresh") val lastRefresh: String? = null,
    @SerialName("next_refresh_at") val nextRefreshAt: String? = null,
    @SerialName("regen_minutes") val regenMinutes: Int? = null
) {
    val isFull: Boolean get() = current >= max
}

object PetEnergyPricing {
    const val MAX_CAPACITY = 15

    fun upgradeCost(maxEnergy: Int): Int =
        (5000 * 2.0.pow((maxOf(maxEnergy, 5) - 5).toDouble())).toInt()
}

@Serializable
data class EnergyUpgradeResultWire(
    @SerialName("max_energy") val maxEnergy: Int,
    @SerialName("current_energy") val currentEnergy: Int,
    val cost: Int,
    @SerialName("purchase_id") val purchaseId: String
)

@Serializable
data class PetCombatRewardsWire(
    val xp: Int = 0,
    val coins: Int = 0
)

@Serializable
data class PetCombatPetSummaryWire(
    val id: String,
    @SerialName("custom_name") val customName: String? = null,
    @SerialName("pet_type") val petType: String,
    @SerialName("evolution_stage") val evolutionStage: String,
    @SerialName("current_level") val currentLevel: Int = 1,
    val rarity: String = "common",
    @SerialName("image_url") val imageUrl: String? = null,
    val name: String? = null
) {
    fun displayName(): String {
        if (!name.isNullOrBlank()) return name
        if (!customName.isNullOrBlank()) return customName
        return petType.replace('_', ' ').replaceFirstChar { it.uppercase() }
    }
}

@Serializable
data class PetCombatStatsSummaryWire(
    val health: Int = 0,
    val strength: Int = 0,
    val defense: Int = 0,
    val speed: Int = 0,
    val intelligence: Int = 0,
    val agility: Int = 0,
    val stamina: Int = 0,
    @SerialName("critical_rate") val criticalRate: Int = 0,
    val resistance: Int = 0,
    val exploration: Int = 0,
    val happiness: Int = 0
) {
    val combatStatPoolTotal: Int
        get() = health + strength + defense + speed + agility + stamina + resistance + criticalRate + intelligence + exploration
}

object PetCombatStatBalancing {
    fun isUnbalanced(attacker: PetCombatStatsSummaryWire, defender: PetCombatStatsSummaryWire): Boolean {
        val poolA = attacker.combatStatPoolTotal
        val poolB = defender.combatStatPoolTotal
        val stronger = maxOf(poolA, poolB)
        val weaker = minOf(poolA, poolB)
        return stronger * 100 > weaker * 105
    }
}

@Serializable
data class PetCombatStatBalancingWire(
    @SerialName("is_unbalanced") val isUnbalanced: Boolean = false,
    @SerialName("attacker_stat_pool") val attackerStatPool: Int = 0,
    @SerialName("defender_stat_pool") val defenderStatPool: Int = 0,
    @SerialName("attacker_pool_battle") val attackerPoolBattle: Int? = null,
    @SerialName("defender_pool_battle") val defenderPoolBattle: Int? = null,
    @SerialName("stronger_side") val strongerSide: String? = null,
    @SerialName("hardcore_buff_multiplier") val hardcoreBuffMultiplier: Double? = null,
    @SerialName("hardcore_bonus_percent") val hardcoreBonusPercent: Int? = null
)

enum class PetCombatChallengeMode(val rawValue: String) {
    BALANCED("balanced"),
    HARDCORE("hardcore");

    val disableNerfChoice: Boolean get() = this == HARDCORE

    val title: String
        get() = when (this) {
            BALANCED -> "Balanced Mode (Safe)"
            HARDCORE -> "Hardcore Mode (No Nerf)"
        }

    companion object {
        fun fromRaw(value: String?): PetCombatChallengeMode =
            entries.firstOrNull { it.rawValue == value } ?: BALANCED
    }
}

@Serializable
data class PetCombatSideWire(
    @SerialName("user_id") val userId: String,
    val username: String? = null,
    val pet: PetCombatPetSummaryWire? = null,
    val stats: PetCombatStatsSummaryWire? = null
)

@Serializable
data class PetCombatPreviewWire(
    @SerialName("can_challenge") val canChallenge: Boolean = false,
    @SerialName("block_reason") val blockReason: String? = null,
    @SerialName("cooldown_expires_at") val cooldownExpiresAt: String? = null,
    @SerialName("stat_balancing") val statBalancing: PetCombatStatBalancingWire? = null,
    val attacker: PetCombatSideWire? = null,
    val defender: PetCombatSideWire? = null,
    val energy: ProfileEnergyWire? = null
) {
    fun isStatUnbalanced(): Boolean {
        statBalancing?.isUnbalanced?.let { return it }
        val attackerStats = attacker?.stats ?: return false
        val defenderStats = defender?.stats ?: return false
        return PetCombatStatBalancing.isUnbalanced(attackerStats, defenderStats)
    }

    fun isAttackerUnderdog(): Boolean = statBalancing?.strongerSide == "defender"

    fun hardcoreBonusLabel(): String? {
        val percent = statBalancing?.hardcoreBonusPercent ?: return null
        if (percent <= 0) return null
        return "+$percent% Coins & XP"
    }

    fun blockReasonText(): String? = when (blockReason) {
        "self_challenge" -> "You cannot challenge yourself."
        "attacker_no_pet" -> "You need a hatched pet to challenge."
        "defender_no_pet" -> "This user has no pet to challenge."
        "attacker_egg" -> "Your pet must hatch before battling."
        "defender_egg" -> "This user's pet has not hatched yet."
        "no_energy" -> "No arena energy left. You regain 1 energy every 4 hours."
        "cooldown_active" -> "You recently battled this user. Try again later."
        null -> null
        else -> blockReason.replace('_', ' ').replaceFirstChar { it.uppercase() }
    }
}

@Serializable
data class PetBattlePetSnapshotWire(
    @SerialName("user_id") val userId: String,
    @SerialName("pet_instance_id") val petInstanceId: String,
    val name: String,
    @SerialName("pet_type") val petType: String,
    @SerialName("evolution_stage") val evolutionStage: String,
    val level: Int,
    val rarity: String,
    @SerialName("image_url") val imageUrl: String? = null,
    @SerialName("max_hp") val maxHp: Int? = null
) {
    fun resolvedMaxHp(fallback: Int = 1): Int = maxHp?.takeIf { it > 0 } ?: maxOf(fallback, 1)
}

@Serializable
data class PetBattleTurnWire(
    val turn: Int,
    val actor: String,
    val action: String,
    val damage: Int,
    @SerialName("is_critical") val isCritical: Boolean = false,
    @SerialName("attacker_hp_after") val attackerHpAfter: Int,
    @SerialName("defender_hp_after") val defenderHpAfter: Int,
    val message: String
)

@Serializable
data class PetBattleResultSummaryWire(
    val winner: String? = null,
    @SerialName("winner_user_id") val winnerUserId: String? = null,
    @SerialName("total_turns") val totalTurns: Int = 0,
    @SerialName("is_draw") val isDraw: Boolean = false
)

@Serializable
data class PetBattleLogWire(
    val version: Int = 1,
    @SerialName("attacker_pet") val attackerPet: PetBattlePetSnapshotWire,
    @SerialName("defender_pet") val defenderPet: PetBattlePetSnapshotWire,
    val turns: List<PetBattleTurnWire> = emptyList(),
    val result: PetBattleResultSummaryWire
)

@Serializable
data class PetCombatResultWire(
    @SerialName("combat_id") val combatId: String,
    @SerialName("winner_user_id") val winnerUserId: String? = null,
    @SerialName("attacker_rewards") val attackerRewards: PetCombatRewardsWire,
    @SerialName("defender_rewards") val defenderRewards: PetCombatRewardsWire,
    @SerialName("battle_log") val battleLog: PetBattleLogWire,
    val energy: ProfileEnergyWire? = null
)

@Serializable
data class PetCombatHeadToHeadLastBattleWire(
    @SerialName("created_at") val createdAt: String? = null,
    val won: Boolean = false,
    @SerialName("is_draw") val isDraw: Boolean = false,
    @SerialName("your_role") val yourRole: String? = null,
    val rewards: PetCombatRewardsWire? = null
)

@Serializable
data class PetCombatUserStatsWire(
    @SerialName("max_damage_dealt") val maxDamageDealt: Int = 0,
    @SerialName("max_damage_taken") val maxDamageTaken: Int = 0,
    @SerialName("total_damage_dealt") val totalDamageDealt: Long = 0,
    @SerialName("total_damage_taken") val totalDamageTaken: Long = 0,
    @SerialName("crits_landed") val critsLanded: Int = 0,
    @SerialName("dodges_performed") val dodgesPerformed: Int = 0,
    @SerialName("total_battles") val totalBattles: Int = 0,
    val wins: Int = 0,
    val losses: Int = 0,
    val draws: Int = 0,
    @SerialName("current_win_streak") val currentWinStreak: Int = 0,
    @SerialName("best_win_streak") val bestWinStreak: Int = 0,
    @SerialName("longest_battle_turns") val longestBattleTurns: Int = 0
)

@Serializable
data class PetCombatHeadToHeadSummaryWire(
    val wins: Int = 0,
    val losses: Int = 0,
    val draws: Int = 0,
    @SerialName("total_battles") val totalBattles: Int = 0,
    @SerialName("win_rate") val winRate: Double = 0.0,
    @SerialName("last_battle") val lastBattle: PetCombatHeadToHeadLastBattleWire? = null
) {
    fun winRatePercentText(): String =
        if (totalBattles <= 0) "0%" else "${kotlin.math.round(winRate * 100).toInt()}%"
}
