import Foundation
import SwiftUI

enum NutritionFoodSaveMode: String, CaseIterable, Identifiable {
    case diary = "Log today"
    case plan = "Plan ahead"

    var id: String { rawValue }
}

struct NutritionMealPlanRow: Decodable, Identifiable {
    let id: UUID
    let creator_id: UUID
    let plan_date: String
    let meal_slot: String
    let recipe_id: UUID?
    let ingredient_id: UUID?
}

struct NutritionMealPlanTargetRow: Decodable, Identifiable {
    let id: UUID
    let plan_id: UUID
    let target_user_id: UUID
    let quantity_g: Double
    let status: String
    let accepted_at: Date?
    let ingredient_id: UUID?
    let recipe_id: UUID?
}

struct NutritionMealPlanInviteUI: Identifiable {
    let targetId: UUID
    var id: UUID { targetId }
    let planId: UUID
    let planDate: Date
    let mealSlot: String
    let foodName: String
    let quantityG: Double
    let caloriesKcal: Double
    let creatorUsername: String?
}

struct NutritionMealPlanItemUI: Identifiable {
    let targetId: UUID
    let planId: UUID
    let targetUserId: UUID
    let planDate: Date
    let mealSlot: String
    let foodName: String
    let quantityG: Double
    let caloriesKcal: Double
    let status: String
    let isCreator: Bool
    let partnerLabel: String?
    let partnerStatusLabel: String?

    var id: UUID { targetId }

    func canMarkEaten(viewingUserId: UUID) -> Bool {
        targetUserId == viewingUserId && status == "accepted"
    }

    func canDecline(viewingUserId: UUID) -> Bool {
        targetUserId == viewingUserId && (status == "pending" || status == "accepted")
    }
}

private struct NutritionMealPlanInsert: Encodable {
    let creator_id: UUID
    let plan_date: String
    let meal_slot: String
    let ingredient_id: UUID?
    let recipe_id: UUID?
}

private struct NutritionMealPlanTargetInsert: Encodable {
    let plan_id: UUID
    let target_user_id: UUID
    let quantity_g: Double
    let ingredient_id: UUID?
    let recipe_id: UUID?
}

private struct MealPlanTargetIdParams: Encodable {
    let p_target_id: UUID
}

private struct MealPlanTargetUpdateParams: Encodable {
    let p_target_id: UUID
    let p_quantity_g: Double
    let p_meal_slot: String?
}

private let mealPlanTargetSelect = "id,plan_id,target_user_id,quantity_g,status,accepted_at,ingredient_id,recipe_id"

private struct MealPlanTargetIdRow: Decodable {
    let id: UUID
}

extension NutritionManager {

    static func fetchFollowingProfiles(userId: UUID) async throws -> [LightweightProfile] {
        struct FollowRow: Decodable { let followee_id: UUID }
        let followRes = try await SupabaseManager.shared.client
            .from("follows")
            .select("followee_id")
            .eq("follower_id", value: userId.uuidString)
            .execute()
        let follows = try JSONDecoder.supabase().decode([FollowRow].self, from: followRes.data)
        let ids = follows.map(\.followee_id)
        guard !ids.isEmpty else { return [] }
        let profRes = try await SupabaseManager.shared.client
            .from("profiles")
            .select("user_id,username,avatar_url")
            .in("user_id", values: ids.map(\.uuidString))
            .order("username", ascending: true)
            .execute()
        return try JSONDecoder.supabase().decode([LightweightProfile].self, from: profRes.data)
            .filter { $0.user_id != userId }
    }

    static func fetchPendingInvites(userId: UUID) async throws -> [NutritionMealPlanInviteUI] {
        let res = try await SupabaseManager.shared.client
            .from("nutrition_meal_plan_targets")
            .select(mealPlanTargetSelect)
            .eq("target_user_id", value: userId.uuidString)
            .eq("status", value: "pending")
            .order("created_at", ascending: false)
            .execute()
        let targets = try JSONDecoder.supabase().decode([NutritionMealPlanTargetRow].self, from: res.data)
        guard !targets.isEmpty else { return [] }
        return try await enrichInvites(targets: targets, inviteeId: userId)
    }

