import SwiftUI
import Charts

struct BodyWeightHistoryView: View {
    @EnvironmentObject private var app: AppState

    @State private var entries: [BodyWeightEntry] = []
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var rangePreset: BodyWeightRangePreset = .days90
    @State private var showLogSheet = false
    @State private var logWeightText = ""
    @State private var logDate = Date()
    @State private var savingLog = false

    private var sortedEntries: [BodyWeightEntry] {
        entries.sorted { $0.measured_at > $1.measured_at }
    }

    private var latestEntry: BodyWeightEntry? { sortedEntries.first }
    private var previousEntry: BodyWeightEntry? { sortedEntries.dropFirst().first }

    private var chartPoints: [BodyWeightChartPoint] {
        BodyWeightPresentation.chartPoints(from: entries, preset: rangePreset)
    }

    var body: some View {
        List {
            if let latestEntry {
                Section {
                    settingsCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(BodyWeightPresentation.formatKg(latestEntry.weight_kg))
                                .font(.title2.weight(.bold))
                                .monospacedDigit()
                            if let delta = BodyWeightPresentation.deltaText(current: latestEntry.weight_kg, previous: previousEntry?.weight_kg) {
                                Text(delta)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            if let monthDelta = BodyWeightPresentation.periodDeltaText(entries: entries, days: 30) {
                                Text(monthDelta)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text("Measured \(latestEntry.measured_at.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Trend") {
                settingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Range", selection: $rangePreset) {
                            ForEach(BodyWeightRangePreset.allCases) { preset in
                                Text(preset.title).tag(preset)
                            }
                        }
                        .pickerStyle(.segmented)

                        if chartPoints.isEmpty {
                            Text("No entries in this range yet.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            Chart(chartPoints) { point in
                                LineMark(
                                    x: .value("Date", point.label),
                                    y: .value("Weight", point.value)
                                )
                                .interpolationMethod(.catmullRom)
                                PointMark(
                                    x: .value("Date", point.label),
                                    y: .value("Weight", point.value)
                                )
                            }
                            .chartPlotStyle { plotArea in
                                plotArea
                                    .background(Color.gray.opacity(0.18))
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .chartYAxisLabel("kg")
                            .frame(height: 220)
                        }
                    }
                }
            }

            Section("History") {
                if loading {
                    settingsCard {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                } else if sortedEntries.isEmpty {
                    settingsCard {
                        Text("No weight entries yet.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(sortedEntries) { entry in
                        settingsCard {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(BodyWeightPresentation.formatKg(entry.weight_kg))
                                        .font(.body.weight(.semibold))
                                        .monospacedDigit()
                                    Text(entry.measured_at.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(BodyWeightPresentation.sourceLabel(entry.sourceKind))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if entry.sourceKind == .manual {
                                Button(role: .destructive) {
                                    Task { await deleteEntry(entry) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
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
        .navigationTitle("Body weight")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Log weight") { showLogSheet = true }
            }
        }
        .sheet(isPresented: $showLogSheet) {
            NavigationStack {
                Form {
                    TextField("Weight (kg)", text: $logWeightText)
                        .keyboardType(.decimalPad)
                    DatePicker("Measured at", selection: $logDate)
                }
                .navigationTitle("Log weight")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showLogSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(savingLog ? "Saving…" : "Save") {
                            Task { await saveManualLog() }
                        }
                        .disabled(savingLog)
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .task { await reload() }
        .refreshable { await reload() }
        .alert("Could not load weight history", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
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

    private func reload() async {
        loading = true
        defer { loading = false }
        do {
            entries = try await BodyWeightClient.listEntries()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveManualLog() async {
        let text = logWeightText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let weight = Double(text), weight > 0 else {
            errorMessage = "Enter a positive weight in kg."
            return
        }
        savingLog = true
        defer { savingLog = false }
        do {
            _ = try await BodyWeightClient.upsertEntry(measuredAt: logDate, weightKg: weight, source: .manual)
            showLogSheet = false
            logWeightText = ""
            logDate = Date()
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteEntry(_ entry: BodyWeightEntry) async {
        do {
            try await BodyWeightClient.deleteEntry(id: entry.id)
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
