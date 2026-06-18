import Foundation
import Supabase

@MainActor
final class PetService {
    static let shared = PetService()
    private init() {}

    private var client: SupabaseClient { SupabaseManager.shared.client }

    func fetchMyPet() async throws -> PetFullData {
        let res = try await client.rpc("get_my_pet_v1").execute()
        if let decoded = try? JSONDecoder.supabaseCustom().decode(PetFullData.self, from: res.data) {
            return decoded
        }
        return try JSONDecoder.supabase().decode(PetFullData.self, from: res.data)
    }

    func fetchMarketItems() async throws -> [PetMarketItemRow] {
        let res = try await client.rpc("list_pet_market_items_v1").execute()
        return try JSONDecoder.supabase().decode([PetMarketItemRow].self, from: res.data)
    }

    func buyItem(itemType: String, quantity: Int = 1) async throws {
        struct Params: Encodable {
            let p_item_type: String
            let p_quantity: Int
        }
        _ = try await client
            .rpc("buy_pet_market_item_v1", params: Params(p_item_type: itemType, p_quantity: quantity))
            .execute()
        await CoinManager.shared.refreshBalance()
    }

    func startIncubation() async throws -> Date? {
        let res = try await client.rpc("start_pet_incubation_v1").execute()
        PetRefreshCenter.notifyPetStateDidChange()
        return decodeHatchAt(from: res.data)
    }

    func feed(itemType: String) async throws {
        struct Params: Encodable {
            let p_item_type: String
        }
        _ = try await client
            .rpc("feed_pet_v1", params: Params(p_item_type: itemType))
            .execute()
    }

    func confirmEvolution() async throws {
        _ = try await client.rpc("confirm_pet_evolution_v1").execute()
    }

    func updateName(_ name: String) async throws {
        struct Params: Encodable {
            let p_name: String
        }
        _ = try await client
            .rpc("update_pet_custom_name_v1", params: Params(p_name: name))
            .execute()
    }

    func rerollEgg() async throws -> Date? {
        let res = try await client.rpc("reroll_pet_egg_v1").execute()
        await CoinManager.shared.refreshBalance()
        PetRefreshCenter.notifyPetStateDidChange()
        return decodeHatchAt(from: res.data)
    }

    func upgradeRarity() async throws -> RarityUpgradeResult {
        let res = try await client.rpc("upgrade_pet_rarity_v1").execute()
        await CoinManager.shared.refreshBalance()
        PetRefreshCenter.notifyPetStateDidChange()
        if let decoded = try? JSONDecoder.supabaseCustom().decode(RarityUpgradeResult.self, from: res.data) {
            return decoded
        }
        return try JSONDecoder.supabase().decode(RarityUpgradeResult.self, from: res.data)
    }

    func fetchCombatPreview(targetUserId: UUID) async throws -> PetCombatPreview {
        struct Params: Encodable {
            let p_target_user_id: UUID
        }
        let res = try await client
            .rpc("get_pet_combat_preview_v1", params: Params(p_target_user_id: targetUserId))
            .execute()
        if let decoded = try? JSONDecoder.supabaseCustom().decode(PetCombatPreview.self, from: res.data) {
            return decoded
        }
        return try JSONDecoder.supabase().decode(PetCombatPreview.self, from: res.data)
    }

    func fetchCombatHeadToHead(opponentUserId: UUID) async throws -> PetCombatHeadToHeadSummary {
        struct Params: Encodable {
            let p_opponent_user_id: UUID
        }
        let res = try await client
            .rpc("get_pet_combat_head_to_head_v1", params: Params(p_opponent_user_id: opponentUserId))
            .execute()
        if let decoded = try? JSONDecoder.supabaseCustom().decode(PetCombatHeadToHeadSummary.self, from: res.data) {
            return decoded
        }
        return try JSONDecoder.supabase().decode(PetCombatHeadToHeadSummary.self, from: res.data)
    }

