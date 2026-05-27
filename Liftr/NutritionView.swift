import SwiftUI

private struct NutritionCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
            )
    }
}

private extension View {
    func nutritionCard() -> some View { modifier(NutritionCardModifier()) }
}

private struct NutritionFactsLabel: View {
    let title: String
    let profile: NutritionProfilePer100g

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption.weight(.bold))
                .padding(.bottom, 6)
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

struct NutritionCalorieBudgetStatusRow: View {
    let remainingKcal: Double
    var titleWhenUnder: String = "Remaining budget"
    var titleWhenOver: String = "Over budget"
    var hintWhenUnder: String = "Room left in today's energy budget"
    var hintWhenOver: String = "Above BMR + activity for today"

    private var isOver: Bool { remainingKcal < 0 }
    private var magnitude: Int { Int(abs(remainingKcal).rounded()) }
    private var accent: Color { isOver ? Color(red: 0.9, green: 0.27, blue: 0.27) : .orange }
    private var iconName: String { isOver ? "arrow.up.circle.fill" : "arrow.down.circle.fill" }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title2)
                .foregroundStyle(accent)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(isOver ? titleWhenOver : titleWhenUnder)
                    .font(.subheadline.weight(.semibold))
                Text(isOver ? hintWhenOver : hintWhenUnder)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text(isOver ? "\(magnitude) kcal over" : "\(magnitude) kcal left")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(accent)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            isOver
                ? "Over budget by \(magnitude) kilocalories"
                : "\(magnitude) kilocalories remaining in today's budget"
        )
    }
}

private struct NutritionMacroRing: View {
    let label: String
    let value: Double
    let target: Double
    let unit: String
    let color: Color

    private var progress: Double {
        guard target > 0 else { return 0 }
        return min(value / target, 1)
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.2), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(Int(value.rounded()))")
                        .font(.caption.weight(.bold))
                    Text(unit)
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 56, height: 56)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct NutritionMacroDashboard: View {
    let recommendation: DailyNutritionRecommendation

    var body: some View {
        HStack(spacing: 8) {
            NutritionMacroRing(
                label: "Cal",
                value: recommendation.total_calories_consumed,
                target: recommendation.calorieRingTarget,
                unit: "kcal",
                color: .orange
            )
            NutritionMacroRing(
                label: "Protein",
                value: recommendation.total_protein_g_consumed,
                target: NutritionDisplayTargets.proteinG,
                unit: "g",
                color: .blue
            )
            NutritionMacroRing(
                label: "Carbs",
                value: recommendation.total_carbs_g_consumed,
                target: NutritionDisplayTargets.carbsG,
                unit: "g",
                color: .green
            )
            NutritionMacroRing(
                label: "Fat",
                value: recommendation.total_fat_g_consumed,
                target: NutritionDisplayTargets.fatG,
                unit: "g",
                color: .yellow
            )
        }
    }
}

private struct NutritionMicroNutrientsSection: View {
    let recommendation: DailyNutritionRecommendation

    var body: some View {
        DisclosureGroup("More nutrients") {
            VStack(spacing: 10) {
                microBar("Saturated fat", value: recommendation.total_saturated_fat_g_consumed, target: NutritionDisplayTargets.saturatedFatG, unit: "g")
                microBar("Sugars", value: recommendation.total_sugars_g_consumed, target: NutritionDisplayTargets.sugarsG, unit: "g")
                microBar("Fiber", value: recommendation.total_fiber_g_consumed, target: NutritionDisplayTargets.fiberG, unit: "g")
                microBar("Sodium", value: recommendation.total_sodium_mg_consumed, target: NutritionDisplayTargets.sodiumMg, unit: "mg")
            }
            .padding(.top, 6)
        }
        .font(.subheadline.weight(.semibold))
    }

    private func microBar(_ label: String, value: Double, target: Double, unit: String) -> some View {
        let progress = target > 0 ? min(value / target, 1) : 0
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                Spacer()
                Text(String(format: "%.1f / %.0f %@", value, target, unit))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: progress)
                .tint(.mint)
        }
    }
}

enum NutritionSheetRoute: Identifiable {
    case addFood(mealSlot: NutritionMealSlot)
    case createIngredient
    case createRecipe
    case editLog(NutritionDiaryItemUI)

    var id: String {
        switch self {
        case .addFood(let mealSlot): return "addFood-\(mealSlot.rawValue)"
        case .createIngredient: return "createIngredient"
        case .createRecipe: return "createRecipe"
        case .editLog(let item): return "edit-\(item.id.uuidString)"
        }
    }
}

@MainActor
final class NutritionViewModel: ObservableObject {
    static let maxInsightsSpanDays = 70

    @Published var monthDate = Date()
    @Published var selectedDate = Date()
    @Published var monthDayBalance: [Date: NutritionMonthDayBalance] = [:]
    @Published var diaryItems: [NutritionDiaryItemUI] = []
    @Published var recommendation: DailyNutritionRecommendation?
    @Published var loading = false
    @Published var error: String?
    @Published var activeSheet: NutritionSheetRoute?

    @Published var insightsFromDate: Date
    @Published var insightsToDate: Date
    @Published var insightsQuickPreset: NutritionInsightsQuickPreset? = .oneWeek
    @Published var smartInsightsLoading = false
    @Published var smartInsights: SmartNutritionRecommendation?
    @Published var smartInsightsError: String?

