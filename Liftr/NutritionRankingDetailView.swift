import SwiftUI

enum NutritionInsightsRoute: Hashable {
    case hub
    case ranking(NutritionRankingKind)
}

enum NutritionRankingKind: String, Hashable, Identifiable {
    case highestCalorieDays
    case highestCalorieMeals
    case mostLoggedIngredients
    case mostLoggedRecipes
    case heaviestMeals

    var id: String { rawValue }

    var rpcType: String {
        switch self {
        case .highestCalorieDays: return "highest_calorie_days"
        case .highestCalorieMeals: return "highest_calorie_meals"
        case .mostLoggedIngredients: return "most_logged_ingredients"
        case .mostLoggedRecipes: return "most_logged_recipes"
        case .heaviestMeals: return "heaviest_meals"
        }
    }

    var screenTitle: String {
        switch self {
        case .highestCalorieDays: return "Top Calorie Days"
        case .highestCalorieMeals: return "Top Calorie Meals"
        case .mostLoggedIngredients: return "Most Logged Ingredients"
        case .mostLoggedRecipes: return "Most Logged Recipes"
        case .heaviestMeals: return "Heaviest Meals"
        }
    }
}

struct NutritionRankingConfig {
    let kind: NutritionRankingKind

    var rankingType: String { kind.rpcType }
    var title: String { kind.screenTitle }
}

struct NutritionRankingDetailView: View {
    @ObservedObject var vm: NutritionViewModel
    let config: NutritionRankingConfig

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if vm.rankingLoading && vm.rankingRows.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else if let error = vm.rankingError, vm.rankingRows.isEmpty {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .rankingCard()
                        .padding(.horizontal)
                } else if vm.rankingRows.isEmpty {
                    Text("No entries yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .rankingCard()
                        .padding(.horizontal)
                } else {
                    ForEach(Array(vm.rankingRows.enumerated()), id: \.element.id) { index, row in
                        rankingRow(row)
                            .onAppear {
                                guard index >= vm.rankingRows.count - 2 else { return }
                                Task { await vm.loadMoreRanking(kind: config.kind) }
                            }
                        if index < vm.rankingRows.count - 1 {
                            Divider()
                                .padding(.leading, 56)
                        }
                    }
                    if vm.rankingLoadingMore {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                }
            }
            .padding(.vertical, 10)
        }
        .scrollContentBackground(.hidden)
        .gradientBG()
        .navigationTitle(config.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: config.kind) {
            await vm.loadRanking(kind: config.kind)
        }
    }

    private func rankingRow(_ row: NutritionRankingRow) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text("\(row.rank_position)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
            VStack(alignment: .leading, spacing: 4) {
                Text(displayTitle(row))
                    .font(.subheadline.weight(.semibold))
                if let subtitle = row.subtitle, !subtitle.isEmpty {
                    Text(displaySubtitle(row, subtitle: subtitle))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Text(formatValue(row))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.orange)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func displayTitle(_ row: NutritionRankingRow) -> String {
        if config.kind == .highestCalorieDays {
            return formatDisplayDate(row.title)
        }
        return row.title
    }

    private func displaySubtitle(_ row: NutritionRankingRow, subtitle: String) -> String {
        if config.kind == .highestCalorieMeals || config.kind == .heaviestMeals {
            return formatDisplayDate(subtitle)
        }
        return subtitle
    }

    private func formatValue(_ row: NutritionRankingRow) -> String {
        switch row.unit_label {
        case "kcal":
            return "\(Int(row.value_numeric.rounded())) kcal"
        case "g":
            if row.value_numeric >= 1000 {
                return String(format: "%.1f kg", row.value_numeric / 1000)
            }
            return "\(Int(row.value_numeric.rounded())) g"
        case "times":
            let count = Int(row.value_numeric.rounded())
            return count == 1 ? "1 time" : "\(count) times"
        default:
            return "\(Int(row.value_numeric.rounded())) \(row.unit_label)"
        }
    }

    private func formatDisplayDate(_ iso: String) -> String {
        let inFmt = DateFormatter()
        inFmt.locale = Locale(identifier: "en_US_POSIX")
        inFmt.timeZone = TimeZone.current
        inFmt.dateFormat = "yyyy-MM-dd"
        guard let date = inFmt.date(from: iso) else { return iso }
        let outFmt = DateFormatter()
        outFmt.dateStyle = .medium
        outFmt.timeStyle = .none
        return outFmt.string(from: date)
    }
}

private extension View {
    func rankingCard() -> some View {
        background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
            )
    }
}
