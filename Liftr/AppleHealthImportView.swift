import SwiftUI

struct AppleHealthImportView: View {
    @EnvironmentObject var app: AppState

    @State private var fromDate = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
    @State private var toDate = Date()
    @State private var importing = false
    @State private var summary: HealthKitImportSummary?
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
                            "Manually imports compatible cardio workouts (run, walk, hike, cycling, swimming, rowing) from Apple Health. "
                                + "Nothing is written back to Health, and already imported sessions are skipped."
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Section("Date range") {
                settingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                quickRangeButton("Today") { applyQuickRangeToday() }
                                quickRangeButton("Last 7 days") { applyQuickRangeLastDays(7) }
                                quickRangeButton("Last 14 days") { applyQuickRangeLastDays(14) }
                            }
                        }
                        .padding(.bottom, 4)

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

    private func quickRangeButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
        .disabled(importing)
    }

    private func applyQuickRangeToday() {
        let cal = Calendar.current
        let t = cal.startOfDay(for: Date())
        fromDate = t
        toDate = t
    }

    private func applyQuickRangeLastDays(_ days: Int) {
        let cal = Calendar.current
        let endDay = cal.startOfDay(for: Date())
        let startDay = cal.date(byAdding: .day, value: -(max(1, days) - 1), to: endDay) ?? endDay
        fromDate = startDay
        toDate = endDay
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
            userId: uid
        )

        await MainActor.run {
            importing = false
            summary = result
            if result.imported == 0, result.failed == 0, result.skippedDuplicate == 0 {
                banner = "No compatible cardio workouts found in this date range."
            }
        }
    }
}
