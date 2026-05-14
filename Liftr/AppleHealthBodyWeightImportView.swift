import SwiftUI

struct AppleHealthBodyWeightImportView: View {
    @EnvironmentObject private var app: AppState

    private enum QuickRangePreset: Hashable {
        case last30Days
        case last90Days
        case lastYear
    }

    @State private var fromDate = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
    @State private var toDate = Date()
    @State private var selectedQuickRange: QuickRangePreset? = .last90Days
    @State private var importing = false
    @State private var summary: BodyWeightImportSummary?
    @State private var syncEnabled = HealthKitBodyWeightSyncService.shared.isSyncEnabled
    @State private var syncPreferenceBusy = false
    @State private var suppressSyncToggleChange = false
    @State private var banner: String?

    var body: some View {
        List {
            Section {
                settingsCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Apple Health body weight")
                            .font(.subheadline.weight(.semibold))
                        Text("Reads body-weight samples from Apple Health. Liftr does not write weight back to Health.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Toggle("Background sync", isOn: $syncEnabled)
                            .disabled(syncPreferenceBusy)
                            .onChange(of: syncEnabled) { _, enabled in
                                guard !suppressSyncToggleChange else { return }
                                Task { await setSyncEnabled(enabled) }
                            }
                        if let lastSync = HealthKitBodyWeightSyncService.shared.lastSyncAt {
                            Text("Last sync: \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Backfill range") {
                settingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            quickRangeButton("Last 30 days", preset: .last30Days) {
                                applyQuickRange(days: 30, preset: .last30Days)
                            }
                            quickRangeButton("Last 90 days", preset: .last90Days) {
                                applyQuickRange(days: 90, preset: .last90Days)
                            }
                            quickRangeButton("Last year", preset: .lastYear) {
                                applyQuickRange(days: 365, preset: .lastYear)
                            }
                        }
                        DatePicker("From", selection: $fromDate, displayedComponents: [.date])
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
                            if importing { ProgressView() }
                            Text(importing ? "Importing…" : "Import weight samples")
                                .font(.body.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(importing || fromDate > toDate)
                }
            }

            if let summary {
                Section("Result") {
                    settingsCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Imported: \(summary.imported)")
                            Text("Skipped duplicates: \(summary.skippedDuplicate)")
                            Text("Failed: \(summary.failed)")
                                .foregroundStyle(summary.failed > 0 ? .red : .secondary)
                            ForEach(summary.errorMessages.prefix(3), id: \.self) { message in
                                Text(message)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                        .font(.footnote)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        .background(Color.clear)
        .navigationTitle("Apple Health weight")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .top) {
            if let banner {
                Text(banner)
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.top, 8)
            }
        }
    }

    @ViewBuilder
    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(0.18))
                )
            content()
                .padding(12)
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
        .listRowBackground(Color.clear)
    }

    private func quickRangeButton(_ title: String, preset: QuickRangePreset, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .tint(selectedQuickRange == preset ? .blue : .secondary)
    }

    private func applyQuickRange(days: Int, preset: QuickRangePreset) {
        selectedQuickRange = preset
        fromDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        toDate = Date()
    }

    private func setSyncEnabled(_ enabled: Bool) async {
        syncPreferenceBusy = true
        defer { syncPreferenceBusy = false }
        do {
            if enabled {
                try await HealthKitBodyWeightSyncService.shared.enableBackgroundSync()
                banner = "Background sync enabled"
            } else {
                HealthKitBodyWeightSyncService.shared.disableBackgroundSync()
                banner = "Background sync disabled"
            }
        } catch {
            suppressSyncToggleChange = true
            syncEnabled = HealthKitBodyWeightSyncService.shared.isSyncEnabled
            suppressSyncToggleChange = false
            banner = error.localizedDescription
        }
    }

    private func runImport() async {
        importing = true
        defer { importing = false }
        do {
            try await HealthKitBodyWeightSyncService.shared.requestReadAuthorization()
            summary = await HealthKitBodyWeightSyncService.shared.syncSamples(from: fromDate, to: toDate)
            banner = "Import finished"
        } catch {
            banner = error.localizedDescription
        }
    }
}
