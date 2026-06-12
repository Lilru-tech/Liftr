package com.lilru.liftr.data

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import io.github.jan.supabase.postgrest.rpc
import kotlin.math.pow
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

object PetService {
    const val STORAGE_PUBLIC_BASE = "https://rjzhaafvkxmvlnpsikbi.supabase.co/storage/v1/object/public"

    fun petImageUrls(petType: String, evolutionStage: String): List<String> {
        val stage = if (evolutionStage.equals("elder", ignoreCase = true)) "elder" else evolutionStage.lowercase()
        return listOf("$STORAGE_PUBLIC_BASE/pets/${petType.lowercase()}_${stage}.png")
    }

    fun petImageUrl(petType: String, evolutionStage: String): String =
        petImageUrls(petType, evolutionStage).first()

    fun resolvedImageUrls(pet: PetInstanceWire): List<String> {
        val urls = mutableListOf<String>()
        pet.imageUrl?.takeIf { it.isNotBlank() }?.let { urls.add(it) }
        val built = petImageUrl(pet.petType, pet.evolutionStage)
        if (!urls.contains(built)) {
            urls.add(built)
        }
        return urls
    }

    fun resolvedImageUrl(pet: PetInstanceWire): String =
        resolvedImageUrls(pet).first()

    fun resolvedCombatPetImageUrl(pet: PetCombatPetSummaryWire): String =
        pet.imageUrl?.takeIf { it.isNotBlank() } ?: petImageUrl(pet.petType, pet.evolutionStage)

    fun marketImageUrl(path: String?): String? {
        if (path.isNullOrBlank()) return null
        return "$STORAGE_PUBLIC_BASE/pets/$path"
    }

    suspend fun fetchMyPet(supabase: SupabaseClient): PetFullDataWire {
        val res = supabase.postgrest.rpc(BackendContracts.Rpc.GET_MY_PET_V1) { }
        return SupabaseResponseDecoding.decodeObject(res.data)
    }

    suspend fun fetchMarketItems(supabase: SupabaseClient): List<PetMarketItemWire> {
        val res = supabase.postgrest.rpc(BackendContracts.Rpc.LIST_PET_MARKET_ITEMS_V1) { }
        return SupabaseResponseDecoding.decodeListOrObject(res.data)
    }

    suspend fun buyItem(supabase: SupabaseClient, itemType: String, quantity: Int = 1) {
        supabase.postgrest.rpc(
            BackendContracts.Rpc.BUY_PET_MARKET_ITEM_V1,
            buildJsonObject {
                put("p_item_type", itemType)
                put("p_quantity", quantity)
            }
        ) { }
        CoinManager.refreshBalanceAfterMutation(supabase)
    }

    suspend fun startIncubation(supabase: SupabaseClient): Long? {
        val res = supabase.postgrest.rpc(BackendContracts.Rpc.START_PET_INCUBATION_V1) { }
        PetRefreshBus.notifyPetStateDidChange()
        return decodeHatchAtMs(res.data)
    }

    suspend fun feed(supabase: SupabaseClient, itemType: String) {
        supabase.postgrest.rpc(
            BackendContracts.Rpc.FEED_PET_V1,
            buildJsonObject { put("p_item_type", itemType) }
        ) { }
    }

    suspend fun confirmEvolution(supabase: SupabaseClient) {
        supabase.postgrest.rpc(BackendContracts.Rpc.CONFIRM_PET_EVOLUTION_V1) { }
    }

    suspend fun updateName(supabase: SupabaseClient, name: String) {
        supabase.postgrest.rpc(
            BackendContracts.Rpc.UPDATE_PET_CUSTOM_NAME_V1,
            buildJsonObject { put("p_name", name) }
        ) { }
    }

