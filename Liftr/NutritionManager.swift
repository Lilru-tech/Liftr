import Foundation

enum NutritionMealSlot: String, CaseIterable, Identifiable {
    case breakfast = "Breakfast"
    case lunch = "Lunch"
    case dinner = "Dinner"
    case snack = "Snack"

    var id: String { rawValue }
}

enum NutritionListScope: String, CaseIterable, Identifiable {
    case all = "All"
    case mine = "Mine"
    case favorites = "Favorites"

    var id: String { rawValue }
}

struct NutritionDiaryLogRow: Decodable, Identifiable {
    let id: UUID
    let user_id: UUID
    let log_date: String
    let meal_slot: String
    let ingredient_id: UUID?
    let recipe_id: UUID?
    let quantity_g: Double
}

struct NutritionProfilePer100g: Hashable {
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var saturatedFat: Double
    var sugars: Double
    var fiber: Double
    var sodiumMg: Double

    static let zero = NutritionProfilePer100g(
        calories: 0, protein: 0, carbs: 0, fat: 0,
        saturatedFat: 0, sugars: 0, fiber: 0, sodiumMg: 0
    )
}

enum NutritionDisplayTargets {
    static let caloriesKcal = 2000.0
    static let proteinG = 150.0
    static let carbsG = 250.0
    static let fatG = 70.0
    static let saturatedFatG = 20.0
    static let sugarsG = 50.0
    static let fiberG = 28.0
    static let sodiumMg = 2300.0
}

struct NutritionIngredientRow: Decodable, Identifiable, Hashable {
    let id: UUID
    let user_id: UUID?
    let name: String
    let calories_per_100g: Double
    let protein_per_100g: Double
    let carbs_per_100g: Double
    let fat_per_100g: Double
    let saturated_fat_per_100g: Double
    let sugars_per_100g: Double
    let fiber_per_100g: Double
    let sodium_mg_per_100g: Double
    let is_public: Bool

    enum CodingKeys: String, CodingKey {
        case id, user_id, name
        case calories_per_100g, protein_per_100g, carbs_per_100g, fat_per_100g
        case saturated_fat_per_100g, sugars_per_100g, fiber_per_100g, sodium_mg_per_100g
        case is_public
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        user_id = try c.decodeIfPresent(UUID.self, forKey: .user_id)
        name = try c.decode(String.self, forKey: .name)
        calories_per_100g = try c.decode(Double.self, forKey: .calories_per_100g)
        protein_per_100g = try c.decode(Double.self, forKey: .protein_per_100g)
        carbs_per_100g = try c.decode(Double.self, forKey: .carbs_per_100g)
        fat_per_100g = try c.decode(Double.self, forKey: .fat_per_100g)
        saturated_fat_per_100g = try c.decodeIfPresent(Double.self, forKey: .saturated_fat_per_100g) ?? 0
        sugars_per_100g = try c.decodeIfPresent(Double.self, forKey: .sugars_per_100g) ?? 0
        fiber_per_100g = try c.decodeIfPresent(Double.self, forKey: .fiber_per_100g) ?? 0
        sodium_mg_per_100g = try c.decodeIfPresent(Double.self, forKey: .sodium_mg_per_100g) ?? 0
        is_public = try c.decode(Bool.self, forKey: .is_public)
    }

    var profilePer100g: NutritionProfilePer100g {
        NutritionProfilePer100g(
            calories: calories_per_100g,
            protein: protein_per_100g,
            carbs: carbs_per_100g,
            fat: fat_per_100g,
            saturatedFat: saturated_fat_per_100g,
            sugars: sugars_per_100g,
            fiber: fiber_per_100g,
            sodiumMg: sodium_mg_per_100g
        )
    }
}

struct NutritionRecipeRow: Decodable, Identifiable {
    let id: UUID
    let user_id: UUID?
    let name: String
    let description: String?
    let created_at: Date?

    enum CodingKeys: String, CodingKey {
        case id, user_id, name, description, created_at
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        user_id = try c.decodeIfPresent(UUID.self, forKey: .user_id)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        created_at = try c.decodeIfPresent(Date.self, forKey: .created_at)
    }
}

struct NutritionRecipeIngredientRow: Decodable {
    let id: UUID
    let recipe_id: UUID
    let ingredient_id: UUID
    let weight_g: Double
}

struct DailyNutritionRecommendation: Decodable {
    let base_calories_target: Double
    let total_calories_consumed: Double
    let total_calories_burned_active: Double
    let remaining_calories: Double
    let net_calories_balance: Double
    let total_protein_g_consumed: Double
    let total_carbs_g_consumed: Double
    let total_fat_g_consumed: Double
    let total_saturated_fat_g_consumed: Double
    let total_sugars_g_consumed: Double
    let total_fiber_g_consumed: Double
    let total_sodium_mg_consumed: Double
    let recommendation_text: String

    var calorieRingTarget: Double {
        base_calories_target > 0 ? base_calories_target : NutritionDisplayTargets.caloriesKcal
    }

