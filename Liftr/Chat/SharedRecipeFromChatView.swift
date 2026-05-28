import SwiftUI

struct SharedRecipeFromChatView: View {
    let snapshot: SharedRecipeSnapshot

    @Environment(\.dismiss) private var dismiss
    @State private var banner: Banner?
    @State private var saving = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(snapshot.name)
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let desc = snapshot.description?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !desc.isEmpty {
                        Text(desc)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Text(macroLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(ingredientsLabel)
                        .font(.subheadline.weight(.semibold))
                    ForEach(Array(snapshot.ingredients.enumerated()), id: \.offset) { _, line in
                        HStack {
                            Text("\(Int(line.weight_g.rounded()))g")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 52, alignment: .leading)
                            Text(line.name)
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                SharedNutritionFactsCard(profile: profile)

                Button {
                    Task { await save() }
                } label: {
                    Group {
                        if saving { ProgressView() }
                        else { Text(saveButtonTitle).frame(maxWidth: .infinity) }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(saving)
            }
            .padding()
        }
        .navigationTitle(titleLabel)
        .navigationBarTitleDisplayMode(.inline)
        .gradientBG()
        .banner($banner)
    }

    private var profile: SharedNutritionProfile {
        if let p = snapshot.profile_per_100g {
            return SharedNutritionProfile(
                calories: p.calories,
                protein: p.protein,
                carbs: p.carbs,
                fat: p.fat,
                saturatedFat: p.saturatedFat,
                sugars: p.sugars,
                fiber: p.fiber,
                sodiumMg: p.sodiumMg
            )
        }
        let totalWeight = snapshot.ingredients.map(\.weight_g).reduce(0, +)
        let denom = max(totalWeight, 1)
        let calories = snapshot.ingredients.map { ($0.calories_per_100g * $0.weight_g) / 100.0 }.reduce(0, +)
        let protein = snapshot.ingredients.map { ($0.protein_per_100g * $0.weight_g) / 100.0 }.reduce(0, +)
        let carbs = snapshot.ingredients.map { ($0.carbs_per_100g * $0.weight_g) / 100.0 }.reduce(0, +)
        let fat = snapshot.ingredients.map { ($0.fat_per_100g * $0.weight_g) / 100.0 }.reduce(0, +)
        let saturatedFat = snapshot.ingredients.map { ($0.saturated_fat_per_100g * $0.weight_g) / 100.0 }.reduce(0, +)
        let sugars = snapshot.ingredients.map { ($0.sugars_per_100g * $0.weight_g) / 100.0 }.reduce(0, +)
        let fiber = snapshot.ingredients.map { ($0.fiber_per_100g * $0.weight_g) / 100.0 }.reduce(0, +)
        let sodiumMg = snapshot.ingredients.map { ($0.sodium_mg_per_100g * $0.weight_g) / 100.0 }.reduce(0, +)
        return SharedNutritionProfile(
            calories: calories * 100.0 / denom,
            protein: protein * 100.0 / denom,
            carbs: carbs * 100.0 / denom,
            fat: fat * 100.0 / denom,
            saturatedFat: saturatedFat * 100.0 / denom,
            sugars: sugars * 100.0 / denom,
            fiber: fiber * 100.0 / denom,
            sodiumMg: sodiumMg * 100.0 / denom
        )
    }

    private var macroLine: String {
        let p = profile
        let c = Int(p.calories.rounded())
        let pr = Int(p.protein.rounded())
        let ca = Int(p.carbs.rounded())
        let f = Int(p.fat.rounded())
        return "\(c) kcal · P \(pr)g · C \(ca)g · F \(f)g (per 100g)"
    }

    private var titleLabel: String {
        if AppLanguage.isSpanish {
            return "Receta"
        }
        return "Recipe"
    }

    private var ingredientsLabel: String {
        if AppLanguage.isSpanish {
            return "Ingredientes"
        }
        return "Ingredients"
    }

    private var saveButtonTitle: String {
        if AppLanguage.isSpanish {
            return "Guardar en mis recetas"
        }
        return "Save to My Recipes"
    }

    @MainActor
    private func save() async {
        if saving { return }
        saving = true
        defer { saving = false }
        do {
            _ = try await ChatService.cloneSharedRecipe(snapshot: snapshot)
            BannerAction.showSuccess(
                AppLanguage.isSpanish
                ? "Añadido a tus recetas"
                : "Saved to your recipes",
                banner: $banner
            )
        } catch {
            BannerAction.showError(error.localizedDescription, banner: $banner)
        }
    }
}