    suspend fun rerollEgg(supabase: SupabaseClient): Long? {
        val res = supabase.postgrest.rpc(BackendContracts.Rpc.REROLL_PET_EGG_V1) { }
        CoinManager.refreshBalanceAfterMutation(supabase)
        PetRefreshBus.notifyPetStateDidChange()
        return decodeHatchAtMs(res.data)
    }

    suspend fun upgradeRarity(supabase: SupabaseClient): RarityUpgradeResultWire {
        val res = supabase.postgrest.rpc(BackendContracts.Rpc.UPGRADE_PET_RARITY_V1) { }
        CoinManager.refreshBalanceAfterMutation(supabase)
        PetRefreshBus.notifyPetStateDidChange()
        return SupabaseResponseDecoding.decodeObject(res.data)
    }

    suspend fun fetchCombatPreview(supabase: SupabaseClient, targetUserId: String): PetCombatPreviewWire {
        val res = supabase.postgrest.rpc(
            BackendContracts.Rpc.GET_PET_COMBAT_PREVIEW_V1,
            buildJsonObject { put("p_target_user_id", targetUserId) }
        ) { }
        return SupabaseResponseDecoding.decodeObject(res.data)
    }

    suspend fun fetchCombatHeadToHead(
        supabase: SupabaseClient,
        opponentUserId: String
    ): PetCombatHeadToHeadSummaryWire {
        val res = supabase.postgrest.rpc(
            BackendContracts.Rpc.GET_PET_COMBAT_HEAD_TO_HEAD_V1,
            buildJsonObject { put("p_opponent_user_id", opponentUserId) }
        ) { }
        return SupabaseResponseDecoding.decodeObject(res.data)
    }

    suspend fun executeCombat(supabase: SupabaseClient, targetOpponentUserId: String): PetCombatResultWire {
        val res = supabase.postgrest.rpc(
            BackendContracts.Rpc.EXECUTE_PET_COMBAT_V1,
            buildJsonObject { put("p_target_opponent_user_id", targetOpponentUserId) }
        ) { }
        CoinManager.refreshBalanceAfterMutation(supabase)
        PetRefreshBus.notifyPetStateDidChange()
        return SupabaseResponseDecoding.decodeObject(res.data)
    }

    suspend fun fetchCombatUserStats(supabase: SupabaseClient): PetCombatUserStatsWire {
        val res = supabase.postgrest.rpc(BackendContracts.Rpc.GET_PET_COMBAT_USER_STATS_V1) { }
        return SupabaseResponseDecoding.decodeObject(res.data)
    }

    suspend fun upgradeEnergyCapacity(supabase: SupabaseClient): EnergyUpgradeResultWire {
        val res = supabase.postgrest.rpc(BackendContracts.Rpc.UPGRADE_PET_ENERGY_CAPACITY_V1) { }
        CoinManager.refreshBalanceAfterMutation(supabase)
        PetRefreshBus.notifyPetStateDidChange()
        return SupabaseResponseDecoding.decodeObject(res.data)
    }

    suspend fun fetchRarityConfig(supabase: SupabaseClient): List<PetRarityConfigWire> {
        return supabase.from(BackendContracts.Tables.PET_RARITY_CONFIG).select {
            order(column = "sort_order", order = Order.ASCENDING)
        }.decodeList<PetRarityConfigWire>()
    }

    suspend fun fetchPetTypeCatalog(supabase: SupabaseClient): List<PetTypeCatalogWire> {
        return supabase.from(BackendContracts.Tables.PET_TYPES).select(
            columns = Columns.raw("name, display_name, description, image_egg")
        ) {
            order(column = "display_name", order = Order.ASCENDING)
        }.decodeList<PetTypeCatalogWire>()
    }

    fun catalogEggImageUrl(row: PetTypeCatalogWire): String {
        val fromDb = row.imageEgg?.takeIf { it.isNotBlank() }
        if (fromDb != null) return fromDb
        return petImageUrl(row.name, "egg")
    }

