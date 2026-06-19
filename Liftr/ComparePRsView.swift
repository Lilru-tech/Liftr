import SwiftUI
import Supabase

private struct PRRow: Decodable, Identifiable {
    let kind: String
    let user_id: UUID
    let label: String
    let metric: String
    let value: Double
    let achieved_at: Date
    var id: String { "\(kind)|\(label)|\(metric)|\(achieved_at.timeIntervalSince1970)" }
}

struct ComparePRsView: View {
    @EnvironmentObject var app: AppState
    
    let myUserId: UUID
    let otherUserId: UUID
    let otherUsername: String
    
    @State private var myPRs: [PRRow] = []
    @State private var otherPRs: [PRRow] = []
    @State private var loading = false
    @State private var error: String?
    
    struct Row: Identifiable {
        let id = UUID()
        let kind: String
        let label: String
        let metric: String
        let myValue: Double?
        let otherValue: Double?
        let winner: Winner
        enum Winner { case me, other, tie, unknown }
    }
    
    private struct Key: Hashable {
        let kind: String
        let label: String
        let metric: String
    }
    
    private var mergedSections: [(title: String, items: [Row])] {
        let mineKeyed = Dictionary(grouping: myPRs, by: { Key(kind: $0.kind, label: $0.label, metric: $0.metric) })
        let otherKeyed = Dictionary(grouping: otherPRs, by: { Key(kind: $0.kind, label: $0.label, metric: $0.metric) })
        let keys = Set(mineKeyed.keys).intersection(otherKeyed.keys)
        
        func better(metric: String, a: Double?, b: Double?) -> Row.Winner {
            guard let a, let b else { return .unknown }
            if abs(a - b) < 1e-9 { return .tie }
            let lowerIsBetter = PrFormatting.lowerIsBetter(metric: metric)
            return lowerIsBetter ? (a < b ? .me : .other) : (a > b ? .me : .other)
        }
        
        var rows: [Row] = []
        for k in keys {
            let mine = mineKeyed[k]?.sorted { $0.achieved_at > $1.achieved_at }.first
            let oth  = otherKeyed[k]?.sorted { $0.achieved_at > $1.achieved_at }.first
            rows.append(.init(
                kind: k.kind,
                label: k.label,
                metric: k.metric,
                myValue: mine?.value,
                otherValue: oth?.value,
                winner: better(metric: k.metric, a: mine?.value, b: oth?.value)
            ))
        }
        
        let dict = Dictionary(grouping: rows, by: { sectionName(forKind: $0.kind) })
        return dict.keys.sorted().map { ($0, dict[$0]!.sorted {
            PrFormatting.activityLabel(kind: $0.kind, label: $0.label).localizedCaseInsensitiveCompare(
                PrFormatting.activityLabel(kind: $1.kind, label: $1.label)
            ) == .orderedAscending
        }) }
    }
    
    private var tally: (me: Int, ties: Int, other: Int) {
        let all = mergedSections.flatMap { $0.items }
        return (
            me: all.filter { $0.winner == .me }.count,
            ties: all.filter { $0.winner == .tie }.count,
            other: all.filter { $0.winner == .other }.count
        )
    }
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Comparing PRs").font(.headline)
                    HStack(spacing: 0) {
                        Text("You")
                            .foregroundStyle(.green)
                        Text(" vs ")
                            .foregroundStyle(.secondary)
                        Text("@\(otherUsername)")
                            .foregroundStyle(.red)
                    }
                    .font(.subheadline)
                }
                Spacer()
                scoreSummary
            }
            .padding(.horizontal)
            
            if loading {
                ProgressView().padding(.top, 12)
            } else if let error {
                Text(error).foregroundStyle(.red).padding(.horizontal)
            } else if mergedSections.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("No comparable PRs yet")
                        .font(.headline)
                    Text("We couldn't find PRs with the same metric for you and @\(otherUsername). Keep training and come back later!")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                List {
                    ForEach(mergedSections, id: \.title) { section in
                        Section(section.title) {
                            ForEach(section.items) { r in
                                HStack(alignment: .firstTextBaseline) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(PrFormatting.activityLabel(kind: r.kind, label: r.label)).font(.body.weight(.semibold))
                                        Text(PrFormatting.prettyMetricName(r.metric, kind: r.kind, label: r.label))
                                            .font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    HStack(spacing: 10) {
                                        Text(PrFormatting.formatValue(metric: r.metric, value: r.myValue, label: r.label))
                                            .fontWeight(r.winner == .me ? .semibold : .regular)
                                            .foregroundStyle(
                                                r.winner == .me ? .green :
                                                    (r.winner == .tie ? .orange : .primary)
                                            )
                                        Text("•").foregroundStyle(.secondary)
                                        Text(PrFormatting.formatValue(metric: r.metric, value: r.otherValue, label: r.label))
                                            .fontWeight(r.winner == .other ? .semibold : .regular)
                                            .foregroundStyle(
                                                r.winner == .other ? .red :
                                                    (r.winner == .tie ? .orange : .primary)
                                            )
                                    }
                                    .font(.subheadline)
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .gradientBG()
        .task { await loadBoth() }
    }
    
    private func loadBoth() async {
        loading = true; defer { loading = false }
        do {
            async let a = fetchPRs(for: myUserId)
            async let b = fetchPRs(for: otherUserId)
            let (mine, theirs) = try await (a, b)
            await MainActor.run {
                myPRs = mine
                otherPRs = theirs
            }
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }
    
    private func fetchPRs(for uid: UUID) async throws -> [PRRow] {
        let res = try await SupabaseManager.shared.client
            .rpc("get_user_prs", params: ["p_user_id": uid.uuidString])
            .execute()
        return try JSONDecoder.supabase().decode([PRRow].self, from: res.data)
    }
    
    @ViewBuilder
    private var scoreSummary: some View {
        let t = tally
        HStack(spacing: 8) {
            Label("\(t.me)",   systemImage: "checkmark.circle").foregroundStyle(.green)
            Label("\(t.ties)", systemImage: "equal.circle")    .foregroundStyle(.orange)
            Label("\(t.other)",systemImage: "xmark.circle")     .foregroundStyle(.red)
        }
        .font(.caption.weight(.semibold))
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Capsule().fill(.ultraThinMaterial))
    }
    
    private func sectionName(forKind k: String) -> String {
        switch k {
        case "strength": return "Strength"
        case "cardio":   return "Cardio"
        case "sport":    return "Sport"
        default:         return "Other"
        }
    }
}