    static func fetchInvite(targetId: UUID, userId: UUID) async throws -> NutritionMealPlanInviteUI? {
        let res = try await SupabaseManager.shared.client
            .from("nutrition_meal_plan_targets")
            .select(mealPlanTargetSelect)
            .eq("id", value: targetId.uuidString)
            .eq("target_user_id", value: userId.uuidString)
            .limit(1)
            .execute()
        let targets = try JSONDecoder.supabase().decode([NutritionMealPlanTargetRow].self, from: res.data)
        guard let target = targets.first else { return nil }
        let invites = try await enrichInvites(targets: [target], inviteeId: userId)
        return invites.first
    }

    static func fetchInvite(planId: UUID, userId: UUID) async throws -> NutritionMealPlanInviteUI? {
        let res = try await SupabaseManager.shared.client
            .from("nutrition_meal_plan_targets")
            .select(mealPlanTargetSelect)
            .eq("plan_id", value: planId.uuidString)
            .eq("target_user_id", value: userId.uuidString)
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
        let targets = try JSONDecoder.supabase().decode([NutritionMealPlanTargetRow].self, from: res.data)
        guard let target = targets.first else { return nil }
        let invites = try await enrichInvites(targets: [target], inviteeId: userId)
        return invites.first
    }

    static func fetchPlannedItems(userId: UUID, date: Date) async throws -> [NutritionMealPlanItemUI] {
        let dateStr = dateOnlyString(date)
        let res = try await SupabaseManager.shared.client
            .from("nutrition_meal_plan_targets")
            .select(mealPlanTargetSelect)
            .eq("target_user_id", value: userId.uuidString)
            .eq("status", value: "accepted")
            .execute()
        let targets = try JSONDecoder.supabase().decode([NutritionMealPlanTargetRow].self, from: res.data)
        guard !targets.isEmpty else { return [] }
        let plans = try await fetchPlans(ids: Array(Set(targets.map(\.plan_id))))
        let plansForDate = plans.filter { $0.plan_date == dateStr }
        let planIdsForDate = Set(plansForDate.map(\.id))
        let filteredTargets = targets.filter { planIdsForDate.contains($0.plan_id) }
        return try await enrichPlannedItems(targets: filteredTargets, userId: userId, dateStr: dateStr, plans: plansForDate)
    }

    static func createMealPlansFromCart(
        creatorId: UUID,
        planDate: Date,
        mealSlot: NutritionMealSlot,
        cart: [NutritionLogCartItem],
        partnerUserIds: [UUID]
    ) async throws {
        let dateStr = dateOnlyString(planDate)
        let defaultAssignees = Set([creatorId] + partnerUserIds.filter { $0 != creatorId })

        for item in cart {
            let ingredientId: UUID?
            let recipeId: UUID?
            switch item.kind {
            case .ingredient(let ing):
                ingredientId = ing.id
                recipeId = nil
            case .recipe(let recipe, let lines) where !lines.isEmpty:
                ingredientId = nil
                recipeId = recipe.id
            default:
                throw NSError(domain: "Nutrition", code: 1, userInfo: [NSLocalizedDescriptionKey: "Recipe still loading."])
            }

            let assignees = item.assignedUserIds.isEmpty ? defaultAssignees : item.assignedUserIds
            guard !assignees.isEmpty else { continue }

            let planPayload = NutritionMealPlanInsert(
                creator_id: creatorId,
                plan_date: dateStr,
                meal_slot: mealSlot.rawValue,
                ingredient_id: ingredientId,
                recipe_id: recipeId
            )
            let planRes = try await SupabaseManager.shared.client
                .from("nutrition_meal_plans")
                .insert(planPayload)
                .select("id")
                .single()
                .execute()
            let planRow = try JSONDecoder.supabase().decode(MealPlanTargetIdRow.self, from: planRes.data)

            let targetRows = assignees.map { userId in
                let quantity = NutritionLogCartLogic.clampGrams(item.perUserGrams[userId] ?? item.grams)
                return NutritionMealPlanTargetInsert(
                    plan_id: planRow.id,
                    target_user_id: userId,
                    quantity_g: quantity,
                    ingredient_id: ingredientId,
                    recipe_id: recipeId
                )
            }
            _ = try await SupabaseManager.shared.client
                .from("nutrition_meal_plan_targets")
                .insert(targetRows)
                .execute()
        }
    }

    static func updateMealPlanTarget(targetId: UUID, quantityG: Double, mealSlot: NutritionMealSlot?) async throws {
        let params = MealPlanTargetUpdateParams(
            p_target_id: targetId,
            p_quantity_g: NutritionLogCartLogic.clampGrams(quantityG),
            p_meal_slot: mealSlot?.rawValue
        )
        _ = try await SupabaseManager.shared.client
            .rpc("update_meal_plan_target", params: params)
            .execute()
    }

