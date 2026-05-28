import SwiftUI

struct SharedIngredientFromChatView: View {
    let snapshot: SharedIngredientSnapshot

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
                    Text(macroLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

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
        SharedNutritionProfile(
            calories: snapshot.calories_per_100g,
            protein: snapshot.protein_per_100g,
            carbs: snapshot.carbs_per_100g,
            fat: snapshot.fat_per_100g,
            saturatedFat: snapshot.saturated_fat_per_100g,
            sugars: snapshot.sugars_per_100g,
            fiber: snapshot.fiber_per_100g,
            sodiumMg: snapshot.sodium_mg_per_100g
        )
    }

    private var macroLine: String {
        let c = Int(snapshot.calories_per_100g.rounded())
        let p = Int(snapshot.protein_per_100g.rounded())
        let ca = Int(snapshot.carbs_per_100g.rounded())
        let f = Int(snapshot.fat_per_100g.rounded())
        return "\(c) kcal · P \(p)g · C \(ca)g · F \(f)g (per 100g)"
    }

    private var titleLabel: String {
        if AppLanguage.isSpanish {
            return "Ingrediente"
        }
        return "Ingredient"
    }

    private var saveButtonTitle: String {
        if AppLanguage.isSpanish {
            return "Guardar en mis ingredientes"
        }
        return "Save to My Ingredients"
    }

    @MainActor
    private func save() async {
        if saving { return }
        saving = true
        defer { saving = false }
        do {
            _ = try await ChatService.cloneSharedIngredient(snapshot: snapshot)
            BannerAction.showSuccess(
                AppLanguage.isSpanish
                ? "Añadido a tus ingredientes"
                : "Saved to your ingredients",
                banner: $banner
            )
        } catch {
            BannerAction.showError(error.localizedDescription, banner: $banner)
        }
    }
}

