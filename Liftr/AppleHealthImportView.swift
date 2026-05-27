import SwiftUI

struct AppleHealthImportView: View {
    @EnvironmentObject var app: AppState

    private enum QuickRangePreset: Hashable {
        case today
        case last7Days
        case last14Days
        case lastMonth
    }

    @State private var fromDate = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
    @State private var toDate = Date()
    @State private var selectedQuickRange: QuickRangePreset? = .last14Days
    @State private var applyingQuickRange = false
    @State private var importing = false
    @State private var summary: HealthKitImportSummary?
    @State private var syncEnabled = HealthKitCardioSyncService.shared.isSyncEnabled
    @State private var syncPreferenceBusy = false
    @State private var suppressSyncToggleChange = false
    @State private var banner: String?
    @State private var showImportHelp = false

    var body: some View {
        List {
            Section {
                settingsCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Apple HealthKit")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)

                        Text(
                            "Imports compatible cardio workouts (run, walk, hike, cycling, swimming, rowing) from Apple Health. "
                                + "With automatic import on, new sessions sync in the background. Nothing is written back to Health, and already imported sessions are skipped."
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        Toggle("Automatic import", isOn: $syncEnabled)
                            .disabled(syncPreferenceBusy)
                            .onChange(of: syncEnabled) { _, enabled in
                                guard !suppressSyncToggleChange else { return }
                                Task { await setSyncEnabled(enabled) }
                            }
                        if let lastSync = HealthKitCardioSyncService.shared.lastSyncAt {
                            Text("Last sync: \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Date range") {
                settingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                quickRangeButton("Today", preset: .today) { applyQuickRangeToday() }
                                quickRangeButton("Last 7 days", preset: .last7Days) { applyQuickRangeLastDays(7) }
                                quickRangeButton("Last 14 days", preset: .last14Days) { applyQuickRangeLastDays(14) }
                                quickRangeButton("Last month", preset: .lastMonth) { applyQuickRangeLastMonth() }
                            }
                        }
                        .padding(.bottom, 4)
                        Text("Selected range: \(displayRangeText)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        DatePicker("From", selection: $fromDate, displayedComponents: [.date])
                        Divider().opacity(0.15)
                        DatePicker("To", selection: $toDate, in: fromDate ... Date(), displayedComponents: [.date])
                    }
                }
            }

            Section {
                settingsCard {
                    Button {
                        Task { await runImport() }
                    } label: {
                        HStack {
                            if importing {
                                ProgressView()
                            }
                            Text(importing ? "Importing…" : "Import workouts")
                                .font(.body.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .disabled(importing || app.userId == nil || fromDate > toDate)
                }
            }

            if let banner {
                Section {
                    settingsCard {
                        Text(banner)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
            }

            if let s = summary {
                Section("Result") {
                    settingsCard {
                        VStack(alignment: .leading, spacing: 10) {
                            LabeledContent("Imported", value: "\(s.imported)")
                            Divider().opacity(0.15)
                            LabeledContent("Already in Liftr", value: "\(s.skippedDuplicate)")
                            if s.mergedDuplicate > 0 {
                                Divider().opacity(0.15)
                                LabeledContent("Merged with existing", value: "\(s.mergedDuplicate)")
                            }
                            Divider().opacity(0.15)
                            LabeledContent("Failed", value: "\(s.failed)")
                            if !s.errorMessages.isEmpty {
                                Divider().opacity(0.15)
                                ForEach(Array(s.errorMessages.enumerated()), id: \.offset) { _, msg in
                                    Text(msg)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        .background(Color.clear)
        .navigationTitle("Apple Health (HealthKit)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showImportHelp = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .accessibilityLabel("Apple Health import information")
            }
        }
        .sheet(isPresented: $showImportHelp) {
            AppleHealthImportHelpSheet()
                .presentationDetents([.medium, .large])
                .presentationBackground(.clear)
        }
        .onChange(of: fromDate) { _, _ in
            handleManualDateChangeIfNeeded()
        }
        .onChange(of: toDate) { _, _ in
            handleManualDateChangeIfNeeded()
        }
    }

    @ViewBuilder
    private func settingsCard<C: View>(@ViewBuilder content: () -> C) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(0.18))
                )
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
        .listRowBackground(Color.clear)
    }

    private func quickRangeButton(_ title: String, preset: QuickRangePreset, action: @escaping () -> Void) -> some View {
        let isSelected = selectedQuickRange == preset
        return Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
        .tint(isSelected ? .accentColor : .secondary)
        .disabled(importing)
        .accessibilityLabel(isSelected ? "\(title), selected" : title)
    }

    private func applyQuickRangeToday() {
        let cal = Calendar.current
        let t = cal.startOfDay(for: Date())
        setQuickRange(.today, from: t, to: t)
    }

    private func applyQuickRangeLastDays(_ days: Int) {
        let cal = Calendar.current
        let endDay = cal.startOfDay(for: Date())
        let startDay = cal.date(byAdding: .day, value: -(max(1, days) - 1), to: endDay) ?? endDay
        let preset: QuickRangePreset = (days == 7) ? .last7Days : .last14Days
        setQuickRange(preset, from: startDay, to: endDay)
    }

    private func applyQuickRangeLastMonth() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let startOfCurrentMonth = cal.date(from: cal.dateComponents([.year, .month], from: today)),
              let startOfLastMonth = cal.date(byAdding: .month, value: -1, to: startOfCurrentMonth),
              let endOfLastMonth = cal.date(byAdding: .day, value: -1, to: startOfCurrentMonth)
        else { return }
        setQuickRange(.lastMonth, from: startOfLastMonth, to: cal.startOfDay(for: endOfLastMonth))
    }

    private func setQuickRange(_ preset: QuickRangePreset, from: Date, to: Date) {
        applyingQuickRange = true
        fromDate = from
        toDate = to
        selectedQuickRange = preset
        applyingQuickRange = false
    }

    private func handleManualDateChangeIfNeeded() {
        guard !applyingQuickRange else { return }
        guard let preset = selectedQuickRange else { return }
        guard !matchesSelectedPresetDates(preset) else { return }
        selectedQuickRange = nil
    }

    private func matchesSelectedPresetDates(_ preset: QuickRangePreset) -> Bool {
        let cal = Calendar.current
        let f = cal.startOfDay(for: fromDate)
        let t = cal.startOfDay(for: toDate)
        switch preset {
        case .today:
            let day = cal.startOfDay(for: Date())
            return f == day && t == day
        case .last7Days:
            let endDay = cal.startOfDay(for: Date())
            let startDay = cal.date(byAdding: .day, value: -6, to: endDay) ?? endDay
            return f == startDay && t == endDay
        case .last14Days:
            let endDay = cal.startOfDay(for: Date())
            let startDay = cal.date(byAdding: .day, value: -13, to: endDay) ?? endDay
            return f == startDay && t == endDay
        case .lastMonth:
            let today = cal.startOfDay(for: Date())
            guard let startOfCurrentMonth = cal.date(from: cal.dateComponents([.year, .month], from: today)),
                  let startOfLastMonth = cal.date(byAdding: .month, value: -1, to: startOfCurrentMonth),
                  let endOfLastMonth = cal.date(byAdding: .day, value: -1, to: startOfCurrentMonth)
            else { return false }
            return f == startOfLastMonth && t == cal.startOfDay(for: endOfLastMonth)
        }
    }

    private static let quickRangeDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private var displayRangeText: String {
        "\(Self.quickRangeDateFormatter.string(from: fromDate)) – \(Self.quickRangeDateFormatter.string(from: toDate))"
    }

    private func setSyncEnabled(_ enabled: Bool) async {
        syncPreferenceBusy = true
        defer { syncPreferenceBusy = false }
        do {
            if enabled {
                let result = try await HealthKitCardioSyncService.shared.enableBackgroundSync()
                summary = result
                if result.imported == 0, result.failed == 0, result.skippedDuplicate == 0, result.mergedDuplicate == 0 {
                    banner = "Automatic import enabled. No compatible cardio workouts found in the last 90 days."
                } else if result.failed > 0, let firstError = result.errorMessages.first {
                    banner = "Automatic import enabled, but the initial import reported: \(firstError)"
                } else {
                    banner = "Automatic import enabled"
                }
            } else {
                HealthKitCardioSyncService.shared.disableBackgroundSync()
                banner = "Automatic import disabled"
                summary = nil
            }
        } catch {
            suppressSyncToggleChange = true
            syncEnabled = HealthKitCardioSyncService.shared.isSyncEnabled
            suppressSyncToggleChange = false
            banner = error.localizedDescription
        }
    }

    private func runImport() async {
        await MainActor.run {
            importing = true
            banner = nil
            summary = nil
        }

        guard let uid = await MainActor.run(body: { app.userId }) else {
            await MainActor.run {
                importing = false
                banner = "You must be signed in."
            }
            return
        }

        let cal = Calendar.current
        let from = cal.startOfDay(for: fromDate)
        let toExclusive = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: toDate)) ?? toDate

        do {
            try await HealthKitCardioImportService.shared.requestReadAuthorization()
        } catch {
            await MainActor.run {
                importing = false
                banner = error.localizedDescription
            }
            return
        }

        let result = await HealthKitCardioImportService.shared.importCardioWorkouts(
            from: from,
            to: toExclusive,
            userId: uid,
            mode: .manual
        )

        await MainActor.run {
            importing = false
            summary = result
            if result.imported == 0, result.failed == 0, result.skippedDuplicate == 0, result.mergedDuplicate == 0 {
                banner = "No compatible cardio workouts found in this date range."
            }
        }
    }
}
