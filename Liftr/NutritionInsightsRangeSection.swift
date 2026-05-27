import SwiftUI

enum NutritionInsightsQuickPreset: Hashable {
    case oneDay
    case oneWeek
    case oneMonth
}

struct NutritionInsightsRangeSection: View {
    @ObservedObject var vm: NutritionViewModel
    let onAnalyze: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Training & recovery insights")
                .font(.subheadline.weight(.semibold))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    quickPill("1 Day", preset: .oneDay) { vm.applyInsightsQuickPreset(.oneDay) }
                    quickPill("1 Week", preset: .oneWeek) { vm.applyInsightsQuickPreset(.oneWeek) }
                    quickPill("1 Month", preset: .oneMonth) { vm.applyInsightsQuickPreset(.oneMonth) }
                }
            }

            Text("Selected range: \(displayRangeText)")
                .font(.caption)
                .foregroundStyle(.secondary)

            DatePicker("From", selection: $vm.insightsFromDate, in: ...vm.insightsToDate, displayedComponents: [.date])
                .onChange(of: vm.insightsFromDate) { _, _ in
                    handleManualDateChangeIfNeeded()
                    vm.clampInsightsDates()
                }
            Divider().opacity(0.15)
            DatePicker(
                "To",
                selection: $vm.insightsToDate,
                in: vm.insightsFromDate ... Date(),
                displayedComponents: [.date]
            )
            .onChange(of: vm.insightsToDate) { _, _ in
                handleManualDateChangeIfNeeded()
                vm.clampInsightsDates()
            }

            Button(action: onAnalyze) {
                Text("Analyze & View Recommendations")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.insightsFromDate > vm.insightsToDate)
        }
        .onAppear { vm.clampInsightsDates() }
    }

    private var displayRangeText: String {
        "\(Self.rangeFormatter.string(from: vm.insightsFromDate)) – \(Self.rangeFormatter.string(from: vm.insightsToDate))"
    }

    private func quickPill(_ title: String, preset: NutritionInsightsQuickPreset, action: @escaping () -> Void) -> some View {
        let isSelected = vm.insightsQuickPreset == preset
        return Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
        .tint(isSelected ? .accentColor : .secondary)
        .accessibilityLabel(isSelected ? "\(title), selected" : title)
    }

    private func handleManualDateChangeIfNeeded() {
        guard let preset = vm.insightsQuickPreset else { return }
        guard !vm.matchesInsightsPresetDates(preset) else { return }
        vm.insightsQuickPreset = nil
    }

    private static let rangeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
}