    init() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekStart = cal.date(byAdding: .day, value: -6, to: today) ?? today
        insightsToDate = today
        insightsFromDate = weekStart
    }

    func load(userId: UUID?) async {
        guard let userId else {
            diaryItems = []
            recommendation = nil
            monthDayBalance = [:]
            error = "Sign in to track nutrition."
            return
        }
        loading = true
        error = nil
        defer { loading = false }
        do {
            async let itemsTask = NutritionManager.fetchDiaryItems(for: userId, date: selectedDate)
            async let recTask = NutritionManager.fetchRecommendation(for: userId, date: selectedDate)
            async let monthTask = NutritionManager.fetchMonthBalance(month: monthDate)
            diaryItems = try await itemsTask
            recommendation = try await recTask
            monthDayBalance = try await monthTask
        } catch {
            self.error = error.localizedDescription
        }
    }

    func groupedItems() -> [(slot: NutritionMealSlot, items: [NutritionDiaryItemUI])] {
        NutritionMealSlot.allCases.map { slot in
            (slot, diaryItems.filter { $0.mealSlot == slot.rawValue })
        }
    }

    func selectDay(_ day: Date) {
        selectedDate = day
    }

    func shiftMonth(_ delta: Int) {
        monthDate = Calendar.current.date(byAdding: .month, value: delta, to: monthDate) ?? monthDate
    }

    func clampInsightsDates() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        insightsToDate = min(cal.startOfDay(for: insightsToDate), today)
        insightsFromDate = cal.startOfDay(for: insightsFromDate)
        if insightsFromDate > insightsToDate {
            insightsFromDate = insightsToDate
        }
        if let earliest = cal.date(byAdding: .day, value: -(Self.maxInsightsSpanDays - 1), to: insightsToDate),
           insightsFromDate < earliest {
            insightsFromDate = earliest
        }
    }

    func applyInsightsQuickPreset(_ preset: NutritionInsightsQuickPreset) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        switch preset {
        case .oneDay:
            insightsFromDate = today
            insightsToDate = today
        case .oneWeek:
            insightsFromDate = cal.date(byAdding: .day, value: -6, to: today) ?? today
            insightsToDate = today
        case .oneMonth:
            insightsFromDate = cal.date(byAdding: .day, value: -29, to: today) ?? today
            insightsToDate = today
        }
        insightsQuickPreset = preset
        clampInsightsDates()
    }

    func matchesInsightsPresetDates(_ preset: NutritionInsightsQuickPreset) -> Bool {
        let cal = Calendar.current
        let f = cal.startOfDay(for: insightsFromDate)
        let t = cal.startOfDay(for: insightsToDate)
        let today = cal.startOfDay(for: Date())
        switch preset {
        case .oneDay:
            return f == today && t == today
        case .oneWeek:
            let start = cal.date(byAdding: .day, value: -6, to: today) ?? today
            return f == start && t == today
        case .oneMonth:
            let start = cal.date(byAdding: .day, value: -29, to: today) ?? today
            return f == start && t == today
        }
    }

    func analyzeSmartInsights() async {
        clampInsightsDates()
        smartInsightsLoading = true
        smartInsights = nil
        smartInsightsError = nil
        let started = Date()
        defer { smartInsightsLoading = false }
        do {
            let result = try await NutritionManager.fetchSmartRecommendation(
                start: insightsFromDate,
                end: insightsToDate
            )
            let elapsed = Date().timeIntervalSince(started)
            if elapsed < 1.0 {
                try await Task.sleep(nanoseconds: UInt64((1.0 - elapsed) * 1_000_000_000))
            }
            smartInsights = result
        } catch {
            smartInsightsError = error.localizedDescription
        }
    }

    func resetSmartInsights() {
        smartInsightsLoading = false
        smartInsights = nil
        smartInsightsError = nil
    }
}

struct NutritionView: View {
    @EnvironmentObject var app: AppState
    @StateObject private var vm = NutritionViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                NutritionMonthCalendar(
                    monthDate: $vm.monthDate,
                    selectedDate: $vm.selectedDate,
                    dayBalance: vm.monthDayBalance,
                    onMonthChange: { Task { await vm.load(userId: app.userId) } },
                    onSelectDay: { day in
                        vm.selectDay(day)
                        Task { await vm.load(userId: app.userId) }
                    }
                )

                summaryCard

                if let error = vm.error {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                dayHeader

                ForEach(vm.groupedItems(), id: \.slot.id) { section in
                    mealSection(slot: section.slot, items: section.items)
                }

                NavigationLink {
                    NutritionInsightsHubView(vm: vm)
                } label: {
                    NutritionInsightsEntryCard()
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .padding(.top, 4)
            }
            .padding(.vertical, 10)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        vm.activeSheet = .addFood(mealSlot: .lunch)
                    } label: {
                        Label("Log food", systemImage: "plus.circle")
                    }
                    Button {
                        vm.activeSheet = .createIngredient
                    } label: {
                        Label("New ingredient", systemImage: "leaf")
                    }
                    Button {
                        vm.activeSheet = .createRecipe
                    } label: {
                        Label("New recipe", systemImage: "book.closed")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .accessibilityLabel("Add nutrition")
            }
        }
        .refreshable { await vm.load(userId: app.userId) }
        .task(id: taskKey) { await vm.load(userId: app.userId) }
        .sheet(item: $vm.activeSheet) { route in
            sheetContent(for: route)
                .gradientBG()
                .presentationBackground(.clear)
                .interactiveDismissDisabled(true)
        }
    }

    private var taskKey: String {
        let uid = app.userId?.uuidString ?? ""
        let day = NutritionManager.dateOnlyString(vm.selectedDate)
        let month = NutritionManager.dateOnlyString(vm.monthDate)
        return "\(uid)-\(day)-\(month)"
    }

    @ViewBuilder
    private func sheetContent(for route: NutritionSheetRoute) -> some View {
        switch route {
        case .addFood(let mealSlot):
            NutritionLogFoodSheet(
                selectedDate: vm.selectedDate,
                userId: app.userId,
                initialMealSlot: mealSlot,
                onDone: { vm.activeSheet = nil; Task { await vm.load(userId: app.userId) } }
            )
        case .createIngredient:
            NutritionCreateIngredientSheet(
                userId: app.userId,
                onDone: { vm.activeSheet = nil; Task { await vm.load(userId: app.userId) } }
            )
        case .createRecipe:
            NutritionCreateRecipeSheet(
                userId: app.userId,
                onDone: { vm.activeSheet = nil; Task { await vm.load(userId: app.userId) } }
            )
        case .editLog(let item):
            NutritionEditDiarySheet(
                item: item,
                onDone: { vm.activeSheet = nil; Task { await vm.load(userId: app.userId) } }
            )
        }
    }

    private var dayHeader: some View {
        let df = DateFormatter()
        df.dateStyle = .full
        return Text(df.string(from: vm.selectedDate))
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Daily balance")
                .font(.headline)

            if vm.loading && vm.recommendation == nil {
                ProgressView()
            } else if let rec = vm.recommendation {
                NutritionMacroDashboard(recommendation: rec)
                HStack(spacing: 8) {
                    balanceColumn(title: "Metabolism (BMR)", value: rec.base_calories_target, color: .blue)
                    balanceColumn(title: "Activity burned", value: rec.total_calories_burned_active, color: .mint)
                    balanceColumn(title: "Consumed", value: rec.total_calories_consumed, color: .orange)
                }
                NutritionCalorieBudgetStatusRow(remainingKcal: rec.displayRemainingCalories)
                NutritionMicroNutrientsSection(recommendation: rec)
            } else {
                Text("Log meals to see your calorie balance.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .nutritionCard()
        .padding(.horizontal)
    }

    private func balanceColumn(title: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(Int(value.rounded()))")
                .font(.title2.weight(.bold))
            Text("kcal")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func mealSection(slot: NutritionMealSlot, items: [NutritionDiaryItemUI]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(slot.rawValue)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    vm.activeSheet = .addFood(mealSlot: slot)
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.weight(.bold))
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal)

            if items.isEmpty {
                Text("No items logged")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal)
            } else {
                ForEach(items) { item in
                    Button {
                        vm.activeSheet = .editLog(item)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                Text("\(Int(item.quantityG.rounded())) g · \(Int(item.caloriesKcal.rounded())) kcal")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(12)
                        .nutritionCard()
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                }
            }
        }
    }
}

