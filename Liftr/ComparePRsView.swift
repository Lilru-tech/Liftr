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
            let m = metric.lowercased()
            let lowerIsBetter = m.contains("pace") || m.contains("fastest")
            if abs(a - b) < 1e-9 { return .tie }
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
        return dict.keys.sorted().map { ($0, dict[$0]!.sorted { $0.label < $1.label }) }
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
                    Text("You vs @\(otherUsername)").foregroundStyle(.secondary)
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
                                        Text(r.label).font(.body.weight(.semibold))
                                        Text(prettyMetricName(r.metric, kind: r.kind))
                                            .font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    HStack(spacing: 10) {
                                        Text(formatValue(metric: r.metric, value: r.myValue))
                                            .fontWeight(r.winner == .me ? .semibold : .regular)
                                            .foregroundStyle(
                                                r.winner == .me ? .green :
                                                    (r.winner == .tie ? .orange : .primary)
                                            )
                                        Text("•").foregroundStyle(.secondary)
                                        Text(formatValue(metric: r.metric, value: r.otherValue))
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
            .from("vw_user_prs")
            .select("*")
            .eq("user_id", value: uid.uuidString)
            .order("achieved_at", ascending: false)
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
    
    private func prettyMetricName(_ metric: String, kind: String) -> String {
        let m = metric.lowercased()
        if m == "max_hr" { return "Max HR" }
        if m == "longest_duration_sec" { return "Longest duration" }
        if m == "longest_distance_km" { return "Longest distance" }
        if m == "fastest_pace_sec_per_km" { return "Fastest pace" }
        if m == "max_elevation_m" { return "Max elevation" }
        if m == "est_1rm_kg" { return "Estimated 1RM" }
        if m == "max_weight_kg" { return "Max weight" }
        if m == "best_set_volume_kg" { return "Best set volume" }
        if m == "max_reps" { return "Max reps" }
        return metric.replacingOccurrences(of: "_", with: " ").capitalized
    }
    
    private func formatValue(metric: String, value: Double?) -> String {
        guard let v = value else { return "—" }
        let m = metric.lowercased()
        if m.hasSuffix("_kg") || m == "est_1rm_kg" || m == "max_weight_kg" || m == "best_set_volume_kg" {
            return String(format: "%.1f kg", v)
        }
        if m.contains("reps") { return "\(Int(v.rounded())) reps" }
        if m == "max_hr" { return "\(Int(v.rounded())) bpm" }
        if m == "longest_distance_km" { return String(format: "%.1f km", v) }
        if m == "max_elevation_m" { return "\(Int(v.rounded())) m" }
        if m == "fastest_pace_sec_per_km" {
            let s = max(1, Int(v.rounded()))
            return String(format: "%d:%02d /km", s/60, s%60)
        }
        if m.hasSuffix("_sec") || m.contains("duration") {
            let s = max(0, Int(v.rounded()))
            let h = s/3600, mm = (s%3600)/60, ss = s%60
            return h > 0 ? String(format:"%d:%02d:%02d", h, mm, ss) : String(format:"%d:%02d", mm, ss)
        }
        return String(format: "%.2f", v)
    }
}