    var displayRemainingCalories: Double {
        remaining_calories
    }

    enum CodingKeys: String, CodingKey {
        case base_calories_target
        case total_calories_consumed, total_calories_burned_active
        case remaining_calories, net_calories_balance
        case total_protein_g_consumed, total_carbs_g_consumed, total_fat_g_consumed
        case total_saturated_fat_g_consumed, total_sugars_g_consumed, total_fiber_g_consumed
        case total_sodium_mg_consumed, recommendation_text
    }

    private static func metabolicRemaining(base: Double, burned: Double, consumed: Double) -> Double {
        base + burned - consumed
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        base_calories_target = Self.decodeFlexibleDouble(c, key: .base_calories_target) ?? NutritionDisplayTargets.caloriesKcal
        total_calories_consumed = Self.decodeFlexibleDouble(c, key: .total_calories_consumed) ?? 0
        total_calories_burned_active = Self.decodeFlexibleDouble(c, key: .total_calories_burned_active) ?? 0
        let metabolic = Self.metabolicRemaining(
            base: base_calories_target,
            burned: total_calories_burned_active,
            consumed: total_calories_consumed
        )
        let remainingFromServer = Self.decodeFlexibleDouble(c, key: .remaining_calories)
        let netFromServer = Self.decodeFlexibleDouble(c, key: .net_calories_balance)
        if let remainingFromServer {
            remaining_calories = remainingFromServer
            net_calories_balance = netFromServer ?? remainingFromServer
        } else {
            remaining_calories = metabolic
            net_calories_balance = netFromServer ?? metabolic
        }
        total_protein_g_consumed = Self.decodeFlexibleDouble(c, key: .total_protein_g_consumed) ?? 0
        total_carbs_g_consumed = Self.decodeFlexibleDouble(c, key: .total_carbs_g_consumed) ?? 0
        total_fat_g_consumed = Self.decodeFlexibleDouble(c, key: .total_fat_g_consumed) ?? 0
        total_saturated_fat_g_consumed = Self.decodeFlexibleDouble(c, key: .total_saturated_fat_g_consumed) ?? 0
        total_sugars_g_consumed = Self.decodeFlexibleDouble(c, key: .total_sugars_g_consumed) ?? 0
        total_fiber_g_consumed = Self.decodeFlexibleDouble(c, key: .total_fiber_g_consumed) ?? 0
        total_sodium_mg_consumed = Self.decodeFlexibleDouble(c, key: .total_sodium_mg_consumed) ?? 0
        recommendation_text = (try? c.decode(String.self, forKey: .recommendation_text)) ?? ""
    }

    private static func decodeFlexibleDouble(_ c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> Double? {
        if let v = try? c.decode(Double.self, forKey: key) { return v }
        if let v = try? c.decode(Int.self, forKey: key) { return Double(v) }
        if let s = try? c.decode(String.self, forKey: key), let v = Double(s.replacingOccurrences(of: ",", with: ".")) { return v }
        return nil
    }

    init(
        base_calories_target: Double,
        total_calories_consumed: Double,
        total_calories_burned_active: Double,
        remaining_calories: Double,
        net_calories_balance: Double,
        total_protein_g_consumed: Double,
        total_carbs_g_consumed: Double,
        total_fat_g_consumed: Double,
        total_saturated_fat_g_consumed: Double,
        total_sugars_g_consumed: Double,
        total_fiber_g_consumed: Double,
        total_sodium_mg_consumed: Double,
        recommendation_text: String
    ) {
        self.base_calories_target = base_calories_target
        self.total_calories_consumed = total_calories_consumed
        self.total_calories_burned_active = total_calories_burned_active
        self.remaining_calories = remaining_calories
        self.net_calories_balance = net_calories_balance
        self.total_protein_g_consumed = total_protein_g_consumed
        self.total_carbs_g_consumed = total_carbs_g_consumed
        self.total_fat_g_consumed = total_fat_g_consumed
        self.total_saturated_fat_g_consumed = total_saturated_fat_g_consumed
        self.total_sugars_g_consumed = total_sugars_g_consumed
        self.total_fiber_g_consumed = total_fiber_g_consumed
        self.total_sodium_mg_consumed = total_sodium_mg_consumed
        self.recommendation_text = recommendation_text
    }
}

struct NutritionDiaryItemUI: Identifiable {
    let id: UUID
    let mealSlot: String
    let name: String
    let quantityG: Double
    let caloriesKcal: Double
    let isRecipe: Bool
}

struct SmartNutritionRecommendation: Decodable {
    let recommendation_text: String
    let alerts: [String]
    let avg_daily_consumed_kcal: Double
    let avg_daily_burned_kcal: Double
    let base_calories_target: Double?
    let avg_daily_energy_out: Double?
    let avg_daily_remaining_budget: Double?

    var displayBaseTarget: Double {
        let b = base_calories_target ?? 0
        return b > 0 ? b : NutritionDisplayTargets.caloriesKcal
    }

