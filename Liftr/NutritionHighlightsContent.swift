import SwiftUI

struct NutritionHighlightsContent: View {
    let loading: Bool
    let highlights: NutritionHighlights?
    let error: String?
    var coinsBalance: Int? = nil
    var showCoinsBalance: Bool = false
    var onOpenRanking: (NutritionRankingKind) -> Void = { _ in }

    @State private var shimmerPhase = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if loading {
                loadingContent
            } else if let error {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .highlightsCard()
            } else if let highlights {
                if highlights.hasAnyLogs {
                    loadedContent(highlights)
                } else {
                    emptyContent
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                shimmerPhase = true
            }
        }
    }

    private var loadingContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            shimmerBlock(height: 88)
            shimmerBlock(height: 120)
            shimmerBlock(height: 120)
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .padding(.top, 8)
        }
    }

    private var emptyContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("No highlights yet", systemImage: "tray")
                .font(.headline)
            Text("Log meals in your diary to unlock personal nutrition highlights.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .highlightsCard()
    }

    private func loadedContent(_ h: NutritionHighlights) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            overviewSection(h)
            recordsSection(h)
            favoritesSection(h)
            habitsSection(h)
            macroChampionsSection(h)
            weeklyHabitsSection(h)
            heaviestMealSection(h)
            consistencyStreakSection(h)
        }
    }

    private func overviewSection(_ h: NutritionHighlights) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Label("Overview", systemImage: "calendar")
                    .font(.headline)
                Spacer(minLength: 8)
                if showCoinsBalance {
                    CoinsBalanceBadge(balance: coinsBalance ?? 0, compact: true)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    statPill(title: "Days logged", value: "\(h.days_logged)")
                    statPill(title: "Entries", value: "\(h.total_log_entries)")
                    statPill(title: "Avg kcal/day", value: formatKcal(h.avg_kcal_per_logged_day))
                }
            }
            if let first = h.first_log_date, let last = h.last_log_date {
                Text("Tracking since \(formatDisplayDate(first)) · latest \(formatDisplayDate(last))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .highlightsCard()
    }

    private func recordsSection(_ h: NutritionHighlights) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Records", systemImage: "flame.fill")
                .font(.headline)
            if let peak = h.peak_day {
                navigableHighlightRow(
                    kind: .highestCalorieDays,
                    title: "Highest calorie day",
                    detail: formatDisplayDate(peak.date),
                    value: formatKcal(peak.kcal)
                )
            }
            if let meal = h.peak_meal_slot {
                navigableHighlightRow(
                    kind: .highestCalorieMeals,
                    title: "Highest calorie meal",
                    detail: "\(meal.meal_slot) · \(formatDisplayDate(meal.date))",
                    value: formatKcal(meal.kcal)
                )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .highlightsCard()
    }

    private func favoritesSection(_ h: NutritionHighlights) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Most logged", systemImage: "heart.fill")
                .font(.headline)
            if let ing = h.top_ingredient {
                navigableFoodRow(
                    kind: .mostLoggedIngredients,
                    title: "Ingredient",
                    name: ing.name,
                    count: ing.log_count,
                    kcal: ing.total_kcal
                )
            }
            if let rec = h.top_recipe {
                navigableFoodRow(
                    kind: .mostLoggedRecipes,
                    title: "Recipe",
                    name: rec.name,
                    count: rec.log_count,
                    kcal: rec.total_kcal
                )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .highlightsCard()
    }

    private func habitsSection(_ h: NutritionHighlights) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Habits", systemImage: "clock.fill")
                .font(.headline)
            if let slot = h.most_used_meal_slot {
                recordRow(
                    title: "Most used meal slot",
                    detail: slot,
                    value: nil
                )
            }
            let ingredientShare = max(0, min(100, 100 - h.recipe_log_share_percent))
            recordRow(
                title: "Log mix",
                detail: "\(formatPercent(ingredientShare)) ingredients · \(formatPercent(h.recipe_log_share_percent)) recipes",
                value: nil
            )
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .highlightsCard()
    }

    @ViewBuilder
    private func macroChampionsSection(_ h: NutritionHighlights) -> some View {
        if let macro = h.macro_champions,
           macro.top_protein_source != nil || macro.top_carb_source != nil {
            VStack(alignment: .leading, spacing: 12) {
                Label("Macro champions", systemImage: "bolt.fill")
                    .font(.headline)
                if let protein = macro.top_protein_source {
                    recordRow(
                        title: "Top protein source",
                        detail: protein.name,
                        value: formatGrams(protein.total_g)
                    )
                }
                if let carbs = macro.top_carb_source {
                    recordRow(
                        title: "Top carb source",
                        detail: carbs.name,
                        value: formatGrams(carbs.total_g)
                    )
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .highlightsCard()
        }
    }

    @ViewBuilder
    private func weeklyHabitsSection(_ h: NutritionHighlights) -> some View {
        if let vol = h.calorie_volatility,
           vol.weekday_avg_kcal > 0 || vol.weekend_avg_kcal > 0 {
            VStack(alignment: .leading, spacing: 12) {
                Label("Weekly habits", systemImage: "calendar.badge.clock")
                    .font(.headline)
                HStack(spacing: 10) {
                    statPill(title: "Weekday avg", value: formatKcal(vol.weekday_avg_kcal))
                    statPill(title: "Weekend avg", value: formatKcal(vol.weekend_avg_kcal))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .highlightsCard()
        }
    }

    @ViewBuilder
    private func heaviestMealSection(_ h: NutritionHighlights) -> some View {
        if let meal = h.heaviest_meal {
            VStack(alignment: .leading, spacing: 12) {
                Label("Heaviest meal", systemImage: "scalemass.fill")
                    .font(.headline)
                navigableHighlightRow(
                    kind: .heaviestMeals,
                    title: meal.meal_slot,
                    detail: formatDisplayDate(meal.date),
                    value: formatWeight(meal.total_weight_g)
                )
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .highlightsCard()
        }
    }

    @ViewBuilder
    private func consistencyStreakSection(_ h: NutritionHighlights) -> some View {
        if let streak = h.consistency_streak,
           streak.current_streak > 0 || streak.best_streak > 0 {
            VStack(alignment: .leading, spacing: 12) {
                Label("Consistency streak", systemImage: "flame.circle.fill")
                    .font(.headline)
                HStack(spacing: 10) {
                    statPill(title: "Current", value: streakDays(streak.current_streak))
                    statPill(title: "Best", value: streakDays(streak.best_streak))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .highlightsCard()
        }
    }

    private func statPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func recordRow(title: String, detail: String, value: String?) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.orange)
            }
        }
    }

    private func navigableHighlightRow(
        kind: NutritionRankingKind,
        title: String,
        detail: String,
        value: String?
    ) -> some View {
        Button {
            onOpenRanking(kind)
        } label: {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    if let value {
                        Text(value)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.orange)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary.opacity(0.7))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func foodRow(title: String, name: String, count: Int, kcal: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(name)
                .font(.subheadline.weight(.semibold))
            Text("\(count)× logged · \(formatKcal(kcal)) total")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func navigableFoodRow(
        kind: NutritionRankingKind,
        title: String,
        name: String,
        count: Int,
        kcal: Double
    ) -> some View {
        Button {
            onOpenRanking(kind)
        } label: {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("\(count)× logged · \(formatKcal(kcal)) total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary.opacity(0.7))
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func shimmerBlock(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.primary.opacity(shimmerPhase ? 0.14 : 0.07))
            .frame(maxWidth: .infinity)
            .frame(height: height)
    }

    private func formatKcal(_ value: Double) -> String {
        "\(Int(value.rounded())) kcal"
    }

    private func formatPercent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    private func formatGrams(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.1f kg", value / 1000)
        }
        return "\(Int(value.rounded())) g"
    }

    private func formatWeight(_ grams: Double) -> String {
        formatGrams(grams)
    }

    private func streakDays(_ count: Int) -> String {
        count == 1 ? "1 day" : "\(count) days"
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
    func highlightsCard() -> some View {
        background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
            )
    }
}
