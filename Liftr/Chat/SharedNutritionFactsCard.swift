import SwiftUI

struct SharedNutritionProfile: Hashable {
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var saturatedFat: Double
    var sugars: Double
    var fiber: Double
    var sodiumMg: Double
}

struct SharedNutritionFactsCard: View {
    let profile: SharedNutritionProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Nutrition Facts")
                .font(.headline.weight(.heavy))
            Text("Per 100g")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)

            HStack(alignment: .firstTextBaseline) {
                Text("Calories")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int(profile.calories.rounded()))")
                    .font(.title2.weight(.heavy))
            }
            .padding(.vertical, 6)

            Rectangle().fill(Color.primary.opacity(0.25)).frame(height: 4)
            factRow("Protein", value: profile.protein, unit: "g")
            factRow("Carbs", value: profile.carbs, unit: "g")
            factRow("Fat", value: profile.fat, unit: "g")

            Rectangle().fill(Color.primary.opacity(0.15)).frame(height: 2)
                .padding(.vertical, 4)

            factRow("Sat. fat", value: profile.saturatedFat, unit: "g", indent: true)
            factRow("Sugars", value: profile.sugars, unit: "g", indent: true)
            factRow("Fiber", value: profile.fiber, unit: "g", indent: true)
            factRow("Sodium", value: profile.sodiumMg, unit: "mg", indent: true)
        }
        .padding(14)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
        )
    }

    private func factRow(_ label: String, value: Double, unit: String, indent: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.caption.weight(indent ? .regular : .semibold))
                .padding(.leading, indent ? 8 : 0)
            Spacer()
            Text(String(format: "%.1f %@", value, unit))
                .font(.caption.monospacedDigit())
        }
        .padding(.vertical, 3)
    }
}