    static func mealPlanErrorMessage(_ error: Error) -> String {
        let text = error.localizedDescription
        if text.contains("INVITEE_MAY_ONLY_UPDATE_QUANTITY") || text.contains("INVITEE_MAY_ONLY_UPDATE_STATUS") {
            return "Could not save your planned meal. Please try again."
        }
        if text.contains("FORBIDDEN") || text.contains("42501") {
            return "You can only update your own planned meal."
        }
        if text.contains("INVALID_STATUS") {
            return "This meal plan can no longer be changed."
        }
        return text
    }

    static func formattedPlanDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df.string(from: date)
    }

    static func fetchMonthPlannedMealCounts(userId: UUID, month: Date) async throws -> [Date: Int] {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: month)
        guard let monthStart = cal.date(from: comps),
              let monthEnd = cal.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart)
        else { return [:] }
        let rangeStart = cal.startOfDay(for: monthStart)
        let rangeEnd = cal.startOfDay(for: monthEnd)

        let res = try await SupabaseManager.shared.client
            .from("nutrition_meal_plan_targets")
            .select(mealPlanTargetSelect)
            .eq("target_user_id", value: userId.uuidString)
            .eq("status", value: "accepted")
            .execute()
        let targets = try JSONDecoder.supabase().decode([NutritionMealPlanTargetRow].self, from: res.data)
        guard !targets.isEmpty else { return [:] }

        let plans = try await fetchPlans(ids: Array(Set(targets.map(\.plan_id))))
        let plansById = Dictionary(uniqueKeysWithValues: plans.map { ($0.id, $0) })
        let df = planDateFormatter()
        var counts: [Date: Int] = [:]
        for target in targets {
            guard let plan = plansById[target.plan_id],
                  let planDate = df.date(from: plan.plan_date)
            else { continue }
            let key = cal.startOfDay(for: planDate)
            guard key >= rangeStart, key <= rangeEnd else { continue }
            counts[key, default: 0] += 1
        }
        return counts
    }

    static func acceptMealPlan(targetId: UUID) async throws {
        let params = MealPlanTargetIdParams(p_target_id: targetId)
        _ = try await SupabaseManager.shared.client
            .rpc("accept_meal_plan", params: params)
            .execute()
    }

    static func rejectMealPlan(targetId: UUID) async throws {
        let params = MealPlanTargetIdParams(p_target_id: targetId)
        _ = try await SupabaseManager.shared.client
            .rpc("reject_meal_plan", params: params)
            .execute()
    }

    @discardableResult
    static func completeMealPlanAsEaten(targetId: UUID) async throws -> UUID {
        let params = MealPlanTargetIdParams(p_target_id: targetId)
        let res = try await SupabaseManager.shared.client
            .rpc("complete_meal_plan_as_eaten", params: params)
            .execute()
        if let id = try? JSONDecoder.supabase().decode(UUID.self, from: res.data) {
            return id
        }
        if let ids = try? JSONDecoder.supabase().decode([UUID].self, from: res.data), let first = ids.first {
            return first
        }
        let text = String(data: res.data, encoding: .utf8)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\" \n"))
        guard let text, let id = UUID(uuidString: text) else {
            throw NSError(domain: "Nutrition", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not read diary log id."])
        }
        return id
    }

    private static func enrichInvites(
        targets: [NutritionMealPlanTargetRow],
        inviteeId: UUID
    ) async throws -> [NutritionMealPlanInviteUI] {
        let planIds = Array(Set(targets.map(\.plan_id)))
        let plans = try await fetchPlans(ids: planIds)
        let plansById = Dictionary(uniqueKeysWithValues: plans.map { ($0.id, $0) })
        let names = try await foodNames(forPlans: plans, targets: targets)
        let kcal = try await foodKcalPerGram(forPlans: plans, targets: targets)
        let creators = Array(Set(plans.map(\.creator_id)))
        let usernames = try await usernames(for: creators)

        let df = planDateFormatter()
        return targets.compactMap { target in
            guard let plan = plansById[target.plan_id] else { return nil }
            guard plan.creator_id != inviteeId else { return nil }
            guard target.target_user_id == inviteeId else { return nil }
            guard let planDate = df.date(from: plan.plan_date) else { return nil }
            let foodKey = target.ingredient_id ?? target.recipe_id ?? plan.ingredient_id ?? plan.recipe_id
            let name = foodKey.flatMap { names[$0] } ?? "Meal"
            let density = foodKey.flatMap { kcal[$0] } ?? 0
            return NutritionMealPlanInviteUI(
                targetId: target.id,
                planId: plan.id,
                planDate: planDate,
                mealSlot: plan.meal_slot,
                foodName: name,
                quantityG: target.quantity_g,
                caloriesKcal: target.quantity_g * density,
                creatorUsername: usernames[plan.creator_id]
            )
        }
    }

    private static func enrichPlannedItems(
        targets: [NutritionMealPlanTargetRow],
        userId: UUID,
        dateStr: String,
        plans: [NutritionMealPlanRow]
    ) async throws -> [NutritionMealPlanItemUI] {
        var allPlans = plans
        let missingPlanIds = Set(targets.map(\.plan_id)).subtracting(Set(allPlans.map(\.id)))
        if !missingPlanIds.isEmpty {
            allPlans.append(contentsOf: try await fetchPlans(ids: Array(missingPlanIds)))
        }
        let plansById = Dictionary(uniqueKeysWithValues: allPlans.map { ($0.id, $0) })
        let names = try await foodNames(forPlans: allPlans, targets: targets)
        let kcal = try await foodKcalPerGram(forPlans: allPlans, targets: targets)
        let siblingTargets = try await fetchTargetsForPlans(ids: Array(plansById.keys))
        let siblingsByPlan = Dictionary(grouping: siblingTargets, by: \.plan_id)
        var userIds = Array(Set(targets.map(\.target_user_id)))
        userIds.append(contentsOf: allPlans.map(\.creator_id))
        userIds.append(contentsOf: siblingTargets.map(\.target_user_id))
        let usernames = try await usernames(for: Array(Set(userIds)))
        let df = planDateFormatter()

        return targets.compactMap { target in
            guard target.target_user_id == userId else { return nil }
            guard let plan = plansById[target.plan_id], plan.plan_date == dateStr else { return nil }
            guard target.status == "accepted" else { return nil }
            guard let planDate = df.date(from: plan.plan_date) else { return nil }
            let foodKey = target.ingredient_id ?? target.recipe_id ?? plan.ingredient_id ?? plan.recipe_id
            let name = foodKey.flatMap { names[$0] } ?? "Meal"
            let density = foodKey.flatMap { kcal[$0] } ?? 0
            let isCreator = plan.creator_id == userId
            let partnerLabel = isCreator
                ? nil
                : usernames[plan.creator_id].map { "from @\($0)" }
            let statusLabel = isCreator
                ? partnerStatusLabel(
                    viewingUserId: userId,
                    siblings: siblingsByPlan[plan.id] ?? [],
                    usernames: usernames
                )
                : nil
            return NutritionMealPlanItemUI(
                targetId: target.id,
                planId: plan.id,
                targetUserId: target.target_user_id,
                planDate: planDate,
                mealSlot: plan.meal_slot,
                foodName: name,
                quantityG: target.quantity_g,
                caloriesKcal: target.quantity_g * density,
                status: target.status,
                isCreator: isCreator,
                partnerLabel: partnerLabel,
                partnerStatusLabel: statusLabel
            )
        }
        .sorted { $0.mealSlot < $1.mealSlot }
    }

    private static func partnerStatusLabel(
        viewingUserId: UUID,
        siblings: [NutritionMealPlanTargetRow],
        usernames: [UUID: String]
    ) -> String? {
        let others = siblings.filter { $0.target_user_id != viewingUserId }
        guard !others.isEmpty else { return nil }
        return others.map { row in
            let name = usernames[row.target_user_id].map { "@\($0)" } ?? "Partner"
            return "\(name) · \(row.status.capitalized)"
        }.joined(separator: " · ")
    }

    private static func fetchTargetsForPlans(ids: [UUID]) async throws -> [NutritionMealPlanTargetRow] {
        guard !ids.isEmpty else { return [] }
        let res = try await SupabaseManager.shared.client
            .from("nutrition_meal_plan_targets")
            .select(mealPlanTargetSelect)
            .in("plan_id", values: ids.map(\.uuidString))
            .execute()
        return try JSONDecoder.supabase().decode([NutritionMealPlanTargetRow].self, from: res.data)
    }

    private static func fetchPlans(ids: [UUID]) async throws -> [NutritionMealPlanRow] {
        guard !ids.isEmpty else { return [] }
        let res = try await SupabaseManager.shared.client
            .from("nutrition_meal_plans")
            .select("id,creator_id,plan_date,meal_slot,recipe_id,ingredient_id")
            .in("id", values: ids.map(\.uuidString))
            .execute()
        return try JSONDecoder.supabase().decode([NutritionMealPlanRow].self, from: res.data)
    }

    private static func foodNames(
        forPlans plans: [NutritionMealPlanRow],
        targets: [NutritionMealPlanTargetRow]
    ) async throws -> [UUID: String] {
        var map: [UUID: String] = [:]
        let ingredientIds = Array(Set(
            plans.compactMap(\.ingredient_id) + targets.compactMap(\.ingredient_id)
        ))
        let recipeIds = Array(Set(
            plans.compactMap(\.recipe_id) + targets.compactMap(\.recipe_id)
        ))
        if !ingredientIds.isEmpty {
            let res = try await SupabaseManager.shared.client
                .from("nutrition_ingredients")
                .select("id,name")
                .in("id", values: ingredientIds.map(\.uuidString))
                .execute()
            struct Row: Decodable { let id: UUID; let name: String }
            let rows = try JSONDecoder.supabase().decode([Row].self, from: res.data)
            for row in rows { map[row.id] = row.name }
        }
        if !recipeIds.isEmpty {
            let res = try await SupabaseManager.shared.client
                .from("nutrition_recipes")
                .select("id,name")
                .in("id", values: recipeIds.map(\.uuidString))
                .execute()
            struct Row: Decodable { let id: UUID; let name: String }
            let rows = try JSONDecoder.supabase().decode([Row].self, from: res.data)
            for row in rows { map[row.id] = row.name }
        }
        return map
    }

    private static func foodKcalPerGram(
        forPlans plans: [NutritionMealPlanRow],
        targets: [NutritionMealPlanTargetRow]
    ) async throws -> [UUID: Double] {
        var map: [UUID: Double] = [:]
        let ingredientIds = Array(Set(
            plans.compactMap(\.ingredient_id) + targets.compactMap(\.ingredient_id)
        ))
        let recipeIds = Array(Set(
            plans.compactMap(\.recipe_id) + targets.compactMap(\.recipe_id)
        ))
        for ingredientId in ingredientIds where map[ingredientId] == nil {
            let res = try await SupabaseManager.shared.client
                .from("nutrition_ingredients")
                .select(ingredientSelectColumns)
                .eq("id", value: ingredientId.uuidString)
                .limit(1)
                .execute()
            let rows = try JSONDecoder.supabase().decode([NutritionIngredientRow].self, from: res.data)
            if let ing = rows.first {
                map[ingredientId] = ing.calories_per_100g / 100.0
            }
        }
        for recipeId in recipeIds where map[recipeId] == nil {
            let lines = try await fetchRecipeLines(recipeId: recipeId)
            let profile = rollupProfilePer100g(lines: lines)
            map[recipeId] = profile.calories / 100.0
        }
        return map
    }

    private static func usernames(for userIds: [UUID]) async throws -> [UUID: String] {
        guard !userIds.isEmpty else { return [:] }
        let res = try await SupabaseManager.shared.client
            .from("profiles")
            .select("user_id,username")
            .in("user_id", values: userIds.map(\.uuidString))
            .execute()
        let rows = try JSONDecoder.supabase().decode([LightweightProfile].self, from: res.data)
        var map: [UUID: String] = [:]
        for row in rows {
            if let name = row.username, !name.isEmpty {
                map[row.user_id] = name
            }
        }
        return map
    }

    private static func planDateFormatter() -> DateFormatter {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone.current
        df.dateFormat = "yyyy-MM-dd"
        return df
    }
}