    suspend fun fetchPetLogs(supabase: SupabaseClient, offset: Int, limit: Int = 5): List<PetLogWire> {
        return supabase.from(BackendContracts.Tables.PET_LOGS).select {
            order(column = "created_at", order = Order.DESCENDING)
            order(column = "id", order = Order.DESCENDING)
            range(offset.toLong(), (offset + limit - 1).toLong())
        }.decodeList<PetLogWire>()
    }

    suspend fun deleteAllPetLogs(supabase: SupabaseClient) {
        supabase.from(BackendContracts.Tables.PET_LOGS).delete { }
    }

    fun rerollCost(rerollCount: Int): Int =
        kotlin.math.floor(50 * 1.1.pow(rerollCount.toDouble())).toInt()

    fun isIncubating(pet: PetInstanceWire): Boolean {
        val hatchMs = parseHatchAtMs(pet.hatchAt) ?: return false
        return pet.evolutionStage.equals("egg", ignoreCase = true) && hatchMs > System.currentTimeMillis()
    }

    fun isPendingHatch(pet: PetInstanceWire): Boolean {
        val hatchMs = parseHatchAtMs(pet.hatchAt) ?: return false
        return pet.evolutionStage.equals("egg", ignoreCase = true) && hatchMs <= System.currentTimeMillis()
    }

    private fun parseHatchAtMs(hatchAt: String?): Long? {
        if (hatchAt.isNullOrBlank()) return null
        return runCatching { java.time.Instant.parse(hatchAt).toEpochMilli() }.getOrNull()
    }

    private fun decodeHatchAtMs(raw: String): Long? {
        return runCatching {
            SupabaseResponseDecoding.decodeObject<HatchRpcResponse>(raw).hatchAt
        }.getOrNull()?.let { parseHatchAtMs(it) }
    }
}

@Serializable
private data class HatchRpcResponse(
    @SerialName("hatch_at") val hatchAt: String? = null
)

@Serializable
data class PetInstanceWire(
    val id: String,
    @SerialName("user_id") val userId: String,
    @SerialName("pet_type") val petType: String,
    @SerialName("custom_name") val customName: String? = null,
    @SerialName("evolution_stage") val evolutionStage: String,
    @SerialName("current_xp") val currentXp: Int = 0,
    @SerialName("current_level") val currentLevel: Int = 1,
    val rarity: String = "common",
    @SerialName("hatch_at") val hatchAt: String? = null,
    @SerialName("is_equipped") val isEquipped: Boolean = true,
    @SerialName("reroll_count") val rerollCount: Int = 0,
    @SerialName("total_feedings") val totalFeedings: Int = 0,
    @SerialName("image_url") val imageUrl: String? = null
)

@Serializable
data class PetStatsWire(
    @SerialName("pet_instance_id") val petInstanceId: String,
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
)

@Serializable
data class PetInventoryWire(
    val id: String,
    @SerialName("user_id") val userId: String,
    @SerialName("item_type") val itemType: String,
    val quantity: Int = 0
)

@Serializable
data class PetFullDataWire(
    val pet: PetInstanceWire? = null,
    val stats: PetStatsWire? = null,
    val inventory: List<PetInventoryWire> = emptyList(),
    @SerialName("xp_required") val xpRequired: Int = 0,
    @SerialName("can_evolve") val canEvolve: Boolean = false,
    val energy: ProfileEnergyWire? = null
)