private enum NutritionCalendarPalette {
    static let noLogs = Color.primary.opacity(0.35)
    static let onBudget = Color.orange
    static let overBudget = Color(red: 0.9, green: 0.27, blue: 0.27)
}

private struct NutritionCalendarLegend: View {
    var body: some View {
        HStack(spacing: 8) {
            legendItem("No logs", color: NutritionCalendarPalette.noLogs)
            legendItem("On budget", color: NutritionCalendarPalette.onBudget)
            legendItem("Over budget", color: NutritionCalendarPalette.overBudget)
        }
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    private func legendItem(_ title: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(title)
        }
    }
}

private struct NutritionMonthCalendar: View {
    @Binding var monthDate: Date
    @Binding var selectedDate: Date
    let dayBalance: [Date: NutritionMonthDayBalance]
    let onMonthChange: () -> Void
    let onSelectDay: (Date) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button { shift(-1) } label: {
                    Image(systemName: "chevron.left").frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Previous month")

                Spacer(minLength: 4)

                VStack(spacing: 3) {
                    Text(NutritionManager.monthTitle(for: monthDate))
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    NutritionCalendarLegend()
                }

                Spacer(minLength: 4)

                Button("Today") {
                    let today = Calendar.current.startOfDay(for: Date())
                    monthDate = today
                    selectedDate = today
                    onSelectDay(today)
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                Button { shift(1) } label: {
                    Image(systemName: "chevron.right").frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Next month")
            }
            LazyVGrid(columns: columns, spacing: 5) {
                ForEach(Array(NutritionManager.weekdaySymbols.enumerated()), id: \.offset) { _, w in
                    Text(w)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                ForEach(NutritionManager.monthGridDays(for: monthDate).indices, id: \.self) { idx in
                    let day = NutritionManager.monthGridDays(for: monthDate)[idx]
                    dayCell(day)
                }
            }
        }
        .nutritionCard()
        .padding(.horizontal)
    }

    private func shift(_ delta: Int) {
        monthDate = Calendar.current.date(byAdding: .month, value: delta, to: monthDate) ?? monthDate
        onMonthChange()
    }

    @ViewBuilder
    private func dayCell(_ day: Date?) -> some View {
        let cal = Calendar.current
        if let day {
            let key = cal.startOfDay(for: day)
            let summary = dayBalance[key]
            let count = summary?.mealLogCount ?? 0
            let selected = cal.isDate(day, inSameDayAs: selectedDate)
            let today = cal.isDateInToday(day)
            let fillColor: Color = {
                guard count > 0, let remaining = summary?.remainingCalories else {
                    return Color.primary.opacity(selected ? 0.12 : 0.05)
                }
                let accent = remaining < 0 ? NutritionCalendarPalette.overBudget : NutritionCalendarPalette.onBudget
                return accent.opacity(selected ? 0.55 : 0.32)
            }()
            Button {
                selectedDate = day
                onSelectDay(day)
            } label: {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(fillColor)
                    Text("\(cal.component(.day, from: day))")
                        .font(.footnote.weight(selected ? .bold : .semibold))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if count > 1 {
                        Text("\(count)")
                            .font(.system(size: 9, weight: .bold))
                            .padding(4)
                            .background(Capsule().fill(.ultraThinMaterial))
                    }
                }
                .frame(height: 34)
                .overlay {
                    if selected {
                        RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.7), lineWidth: 2)
                    } else if today {
                        RoundedRectangle(cornerRadius: 10).strokeBorder(Color.mint.opacity(0.8), lineWidth: 1.5)
                    }
                }
            }
            .buttonStyle(.plain)
        } else {
            Color.clear.frame(height: 34)
        }
    }
}

private struct NutritionRecipeLineEditor: View {
    let name: String
    let weightG: Double
    let onWeightChange: (Double) -> Void
    let onDelete: () -> Void

