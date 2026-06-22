import SwiftUI

struct PetLogsView: View {
    let logs: [PetLog]
    let hasMore: Bool
    let onLoadMore: () -> Void
    let onDeleteAll: () -> Void
    var onFilterChange: ((Set<String>) -> Void)? = nil

    @AppStorage(LogFilterPreferences.petDisabledStorageKey) private var disabledCategoriesRaw = ""
    @State private var showFilterSheet = false

    private var disabledCategories: Set<String> {
        LogFilterPreferences.decodeDisabledCategories(disabledCategoriesRaw)
    }

    private var filteredLogs: [PetLog] {
        PetLogFilterCategory.filter(logs, disabledKeys: disabledCategories)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Logs")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    showFilterSheet = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Log filters")
            }

            if logs.isEmpty {
                Text("No logs yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            } else if filteredLogs.isEmpty {
                Text("No logs match your filters.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            } else {
                ForEach(filteredLogs) { log in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(PetLog.title(for: log))
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(log.createdAt.formatted(date: .numeric, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if let subtitle = PetLog.subtitle(for: log) {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if log.expGained > 0 {
                            Text("Exp gained: \(log.expGained)")
                                .font(.caption)
                        }
                        if let level = log.newLevel {
                            Text("New level: \(level)")
                                .font(.caption)
                        }
                        if let delta = log.statsDelta, !delta.isEmpty {
                            ForEach(delta.sorted(by: { $0.key < $1.key }), id: \.key) { stat, value in
                                Text("• \(stat.capitalized): +\(value)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                }

                HStack {
                    if hasMore {
                        Button("See more logs...", action: onLoadMore)
                            .font(.caption)
                    }
                    Spacer()
                    Button("Delete logs", role: .destructive, action: onDeleteAll)
                        .font(.caption)
                }
            }
        }
        .sheet(isPresented: $showFilterSheet) {
            PetLogFilterSheet(
                disabledCategories: Binding(
                    get: { disabledCategories },
                    set: { disabledCategoriesRaw = LogFilterPreferences.encodeDisabledCategories($0) }
                )
            )
            .presentationDetents([.medium, .large])
        }
        .onChange(of: disabledCategoriesRaw) { _, newValue in
            let keys = LogFilterPreferences.decodeDisabledCategories(newValue)
            onFilterChange?(keys)
        }
    }
}