    var displayEnergyOut: Double {
        if let e = avg_daily_energy_out { return e }
        return displayBaseTarget + avg_daily_burned_kcal
    }

    var displayRemainingBudget: Double {
        if let r = avg_daily_remaining_budget { return r }
        return displayEnergyOut - avg_daily_consumed_kcal
    }

    enum CodingKeys: String, CodingKey {
        case recommendation_text, alerts
        case avg_daily_consumed_kcal, avg_daily_burned_kcal
        case base_calories_target, avg_daily_energy_out, avg_daily_remaining_budget
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        recommendation_text = try c.decode(String.self, forKey: .recommendation_text)
        alerts = try c.decodeIfPresent([String].self, forKey: .alerts) ?? []
        avg_daily_consumed_kcal = try c.decode(Double.self, forKey: .avg_daily_consumed_kcal)
        avg_daily_burned_kcal = try c.decode(Double.self, forKey: .avg_daily_burned_kcal)
        base_calories_target = try c.decodeIfPresent(Double.self, forKey: .base_calories_target)
        avg_daily_energy_out = try c.decodeIfPresent(Double.self, forKey: .avg_daily_energy_out)
        avg_daily_remaining_budget = try c.decodeIfPresent(Double.self, forKey: .avg_daily_remaining_budget)
    }
}

private struct NutritionRecommendationParams: Encodable {
    let p_date: String
}

private struct NutritionMonthBalanceParams: Encodable {
    let p_month: String
}

struct NutritionMonthDayBalance: Equatable {
    let mealLogCount: Int
    let remainingCalories: Double
}

private struct SmartNutritionRecommendationParams: Encodable {
    let p_start_date: String
    let p_end_date: String
}

private struct NutritionDiaryInsert: Encodable {
    let user_id: UUID
    let log_date: String
    let meal_slot: String
    let ingredient_id: UUID?
    let recipe_id: UUID?
    let quantity_g: Double
}

private struct NutritionDiaryUpdate: Encodable {
    let meal_slot: String
    let quantity_g: Double
}

private struct NutritionIngredientInsert: Encodable {
    let user_id: UUID
    let name: String
    let calories_per_100g: Double
    let protein_per_100g: Double
    let carbs_per_100g: Double
    let fat_per_100g: Double
    let saturated_fat_per_100g: Double
    let sugars_per_100g: Double
    let fiber_per_100g: Double
    let sodium_mg_per_100g: Double
    let is_public: Bool
}

private struct NutritionRecipeInsert: Encodable {
    let user_id: UUID
    let name: String
    let description: String?
}

private struct NutritionRecipeIngredientInsert: Encodable {
    let recipe_id: UUID
    let ingredient_id: UUID
    let weight_g: Double
}

private struct NutritionMonthLogRow: Decodable {
    let log_date: String
    let entry_count: Int
}

struct NutritionRecipeLineDraft: Identifiable, Hashable {
    let id = UUID()
    var ingredient: NutritionIngredientRow
    var weightG: Double
}

enum NutritionManager {

    static let ingredientSelectColumns =
        "id,user_id,name,calories_per_100g,protein_per_100g,carbs_per_100g,fat_per_100g,saturated_fat_per_100g,sugars_per_100g,fiber_per_100g,sodium_mg_per_100g,is_public"

    static let recipeSelectColumns = "id,user_id,name,description,created_at"

    static let ingredientPageSize = 50

    static func fetchFavoriteIngredientIds() async throws -> Set<UUID> {
        let res = try await SupabaseManager.shared.client
            .from("user_favorite_nutrition_ingredients")
            .select("ingredient_id")
            .execute()
        struct Row: Decodable { let ingredient_id: UUID }
        let rows = try JSONDecoder.supabase().decode([Row].self, from: res.data)
        return Set(rows.map(\.ingredient_id))
    }

    static func fetchFavoriteRecipeIds() async throws -> Set<UUID> {
        let res = try await SupabaseManager.shared.client
            .from("user_favorite_nutrition_recipes")
            .select("recipe_id")
            .execute()
        struct Row: Decodable { let recipe_id: UUID }
        let rows = try JSONDecoder.supabase().decode([Row].self, from: res.data)
        return Set(rows.map(\.recipe_id))
    }

    static func toggleFavoriteIngredient(ingredientId: UUID, isFavorite: Bool) async throws {
        let session = try await SupabaseManager.shared.client.auth.session
        if isFavorite {
            struct Row: Encodable {
                let user_id: UUID
                let ingredient_id: UUID
            }
            _ = try await SupabaseManager.shared.client
                .from("user_favorite_nutrition_ingredients")
                .upsert([Row(user_id: session.user.id, ingredient_id: ingredientId)], onConflict: "user_id,ingredient_id")
                .execute()
        } else {
            _ = try await SupabaseManager.shared.client
                .from("user_favorite_nutrition_ingredients")
                .delete()
                .eq("user_id", value: session.user.id.uuidString)
                .eq("ingredient_id", value: ingredientId.uuidString)
                .execute()
        }
    }