    func executeCombat(targetOpponentUserId: UUID, disableNerfChoice: Bool = false) async throws -> PetCombatResult {
        struct Params: Encodable {
            let p_target_opponent_user_id: UUID
            let p_disable_nerf_choice: Bool
        }
        let res = try await client
            .rpc("execute_pet_combat_v1", params: Params(
                p_target_opponent_user_id: targetOpponentUserId,
                p_disable_nerf_choice: disableNerfChoice
            ))
            .execute()
        await CoinManager.shared.refreshBalance()
        PetRefreshCenter.notifyPetStateDidChange()
        if let decoded = try? JSONDecoder.supabaseCustom().decode(PetCombatResult.self, from: res.data) {
            return decoded
        }
        return try JSONDecoder.supabase().decode(PetCombatResult.self, from: res.data)
    }

    func fetchCombatUserStats() async throws -> PetCombatUserStats {
        let res = try await client
            .rpc("get_pet_combat_user_stats_v1")
            .execute()
        if let decoded = try? JSONDecoder.supabaseCustom().decode(PetCombatUserStats.self, from: res.data) {
            return decoded
        }
        return try JSONDecoder.supabase().decode(PetCombatUserStats.self, from: res.data)
    }

    func upgradeEnergyCapacity() async throws -> EnergyUpgradeResult {
        let res = try await client.rpc("upgrade_pet_energy_capacity_v1").execute()
        await CoinManager.shared.refreshBalance()
        PetRefreshCenter.notifyPetStateDidChange()
        if let decoded = try? JSONDecoder.supabaseCustom().decode(EnergyUpgradeResult.self, from: res.data) {
            return decoded
        }
        return try JSONDecoder.supabase().decode(EnergyUpgradeResult.self, from: res.data)
    }

    private func decodeHatchAt(from data: Data) -> Date? {
        struct HatchPayload: Decodable {
            let hatchAt: Date?

            enum CodingKeys: String, CodingKey {
                case hatchAt = "hatch_at"
            }
        }

        if let payload = try? JSONDecoder.supabaseCustom().decode(HatchPayload.self, from: data) {
            return payload.hatchAt
        }
        if let payload = try? JSONDecoder.supabase().decode(HatchPayload.self, from: data) {
            return payload.hatchAt
        }
        return nil
    }

    func fetchRarityConfig() async throws -> [PetRarityConfigRow] {
        let res = try await client
            .from("pet_rarity_config")
            .select()
            .order("sort_order", ascending: true)
            .execute()
        return try JSONDecoder.supabase().decode([PetRarityConfigRow].self, from: res.data)
    }

    func fetchPetTypeCatalog() async throws -> [PetTypeCatalogRow] {
        let res = try await client
            .from("pet_types")
            .select("name, display_name, description, image_egg")
            .order("display_name", ascending: true)
            .execute()
        return try JSONDecoder.supabase().decode([PetTypeCatalogRow].self, from: res.data)
    }

    func fetchMyPetDex() async throws -> PetDexData {
        let res = try await client.rpc("get_my_pet_dex_v1").execute()
        if let decoded = try? JSONDecoder.supabaseCustom().decode(PetDexData.self, from: res.data) {
            return decoded
        }
        return try JSONDecoder.supabase().decode(PetDexData.self, from: res.data)
    }

    func fetchPetSpeciesDetail(petType: String) async throws -> PetSpeciesDetail {
        struct Params: Encodable {
            let p_pet_type: String
        }
        let res = try await client
            .rpc("get_pet_species_detail_v1", params: Params(p_pet_type: petType))
            .execute()
        if let decoded = try? JSONDecoder.supabaseCustom().decode(PetSpeciesDetail.self, from: res.data) {
            return decoded
        }
        return try JSONDecoder.supabase().decode(PetSpeciesDetail.self, from: res.data)
    }

    func fetchPetLogs(offset: Int, limit: Int = 5) async throws -> [PetLog] {
        let res = try await client
            .from("pet_logs")
            .select("id, event_type, item_type, exp_gained, new_level, stats_delta, details, created_at")
            .order("created_at", ascending: false)
            .order("id", ascending: false)
            .range(from: offset, to: offset + limit - 1)
            .execute()
        return try JSONDecoder.supabase().decode([PetLogRow].self, from: res.data).map(\.petLog)
    }

    func deleteAllPetLogs() async throws {
        _ = try await client.from("pet_logs").delete().execute()
    }
}