    @State private var weightText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
            }
            HStack(spacing: 12) {
                Button { applyWeight(weightG - 5) } label: {
                    Image(systemName: "minus.circle.fill").font(.title3)
                }
                TextField("g", text: $weightText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.body.weight(.bold))
                    .frame(width: 88)
                    .onChange(of: weightText) { _, newValue in
                        let filtered = newValue.filter { $0.isNumber }
                        if filtered != newValue { weightText = filtered }
                        guard let v = Double(filtered), v > 0 else { return }
                        applyWeight(v)
                    }
                Button { applyWeight(weightG + 5) } label: {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
            }
            .frame(maxWidth: .infinity)
            .onAppear { syncText() }
            .onChange(of: weightG) { _, _ in syncText() }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach([5.0, 10.0, 50.0, 100.0, 150.0, 200.0, 250.0], id: \.self) { preset in
                        Button {
                            applyWeight(preset)
                        } label: {
                            Text("\(Int(preset)) g")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    weightG == preset ? Color.orange.opacity(0.25) : Color.primary.opacity(0.06),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
        .nutritionCard()
    }

    private func syncText() {
        let t = "\(Int(weightG.rounded()))"
        if weightText != t { weightText = t }
    }

    private func applyWeight(_ value: Double) {
        onWeightChange(min(2000, max(5, value)))
        syncText()
    }
}

private struct NutritionGramsInput: View {
    @Binding var grams: Double
    var kcalPreview: Double?

    private let presets: [Double] = [50, 100, 150, 200, 250]
    @State private var gramsText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Portion")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let kcalPreview {
                    Text("\(Int(kcalPreview.rounded())) kcal")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
            HStack(spacing: 12) {
                Button { applyGrams(grams - 5) } label: {
                    Image(systemName: "minus.circle.fill").font(.title2)
                }
                TextField("g", text: $gramsText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.title3.weight(.bold))
                    .frame(width: 88)
                    .onChange(of: gramsText) { _, newValue in
                        let filtered = newValue.filter { $0.isNumber }
                        if filtered != newValue { gramsText = filtered }
                        guard let v = Double(filtered), v > 0 else { return }
                        applyGrams(v)
                    }
                Button { applyGrams(grams + 5) } label: {
                    Image(systemName: "plus.circle.fill").font(.title2)
                }
            }
            .frame(maxWidth: .infinity)
            .onAppear { syncTextFromGrams() }
            .onChange(of: grams) { _, _ in syncTextFromGrams() }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(presets, id: \.self) { p in
                        Button {
                            applyGrams(p)
                        } label: {
                            Text("\(Int(p)) g")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    grams == p ? Color.orange.opacity(0.25) : Color.primary.opacity(0.06),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .nutritionCard()
    }

    private func syncTextFromGrams() {
        let t = "\(Int(grams.rounded()))"
        if gramsText != t { gramsText = t }
    }

    private func applyGrams(_ value: Double) {
        grams = min(2000, max(5, value))
        syncTextFromGrams()
    }
}

private struct NutritionMaterialTextField: View {
    let title: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(title, text: $text)
                .keyboardType(keyboard)
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
                )
        }
    }
}

private enum NutritionLogNestedSheet: String, Identifiable {
    case createIngredient
    case createRecipe
    var id: String { rawValue }
}

private struct NutritionLogFoodSheet: View {
    let selectedDate: Date
    let userId: UUID?
    let initialMealSlot: NutritionMealSlot
    let onDone: () -> Void

    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var nestedSheet: NutritionLogNestedSheet?
    @State private var mode: String = "Ingredient"
    @State private var searchText = ""
    @State private var ingredients: [NutritionIngredientRow] = []
    @State private var recipes: [NutritionRecipeRow] = []
    @State private var selectedIngredient: NutritionIngredientRow?
    @State private var selectedRecipe: NutritionRecipeRow?
    @State private var selectedRecipeLines: [NutritionRecipeLineDraft] = []
    @State private var loadingRecipeComposition = false
    @State private var grams: Double = 100
    @State private var mealSlot: NutritionMealSlot
    @State private var loading = false
    @State private var loadingMoreIngredients = false
    @State private var ingredientPage = 0
    @State private var canLoadMoreIngredients = true
    @State private var saving = false
    @State private var error: String?
    @State private var listScope: NutritionListScope = .all
    @State private var favoriteIngredientIds: Set<UUID> = []
    @State private var favoriteRecipeIds: Set<UUID> = []
    @State private var showShareIngredientToChat = false
    @State private var showShareRecipeToChat = false

    private var hasLogSelection: Bool {
        selectedIngredient != nil || selectedRecipe != nil
    }

