import SwiftUI

struct PetLogsView: View {
    let logs: [PetLog]
    let hasMore: Bool
    let onLoadMore: () -> Void
    let onDeleteAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if logs.isEmpty {
                Text("No logs yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            } else {
                ForEach(logs) { log in
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
    }
}
