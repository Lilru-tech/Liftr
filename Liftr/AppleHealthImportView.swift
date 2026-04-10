import SwiftUI

struct AppleHealthImportView: View {
    @EnvironmentObject var app: AppState

    @State private var fromDate = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
    @State private var toDate = Date()
    @State private var importing = false
    @State private var summary: HealthKitImportSummary?
    @State private var banner: String?

    var body: some View {
        List {
            Section {
                settingsCard {
                    Text(
                        "Imports workouts saved in the Health app (for example from Apple Watch): run, walk, hike, bike, swim, row. "
                            + "Indoor walk or run (treadmill) is saved as Treadmill when Apple marks the workout as indoor. "
                            + "Route and heart rate are included when Apple provides them. Already imported sessions are skipped. "
                            + "Other workout types in Health (strength, team sports, etc.) are not part of this import."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }

            Section("Date range") {
                settingsCard {
                    VStack(alignment: .leading, spacing: 12) {
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
        .navigationTitle("Apple Health")
        .navigationBarTitleDisplayMode(.inline)
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
                banner = "No matching workouts found in this range."
            }
        }
    }
}