    static func toggleFavoriteRecipe(recipeId: UUID, isFavorite: Bool) async throws {
        let session = try await SupabaseManager.shared.client.auth.session
        if isFavorite {
            struct Row: Encodable {
                let user_id: UUID
                let recipe_id: UUID
            }
            _ = try await SupabaseManager.shared.client
                .from("user_favorite_nutrition_recipes")
                .upsert([Row(user_id: session.user.id, recipe_id: recipeId)], onConflict: "user_id,recipe_id")
                .execute()
        } else {
            _ = try await SupabaseManager.shared.client
                .from("user_favorite_nutrition_recipes")
                .delete()
                .eq("user_id", value: session.user.id.uuidString)
                .eq("recipe_id", value: recipeId.uuidString)
                .execute()
        }
    }

    static func rollupProfilePer100g(lines: [NutritionRecipeLineDraft]) -> NutritionProfilePer100g {
        var totalWeight = 0.0
        var calories = 0.0
        var protein = 0.0
        var carbs = 0.0
        var fat = 0.0
        var saturatedFat = 0.0
        var sugars = 0.0
        var fiber = 0.0
        var sodiumMg = 0.0
        for line in lines {
            let w = line.weightG
            guard w > 0 else { continue }
            let p = line.ingredient.profilePer100g
            totalWeight += w
            calories += w * p.calories / 100.0
            protein += w * p.protein / 100.0
            carbs += w * p.carbs / 100.0
            fat += w * p.fat / 100.0
            saturatedFat += w * p.saturatedFat / 100.0
            sugars += w * p.sugars / 100.0
            fiber += w * p.fiber / 100.0
            sodiumMg += w * p.sodiumMg / 100.0
        }
        guard totalWeight > 0 else { return .zero }
        let scale = 100.0 / totalWeight
        return NutritionProfilePer100g(
            calories: calories * scale,
            protein: protein * scale,
            carbs: carbs * scale,
            fat: fat * scale,
            saturatedFat: saturatedFat * scale,
            sugars: sugars * scale,
            fiber: fiber * scale,
            sodiumMg: sodiumMg * scale
        )
    }

    static func dateOnlyString(_ d: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone.current
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: d)
    }

    static func fetchSmartRecommendation(start: Date, end: Date) async throws -> SmartNutritionRecommendation {
        let params = SmartNutritionRecommendationParams(
            p_start_date: dateOnlyString(start),
            p_end_date: dateOnlyString(end)
        )
        let res = try await SupabaseManager.shared.client
            .rpc("get_smart_nutrition_recommendation_v1", params: params)
            .execute()
        let decoder = JSONDecoder.supabase()
        if let rows = try? decoder.decode([SmartNutritionRecommendation].self, from: res.data), let first = rows.first {
            return first
        }
        return try decoder.decode(SmartNutritionRecommendation.self, from: res.data)
    }

    static func fetchRecommendation(for userId: UUID, date: Date) async throws -> DailyNutritionRecommendation {
        let params = NutritionRecommendationParams(p_date: dateOnlyString(date))
        let res = try await SupabaseManager.shared.client
            .rpc("get_daily_nutrition_recommendation_v1", params: params)
            .execute()
        let decoder = JSONDecoder.supabase()
        let rec: DailyNutritionRecommendation
        if let rows = try? decoder.decode([DailyNutritionRecommendation].self, from: res.data), let first = rows.first {
            rec = first
        } else {
            rec = try decoder.decode(DailyNutritionRecommendation.self, from: res.data)
        }
        if rec.total_calories_consumed > 0,
           rec.total_protein_g_consumed < 0.01,
           rec.total_carbs_g_consumed < 0.01,
           rec.total_fat_g_consumed < 0.01 {
            return try await enrichRecommendationFromDiary(rec, userId: userId, date: date)
        }
        return rec
    }

