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

    @ViewBuilder
    func nutritionCartLineChrome(grouped: Bool) -> some View {
        if grouped {
            padding(12).nutritionCard()
        } else {
            self
        }
    }
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

private struct NutritionTotalsLabel: View {
    let title: String
    let grams: Double
    let totals: NutritionProfilePer100g

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption.weight(.bold))
                .padding(.bottom, 6)
            Text("Nutrition Summary")
                .font(.headline.weight(.heavy))
            Text("Total for \(Int(grams.rounded()))g")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
            HStack(alignment: .firstTextBaseline) {
                Text("Calories")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int(totals.calories.rounded()))")
                    .font(.title2.weight(.heavy))
            }
            .padding(.vertical, 6)
            Rectangle().fill(Color.primary.opacity(0.25)).frame(height: 4)
            factRow("Protein", value: totals.protein, unit: "g")
            factRow("Carbs", value: totals.carbs, unit: "g")
            factRow("Fat", value: totals.fat, unit: "g")
            Rectangle().fill(Color.primary.opacity(0.15)).frame(height: 2)
                .padding(.vertical, 4)
            factRow("Sat. fat", value: totals.saturatedFat, unit: "g", indent: true)
            factRow("Sugars", value: totals.sugars, unit: "g", indent: true)
            factRow("Fiber", value: totals.fiber, unit: "g", indent: true)
            factRow("Sodium", value: totals.sodiumMg, unit: "mg", indent: true)
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
    case addFood(mealSlot: NutritionMealSlot, saveMode: NutritionFoodSaveMode = .diary)
    case createIngredient
    case createRecipe
    case editLog(NutritionDiaryItemUI)
    case editPlannedMeal(NutritionMealPlanItemUI)

    var id: String {
        switch self {
        case .addFood(let mealSlot, let saveMode): return "addFood-\(mealSlot.rawValue)-\(saveMode.rawValue)"
        case .createIngredient: return "createIngredient"
        case .createRecipe: return "createRecipe"
        case .editLog(let item): return "edit-\(item.id.uuidString)"
        case .editPlannedMeal(let item): return "editPlan-\(item.targetId.uuidString)"
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
    @Published var plannedItems: [NutritionMealPlanItemUI] = []
    @Published var pendingInvites: [NutritionMealPlanInviteUI] = []
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
            plannedItems = []
            pendingInvites = []
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
            async let plannedMonthTask = NutritionManager.fetchMonthPlannedMealCounts(userId: userId, month: monthDate)
            async let plannedTask = NutritionManager.fetchPlannedItems(userId: userId, date: selectedDate)
            async let invitesTask = NutritionManager.fetchPendingInvites(userId: userId)
            diaryItems = try await itemsTask
            recommendation = try await recTask
            let balance = try await monthTask
            let plannedCounts = try await plannedMonthTask
            monthDayBalance = NutritionManager.mergeMonthBalanceWithPlanned(balance, plannedCounts: plannedCounts)
            plannedItems = try await plannedTask
            pendingInvites = try await invitesTask
        } catch {
            self.error = error.localizedDescription
        }
    }

    func acceptInvite(targetId: UUID, userId: UUID?) async {
        guard userId != nil else { return }
        do {
            try await NutritionManager.acceptMealPlan(targetId: targetId)
            await load(userId: userId)
        } catch {
            self.error = NutritionManager.mealPlanErrorMessage(error)
        }
    }

    func rejectInvite(targetId: UUID, userId: UUID?) async {
        guard userId != nil else { return }
        do {
            try await NutritionManager.rejectMealPlan(targetId: targetId)
            await load(userId: userId)
        } catch {
            self.error = NutritionManager.mealPlanErrorMessage(error)
        }
    }

    func completePlannedMeal(targetId: UUID, userId: UUID?) async {
        guard userId != nil else { return }
        do {
            try await NutritionManager.completeMealPlanAsEaten(targetId: targetId)
            await load(userId: userId)
        } catch {
            self.error = NutritionManager.mealPlanErrorMessage(error)
        }
    }

    func updatePlannedMeal(
        targetId: UUID,
        mealSlot: NutritionMealSlot,
        quantityG: Double,
        userId: UUID?
    ) async {
        guard userId != nil else { return }
        do {
            try await NutritionManager.updateMealPlanTarget(
                targetId: targetId,
                quantityG: quantityG,
                mealSlot: mealSlot
            )
            await load(userId: userId)
        } catch {
            self.error = NutritionManager.mealPlanErrorMessage(error)
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
    @State private var expandedMealSlots: Set<String> = []
    @State private var mealTotalsBySlot: [String: (grams: Double, totals: NutritionProfilePer100g)] = [:]
    @State private var mealTotalsLoadingSlots: Set<String> = []

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

                if !vm.pendingInvites.isEmpty {
                    pendingInvitesSection
                }

                if !vm.plannedItems.isEmpty {
                    plannedMealsSection
                }

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
        .onChange(of: vm.diaryItems) { _, _ in
            mealTotalsBySlot = [:]
            mealTotalsLoadingSlots = []
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        vm.activeSheet = .addFood(mealSlot: .lunch, saveMode: .diary)
                    } label: {
                        Label("Log food", systemImage: "plus.circle")
                    }
                    Button {
                        vm.activeSheet = .addFood(mealSlot: .lunch, saveMode: .plan)
                    } label: {
                        Label("Plan food", systemImage: "calendar.badge.plus")
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
        case .addFood(let mealSlot, let saveMode):
            NutritionLogFoodSheet(
                selectedDate: vm.selectedDate,
                userId: app.userId,
                initialMealSlot: mealSlot,
                saveMode: saveMode,
                onDone: { vm.activeSheet = nil; Task { await vm.load(userId: app.userId) } }
            )
        case .createIngredient:
            NutritionIngredientEditorSheet(
                mode: .create,
                userId: app.userId,
                onDone: { vm.activeSheet = nil; Task { await vm.load(userId: app.userId) } }
            )
        case .createRecipe:
            NutritionRecipeEditorSheet(
                mode: .create,
                userId: app.userId,
                onDone: { vm.activeSheet = nil; Task { await vm.load(userId: app.userId) } }
            )
        case .editLog(let item):
            NutritionEditDiarySheet(
                item: item,
                onDone: { vm.activeSheet = nil; Task { await vm.load(userId: app.userId) } }
            )
        case .editPlannedMeal(let item):
            NutritionEditPlannedMealSheet(
                item: item,
                onDone: { vm.activeSheet = nil; Task { await vm.load(userId: app.userId) } },
                onDecline: { vm.activeSheet = nil; Task { await vm.rejectInvite(targetId: item.targetId, userId: app.userId) } },
                onMarkEaten: {
                    vm.activeSheet = nil
                    Task { await vm.completePlannedMeal(targetId: item.targetId, userId: app.userId) }
                }
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

    private var pendingInvitesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Meal invitations")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal)
            ForEach(vm.pendingInvites) { invite in
                VStack(alignment: .leading, spacing: 8) {
                    Text(invite.foodName)
                        .font(.subheadline.weight(.semibold))
                    Text(NutritionManager.formattedPlanDate(invite.planDate))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(invite.mealSlot) · \(Int(invite.quantityG.rounded())) g · \(Int(invite.caloriesKcal.rounded())) kcal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let creator = invite.creatorUsername {
                        Text("From @\(creator)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Button("Decline") {
                            Task { await vm.rejectInvite(targetId: invite.targetId, userId: app.userId) }
                        }
                        .buttonStyle(.bordered)
                        Button("Accept") {
                            Task { await vm.acceptInvite(targetId: invite.targetId, userId: app.userId) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(12)
                .nutritionCard()
                .padding(.horizontal)
            }
        }
    }

    private var plannedMealsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Planned meals")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal)
            ForEach(vm.plannedItems) { item in
                Button {
                    vm.activeSheet = .editPlannedMeal(item)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(item.foodName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Text("\(item.mealSlot) · \(Int(item.quantityG.rounded())) g · \(Int(item.caloriesKcal.rounded())) kcal")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let partner = item.partnerLabel {
                            Text(partner)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if let status = item.partnerStatusLabel {
                            Text(status)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if let userId = app.userId, item.canMarkEaten(viewingUserId: userId) || item.canDecline(viewingUserId: userId) {
                            HStack {
                                if item.canDecline(viewingUserId: userId) {
                                    Button("Decline") {
                                        Task { await vm.rejectInvite(targetId: item.targetId, userId: app.userId) }
                                    }
                                    .buttonStyle(.bordered)
                                }
                                if item.canMarkEaten(viewingUserId: userId) {
                                    Button("Mark as eaten") {
                                        Task { await vm.completePlannedMeal(targetId: item.targetId, userId: app.userId) }
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                        }
                    }
                    .padding(12)
                    .nutritionCard()
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
            }
        }
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
        let mealTotalKcal = items.isEmpty
            ? nil
            : Int(items.reduce(0) { $0 + $1.caloriesKcal }.rounded())
        let slotKey = slot.rawValue
        let isExpanded = expandedMealSlots.contains(slotKey)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    let expanding = !isExpanded
                    withAnimation(.easeInOut(duration: 0.18)) {
                        if expanding { expandedMealSlots.insert(slotKey) } else { expandedMealSlots.remove(slotKey) }
                    }
                    guard expanding else { return }
                    guard !items.isEmpty else { return }
                    guard mealTotalsBySlot[slotKey] == nil else { return }
                    guard !mealTotalsLoadingSlots.contains(slotKey) else { return }
                    mealTotalsLoadingSlots.insert(slotKey)
                    Task {
                        defer { mealTotalsLoadingSlots.remove(slotKey) }
                        do {
                            let res = try await NutritionManager.fetchMealSlotTotals(items: items)
                            mealTotalsBySlot[slotKey] = res
                        } catch {
                            vm.error = error.localizedDescription
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(slot.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        if let mealTotalKcal {
                            Text("\(mealTotalKcal) kcal")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    mealTotalKcal.map { "\(slot.rawValue), \($0) kilocalories" } ?? slot.rawValue
                )

                Spacer()

                Menu {
                    Button("Log food") {
                        vm.activeSheet = .addFood(mealSlot: slot, saveMode: .diary)
                    }
                    Button("Plan food") {
                        vm.activeSheet = .addFood(mealSlot: slot, saveMode: .plan)
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.blue)
                }
            }
            .padding(.horizontal)

            if isExpanded {
                Group {
                    if mealTotalsLoadingSlots.contains(slotKey) {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if let cached = mealTotalsBySlot[slotKey] {
                        NutritionTotalsLabel(title: "Summary", grams: cached.grams, totals: cached.totals)
                    }
                }
                .padding(.horizontal)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

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
    static let planned = WorkoutTint.sport
}

private struct NutritionCalendarLegend: View {
    var body: some View {
        HStack(spacing: 8) {
            legendItem("No logs", color: NutritionCalendarPalette.noLogs)
            legendItem("On budget", color: NutritionCalendarPalette.onBudget)
            legendItem("Over budget", color: NutritionCalendarPalette.overBudget)
            legendItem("Planned", color: NutritionCalendarPalette.planned)
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
            let plannedCount = summary?.plannedMealCount ?? 0
            let selected = cal.isDate(day, inSameDayAs: selectedDate)
            let today = cal.isDateInToday(day)
            let fillColor: Color = {
                if count > 0, let remaining = summary?.remainingCalories {
                    let accent = remaining < 0 ? NutritionCalendarPalette.overBudget : NutritionCalendarPalette.onBudget
                    return accent.opacity(selected ? 0.55 : 0.32)
                }
                if plannedCount > 0 {
                    return NutritionCalendarPalette.planned.opacity(selected ? 0.55 : 0.32)
                }
                return Color.primary.opacity(selected ? 0.12 : 0.05)
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
                .overlay(alignment: .bottom) {
                    if count > 0, plannedCount > 0 {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(NutritionCalendarPalette.planned, lineWidth: 2)
                            .padding(1)
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
    var showsPortionEditor: Bool = true
    var groupedInCart: Bool = false

    @FocusState private var isWeightFocused: Bool
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
            if showsPortionEditor {
            HStack(spacing: 12) {
                Button { applyWeightCommitted(weightG - 5) } label: {
                    Image(systemName: "minus.circle.fill").font(.title3)
                }
                TextField("g", text: $weightText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.body.weight(.bold))
                    .frame(width: 88)
                    .focused($isWeightFocused)
                    .onChange(of: weightText) { _, newValue in
                        let filtered = newValue.filter { $0.isNumber }
                        if filtered != newValue { weightText = filtered }
                        guard let v = Double(filtered), v > 0 else { return }
                        applyWeightWhileTyping(v)
                    }
                    .onChange(of: isWeightFocused) { _, focused in
                        if !focused { commitWeightText() }
                    }
                Button { applyWeightCommitted(weightG + 5) } label: {
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
                            applyWeightCommitted(preset)
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
        }
        .nutritionCartLineChrome(grouped: !groupedInCart)
    }

    private func syncText() {
        let t = "\(Int(weightG.rounded()))"
        if weightText != t { weightText = t }
    }

    private func applyWeightWhileTyping(_ value: Double) {
        onWeightChange(min(2000, value))
    }

    private func applyWeightCommitted(_ value: Double) {
        onWeightChange(min(2000, max(5, value)))
        syncText()
    }

    private func commitWeightText() {
        let filtered = weightText.filter { $0.isNumber }
        guard let v = Double(filtered), v > 0 else {
            syncText()
            return
        }
        applyWeightCommitted(v)
    }
}

private struct NutritionGramsInput: View {
    @Binding var grams: Double
    var kcalPreview: Double?

    private let presets: [Double] = [50, 100, 150, 200, 250]
    @FocusState private var isGramsFocused: Bool
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
                Button { applyGramsCommitted(grams - 5) } label: {
                    Image(systemName: "minus.circle.fill").font(.title2)
                }
                TextField("g", text: $gramsText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.title3.weight(.bold))
                    .frame(width: 88)
                    .focused($isGramsFocused)
                    .onChange(of: gramsText) { _, newValue in
                        let filtered = newValue.filter { $0.isNumber }
                        if filtered != newValue { gramsText = filtered }
                        guard let v = Double(filtered), v > 0 else { return }
                        applyGramsWhileTyping(v)
                    }
                    .onChange(of: isGramsFocused) { _, focused in
                        if !focused { commitGramsText() }
                    }
                Button { applyGramsCommitted(grams + 5) } label: {
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
                            applyGramsCommitted(p)
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

    private func applyGramsWhileTyping(_ value: Double) {
        grams = min(2000, value)
    }

    private func applyGramsCommitted(_ value: Double) {
        grams = min(2000, max(5, value))
        syncTextFromGrams()
    }

    private func commitGramsText() {
        let filtered = gramsText.filter { $0.isNumber }
        guard let v = Double(filtered), v > 0 else {
            syncTextFromGrams()
            return
        }
        applyGramsCommitted(v)
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

private enum NutritionLogNestedSheet: Identifiable {
    case createIngredient
    case createRecipe
    case editIngredient(NutritionIngredientRow)
    case editRecipe(NutritionRecipeRow)

    var id: String {
        switch self {
        case .createIngredient: return "createIngredient"
        case .createRecipe: return "createRecipe"
        case .editIngredient(let ingredient): return "editIngredient-\(ingredient.id.uuidString)"
        case .editRecipe(let recipe): return "editRecipe-\(recipe.id.uuidString)"
        }
    }
}

struct NutritionLogCartItem: Identifiable {
    let id: UUID
    enum Kind {
        case ingredient(NutritionIngredientRow)
        case recipe(NutritionRecipeRow, lines: [NutritionRecipeLineDraft])
    }
    var kind: Kind
    var grams: Double
    var isLoadingComposition: Bool
    var assignedUserIds: Set<UUID> = []
    var perUserGrams: [UUID: Double] = [:]

    var ingredientId: UUID? {
        if case .ingredient(let row) = kind { return row.id }
        return nil
    }

    var recipeId: UUID? {
        if case .recipe(let row, _) = kind { return row.id }
        return nil
    }

    var displayName: String {
        switch kind {
        case .ingredient(let row): return row.name
        case .recipe(let row, _): return row.name
        }
    }
}

enum NutritionLogCartLogic {
    static let maxItems = 20

    static func clampGrams(_ grams: Double) -> Double {
        min(2000, max(5, grams))
    }

    static func lineKcal(_ item: NutritionLogCartItem) -> Double? {
        guard !item.isLoadingComposition else { return nil }
        switch item.kind {
        case .ingredient(let row):
            return item.grams * row.calories_per_100g / 100.0
        case .recipe(_, let lines) where !lines.isEmpty:
            let profile = NutritionManager.rollupProfilePer100g(lines: lines)
            return item.grams * profile.calories / 100.0
        default:
            return nil
        }
    }

    static func totalKcal(_ cart: [NutritionLogCartItem]) -> Int {
        cart.compactMap { lineKcal($0) }.reduce(0) { $0 + Int($1.rounded()) }
    }

    static func canSave(_ cart: [NutritionLogCartItem], saving: Bool) -> Bool {
        !saving && !cart.isEmpty && !cart.contains(where: \.isLoadingComposition)
    }
}

private struct NutritionLogFoodSheet: View {
    let selectedDate: Date
    let userId: UUID?
    let initialMealSlot: NutritionMealSlot
    let saveMode: NutritionFoodSaveMode
    let onDone: () -> Void

    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var nestedSheet: NutritionLogNestedSheet?
    @State private var planDate: Date
    @State private var selectedPartners: [LightweightProfile] = []
    @State private var showParticipantsPicker = false
    @State private var mode: String = "Ingredient"
    @State private var searchText = ""
    @State private var ingredients: [NutritionIngredientRow] = []
    @State private var recipes: [NutritionRecipeRow] = []
    @State private var cart: [NutritionLogCartItem] = []
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
    @State private var shareIngredientSnapshot: SharedIngredientSnapshot?
    @State private var shareRecipeSnapshot: SharedRecipeSnapshot?
    @State private var showShareIngredientToChat = false
    @State private var showShareRecipeToChat = false
    @State private var pendingDeleteRecipeId: UUID?
    @State private var pendingDeleteIngredientId: UUID?

    private var hasCart: Bool { !cart.isEmpty }

    private func cartItemEffectiveGrams(_ item: NutritionLogCartItem) -> Double {
        if saveMode == .plan, !item.perUserGrams.isEmpty {
            return item.perUserGrams.values.reduce(0, +)
        }
        return item.grams
    }

    private func cartItemProfilePer100g(_ item: NutritionLogCartItem) -> NutritionProfilePer100g? {
        guard !item.isLoadingComposition else { return nil }
        switch item.kind {
        case .ingredient(let ing):
            return ing.profilePer100g
        case .recipe(_, let lines) where !lines.isEmpty:
            return NutritionManager.rollupProfilePer100g(lines: lines)
        default:
            return nil
        }
    }

    private func cartTotalsProfile() -> NutritionProfilePer100g? {
        guard !cart.isEmpty else { return nil }
        guard !cart.contains(where: \.isLoadingComposition) else { return nil }
        let totals = cart.compactMap { item -> NutritionProfilePer100g? in
            guard let per100 = cartItemProfilePer100g(item) else { return nil }
            return NutritionManager.totalsFromPer100g(per100, grams: cartItemEffectiveGrams(item))
        }
        guard !totals.isEmpty else { return nil }
        return NutritionManager.sumProfiles(totals)
    }

    private var planDefaultAssigneeIds: Set<UUID> {
        var ids = Set(selectedPartners.map(\.user_id))
        if let userId { ids.insert(userId) }
        return ids
    }

    private var planAssigneeProfiles: [LightweightProfile] {
        var profiles = selectedPartners
        if let userId, !profiles.contains(where: { $0.user_id == userId }) {
            profiles.insert(LightweightProfile(user_id: userId, username: "You", avatar_url: nil), at: 0)
        }
        return profiles
    }

    private func cartContainsIngredient(_ id: UUID) -> Bool {
        cart.contains { $0.ingredientId == id }
    }

    private func cartContainsRecipe(_ id: UUID) -> Bool {
        cart.contains { $0.recipeId == id }
    }

    init(
        selectedDate: Date,
        userId: UUID?,
        initialMealSlot: NutritionMealSlot = .lunch,
        saveMode: NutritionFoodSaveMode = .diary,
        onDone: @escaping () -> Void
    ) {
        self.selectedDate = selectedDate
        self.userId = userId
        self.initialMealSlot = initialMealSlot
        self.saveMode = saveMode
        self.onDone = onDone
        _mealSlot = State(initialValue: initialMealSlot)
        let cal = Calendar.current
        let defaultPlan = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: selectedDate)) ?? selectedDate
        _planDate = State(initialValue: defaultPlan)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 12) {
                        if saveMode == .plan {
                            DatePicker("Plan date", selection: $planDate, in: Date()..., displayedComponents: .date)
                            VStack(alignment: .leading, spacing: 8) {
                                Text("PARTICIPANTS")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                SectionCard {
                                    if selectedPartners.isEmpty {
                                        Text("No participants added")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.vertical, 4)
                                    } else {
                                        ForEach(selectedPartners, id: \.id) { profile in
                                            HStack {
                                                Text(profile.username.map { "@\($0)" } ?? "User")
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                                Spacer()
                                                Button(role: .destructive) {
                                                    selectedPartners.removeAll { $0.id == profile.id }
                                                } label: {
                                                    Image(systemName: "xmark.circle.fill")
                                                }
                                                .buttonStyle(.borderless)
                                            }
                                            .padding(.vertical, 2)
                                        }
                                    }
                                    Divider().padding(.vertical, 6)
                                    Button {
                                        showParticipantsPicker = true
                                    } label: {
                                        Label("Add participants", systemImage: "person.crop.circle.badge.plus")
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }

                        Picker("Type", selection: $mode) {
                            Text("Ingredient").tag("Ingredient")
                            Text("Recipe").tag("Recipe")
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: mode) { _, _ in
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

                        Text("Tap items to add. Tap again to remove.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

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
                    if hasCart {
                        logFoodCartPanel
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.22), value: hasCart)
            }
            .navigationTitle(saveMode == .plan ? "Plan food" : "Log food")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showParticipantsPicker) {
                MealPlanParticipantsPickerSheet(
                    alreadySelected: Set(selectedPartners),
                    onPick: { picked in
                        var merged = selectedPartners
                        for profile in picked where !merged.contains(where: { $0.id == profile.id }) {
                            merged.append(profile)
                        }
                        selectedPartners = merged
                    }
                )
                .gradientBG()
            }
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
                    NutritionIngredientEditorSheet(
                        mode: .create,
                        userId: userId,
                        onDone: {
                            nestedSheet = nil
                            Task { await runSearch() }
                        }
                    )
                    .gradientBG()
                case .editIngredient(let ingredient):
                    NutritionIngredientEditorSheet(
                        mode: .edit(ingredient),
                        userId: userId,
                        onDone: {
                            nestedSheet = nil
                            Task {
                                await runSearch()
                                syncCartIngredient(ingredient.id)
                            }
                        },
                        onDeleted: {
                            nestedSheet = nil
                            removeFromCart(ingredientId: ingredient.id)
                            Task { await runSearch() }
                        }
                    )
                    .gradientBG()
                case .createRecipe:
                    NutritionRecipeEditorSheet(
                        mode: .create,
                        userId: userId,
                        onDone: {
                            nestedSheet = nil
                            Task { await runSearch() }
                        }
                    )
                    .gradientBG()
                case .editRecipe(let recipe):
                    NutritionRecipeEditorSheet(
                        mode: .edit(recipe),
                        userId: userId,
                        onDone: {
                            nestedSheet = nil
                            Task {
                                await runSearch()
                                syncCartRecipe(recipe.id)
                            }
                        },
                        onDeleted: {
                            nestedSheet = nil
                            removeFromCart(recipeId: recipe.id)
                            Task { await runSearch() }
                        }
                    )
                    .gradientBG()
                }
            }
            .sheet(isPresented: $showShareIngredientToChat) {
                if let snap = shareIngredientSnapshot {
                    ShareIngredientToChatSheet(snapshot: snap) {}
                        .environmentObject(app)
                        .gradientBG()
                }
            }
            .sheet(isPresented: $showShareRecipeToChat) {
                if let snap = shareRecipeSnapshot {
                    ShareRecipeToChatSheet(snapshot: snap) {}
                        .environmentObject(app)
                        .gradientBG()
                }
            }
        }
    }

    private var logFoodCartPanel: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(cart.count) items")
                        .font(.headline)
                    let total = NutritionLogCartLogic.totalKcal(cart)
                    if total > 0 {
                        Text("\(total) kcal total")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    cart = []
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 32, height: 32)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear cart")
            }

            Picker("Meal", selection: $mealSlot) {
                ForEach(NutritionMealSlot.allCases) { slot in
                    Text(slot.rawValue).tag(slot)
                }
            }
            .pickerStyle(.segmented)

            ScrollView {
                VStack(spacing: cart.count > 1 ? 14 : 8) {
                    ForEach(cart) { item in
                        let groupsCartLines = cart.count > 1
                        if item.isLoadingComposition {
                            HStack {
                                Text(item.displayName)
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                ProgressView()
                                Button(role: .destructive) {
                                    cart.removeAll { $0.id == item.id }
                                } label: {
                                    Image(systemName: "trash")
                                }
                            }
                            .nutritionCartLineChrome(grouped: true)
                        } else {
                            let kcal = NutritionLogCartLogic.lineKcal(item)
                            let multiAssigneePlan = saveMode == .plan && planCartSelectedAssigneeCount(item) > 1
                            VStack(alignment: .leading, spacing: 10) {
                                NutritionRecipeLineEditor(
                                    name: multiAssigneePlan
                                        ? item.displayName
                                        : item.displayName + (kcal != nil ? " · \(Int(kcal!.rounded())) kcal" : ""),
                                    weightG: item.grams,
                                    onWeightChange: { updateCartGrams(itemId: item.id, grams: $0) },
                                    onDelete: { cart.removeAll { $0.id == item.id } },
                                    showsPortionEditor: !multiAssigneePlan,
                                    groupedInCart: groupsCartLines
                                )
                                if saveMode == .plan, !planAssigneeProfiles.isEmpty {
                                    planCartAssigneeRow(itemId: item.id)
                                }
                            }
                            .nutritionCartLineChrome(grouped: groupsCartLines)
                        }
                    }

                    if let totals = cartTotalsProfile() {
                        let grams = cart.reduce(0.0) { $0 + cartItemEffectiveGrams($1) }
                        NutritionTotalsLabel(title: "Summary", grams: grams, totals: totals)
                            .nutritionCartLineChrome(grouped: cart.count > 1)
                    }
                }
            }
            .frame(maxHeight: 280)

            Button { Task { await saveCart() } } label: {
                Group {
                    if saving { ProgressView() }
                    else {
                        Text(saveMode == .plan ? "Plan \(cart.count) meal(s)" : "Add \(cart.count) to diary")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!NutritionLogCartLogic.canSave(cart, saving: saving))
        }
        .padding(16)
        .nutritionCard()
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .confirmationDialog(
            "Delete this recipe?",
            isPresented: Binding(
                get: { pendingDeleteRecipeId != nil },
                set: { if !$0 { pendingDeleteRecipeId = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete recipe", role: .destructive) {
                if let id = pendingDeleteRecipeId {
                    Task { await deleteRecipeById(id) }
                }
                pendingDeleteRecipeId = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteRecipeId = nil }
        } message: {
            Text("This removes the recipe and any diary entries logged with it.")
        }
        .confirmationDialog(
            "Delete this ingredient?",
            isPresented: Binding(
                get: { pendingDeleteIngredientId != nil },
                set: { if !$0 { pendingDeleteIngredientId = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete ingredient", role: .destructive) {
                if let id = pendingDeleteIngredientId {
                    Task { await deleteIngredientById(id) }
                }
                pendingDeleteIngredientId = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteIngredientId = nil }
        } message: {
            Text("This removes the ingredient and any diary entries logged with it.")
        }
    }

    private func deleteRecipeById(_ recipeId: UUID) async {
        saving = true
        defer { saving = false }
        do {
            try await NutritionManager.deleteRecipe(recipeId: recipeId)
            removeFromCart(recipeId: recipeId)
            await runSearch()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func deleteIngredientById(_ ingredientId: UUID) async {
        saving = true
        defer { saving = false }
        do {
            try await NutritionManager.deleteIngredient(ingredientId: ingredientId)
            removeFromCart(ingredientId: ingredientId)
            await runSearch()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func ingredientShareSnapshot(_ ing: NutritionIngredientRow) -> SharedIngredientSnapshot {
        SharedIngredientSnapshot(
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

    private func recipeShareSnapshot(_ recipe: NutritionRecipeRow, lines: [NutritionRecipeLineDraft]) -> SharedRecipeSnapshot? {
        guard !lines.isEmpty else { return nil }
        let items = lines.map { line in
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
        let profile = NutritionManager.rollupProfilePer100g(lines: lines)
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

    private func clearCart() {
        cart = []
    }

    private func removeFromCart(ingredientId: UUID? = nil, recipeId: UUID? = nil) {
        cart.removeAll { item in
            if let ingredientId, item.ingredientId == ingredientId { return true }
            if let recipeId, item.recipeId == recipeId { return true }
            return false
        }
    }

    private func updateCartGrams(itemId: UUID, grams: Double) {
        guard let index = cart.firstIndex(where: { $0.id == itemId }) else { return }
        cart[index].grams = NutritionLogCartLogic.clampGrams(grams)
    }

    private func updateCartPerUserGrams(itemId: UUID, userId: UUID, grams: Double) {
        guard let index = cart.firstIndex(where: { $0.id == itemId }) else { return }
        cart[index].perUserGrams[userId] = NutritionLogCartLogic.clampGrams(grams)
    }

    private func cartGramsForUser(item: NutritionLogCartItem, userId: UUID) -> Double {
        item.perUserGrams[userId] ?? item.grams
    }

    private func planCartSelectedAssigneeCount(_ item: NutritionLogCartItem) -> Int {
        let ids = item.assignedUserIds.isEmpty
            ? Set(planDefaultAssigneeIds)
            : item.assignedUserIds
        return planAssigneeProfiles.filter { ids.contains($0.user_id) }.count
    }

    @ViewBuilder
    private func planCartAssigneeRow(itemId: UUID) -> some View {
        if let index = cart.firstIndex(where: { $0.id == itemId }) {
            let item = cart[index]
            let selectedProfiles = planAssigneeProfiles.filter {
                item.assignedUserIds.contains($0.user_id)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("For")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(planAssigneeProfiles, id: \.id) { profile in
                            let selected = item.assignedUserIds.contains(profile.user_id)
                            Button {
                                toggleCartAssignee(itemId: itemId, userId: profile.user_id)
                            } label: {
                                Text(profile.username.map { "@\($0)" } ?? "User")
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(selected ? Color.accentColor.opacity(0.25) : Color.white.opacity(0.12), in: Capsule())
                                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if selectedProfiles.count > 1 {
                    Text("Amount per person")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(selectedProfiles, id: \.id) { profile in
                        let userGrams = cartGramsForUser(item: item, userId: profile.user_id)
                        let lineKcal: Double? = {
                            switch item.kind {
                            case .ingredient(let ing):
                                return userGrams * ing.calories_per_100g / 100.0
                            case .recipe(_, let lines):
                                let profile100 = NutritionManager.rollupProfilePer100g(lines: lines)
                                return userGrams * profile100.calories / 100.0
                            }
                        }()
                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile.username.map { "@\($0)" } ?? "User")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            NutritionGramsInput(
                                grams: Binding(
                                    get: { cartGramsForUser(item: cart[index], userId: profile.user_id) },
                                    set: { updateCartPerUserGrams(itemId: itemId, userId: profile.user_id, grams: $0) }
                                ),
                                kcalPreview: lineKcal
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func toggleCartAssignee(itemId: UUID, userId: UUID) {
        guard let index = cart.firstIndex(where: { $0.id == itemId }) else { return }
        if cart[index].assignedUserIds.contains(userId) {
            cart[index].assignedUserIds.remove(userId)
            cart[index].perUserGrams.removeValue(forKey: userId)
        } else {
            cart[index].assignedUserIds.insert(userId)
        }
        if cart[index].assignedUserIds.isEmpty, let selfId = self.userId {
            cart[index].assignedUserIds.insert(selfId)
        }
    }

    private func syncCartIngredient(_ ingredientId: UUID) {
        guard let updated = ingredients.first(where: { $0.id == ingredientId }) else { return }
        guard let index = cart.firstIndex(where: { $0.ingredientId == ingredientId }) else { return }
        cart[index].kind = .ingredient(updated)
    }

    private func syncCartRecipe(_ recipeId: UUID) {
        guard let updated = recipes.first(where: { $0.id == recipeId }) else { return }
        if let index = cart.firstIndex(where: { $0.recipeId == recipeId }) {
            if case .recipe(_, let lines) = cart[index].kind {
                cart[index].kind = .recipe(updated, lines: lines)
            }
        }
        Task { await refreshCartRecipeLines(recipeId: recipeId) }
    }

    private func refreshCartRecipeLines(recipeId: UUID) async {
        do {
            let lines = try await NutritionManager.fetchRecipeLines(recipeId: recipeId)
            guard let updated = recipes.first(where: { $0.id == recipeId }) else { return }
            guard let index = cart.firstIndex(where: { $0.recipeId == recipeId }) else { return }
            let total = NutritionManager.totalRecipeWeightG(lines: lines)
            cart[index].kind = .recipe(updated, lines: lines)
            cart[index].isLoadingComposition = false
            if total > 0 {
                cart[index].grams = total
            }
        } catch {
            removeFromCart(recipeId: recipeId)
        }
    }

    private func toggleCartIngredient(_ row: NutritionIngredientRow) {
        if cartContainsIngredient(row.id) {
            removeFromCart(ingredientId: row.id)
            return
        }
        guard cart.count < NutritionLogCartLogic.maxItems else {
            error = "You can add up to \(NutritionLogCartLogic.maxItems) items at once."
            return
        }
        cart.append(
            NutritionLogCartItem(
                id: UUID(),
                kind: .ingredient(row),
                grams: 100,
                isLoadingComposition: false,
                assignedUserIds: planDefaultAssigneeIds
            )
        )
    }

    private func toggleCartRecipe(_ row: NutritionRecipeRow) {
        if cartContainsRecipe(row.id) {
            removeFromCart(recipeId: row.id)
            return
        }
        guard cart.count < NutritionLogCartLogic.maxItems else {
            error = "You can add up to \(NutritionLogCartLogic.maxItems) items at once."
            return
        }
        let itemId = UUID()
        cart.append(
            NutritionLogCartItem(
                id: itemId,
                kind: .recipe(row, lines: []),
                grams: 100,
                isLoadingComposition: true,
                assignedUserIds: planDefaultAssigneeIds
            )
        )
        Task {
            do {
                let lines = try await NutritionManager.fetchRecipeLines(recipeId: row.id)
                guard let index = cart.firstIndex(where: { $0.id == itemId }) else { return }
                let total = NutritionManager.totalRecipeWeightG(lines: lines)
                cart[index].kind = .recipe(row, lines: lines)
                cart[index].isLoadingComposition = false
                if total > 0 {
                    cart[index].grams = total
                }
            } catch {
                cart.removeAll { $0.id == itemId }
                self.error = error.localizedDescription
            }
        }
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

    private func ingredientRow(_ row: NutritionIngredientRow) -> some View {
        let inCart = cartContainsIngredient(row.id)
        let canManage = userId != nil && row.user_id == userId
        return HStack(spacing: 8) {
            Button {
                toggleCartIngredient(row)
            } label: {
                HStack {
                    VStack(alignment: .leading) {
                        Text(row.name).font(.subheadline.weight(.medium))
                        Text("\(Int(row.calories_per_100g.rounded())) kcal / 100g")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if inCart {
                        Image(systemName: "checkmark.circle.fill")
                    }
                }
            }
            .buttonStyle(.plain)

            Menu {
                Button("Share via Chat") {
                    shareIngredientSnapshot = ingredientShareSnapshot(row)
                    showShareIngredientToChat = true
                }
                if canManage {
                    Button("Edit") { nestedSheet = .editIngredient(row) }
                    Button("Delete", role: .destructive) { pendingDeleteIngredientId = row.id }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }

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
        let inCart = cartContainsRecipe(row.id)
        let canManage = userId != nil && row.user_id == userId
        return HStack(spacing: 8) {
            Button {
                toggleCartRecipe(row)
            } label: {
                HStack {
                    Text(row.name)
                    Spacer()
                    if inCart {
                        Image(systemName: "checkmark.circle.fill")
                    }
                }
            }
            .buttonStyle(.plain)

            Menu {
                Button("Share via Chat") {
                    Task {
                        if let item = cart.first(where: { $0.recipeId == row.id }),
                           case .recipe(_, let lines) = item.kind,
                           !lines.isEmpty,
                           let snap = recipeShareSnapshot(row, lines: lines) {
                            shareRecipeSnapshot = snap
                            showShareRecipeToChat = true
                            return
                        }
                        do {
                            let lines = try await NutritionManager.fetchRecipeLines(recipeId: row.id)
                            if let snap = recipeShareSnapshot(row, lines: lines) {
                                shareRecipeSnapshot = snap
                                showShareRecipeToChat = true
                            }
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                }
                if canManage {
                    Button("Edit") { nestedSheet = .editRecipe(row) }
                    Button("Delete", role: .destructive) { pendingDeleteRecipeId = row.id }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }

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

    private func saveCart() async {
        guard let userId else { return }
        guard !cart.isEmpty else {
            error = "Add at least one item."
            return
        }
        guard !cart.contains(where: \.isLoadingComposition) else { return }
        saving = true
        error = nil
        defer { saving = false }
        do {
            if saveMode == .plan {
                try await NutritionManager.createMealPlansFromCart(
                    creatorId: userId,
                    planDate: planDate,
                    mealSlot: mealSlot,
                    cart: cart,
                    partnerUserIds: selectedPartners.map(\.user_id)
                )
            } else {
                for item in cart {
                    let quantity = NutritionLogCartLogic.clampGrams(item.grams)
                    switch item.kind {
                    case .ingredient(let ing):
                        try await NutritionManager.insertDiaryLog(
                            userId: userId,
                            date: selectedDate,
                            mealSlot: mealSlot,
                            ingredientId: ing.id,
                            recipeId: nil,
                            quantityG: quantity
                        )
                    case .recipe(let recipe, let lines) where !lines.isEmpty:
                        try await NutritionManager.insertDiaryLog(
                            userId: userId,
                            date: selectedDate,
                            mealSlot: mealSlot,
                            ingredientId: nil,
                            recipeId: recipe.id,
                            quantityG: quantity
                        )
                    default:
                        error = "Recipe still loading."
                        return
                    }
                }
            }
            dismiss()
            onDone()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private enum NutritionIngredientEditorMode {
    case create
    case edit(NutritionIngredientRow)
}

private struct NutritionIngredientEditorSheet: View {
    let mode: NutritionIngredientEditorMode
    let userId: UUID?
    let onDone: () -> Void
    var onDeleted: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var form = NutritionIngredientFormState()
    @State private var saving = false
    @State private var error: String?
    @State private var showSourceChooser = false
    @State private var activePickerSource: ImagePickerBridge.Source?
    @State private var isScanning = false
    @State private var scanBanner: Banner?
    @State private var showDeleteConfirmation = false

    private var isEdit: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var editingIngredientId: UUID? {
        if case .edit(let ingredient) = mode { return ingredient.id }
        return nil
    }

    private var navigationTitle: String {
        isEdit ? "Edit ingredient" : "New ingredient"
    }

    private var saveButtonTitle: String {
        isEdit ? "Save changes" : "Save ingredient"
    }

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
                    if !isEdit {
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
                    }
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
                    if isEdit {
                        Button(role: .destructive) { showDeleteConfirmation = true } label: {
                            Text("Delete ingredient").frame(maxWidth: .infinity)
                        }
                        .disabled(saving)
                    }
                    if let error {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                    Button { Task { await save() } } label: {
                        Group {
                            if saving { ProgressView() }
                            else { Text(saveButtonTitle).frame(maxWidth: .infinity) }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(saving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss(); onDone() }
                }
            }
            .banner($scanBanner)
            .confirmationDialog(
                "Delete this ingredient?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete ingredient", role: .destructive) { Task { await deleteIngredient() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the ingredient and any diary entries logged with it.")
            }
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
            .onAppear { bootstrap() }
        }
    }

    private func bootstrap() {
        if case .edit(let ingredient) = mode {
            name = ingredient.name
            form = .from(ingredient: ingredient)
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
            switch mode {
            case .create:
                _ = try await NutritionManager.createIngredient(
                    userId: userId,
                    name: name,
                    profile: profile
                )
            case .edit(let ingredient):
                _ = try await NutritionManager.updateIngredient(
                    ingredientId: ingredient.id,
                    name: name,
                    profile: profile
                )
            }
            dismiss()
            onDone()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func deleteIngredient() async {
        guard let ingredientId = editingIngredientId else { return }
        saving = true
        error = nil
        defer { saving = false }
        do {
            try await NutritionManager.deleteIngredient(ingredientId: ingredientId)
            dismiss()
            if let onDeleted {
                onDeleted()
            } else {
                onDone()
            }
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

private enum NutritionRecipeEditorMode {
    case create
    case edit(NutritionRecipeRow)
}

private struct NutritionRecipeEditorSheet: View {
    let mode: NutritionRecipeEditorMode
    let userId: UUID?
    let onDone: () -> Void
    var onDeleted: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var searchText = ""
    @State private var pickResults: [NutritionIngredientRow] = []
    @State private var lines: [NutritionRecipeLineDraft] = []
    @State private var pickWeight: Double = 100
    @State private var selectedPick: NutritionIngredientRow?
    @State private var saving = false
    @State private var loadingInitial = false
    @State private var error: String?
    @State private var showDeleteConfirmation = false

    private var isEdit: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var editingRecipeId: UUID? {
        if case .edit(let recipe) = mode { return recipe.id }
        return nil
    }

    private var navigationTitle: String {
        isEdit ? "Edit recipe" : "New recipe"
    }

    private var saveButtonTitle: String {
        isEdit ? "Save changes" : "Save recipe"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if loadingInitial {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
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
                    if isEdit {
                        Button(role: .destructive) { showDeleteConfirmation = true } label: {
                            Text("Delete recipe").frame(maxWidth: .infinity)
                        }
                        .disabled(saving || loadingInitial)
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
                            else { Text(saveButtonTitle).frame(maxWidth: .infinity) }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(saving || loadingInitial || lines.isEmpty || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss(); onDone() }
                }
            }
            .confirmationDialog(
                "Delete this recipe?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete recipe", role: .destructive) { Task { await deleteRecipe() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the recipe and any diary entries logged with it.")
            }
            .task { await bootstrap() }
        }
    }

    private func setLineWeight(_ lineId: UUID, _ weight: Double) {
        guard let index = lines.firstIndex(where: { $0.id == lineId }) else { return }
        lines[index].weightG = min(2000, weight)
    }

    private func normalizedRecipeLines() -> [NutritionRecipeLineDraft] {
        lines.map { line in
            var copy = line
            copy.weightG = min(2000, max(5, line.weightG))
            return copy
        }
    }

    private func bootstrap() async {
        if case .edit(let recipe) = mode {
            loadingInitial = true
            name = recipe.name
            description = recipe.description ?? ""
            lines = (try? await NutritionManager.fetchRecipeLines(recipeId: recipe.id)) ?? []
            loadingInitial = false
        }
        await searchPick()
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
            let committedLines = normalizedRecipeLines()
            switch mode {
            case .create:
                _ = try await NutritionManager.createRecipe(
                    userId: userId,
                    name: name,
                    description: description,
                    lines: committedLines
                )
            case .edit(let recipe):
                _ = try await NutritionManager.updateRecipe(
                    recipeId: recipe.id,
                    name: name,
                    description: description,
                    lines: committedLines
                )
            }
            dismiss()
            onDone()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func deleteRecipe() async {
        guard let recipeId = editingRecipeId else { return }
        saving = true
        error = nil
        defer { saving = false }
        do {
            try await NutritionManager.deleteRecipe(recipeId: recipeId)
            dismiss()
            if let onDeleted {
                onDeleted()
            } else {
                onDone()
            }
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
    @State private var compositionLoading = false
    @State private var profilePer100g: NutritionProfilePer100g?

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
                    if compositionLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if let profilePer100g {
                        let totals = NutritionManager.totalsFromPer100g(profilePer100g, grams: grams)
                        NutritionTotalsLabel(title: "Summary", grams: grams, totals: totals)
                    }
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
            .task { await loadCompositionIfNeeded() }
        }
    }

    private func loadCompositionIfNeeded() async {
        guard profilePer100g == nil else { return }
        guard item.ingredientId != nil || item.recipeId != nil else { return }
        compositionLoading = true
        defer { compositionLoading = false }
        do {
            if let ingredientId = item.ingredientId {
                let ing = try await NutritionManager.fetchIngredientById(ingredientId)
                profilePer100g = ing.profilePer100g
                return
            }
            if let recipeId = item.recipeId {
                profilePer100g = try await NutritionManager.fetchRecipeProfilePer100g(recipeId: recipeId)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func save() async {
        saving = true
        error = nil
        defer { saving = false }
        do {
            try await NutritionManager.updateDiaryLog(logId: item.id, mealSlot: mealSlot, quantityG: min(2000, max(5, grams)))
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

private struct NutritionEditPlannedMealSheet: View {
    let item: NutritionMealPlanItemUI
    let onDone: () -> Void
    let onDecline: () -> Void
    let onMarkEaten: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var app: AppState
    @State private var mealSlot: NutritionMealSlot
    @State private var grams: Double
    @State private var saving = false
    @State private var error: String?

    init(
        item: NutritionMealPlanItemUI,
        onDone: @escaping () -> Void,
        onDecline: @escaping () -> Void,
        onMarkEaten: @escaping () -> Void
    ) {
        self.item = item
        self.onDone = onDone
        self.onDecline = onDecline
        self.onMarkEaten = onMarkEaten
        _mealSlot = State(initialValue: NutritionMealSlot(rawValue: item.mealSlot) ?? .lunch)
        _grams = State(initialValue: item.quantityG)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Text(item.foodName)
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let partner = item.partnerLabel {
                        Text(partner)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Picker("Meal", selection: $mealSlot) {
                        ForEach(NutritionMealSlot.allCases) { slot in
                            Text(slot.rawValue).tag(slot)
                        }
                    }
                    .pickerStyle(.segmented)
                    NutritionGramsInput(
                        grams: $grams,
                        kcalPreview: item.caloriesKcal * grams / max(item.quantityG, 1)
                    )
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
                    if app.userId.map({ item.canMarkEaten(viewingUserId: $0) }) == true {
                        Button {
                            dismiss()
                            onMarkEaten()
                        } label: {
                            Text("Mark as eaten").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    if app.userId.map({ item.canDecline(viewingUserId: $0) }) == true {
                        Button(role: .destructive) {
                            dismiss()
                            onDecline()
                        } label: {
                            Text("Decline plan").frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Planned meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss(); onDone() }
                }
            }
        }
    }

    private func save() async {
        guard app.userId != nil else { return }
        saving = true
        error = nil
        defer { saving = false }
        do {
            try await NutritionManager.updateMealPlanTarget(
                targetId: item.targetId,
                quantityG: grams,
                mealSlot: mealSlot
            )
            dismiss()
            onDone()
        } catch let err {
            error = NutritionManager.mealPlanErrorMessage(err)
        }
    }
}