    init(
        selectedDate: Date,
        userId: UUID?,
        initialMealSlot: NutritionMealSlot = .lunch,
        onDone: @escaping () -> Void
    ) {
        self.selectedDate = selectedDate
        self.userId = userId
        self.initialMealSlot = initialMealSlot
        self.onDone = onDone
        _mealSlot = State(initialValue: initialMealSlot)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 12) {
                        Picker("Type", selection: $mode) {
                            Text("Ingredient").tag("Ingredient")
                            Text("Recipe").tag("Recipe")
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: mode) { _, _ in
                            clearLogSelection()
                            Task { await runSearch() }
                        }

                        Picker("List", selection: $listScope) {
                            ForEach(NutritionListScope.allCases) { scope in
                                Text(scope.rawValue).tag(scope)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: listScope) { _, _ in Task { await runSearch() } }

                        HStack(spacing: 8) {
                            Button("New ingredient") { nestedSheet = .createIngredient }
                                .font(.caption.weight(.semibold))
                                .buttonStyle(.bordered)
                            Button("New recipe") { nestedSheet = .createRecipe }
                                .font(.caption.weight(.semibold))
                                .buttonStyle(.bordered)
                        }

                        NutritionMaterialTextField(title: "Search", text: $searchText)
                            .onChange(of: searchText) { _, _ in Task { await runSearch() } }

                        if let error {
                            Text(error).font(.caption).foregroundStyle(.red)
                        }

                        if loading {
                            ProgressView()
                        } else if mode == "Ingredient" {
                            ForEach(Array(ingredients.enumerated()), id: \.element.id) { index, row in
                                ingredientRow(row)
                                    .onAppear {
                                        guard index >= ingredients.count - 5 else { return }
                                        Task { await loadMoreIngredientsIfNeeded() }
                                    }
                            }
                            if loadingMoreIngredients {
                                ProgressView()
                                    .padding(.vertical, 8)
                            }
                            if ingredients.isEmpty {
                                emptySearchHint
                            }
                        } else {
                            ForEach(recipes) { row in
                                recipeRow(row)
                            }
                            if recipes.isEmpty {
                                Text(emptyRecipesHint)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding()
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if hasLogSelection {
                        logFoodConfirmPanel
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.22), value: hasLogSelection)
            }
            .navigationTitle("Log food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss(); onDone() }
                }
            }
            .task {
                await loadFavorites()
                await runSearch()
            }
            .sheet(item: $nestedSheet) { sheet in
                switch sheet {
                case .createIngredient:
                    NutritionCreateIngredientSheet(userId: userId) {
                        nestedSheet = nil
                        Task { await runSearch() }
                    }
                    .gradientBG()
                case .createRecipe:
                    NutritionCreateRecipeSheet(userId: userId) {
                        nestedSheet = nil
                        Task { await runSearch() }
                    }
                    .gradientBG()
                }
            }
            .sheet(isPresented: $showShareIngredientToChat) {
                if let snap = sharedIngredientSnapshot {
                    ShareIngredientToChatSheet(snapshot: snap) {}
                        .environmentObject(app)
                        .gradientBG()
                }
            }
            .sheet(isPresented: $showShareRecipeToChat) {
                if let snap = sharedRecipeSnapshot {
                    ShareRecipeToChatSheet(snapshot: snap) {}
                        .environmentObject(app)
                        .gradientBG()
                }
            }
        }
    }

    private var logFoodConfirmPanel: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Text(logSelectionTitle)
                    .font(.headline)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    clearLogSelection()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 32, height: 32)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }

            Picker("Meal", selection: $mealSlot) {
                ForEach(NutritionMealSlot.allCases) { slot in
                    Text(slot.rawValue).tag(slot)
                }
            }
            .pickerStyle(.segmented)

            ScrollView {
                logFoodConfirmDetails
            }
            .frame(maxHeight: 200)

            NutritionGramsInput(grams: $grams, kcalPreview: previewKcal)

            if sharedIngredientSnapshot != nil || sharedRecipeSnapshot != nil {
                Button {
                    if sharedIngredientSnapshot != nil {
                        showShareIngredientToChat = true
                    } else if sharedRecipeSnapshot != nil {
                        showShareRecipeToChat = true
                    }
                } label: {
                    Text("Share via Chat").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(saving)
            }

            Button { Task { await save() } } label: {
                Group {
                    if saving { ProgressView() }
                    else { Text("Add to diary").frame(maxWidth: .infinity) }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(saving || (selectedRecipe != nil && (loadingRecipeComposition || selectedRecipeLines.isEmpty)))
        }
        .padding(16)
        .nutritionCard()
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var sharedIngredientSnapshot: SharedIngredientSnapshot? {
        guard let ing = selectedIngredient else { return nil }
        return SharedIngredientSnapshot(
            v: 1,
            type: "shared_ingredient",
            name: ing.name,
            calories_per_100g: ing.calories_per_100g,
            protein_per_100g: ing.protein_per_100g,
            carbs_per_100g: ing.carbs_per_100g,
            fat_per_100g: ing.fat_per_100g,
            saturated_fat_per_100g: ing.saturated_fat_per_100g,
            sugars_per_100g: ing.sugars_per_100g,
            fiber_per_100g: ing.fiber_per_100g,
            sodium_mg_per_100g: ing.sodium_mg_per_100g
        )
    }

    private var sharedRecipeSnapshot: SharedRecipeSnapshot? {
        guard let recipe = selectedRecipe else { return nil }
        guard !selectedRecipeLines.isEmpty else { return nil }
        let items = selectedRecipeLines.map { line in
            SharedRecipeIngredientSnapshot(
                name: line.ingredient.name,
                weight_g: line.weightG,
                calories_per_100g: line.ingredient.calories_per_100g,
                protein_per_100g: line.ingredient.protein_per_100g,
                carbs_per_100g: line.ingredient.carbs_per_100g,
                fat_per_100g: line.ingredient.fat_per_100g,
                saturated_fat_per_100g: line.ingredient.saturated_fat_per_100g,
                sugars_per_100g: line.ingredient.sugars_per_100g,
                fiber_per_100g: line.ingredient.fiber_per_100g,
                sodium_mg_per_100g: line.ingredient.sodium_mg_per_100g
            )
        }
        let profile = NutritionManager.rollupProfilePer100g(lines: selectedRecipeLines)
        return SharedRecipeSnapshot(
            v: 1,
            type: "shared_recipe",
            name: recipe.name,
            description: recipe.description,
            ingredients: items,
            profile_per_100g: SharedRecipeProfilePer100gSnapshot(
                calories: profile.calories,
                protein: profile.protein,
                carbs: profile.carbs,
                fat: profile.fat,
                saturatedFat: profile.saturatedFat,
                sugars: profile.sugars,
                fiber: profile.fiber,
                sodiumMg: profile.sodiumMg
            )
        )
    }

    @ViewBuilder
    private var logFoodConfirmDetails: some View {
        VStack(spacing: 12) {
            if let ing = selectedIngredient {
                NutritionFactsLabel(title: "Nutrition Facts", profile: ing.profilePer100g)
            } else if let recipe = selectedRecipe {
                if let desc = recipe.description?.trimmingCharacters(in: .whitespacesAndNewlines), !desc.isEmpty {
                    DisclosureGroup("Description") {
                        Text(desc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.subheadline.weight(.semibold))
                }
                if loadingRecipeComposition {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else if !selectedRecipeLines.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(selectedRecipeLines, id: \.id) { line in
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle")
                                    .font(.caption)
                                    .foregroundStyle(.mint)
                                Text("\(Int(line.weightG.rounded()))g \(line.ingredient.name)")
                                    .font(.caption)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    NutritionFactsLabel(
                        title: "Nutrition Facts",
                        profile: NutritionManager.rollupProfilePer100g(lines: selectedRecipeLines)
                    )
                }
            }
        }
    }

    private var logSelectionTitle: String {
        if let ing = selectedIngredient { return ing.name }
        if let recipe = selectedRecipe { return recipe.name }
        return ""
    }

    private func clearLogSelection() {
        selectedIngredient = nil
        selectedRecipe = nil
        selectedRecipeLines = []
        loadingRecipeComposition = false
    }

    private var emptySearchHint: some View {
        let base: String
        switch listScope {
        case .all:
            base = searchText.isEmpty ? "Browse ingredients below or search by name." : "No matches for \"\(searchText)\"."
        case .mine:
            base = "No custom ingredients yet. Tap New ingredient to create one."
        case .favorites:
            base = "No favorite ingredients yet. Tap the star on any item to save it here."
        }
        return Text(base)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var emptyRecipesHint: String {
        switch listScope {
        case .all:
            return "Browse catalog recipes or create your own to log combined meals."
        case .mine:
            return "No custom recipes yet. Tap New recipe to create one."
        case .favorites:
            return "No favorite recipes yet. Tap the star on any recipe to save it here."
        }
    }

    private func loadFavorites() async {
        favoriteIngredientIds = (try? await NutritionManager.fetchFavoriteIngredientIds()) ?? []
        favoriteRecipeIds = (try? await NutritionManager.fetchFavoriteRecipeIds()) ?? []
    }

    private func toggleFavoriteIngredient(_ id: UUID) async {
        let adding = !favoriteIngredientIds.contains(id)
        if adding { favoriteIngredientIds.insert(id) } else { favoriteIngredientIds.remove(id) }
        if listScope == .favorites && !adding {
            ingredients.removeAll { $0.id == id }
        }
        do {
            try await NutritionManager.toggleFavoriteIngredient(ingredientId: id, isFavorite: adding)
        } catch {
            if adding { favoriteIngredientIds.remove(id) } else { favoriteIngredientIds.insert(id) }
        }
    }

    private func toggleFavoriteRecipe(_ id: UUID) async {
        let adding = !favoriteRecipeIds.contains(id)
        if adding { favoriteRecipeIds.insert(id) } else { favoriteRecipeIds.remove(id) }
        if listScope == .favorites && !adding {
            recipes.removeAll { $0.id == id }
        }
        do {
            try await NutritionManager.toggleFavoriteRecipe(recipeId: id, isFavorite: adding)
        } catch {
            if adding { favoriteRecipeIds.remove(id) } else { favoriteRecipeIds.insert(id) }
        }
    }

    private var previewKcal: Double? {
        if let ing = selectedIngredient {
            return grams * ing.calories_per_100g / 100.0
        }
        if selectedRecipe != nil, !selectedRecipeLines.isEmpty {
            let profile = NutritionManager.rollupProfilePer100g(lines: selectedRecipeLines)
            return grams * profile.calories / 100.0
        }
        return nil
    }

    private func loadRecipeComposition(recipeId: UUID) async {
        loadingRecipeComposition = true
        defer { loadingRecipeComposition = false }
        do {
            let lines = try await NutritionManager.fetchRecipeLines(recipeId: recipeId)
            guard selectedRecipe?.id == recipeId else { return }
            selectedRecipeLines = lines
            let total = NutritionManager.totalRecipeWeightG(lines: lines)
            if total > 0 {
                grams = total
            }
        } catch {
            if selectedRecipe?.id == recipeId {
                selectedRecipeLines = []
            }
        }
    }

    private func ingredientRow(_ row: NutritionIngredientRow) -> some View {
        HStack(spacing: 8) {
            Button {
                selectedIngredient = row
                selectedRecipe = nil
                selectedRecipeLines = []
            } label: {
                HStack {
                    VStack(alignment: .leading) {
                        Text(row.name).font(.subheadline.weight(.medium))
                        Text("\(Int(row.calories_per_100g.rounded())) kcal / 100g")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if selectedIngredient?.id == row.id {
                        Image(systemName: "checkmark.circle.fill")
                    }
                }
            }
            .buttonStyle(.plain)

            Button {
                Task { await toggleFavoriteIngredient(row.id) }
            } label: {
                Image(systemName: favoriteIngredientIds.contains(row.id) ? "star.fill" : "star")
                    .foregroundStyle(favoriteIngredientIds.contains(row.id) ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .nutritionCard()
    }

    private func recipeRow(_ row: NutritionRecipeRow) -> some View {
        HStack(spacing: 8) {
            Button {
                selectedRecipe = row
                selectedIngredient = nil
                selectedRecipeLines = []
                Task { await loadRecipeComposition(recipeId: row.id) }
            } label: {
                HStack {
                    Text(row.name)
                    Spacer()
                    if selectedRecipe?.id == row.id {
                        Image(systemName: "checkmark.circle.fill")
                    }
                }
            }
            .buttonStyle(.plain)

            Button {
                Task { await toggleFavoriteRecipe(row.id) }
            } label: {
                Image(systemName: favoriteRecipeIds.contains(row.id) ? "star.fill" : "star")
                    .foregroundStyle(favoriteRecipeIds.contains(row.id) ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .nutritionCard()
    }

    private func runSearch() async {
        guard let userId else { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            if mode == "Ingredient" {
                ingredientPage = 0
                canLoadMoreIngredients = true
                let page = try await NutritionManager.fetchIngredientsPage(
                    userId: userId,
                    query: searchText,
                    page: 0,
                    scope: listScope,
                    favoriteIds: favoriteIngredientIds
                )
                ingredients = page.rows
                canLoadMoreIngredients = page.hasMore
            } else {
                recipes = try await NutritionManager.fetchRecipes(
                    userId: userId,
                    query: searchText,
                    scope: listScope,
                    favoriteIds: favoriteRecipeIds
                )
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadMoreIngredientsIfNeeded() async {
        guard let userId else { return }
        guard mode == "Ingredient" else { return }
        guard canLoadMoreIngredients, !loading, !loadingMoreIngredients else { return }
        loadingMoreIngredients = true
        defer { loadingMoreIngredients = false }
        do {
            let nextPage = ingredientPage + 1
            let page = try await NutritionManager.fetchIngredientsPage(
                userId: userId,
                query: searchText,
                page: nextPage,
                scope: listScope,
                favoriteIds: favoriteIngredientIds
            )
            var seen = Set(ingredients.map(\.id))
            let fresh = page.rows.filter { seen.insert($0.id).inserted }
            guard !fresh.isEmpty else {
                canLoadMoreIngredients = page.hasMore
                if page.hasMore { ingredientPage = nextPage }
                return
            }
            ingredients.append(contentsOf: fresh)
            ingredientPage = nextPage
            canLoadMoreIngredients = page.hasMore
        } catch {
            canLoadMoreIngredients = false
        }
    }

    private func save() async {
        guard let userId else { return }
        saving = true
        error = nil
        defer { saving = false }
        do {
            if let ing = selectedIngredient {
                try await NutritionManager.insertDiaryLog(
                    userId: userId,
                    date: selectedDate,
                    mealSlot: mealSlot,
                    ingredientId: ing.id,
                    recipeId: nil,
                    quantityG: grams
                )
            } else if let recipe = selectedRecipe {
                try await NutritionManager.insertDiaryLog(
                    userId: userId,
                    date: selectedDate,
                    mealSlot: mealSlot,
                    ingredientId: nil,
                    recipeId: recipe.id,
                    quantityG: grams
                )
            } else {
                error = "Select an item."
                return
            }
            dismiss()
            onDone()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct NutritionCreateIngredientSheet: View {
    let userId: UUID?
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var form = NutritionIngredientFormState()
    @State private var saving = false
    @State private var error: String?
    @State private var showSourceChooser = false
    @State private var activePickerSource: ImagePickerBridge.Source?
    @State private var isScanning = false
    @State private var scanBanner: Banner?

    private func formBinding(_ keyPath: WritableKeyPath<NutritionIngredientFormState, String>) -> Binding<String> {
        Binding(
            get: { form[keyPath: keyPath] },
            set: { newValue in
                form = form.updating(keyPath, to: newValue)
            }
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    NutritionMaterialTextField(title: "Name", text: $name)
                    Button {
                        showSourceChooser = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "camera.fill")
                            Text("Scan Nutrition Label")
                            Spacer()
                            if isScanning {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(12)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isScanning || saving)
                    NutritionMaterialTextField(title: "Calories per 100g", text: formBinding(\.calories), keyboard: .decimalPad)
                    NutritionMaterialTextField(title: "Protein per 100g (g)", text: formBinding(\.protein), keyboard: .decimalPad)
                    NutritionMaterialTextField(title: "Carbs per 100g (g)", text: formBinding(\.carbs), keyboard: .decimalPad)
                    NutritionMaterialTextField(title: "Fat per 100g (g)", text: formBinding(\.fat), keyboard: .decimalPad)
                    NutritionMaterialTextField(title: "Saturated fat per 100g (g)", text: formBinding(\.saturatedFat), keyboard: .decimalPad)
                    NutritionMaterialTextField(title: "Sugars per 100g (g)", text: formBinding(\.sugars), keyboard: .decimalPad)
                    NutritionMaterialTextField(title: "Fiber per 100g (g)", text: formBinding(\.fiber), keyboard: .decimalPad)
                    NutritionMaterialTextField(title: "Sodium per 100g (mg)", text: formBinding(\.sodiumMg), keyboard: .decimalPad)
                    NutritionFactsLabel(title: name.isEmpty ? "Preview" : name, profile: form.profilePer100g())
                        .id(form.revision)
                    if let error {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                    Button { Task { await save() } } label: {
                        Group {
                            if saving { ProgressView() }
                            else { Text("Save ingredient").frame(maxWidth: .infinity) }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(saving)
                }
                .padding()
            }
            .navigationTitle("New ingredient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss(); onDone() }
                }
            }
            .banner($scanBanner)
            .confirmationDialog("Scan nutrition label", isPresented: $showSourceChooser, titleVisibility: .visible) {
                Button("Take Photo") {
                    activePickerSource = .camera
                }
                Button("Photo Library") {
                    activePickerSource = .photoLibrary
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(item: $activePickerSource) { source in
                ImagePickerBridge(
                    source: source,
                    onImage: { image in
                        activePickerSource = nil
                        Task { await processScannedImage(image) }
                    },
                    onCancel: { activePickerSource = nil }
                )
            }
        }
    }

    @MainActor
    private func processScannedImage(_ image: UIImage) async {
        withAnimation(.easeInOut(duration: 0.2)) {
            form = .clearedForScan()
        }
        isScanning = true
        defer { isScanning = false }
        do {
            let recognition = try await NutritionLabelOCRService.recognize(from: image)
            let parsed = NutritionLabelParser.parse(recognition: recognition)
            withAnimation(.easeInOut(duration: 0.2)) {
                form = .applyingScan(parsed)
            }
        } catch {
            BannerAction.showError(
                error.localizedDescription,
                banner: $scanBanner
            )
        }
    }

    private func save() async {
        guard let userId else { return }
        guard let cals = Double(form.calories.replacingOccurrences(of: ",", with: ".")) else {
            error = "Enter valid calories."
            return
        }
        saving = true
        error = nil
        defer { saving = false }
        do {
            var profile = form.profilePer100g()
            profile.calories = cals
            _ = try await NutritionManager.createIngredient(
                userId: userId,
                name: name,
                profile: profile
            )
            dismiss()
            onDone()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

extension ImagePickerBridge.Source: Identifiable {
    var id: String {
        switch self {
        case .camera: return "camera"
        case .photoLibrary: return "photoLibrary"
        }
    }
}

private struct NutritionCreateRecipeSheet: View {
    let userId: UUID?
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var searchText = ""
    @State private var pickResults: [NutritionIngredientRow] = []
    @State private var lines: [NutritionRecipeLineDraft] = []
    @State private var pickWeight: Double = 100
    @State private var selectedPick: NutritionIngredientRow?
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    NutritionMaterialTextField(title: "Recipe name", text: $name)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Description")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Optional description", text: $description, axis: .vertical)
                            .lineLimit(3...6)
                            .padding(12)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    Text("Add multiple ingredients. Set grams before adding, then adjust each line with +/− or presets.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(lines.isEmpty ? "Ingredients" : "Ingredients (\(lines.count))")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(lines) { line in
                        NutritionRecipeLineEditor(
                            name: line.ingredient.name,
                            weightG: line.weightG,
                            onWeightChange: { setLineWeight(line.id, $0) },
                            onDelete: { lines.removeAll { $0.id == line.id } }
                        )
                    }
                    NutritionMaterialTextField(title: "Search ingredient to add", text: $searchText)
                        .onChange(of: searchText) { _, _ in Task { await searchPick() } }
                    ForEach(pickResults) { row in
                        HStack(spacing: 8) {
                            Button {
                                selectedPick = row
                            } label: {
                                HStack {
                                    Text(row.name)
                                    Spacer()
                                    if selectedPick?.id == row.id {
                                        Image(systemName: "checkmark.circle.fill")
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            Button("Add") {
                                lines.append(NutritionRecipeLineDraft(ingredient: row, weightG: pickWeight))
                                selectedPick = nil
                                pickWeight = 100
                            }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.bordered)
                        }
                        .padding(10)
                        .nutritionCard()
                    }
                    if let pick = selectedPick {
                        NutritionFactsLabel(title: pick.name, profile: pick.profilePer100g)
                        NutritionGramsInput(grams: $pickWeight, kcalPreview: nil)
                        Button("Add to recipe") {
                            lines.append(NutritionRecipeLineDraft(ingredient: pick, weightG: pickWeight))
                            selectedPick = nil
                            pickWeight = 100
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    if !lines.isEmpty {
                        NutritionFactsLabel(
                            title: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Recipe preview" : name,
                            profile: NutritionManager.rollupProfilePer100g(lines: lines)
                        )
                    }
                    if let error {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                    Button { Task { await save() } } label: {
                        Group {
                            if saving { ProgressView() }
                            else { Text("Save recipe").frame(maxWidth: .infinity) }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(saving || lines.isEmpty || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 10)
                .background(.ultraThinMaterial)
                .overlay(
                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 1),
                    alignment: .top
                )
            }
            .navigationTitle("New recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss(); onDone() }
                }
            }
            .task { await searchPick() }
        }
    }

    private func setLineWeight(_ lineId: UUID, _ weight: Double) {
        guard let index = lines.firstIndex(where: { $0.id == lineId }) else { return }
        lines[index].weightG = min(2000, max(5, weight))
    }

    private func searchPick() async {
        guard let userId else { return }
        pickResults = (try? await NutritionManager.searchIngredients(userId: userId, query: searchText)) ?? []
    }

    private func save() async {
        guard let userId else { return }
        saving = true
        error = nil
        defer { saving = false }
        do {
            _ = try await NutritionManager.createRecipe(
                userId: userId,
                name: name,
                description: description,
                lines: lines
            )
            dismiss()
            onDone()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct NutritionEditDiarySheet: View {
    let item: NutritionDiaryItemUI
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var mealSlot: NutritionMealSlot
    @State private var grams: Double
    @State private var saving = false
    @State private var error: String?

    init(item: NutritionDiaryItemUI, onDone: @escaping () -> Void) {
        self.item = item
        self.onDone = onDone
        _mealSlot = State(initialValue: NutritionMealSlot(rawValue: item.mealSlot) ?? .lunch)
        _grams = State(initialValue: item.quantityG)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Text(item.name)
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Picker("Meal", selection: $mealSlot) {
                        ForEach(NutritionMealSlot.allCases) { slot in
                            Text(slot.rawValue).tag(slot)
                        }
                    }
                    .pickerStyle(.segmented)
                    NutritionGramsInput(grams: $grams, kcalPreview: item.caloriesKcal * grams / max(item.quantityG, 1))
                    if let error {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                    Button { Task { await save() } } label: {
                        Group {
                            if saving { ProgressView() }
                            else { Text("Save changes").frame(maxWidth: .infinity) }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    Button(role: .destructive) { Task { await deleteEntry() } } label: {
                        Text("Delete from diary").frame(maxWidth: .infinity)
                    }
                    .disabled(saving)
                }
                .padding()
            }
            .navigationTitle("Edit entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss(); onDone() }
                }
            }
        }
    }

    private func save() async {
        saving = true
        error = nil
        defer { saving = false }
        do {
            try await NutritionManager.updateDiaryLog(logId: item.id, mealSlot: mealSlot, quantityG: grams)
            dismiss()
            onDone()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func deleteEntry() async {
        saving = true
        error = nil
        defer { saving = false }
        do {
            try await NutritionManager.deleteDiaryLog(logId: item.id)
            dismiss()
            onDone()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