    private static func enrichRecommendationFromDiary(
        _ rec: DailyNutritionRecommendation,
        userId: UUID,
        date: Date
    ) async throws -> DailyNutritionRecommendation {
        let items = try await fetchDiaryItems(for: userId, date: date)
        guard !items.isEmpty else { return rec }
        let dateStr = dateOnlyString(date)
        let logRes = try await SupabaseManager.shared.client
            .from("nutrition_diary_logs")
            .select("id,user_id,log_date,meal_slot,ingredient_id,recipe_id,quantity_g")
            .eq("user_id", value: userId.uuidString)
            .eq("log_date", value: dateStr)
            .execute()
        let logs = try JSONDecoder.supabase().decode([NutritionDiaryLogRow].self, from: logRes.data)
        var protein = 0.0
        var carbs = 0.0
        var fat = 0.0
        var saturatedFat = 0.0
        var sugars = 0.0
        var fiber = 0.0
        var sodiumMg = 0.0
        let ingredientIds = Array(Set(logs.compactMap(\.ingredient_id)))
        let recipeIds = Array(Set(logs.compactMap(\.recipe_id)))
        var ingredientsById: [UUID: NutritionIngredientRow] = [:]
        if !ingredientIds.isEmpty {
            let ingRes = try await SupabaseManager.shared.client
                .from("nutrition_ingredients")
                .select(ingredientSelectColumns)
                .in("id", values: ingredientIds.map(\.uuidString))
                .execute()
            let rows = try JSONDecoder.supabase().decode([NutritionIngredientRow].self, from: ingRes.data)
            ingredientsById = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        }
        var recipeDensity: [UUID: NutritionProfilePer100g] = [:]
        if !recipeIds.isEmpty {
            for recipeId in recipeIds {
                let lines = try await fetchRecipeLines(recipeId: recipeId)
                recipeDensity[recipeId] = rollupProfilePer100g(lines: lines)
            }
        }
        for log in logs {
            let q = log.quantity_g
            if let ingId = log.ingredient_id, let ing = ingredientsById[ingId] {
                let p = ing.profilePer100g
                protein += q * p.protein / 100.0
                carbs += q * p.carbs / 100.0
                fat += q * p.fat / 100.0
                saturatedFat += q * p.saturatedFat / 100.0
                sugars += q * p.sugars / 100.0
                fiber += q * p.fiber / 100.0
                sodiumMg += q * p.sodiumMg / 100.0
            } else if let recipeId = log.recipe_id, let profile = recipeDensity[recipeId] {
                protein += q * profile.protein / 100.0
                carbs += q * profile.carbs / 100.0
                fat += q * profile.fat / 100.0
                saturatedFat += q * profile.saturatedFat / 100.0
                sugars += q * profile.sugars / 100.0
                fiber += q * profile.fiber / 100.0
                sodiumMg += q * profile.sodiumMg / 100.0
            }
        }
        return DailyNutritionRecommendation(
            base_calories_target: rec.base_calories_target,
            total_calories_consumed: rec.total_calories_consumed,
            total_calories_burned_active: rec.total_calories_burned_active,
            remaining_calories: rec.remaining_calories,
            net_calories_balance: rec.net_calories_balance,
            total_protein_g_consumed: protein,
            total_carbs_g_consumed: carbs,
            total_fat_g_consumed: fat,
            total_saturated_fat_g_consumed: saturatedFat,
            total_sugars_g_consumed: sugars,
            total_fiber_g_consumed: fiber,
            total_sodium_mg_consumed: sodiumMg,
            recommendation_text: rec.recommendation_text
        )
    }