struct NutritionMealPlanInviteDetailView: View {
    let targetId: UUID?
    let planId: UUID?

    init(targetId: UUID) {
        self.targetId = targetId
        self.planId = nil
    }

    init(planId: UUID) {
        self.targetId = nil
        self.planId = planId
    }

    @EnvironmentObject private var app: AppState
    @State private var invite: NutritionMealPlanInviteUI?
    @State private var loading = true
    @State private var acting = false
    @State private var error: String?

    var body: some View {
        Group {
            if loading {
                ProgressView("Loading invitation…")
            } else if let invite {
                VStack(alignment: .leading, spacing: 16) {
                    SectionCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(invite.mealSlot, systemImage: "fork.knife")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(invite.foodName)
                                .font(.title2.weight(.bold))
                            Text(formattedDate(invite.planDate))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("\(Int(invite.quantityG.rounded())) g · \(Int(invite.caloriesKcal.rounded())) kcal")
                                .font(.subheadline.weight(.medium))
                            if let creator = invite.creatorUsername {
                                HStack(spacing: 8) {
                                    Image(systemName: "person.crop.circle")
                                        .foregroundStyle(.secondary)
                                    Text("Planned by @\(creator)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let error {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                    HStack {
                        Button("Decline") {
                            Task { await reject() }
                        }
                        .buttonStyle(.bordered)
                        .disabled(acting)
                        Button("Accept") {
                            Task { await accept() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(acting)
                    }
                }
                .padding()
            } else {
                Text(error ?? "Invitation not found.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Meal invitation")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func formattedDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        return df.string(from: date)
    }

    private func load() async {
        loading = true
        defer { loading = false }
        guard let userId = app.userId else {
            error = "Sign in required."
            return
        }
        do {
            if let targetId {
                invite = try await NutritionManager.fetchInvite(targetId: targetId, userId: userId)
            } else if let planId {
                invite = try await NutritionManager.fetchInvite(planId: planId, userId: userId)
            }
            if invite == nil { error = "Invitation not found." }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private var resolvedTargetId: UUID? {
        invite?.targetId ?? targetId
    }

    private func accept() async {
        guard let targetId = resolvedTargetId else { return }
        acting = true
        defer { acting = false }
        do {
            try await NutritionManager.acceptMealPlan(targetId: targetId)
            if let userId = app.userId {
                if let planId {
                    invite = try await NutritionManager.fetchInvite(planId: planId, userId: userId)
                } else {
                    invite = try await NutritionManager.fetchInvite(targetId: targetId, userId: userId)
                }
            }
        } catch {
            self.error = NutritionManager.mealPlanErrorMessage(error)
        }
    }

    private func reject() async {
        guard let targetId = resolvedTargetId else { return }
        acting = true
        defer { acting = false }
        do {
            try await NutritionManager.rejectMealPlan(targetId: targetId)
            invite = nil
        } catch {
            self.error = NutritionManager.mealPlanErrorMessage(error)
        }
    }
}

struct MealPlanParticipantsPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var loading = false
    @State private var results: [LightweightProfile] = []
    @State private var followees: [LightweightProfile] = []
    let alreadySelected: Set<LightweightProfile>
    let onPick: ([LightweightProfile]) -> Void

    @State private var tempSelected: Set<LightweightProfile> = []

    var body: some View {
        NavigationStack {
            List {
                if results.isEmpty && !query.isEmpty && !loading {
                    Text("No users found")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(results, id: \.id) { profile in
                        let isOn = Binding<Bool>(
                            get: { tempSelected.contains(profile) || alreadySelected.contains(profile) },
                            set: { newVal in
                                if newVal { tempSelected.insert(profile) }
                                else { tempSelected.remove(profile) }
                            }
                        )
                        HStack(spacing: 10) {
                            AvatarView(urlString: profile.avatar_url)
                                .frame(width: 36, height: 36)
                            Text(profile.username ?? "Unknown")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                            Toggle("", isOn: isOn).labelsHidden()
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onPick(Array(tempSelected))
                        dismiss()
                    }
                    .disabled(tempSelected.isEmpty)
                }
            }
            .overlay {
                if loading {
                    ProgressView("Searching…")
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .scrollContentBackground(.hidden)
            .listRowBackground(Color.clear)
            .task { await loadFollowees() }
            .onChange(of: query) { _, new in
                Task { await searchUsers(new) }
            }
        }
    }

    private func loadFollowees() async {
        await MainActor.run { loading = true }
        defer { Task { await MainActor.run { loading = false } } }
        guard let userId = try? await SupabaseManager.shared.client.auth.session.user.id else { return }
        do {
            followees = try await NutritionManager.fetchFollowingProfiles(userId: userId)
            await MainActor.run {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    results = followees
                }
            }
        } catch {
            await MainActor.run {
                followees = []
                results = []
            }
        }
    }

    private func searchUsers(_ q: String) async {
        let trimmed = q.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            await MainActor.run { results = followees; loading = false }
            return
        }
        await MainActor.run { loading = true }
        defer { Task { await MainActor.run { loading = false } } }
        let filtered = followees.filter {
            ($0.username ?? "").localizedCaseInsensitiveContains(trimmed)
        }
        await MainActor.run { results = filtered }
    }
}