@Serializable
data class PetLogWire(
    val id: Long,
    @SerialName("event_type") val eventType: String,
    @SerialName("item_type") val itemType: String? = null,
    @SerialName("exp_gained") val expGained: Int = 0,
    @SerialName("new_level") val newLevel: Int? = null,
    @SerialName("stats_delta") val statsDelta: Map<String, Int>? = null,
    @Serializable(with = PetLogDetailsSerializer::class)
    val details: Map<String, String>? = null,
    @SerialName("created_at") val createdAt: String
) {
    fun title(): String = when (eventType) {
        "item_used", "fed" -> {
            val name = details?.get("reason") ?: itemType
            if (name != null) "Used ${name.replace('_', ' ').replaceFirstChar { it.uppercase() }}"
            else "Used item"
        }
        "level_up" -> "Level up"
        "incubation_started" -> "Incubation started"
        "hatched" -> "Hatched"
        "evolution" -> "Evolution"
        "rarity_upgrade" -> {
            val from = details?.get("from_rarity")
            val to = details?.get("to_rarity")
            if (from != null && to != null) {
                "Rarity upgrade: ${from.replaceFirstChar { it.uppercase() }} → ${to.replaceFirstChar { it.uppercase() }}"
            } else {
                "Rarity upgrade"
            }
        }
        "coins_generated" -> {
            val coins = details?.get("coins")
            if (!coins.isNullOrBlank()) "Coins generated: +$coins"
            else "Coins generated"
        }
        "workout_pet_bonus" -> {
            val message = details?.get("message")
            if (!message.isNullOrBlank()) message
            else {
                val coins = details?.get("coins")
                if (!coins.isNullOrBlank()) "Your pet helped you earn +$coins coins!"
                else "Pet workout bonus"
            }
        }
        "combat" -> {
            val opponent = details?.get("opponent_username")?.takeIf { it.isNotBlank() }?.let { "@$it" } ?: "opponent"
            when {
                details?.get("is_draw") == "true" -> "Draw vs $opponent"
                details?.get("won") == "true" -> "Victory vs $opponent"
                else -> "Defeat vs $opponent"
            }
        }
        else -> eventType.replace('_', ' ').replaceFirstChar { it.uppercase() }
    }

    fun subtitle(): String? {
        if (eventType != "combat") return null
        if (details?.get("is_draw") == "true" || details?.get("won") == "true") {
            val coins = details?.get("coins_gained")?.toIntOrNull() ?: 0
            val parts = buildList {
                if (expGained > 0) add("+$expGained XP")
                if (coins > 0) add("+$coins coins")
            }
            return parts.takeIf { it.isNotEmpty() }?.joinToString(" · ") ?: "No rewards"
        }
        return "No rewards"
    }

    fun showsCombatSubtitle(): Boolean = eventType == "combat" && subtitle() != null
}

@Serializable
data class RarityUpgradeResultWire(
    @SerialName("pet_instance_id") val petInstanceId: String,
    @SerialName("from_rarity") val fromRarity: String,
    @SerialName("to_rarity") val toRarity: String,
    val cost: Int,
    @SerialName("from_stat_multiplier") val fromStatMultiplier: Double,
    @SerialName("to_stat_multiplier") val toStatMultiplier: Double,
    @SerialName("from_coin_multiplier") val fromCoinMultiplier: Double,
    @SerialName("to_coin_multiplier") val toCoinMultiplier: Double,
    @SerialName("purchase_id") val purchaseId: String
)

@Serializable
data class PetRarityConfigWire(
    val rarity: String,
    @SerialName("display_name") val displayName: String,
    @SerialName("color_hex") val colorHex: String,
    @SerialName("drop_weight") val dropWeight: Int,
    @SerialName("coin_multiplier") val coinMultiplier: Double,
    @SerialName("stat_multiplier") val statMultiplier: Double,
    @SerialName("sort_order") val sortOrder: Int
)

@Serializable
data class PetTypeCatalogWire(
    val name: String,
    @SerialName("display_name") val displayName: String,
    val description: String = "",
    @SerialName("image_egg") val imageEgg: String? = null
)

@Serializable
data class PetMarketItemWire(
    @SerialName("item_type") val itemType: String,
    @SerialName("display_name") val displayName: String,
    val description: String = "",
    val price: Int = 0,
    val category: String = "",
    @SerialName("image_path") val imagePath: String? = null,
    @SerialName("is_active") val isActive: Boolean = true
)