    static func fetchDiaryItems(for userId: UUID, date: Date) async throws -> [NutritionDiaryItemUI] {
        let dateStr = dateOnlyString(date)
        let res = try await SupabaseManager.shared.client
            .from("nutrition_diary_logs")
            .select("id,user_id,log_date,meal_slot,ingredient_id,recipe_id,quantity_g")
            .eq("user_id", value: userId.uuidString)
            .eq("log_date", value: dateStr)
            .order("meal_slot", ascending: true)
            .execute()

        let logs = try JSONDecoder.supabase().decode([NutritionDiaryLogRow].self, from: res.data)
        if logs.isEmpty { return [] }

        let ingredientIds = Array(Set(logs.compactMap(\.ingredient_id)))
        let recipeIds = Array(Set(logs.compactMap(\.recipe_id)))

        var ingredientsById: [UUID: NutritionIngredientRow] = [:]
        if !ingredientIds.isEmpty {
            let ingRes = try await SupabaseManager.shared.client
                .from("nutrition_ingredients")
                .select(ingredientSelectColumns)
                .in("id", values: ingredientIds.map(\.uuidString))
                .execute()
            let rows = try JSONDecoder.supabase().decode([NutritionIngredientRow].self, from: ingRes.data)
            ingredientsById = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        }

        var recipesById: [UUID: NutritionRecipeRow] = [:]
        var recipeKcalPerGram: [UUID: Double] = [:]
        if !recipeIds.isEmpty {
            let recRes = try await SupabaseManager.shared.client
                .from("nutrition_recipes")
                .select(recipeSelectColumns)
                .in("id", values: recipeIds.map(\.uuidString))
                .execute()
            let recipes = try JSONDecoder.supabase().decode([NutritionRecipeRow].self, from: recRes.data)
            recipesById = Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, $0) })

            let joinRes = try await SupabaseManager.shared.client
                .from("nutrition_recipe_ingredients")
                .select("id,recipe_id,ingredient_id,weight_g")
                .in("recipe_id", values: recipeIds.map(\.uuidString))
                .execute()
            let joins = try JSONDecoder.supabase().decode([NutritionRecipeIngredientRow].self, from: joinRes.data)

            let joinIngredientIds = Array(Set(joins.map(\.ingredient_id)))
            if !joinIngredientIds.isEmpty {
                let missing = joinIngredientIds.filter { ingredientsById[$0] == nil }
                if !missing.isEmpty {
                    let extraRes = try await SupabaseManager.shared.client
                        .from("nutrition_ingredients")
                        .select(ingredientSelectColumns)
                        .in("id", values: missing.map(\.uuidString))
                        .execute()
                    let extra = try JSONDecoder.supabase().decode([NutritionIngredientRow].self, from: extraRes.data)
                    for row in extra { ingredientsById[row.id] = row }
                }
            }

            let joinsByRecipe = Dictionary(grouping: joins, by: \.recipe_id)
            for (recipeId, items) in joinsByRecipe {
                var totalKcal = 0.0
                var totalWeight = 0.0
                for item in items {
                    guard let ing = ingredientsById[item.ingredient_id] else { continue }
                    totalKcal += item.weight_g * ing.calories_per_100g / 100.0
                    totalWeight += item.weight_g
                }
                if totalWeight > 0 {
                    recipeKcalPerGram[recipeId] = totalKcal / totalWeight
                }
            }
        }

        return logs.map { log in
            if let ingredientId = log.ingredient_id, let ing = ingredientsById[ingredientId] {
                let kcal = log.quantity_g * ing.calories_per_100g / 100.0
                return NutritionDiaryItemUI(
                    id: log.id,
                    mealSlot: log.meal_slot,
                    name: ing.name,
                    quantityG: log.quantity_g,
                    caloriesKcal: kcal,
                    isRecipe: false
                )
            }
            if let recipeId = log.recipe_id, let recipe = recipesById[recipeId] {
                let density = recipeKcalPerGram[recipeId] ?? 0
                let kcal = log.quantity_g * density
                return NutritionDiaryItemUI(
                    id: log.id,
                    mealSlot: log.meal_slot,
                    name: recipe.name,
                    quantityG: log.quantity_g,
                    caloriesKcal: kcal,
                    isRecipe: true
                )
            }
            return NutritionDiaryItemUI(
                id: log.id,
                mealSlot: log.meal_slot,
                name: "Unknown item",
                quantityG: log.quantity_g,
                caloriesKcal: 0,
                isRecipe: false
            )
        }
    }

    private static func fetchPublicIngredients(
        trimmedQuery: String,
        limit: Int
    ) async throws -> [NutritionIngredientRow] {
        if trimmedQuery.isEmpty {
            let res = try await SupabaseManager.shared.client
                .from("nutrition_ingredients")
                .select(ingredientSelectColumns)
                .eq("is_public", value: true)
                .order("name", ascending: true)
                .limit(limit)
                .execute()
            return try JSONDecoder.supabase().decode([NutritionIngredientRow].self, from: res.data)
        }
        let res = try await SupabaseManager.shared.client
            .from("nutrition_ingredients")
            .select(ingredientSelectColumns)
            .eq("is_public", value: true)
            .ilike("name", pattern: "%\(trimmedQuery)%")
            .order("name", ascending: true)
            .limit(limit)
            .execute()
        return try JSONDecoder.supabase().decode([NutritionIngredientRow].self, from: res.data)
    }

    private static func fetchOwnIngredients(
        userId: UUID,
        trimmedQuery: String,
        limit: Int
    ) async throws -> [NutritionIngredientRow] {
        if trimmedQuery.isEmpty {
            let res = try await SupabaseManager.shared.client
                .from("nutrition_ingredients")
                .select(ingredientSelectColumns)
                .eq("user_id", value: userId.uuidString)
                .order("name", ascending: true)
                .limit(limit)
                .execute()
            return try JSONDecoder.supabase().decode([NutritionIngredientRow].self, from: res.data)
        }
        let res = try await SupabaseManager.shared.client
            .from("nutrition_ingredients")
            .select(ingredientSelectColumns)
            .eq("user_id", value: userId.uuidString)
            .ilike("name", pattern: "%\(trimmedQuery)%")
            .order("name", ascending: true)
            .limit(limit)
            .execute()
        return try JSONDecoder.supabase().decode([NutritionIngredientRow].self, from: res.data)
    }

    static func fetchIngredientsPage(
        userId: UUID,
        query: String,
        page: Int,
        scope: NutritionListScope = .all,
        favoriteIds: Set<UUID>? = nil
    ) async throws -> (rows: [NutritionIngredientRow], hasMore: Bool) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if scope == .favorites {
            let ids = favoriteIds ?? []
            if ids.isEmpty { return ([], false) }
            let from = page * ingredientPageSize
            let to = from + ingredientPageSize - 1
            var request = SupabaseManager.shared.client
                .from("nutrition_ingredients")
                .select(ingredientSelectColumns)
                .in("id", values: ids.map(\.uuidString))
                .or("is_public.eq.true,user_id.eq.\(userId.uuidString)")
            if !trimmed.isEmpty {
                request = request.ilike("name", pattern: "%\(trimmed)%")
            }
            let res = try await request
                .order("name", ascending: true)
                .range(from: from, to: to)
                .execute()
            let rows = try JSONDecoder.supabase().decode([NutritionIngredientRow].self, from: res.data)
            return (rows, rows.count == ingredientPageSize)
        }
        let from = page * ingredientPageSize
        let to = from + ingredientPageSize - 1
        var request = SupabaseManager.shared.client
            .from("nutrition_ingredients")
            .select(ingredientSelectColumns)
        switch scope {
        case .all:
            request = request.or("is_public.eq.true,user_id.eq.\(userId.uuidString)")
        case .mine:
            request = request.eq("user_id", value: userId.uuidString)
        case .favorites:
            break
        }
        if !trimmed.isEmpty {
            request = request.ilike("name", pattern: "%\(trimmed)%")
        }
        let res = try await request
            .order("name", ascending: true)
            .range(from: from, to: to)
            .execute()
        let rows = try JSONDecoder.supabase().decode([NutritionIngredientRow].self, from: res.data)
        return (rows, rows.count == ingredientPageSize)
    }

    static func searchIngredients(userId: UUID, query: String, limit: Int = 120) async throws -> [NutritionIngredientRow] {
        var page = 0
        var all: [NutritionIngredientRow] = []
        while all.count < limit {
            let (rows, hasMore) = try await fetchIngredientsPage(userId: userId, query: query, page: page)
            all.append(contentsOf: rows)
            if !hasMore || rows.isEmpty { break }
            page += 1
        }
        return Array(all.prefix(limit))
    }

    static func fetchRecipes(
        userId: UUID,
        query: String,
        limit: Int = 40,
        scope: NutritionListScope = .all,
        favoriteIds: Set<UUID>? = nil
    ) async throws -> [NutritionRecipeRow] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if scope == .favorites {
            let ids = favoriteIds ?? []
            if ids.isEmpty { return [] }
            var request = SupabaseManager.shared.client
                .from("nutrition_recipes")
                .select(recipeSelectColumns)
                .in("id", values: ids.map(\.uuidString))
            if !trimmed.isEmpty {
                request = request.ilike("name", pattern: "%\(trimmed)%")
            }
            let res = try await request
                .order("name", ascending: true)
                .limit(limit)
                .execute()
            return try JSONDecoder.supabase().decode([NutritionRecipeRow].self, from: res.data)
        }
        var request = SupabaseManager.shared.client
            .from("nutrition_recipes")
            .select(recipeSelectColumns)
        switch scope {
        case .all:
            request = request.or("user_id.is.null,user_id.eq.\(userId.uuidString)")
        case .mine:
            request = request.eq("user_id", value: userId.uuidString)
        case .favorites:
            break
        }
        if !trimmed.isEmpty {
            request = request.ilike("name", pattern: "%\(trimmed)%")
        }
        let res = try await request
            .order("name", ascending: true)
            .limit(limit)
            .execute()
        return try JSONDecoder.supabase().decode([NutritionRecipeRow].self, from: res.data)
    }

    static func fetchRecipeLines(recipeId: UUID) async throws -> [NutritionRecipeLineDraft] {
        let joinRes = try await SupabaseManager.shared.client
            .from("nutrition_recipe_ingredients")
            .select("id,recipe_id,ingredient_id,weight_g")
            .eq("recipe_id", value: recipeId.uuidString)
            .execute()
        let joins = try JSONDecoder.supabase().decode([NutritionRecipeIngredientRow].self, from: joinRes.data)
        guard !joins.isEmpty else { return [] }
        let ingredientIds = Array(Set(joins.map(\.ingredient_id)))
        let ingRes = try await SupabaseManager.shared.client
            .from("nutrition_ingredients")
            .select(ingredientSelectColumns)
            .in("id", values: ingredientIds.map(\.uuidString))
            .execute()
        let ingredients = try JSONDecoder.supabase().decode([NutritionIngredientRow].self, from: ingRes.data)
        let ingredientsById = Dictionary(uniqueKeysWithValues: ingredients.map { ($0.id, $0) })
        return joins.compactMap { join in
            guard let ingredient = ingredientsById[join.ingredient_id] else { return nil }
            return NutritionRecipeLineDraft(ingredient: ingredient, weightG: join.weight_g)
        }
    }

    static func totalRecipeWeightG(lines: [NutritionRecipeLineDraft]) -> Double {
        lines.reduce(0) { $0 + $1.weightG }
    }

    static func insertDiaryLog(
        userId: UUID,
        date: Date,
        mealSlot: NutritionMealSlot,
        ingredientId: UUID?,
        recipeId: UUID?,
        quantityG: Double
    ) async throws {
        let payload = NutritionDiaryInsert(
            user_id: userId,
            log_date: dateOnlyString(date),
            meal_slot: mealSlot.rawValue,
            ingredient_id: ingredientId,
            recipe_id: recipeId,
            quantity_g: quantityG
        )
        _ = try await SupabaseManager.shared.client
            .from("nutrition_diary_logs")
            .insert(payload)
            .execute()
    }

    static func updateDiaryLog(
        logId: UUID,
        mealSlot: NutritionMealSlot,
        quantityG: Double
    ) async throws {
        let payload = NutritionDiaryUpdate(
            meal_slot: mealSlot.rawValue,
            quantity_g: quantityG
        )
        _ = try await SupabaseManager.shared.client
            .from("nutrition_diary_logs")
            .update(payload)
            .eq("id", value: logId.uuidString)
            .execute()
    }

    static func deleteDiaryLog(logId: UUID) async throws {
        _ = try await SupabaseManager.shared.client
            .from("nutrition_diary_logs")
            .delete()
            .eq("id", value: logId.uuidString)
            .execute()
    }

    static func fetchMonthBalance(month: Date) async throws -> [Date: NutritionMonthDayBalance] {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: month)
        guard let start = cal.date(from: comps) else { return [:] }
        let params = NutritionMonthBalanceParams(p_month: dateOnlyString(start))
        let res = try await SupabaseManager.shared.client
            .rpc("get_nutrition_month_balance_v1", params: params)
            .execute()
        struct Row: Decodable {
            let log_date: String
            let meal_log_count: Int
            let remaining_calories: Double
        }
        let decoder = JSONDecoder.supabase()
        let rows: [Row]
        if let array = try? decoder.decode([Row].self, from: res.data) {
            rows = array
        } else if let single = try? decoder.decode(Row.self, from: res.data) {
            rows = [single]
        } else {
            rows = []
        }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone.current
        df.dateFormat = "yyyy-MM-dd"
        var map: [Date: NutritionMonthDayBalance] = [:]
        for row in rows {
            guard let d = df.date(from: row.log_date) else { continue }
            let key = cal.startOfDay(for: d)
            map[key] = NutritionMonthDayBalance(
                mealLogCount: row.meal_log_count,
                remainingCalories: row.remaining_calories
            )
        }
        return map
    }

    static func createIngredient(
        userId: UUID,
        name: String,
        profile: NutritionProfilePer100g
    ) async throws -> NutritionIngredientRow {
        let payload = NutritionIngredientInsert(
            user_id: userId,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            calories_per_100g: profile.calories,
            protein_per_100g: profile.protein,
            carbs_per_100g: profile.carbs,
            fat_per_100g: profile.fat,
            saturated_fat_per_100g: profile.saturatedFat,
            sugars_per_100g: profile.sugars,
            fiber_per_100g: profile.fiber,
            sodium_mg_per_100g: profile.sodiumMg,
            is_public: false
        )
        let res = try await SupabaseManager.shared.client
            .from("nutrition_ingredients")
            .insert(payload)
            .select(ingredientSelectColumns)
            .single()
            .execute()
        return try JSONDecoder.supabase().decode(NutritionIngredientRow.self, from: res.data)
    }

    static func createRecipe(
        userId: UUID,
        name: String,
        description: String?,
        lines: [NutritionRecipeLineDraft]
    ) async throws -> NutritionRecipeRow {
        guard !lines.isEmpty else {
            throw NSError(domain: "Nutrition", code: 1, userInfo: [NSLocalizedDescriptionKey: "Add at least one ingredient to the recipe."])
        }
        let trimmedDesc = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        let recipePayload = NutritionRecipeInsert(
            user_id: userId,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            description: (trimmedDesc?.isEmpty == false) ? trimmedDesc : nil
        )
        let recipeRes = try await SupabaseManager.shared.client
            .from("nutrition_recipes")
            .insert(recipePayload)
            .select(recipeSelectColumns)
            .single()
            .execute()
        let recipe = try JSONDecoder.supabase().decode(NutritionRecipeRow.self, from: recipeRes.data)
        let joinPayloads = lines.map {
            NutritionRecipeIngredientInsert(
                recipe_id: recipe.id,
                ingredient_id: $0.ingredient.id,
                weight_g: $0.weightG
            )
        }
        _ = try await SupabaseManager.shared.client
            .from("nutrition_recipe_ingredients")
            .insert(joinPayloads)
            .execute()
        return recipe
    }

    static func monthTitle(for month: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "MMMM yyyy"
        return df.string(from: month)
    }

    static func monthGridDays(for month: Date) -> [Date?] {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: month)
        guard let first = cal.date(from: comps),
              let dayRange = cal.range(of: .day, in: .month, for: first) else { return [] }
        let weekday = cal.component(.weekday, from: first)
        let leading = (weekday + 5) % 7
        var days: [Date?] = Array(repeating: nil, count: leading)
        for day in dayRange {
            if let d = cal.date(byAdding: .day, value: day - 1, to: first) {
                days.append(d)
            }
        }
        while days.count % 7 != 0 { days.append(nil) }
        return days
    }

    private static let weekStartMonday = 2

    static let weekdaySymbols: [String] = {
        let fmt = DateFormatter()
        fmt.locale = .current
        let symbols = fmt.shortWeekdaySymbols ?? ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let startIndex = (weekStartMonday - 1 + symbols.count) % symbols.count
        let head = Array(symbols[startIndex...])
        let tail = Array(symbols[..<startIndex])
        return head + tail
    }()
}
