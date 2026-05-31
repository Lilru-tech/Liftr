import SwiftUI
import Supabase

private struct XPEventUIModel: Identifiable {
    let id: String
    let createdAt: Date
    let gainedXP: Int64
}

private struct ParsedXPStatEvent {
    let gained: Int64
    let workoutId: Int?
}

private struct XPStatsForKind: Identifiable {
    var id: String { kindLabel }
    let kindLabel: String
    let eventCount: Int
    let totalXP: Int64
    let maxXP: Int64
    var avgXP: Double {
        guard eventCount > 0 else { return 0 }
        return Double(totalXP) / Double(eventCount)
    }
}

private struct XPStatsSummary {
    let sampledEventCount: Int
    let totalXPFromSample: Int64
    let maxSingleAward: Int64
    let avgPerEvent: Double
    let byKind: [XPStatsForKind]
    let bonusNoWorkoutEventCount: Int
    let bonusNoWorkoutTotalXP: Int64
    let orphanWorkoutRefEventCount: Int
    let orphanWorkoutRefTotalXP: Int64
}

struct UserLevelDetailView: View {
    let userId: UUID

    @State private var level: Int = 1
    @State private var xp: Int64 = 0
    @State private var currentLevelThresholdXP: Int64 = 0
    @State private var nextLevelThresholdXP: Int64?
    @State private var lastActivityAt: Date?
    @State private var milestones: [(level: Int, xpRequired: Int64)] = []
    @State private var xpEvents: [XPEventUIModel] = []
    @State private var xpEventsFailed = false
    @State private var xpEventsCanLoadMore = false
    @State private var xpEventsLoadingMore = false
    @State private var xpHistoryExpanded = false

    private let xpEventsPageSize = 10
    private let xpStatsSampleLimit = 800
    @State private var loading = true
    @State private var loadError: String?
    @State private var xpStatsSummary: XPStatsSummary?
    @State private var xpStatsLoading = false

    private var xpToNextLevel: Int64? {
        guard let cap = nextLevelThresholdXP else { return nil }
        return max(0, cap - xp)
    }

    private var nextLevelNumber: Int { level + 1 }

    private var progressRatio: Double {
        guard let cap = nextLevelThresholdXP else { return 0 }
        return levelProgressRatio(
            totalXp: xp,
            currentLevelThresholdXp: currentLevelThresholdXP,
            nextLevelThresholdXp: cap
        )
    }

    private var summaryActivityDate: Date? {
        xpEvents.first?.createdAt ?? lastActivityAt
    }

    private var lastEventGainedXP: Int64? {
        guard let g = xpEvents.first?.gainedXP, g != 0 else { return nil }
        return g
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if loading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    } else if let loadError {
                        Text(loadError)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        progressCard
                        milestonesCard
                        xpStatsCard
                        lastActivityCard
                        howItWorksCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            if !loading && loadError == nil {
                leaderboardLink
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial.opacity(0.5))
            }
        }
        .navigationTitle("Level & XP")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("LV \(level)")
                    .font(.title2.weight(.black))
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(Capsule().fill(Color.yellow.opacity(0.28)))
                    .overlay(Capsule().stroke(Color.white.opacity(0.2)))
                Text("\(formatXP(xp)) XP")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if let cap = nextLevelThresholdXP {
                VStack(alignment: .leading, spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.12))
                            Capsule().fill(Color.green.opacity(0.4))
                                .frame(width: geo.size.width * progressRatio)
                                .animation(.easeInOut(duration: 0.35), value: progressRatio)
                        }
                    }
                    .frame(height: 8)
                    .clipped()

                    Text("Next level needs \(formatXP(cap)) total XP (cumulative).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if let need = xpToNextLevel {
                        if need == 0 {
                            Text("You’ve reached the XP for the next level — it will show after the next recalculation.")
                                .font(.subheadline.weight(.medium))
                        } else {
                            Text("\(formatXP(need)) XP to go until Level \(nextLevelNumber).")
                                .font(.subheadline.weight(.medium))
                        }
                    }
                }
            } else {
                Text("You’re at the top configured level, or thresholds aren’t available for the next tier.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 0.8)
        }
    }

    private var milestonesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Upcoming milestones")
                .font(.subheadline.weight(.semibold))
            if milestones.isEmpty {
                Text("No further level thresholds are configured ahead of your current level.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(milestones.enumerated()), id: \.element.level) { idx, row in
                        if idx > 0 { Divider().opacity(0.35) }
                        HStack {
                            Text("Level \(row.level)")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text("\(formatXP(row.xpRequired)) XP")
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 0.8)
        }
    }

    private var xpStatsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("XP snapshot")
                .font(.subheadline.weight(.semibold))
            if xpStatsLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else if let s = xpStatsSummary {
                Text("Based on your last \(s.sampledEventCount) XP events (up to \(xpStatsSampleLimit) loaded).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 2)

                HStack(spacing: 12) {
                    xpStatMini(title: "Sum (sample)", value: formatXP(s.totalXPFromSample))
                    xpStatMini(title: "Best single", value: formatXP(s.maxSingleAward))
                    xpStatMini(title: "Avg / event", value: formatAvgXP(s.avgPerEvent))
                }

                if !s.byKind.isEmpty {
                    Text("By workout type")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                    VStack(spacing: 0) {
                        ForEach(Array(s.byKind.enumerated()), id: \.element.id) { i, row in
                            if i > 0 { Divider().opacity(0.35) }
                            kindStatsRow(row)
                        }
                    }
                }

                if s.bonusNoWorkoutEventCount > 0 {
                    HStack {
                        Text("Bonuses (no workout)")
                            .font(.caption.weight(.medium))
                        Spacer()
                        Text("\(s.bonusNoWorkoutEventCount)× · \(formatXP(s.bonusNoWorkoutTotalXP)) XP")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.top, 4)
                }
                if s.orphanWorkoutRefEventCount > 0 {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Workout link missing")
                                .font(.caption.weight(.medium))
                            Text("XP tied to a workout id that is not in your workouts anymore (often after a delete).")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer(minLength: 8)
                        Text("\(s.orphanWorkoutRefEventCount)× · \(formatXP(s.orphanWorkoutRefTotalXP)) XP")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(.top, s.bonusNoWorkoutEventCount > 0 ? 6 : 4)
                }
            } else {
                Text("Stats will appear when XP events can be loaded.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 0.8)
        }
    }

    private func xpStatMini(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func kindStatsRow(_ row: XPStatsForKind) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(row.kindLabel)
                .font(.subheadline.weight(.medium))
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("max \(formatXP(row.maxXP)) · avg \(formatAvgXP(row.avgXP))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text("\(row.eventCount)× · \(formatXP(row.totalXP)) XP")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 8)
    }

    private var lastActivityCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            DisclosureGroup(isExpanded: $xpHistoryExpanded) {
                Group {
                    if xpEventsFailed {
                        Text("Couldn’t load XP events (table or permissions may differ).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    } else if xpEvents.isEmpty {
                        Text("No XP events returned yet.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(xpEvents) { ev in
                                    xpEventRow(ev)
                                    Divider().opacity(0.35)
                                }
                                if xpEventsCanLoadMore {
                                    Group {
                                        if xpEventsLoadingMore {
                                            ProgressView()
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 12)
                                        } else {
                                            Color.clear.frame(height: 1)
                                        }
                                    }
                                    .onAppear {
                                        Task { await loadMoreXPEvents() }
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 240)
                        .padding(.top, 8)
                    }
                }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Last XP activity")
                        .font(.subheadline.weight(.semibold))
                    if let d = summaryActivityDate {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(lastActivityRelative(d))
                                    .font(.body.weight(.medium))
                                Text(d.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 12)
                            if let g = lastEventGainedXP {
                                Text("+\(formatXP(g)) XP")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.green)
                            } else if !xpEvents.isEmpty {
                                Text("+0 XP")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    } else {
                        Text("No timestamp on file for this profile.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .tint(.accentColor)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 0.8)
        }
    }

    private func xpEventRow(_ ev: XPEventUIModel) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ev.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline.weight(.medium))
                Text(lastActivityRelative(ev.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(ev.gainedXP >= 0 ? "+\(formatXP(ev.gainedXP)) XP" : "\(formatXP(ev.gainedXP)) XP")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(ev.gainedXP >= 0 ? Color.primary : Color.orange)
        }
        .padding(.vertical, 10)
    }

    private var howItWorksCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How you earn XP")
                .font(.subheadline.weight(.semibold))
            VStack(alignment: .leading, spacing: 8) {
                bulletRow("Logging workouts and other eligible activity records XP events on the server.")
                bulletRow("Your level is derived from your total XP using the level_thresholds table.")
                bulletRow("After longer breaks, newly awarded points may be reduced (soft decay), so consistency matters.")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 0.8)
        }
    }

    private func bulletRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .font(.footnote.weight(.bold))
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var leaderboardLink: some View {
        NavigationLink {
            RankingView(presetMetric: .level, presetScope: .friends)
                .gradientBG()
        } label: {
            Label("Level leaderboard (friends)", systemImage: "trophy.fill")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
    }

    private func load() async {
        await MainActor.run {
            loading = true
            loadError = nil
            xpEventsFailed = false
            xpEventsCanLoadMore = false
            xpEventsLoadingMore = false
        }
        struct GetUserLevelParams: Encodable { let p_user: UUID }
        struct UL: Decodable { let level: Int; let xp: Int64; let last_activity_at: String? }
        struct Thr: Decodable { let level: Int; let xp_required: Int64 }

        do {
            let res = try await SupabaseManager.shared.client
                .rpc("get_user_level", params: GetUserLevelParams(p_user: userId))
                .execute()
            let rows = try JSONDecoder.supabase().decode([UL].self, from: res.data)
            let row = rows.first
            let lv = row?.level ?? 1
            let totalXp = row?.xp ?? 0
            let parsedDate = parseLastActivity(row?.last_activity_at)

            let thresholdLevels = [lv, lv + 1, lv + 2, lv + 3]
            let thrRes = try await SupabaseManager.shared.client
                .from("level_thresholds")
                .select("level,xp_required")
                .in("level", values: thresholdLevels)
                .order("level", ascending: true)
                .execute()
            let thrRows = try JSONDecoder.supabase().decode([Thr].self, from: thrRes.data)
            let ms = thrRows
                .filter { $0.level > lv }
                .map { (level: $0.level, xpRequired: $0.xp_required) }
            let currentFloor = thrRows.first(where: { $0.level == lv })?.xp_required ?? 0
            let nextCap: Int64? = thrRows.first(where: { $0.level == lv + 1 })?.xp_required

            let events = await fetchXPEventsFirstPage()

            await MainActor.run {
                self.level = lv
                self.xp = totalXp
                self.currentLevelThresholdXP = currentFloor
                self.nextLevelThresholdXP = nextCap
                self.lastActivityAt = parsedDate
                self.milestones = ms
                self.xpEvents = events.models
                self.xpEventsFailed = events.failed
                self.xpEventsCanLoadMore = events.canLoadMore
                self.loading = false
            }
            Task { await loadXPStatsSummary() }
        } catch {
            await MainActor.run {
                self.loadError = "Couldn’t load level data."
                self.loading = false
            }
        }
    }

    private func fetchXPEventsFirstPage() async -> (models: [XPEventUIModel], failed: Bool, canLoadMore: Bool) {
        do {
            let parsed = try await fetchXPEventsPage(offset: 0)
            let canMore = parsed.count >= xpEventsPageSize
            return (parsed, false, canMore)
        } catch {
            return ([], true, false)
        }
    }

    private func fetchXPEventsPage(offset: Int) async throws -> [XPEventUIModel] {
        let from = offset
        let to = offset + xpEventsPageSize - 1
        let res = try await SupabaseManager.shared.client
            .from("xp_events")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("created_at", ascending: false)
            .range(from: from, to: to)
            .execute()
        return parseXPEventsJSON(data: res.data)
    }

    private func loadXPStatsSummary() async {
        await MainActor.run {
            xpStatsLoading = true
            xpStatsSummary = nil
        }
        defer { Task { await MainActor.run { xpStatsLoading = false } } }

        do {
            let res = try await SupabaseManager.shared.client
                .from("xp_events")
                .select()
                .eq("user_id", value: userId.uuidString)
                .order("created_at", ascending: false)
                .range(from: 0, to: xpStatsSampleLimit - 1)
                .execute()
            let events = parseXPEventsForStats(data: res.data)
            guard !events.isEmpty else {
                await MainActor.run { xpStatsSummary = nil }
                return
            }

            let workoutIds = events.compactMap(\.workoutId)
            let kindById = try await fetchWorkoutKinds(for: workoutIds, ownerId: userId)
            let summary = buildXPStatsSummary(events: events, workoutKindById: kindById)
            await MainActor.run { xpStatsSummary = summary }
        } catch {
            await MainActor.run { xpStatsSummary = nil }
        }
    }

    private func fetchWorkoutKinds(for workoutIds: [Int], ownerId: UUID) async throws -> [Int: String] {
        let unique = Array(Set(workoutIds))
        guard !unique.isEmpty else { return [:] }
        var out: [Int: String] = [:]
        var idx = 0
        while idx < unique.count {
            let end = min(idx + 100, unique.count)
            let chunk = Array(unique[idx..<end])
            let wres = try await SupabaseManager.shared.client
                .from("workouts")
                .select("id,kind")
                .in("id", values: chunk)
                .eq("user_id", value: ownerId.uuidString)
                .execute()
            if let arr = try? JSONSerialization.jsonObject(with: wres.data) as? [[String: Any]] {
                for obj in arr {
                    let wid = (obj["id"] as? NSNumber)?.intValue ?? (obj["id"] as? Int)
                    let kind = obj["kind"] as? String
                    if let wid, let kind {
                        out[wid] = kind
                    }
                }
            }
            idx = end
        }
        return out
    }

    private func buildXPStatsSummary(
        events: [ParsedXPStatEvent],
        workoutKindById: [Int: String]
    ) -> XPStatsSummary {
        let gains = events.map(\.gained)
        let total = gains.reduce(0, +)
        let maxSingle = gains.max() ?? 0
        let avg = events.isEmpty ? 0 : Double(total) / Double(events.count)

        var bucket: [String: (count: Int, sum: Int64, max: Int64)] = [:]
        var bonusNoWorkoutCount = 0
        var bonusNoWorkoutSum: Int64 = 0
        var orphanWorkoutRefCount = 0
        var orphanWorkoutRefSum: Int64 = 0

        for e in events {
            if e.workoutId == nil {
                bonusNoWorkoutCount += 1
                bonusNoWorkoutSum += e.gained
                continue
            }
            guard let wid = e.workoutId, let raw = workoutKindById[wid] else {
                orphanWorkoutRefCount += 1
                orphanWorkoutRefSum += e.gained
                continue
            }
            let label = normalizedWorkoutKindLabel(raw)
            var b = bucket[label] ?? (0, 0, 0)
            b.count += 1
            b.sum += e.gained
            b.max = max(b.max, e.gained)
            bucket[label] = b
        }

        let preferredOrder = ["Strength", "Cardio", "Sport", "Other"]
        var byKind: [XPStatsForKind] = []
        for label in preferredOrder {
            guard let b = bucket[label], b.count > 0 else { continue }
            byKind.append(XPStatsForKind(
                kindLabel: label,
                eventCount: b.count,
                totalXP: b.sum,
                maxXP: b.max
            ))
        }

        return XPStatsSummary(
            sampledEventCount: events.count,
            totalXPFromSample: total,
            maxSingleAward: maxSingle,
            avgPerEvent: avg,
            byKind: byKind,
            bonusNoWorkoutEventCount: bonusNoWorkoutCount,
            bonusNoWorkoutTotalXP: bonusNoWorkoutSum,
            orphanWorkoutRefEventCount: orphanWorkoutRefCount,
            orphanWorkoutRefTotalXP: orphanWorkoutRefSum
        )
    }

    private func normalizedWorkoutKindLabel(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch t {
        case "strength": return "Strength"
        case "cardio": return "Cardio"
        case "sport": return "Sport"
        default: return "Other"
        }
    }

    private func parseXPEventsForStats(data: Data) -> [ParsedXPStatEvent] {
        guard let top = try? JSONSerialization.jsonObject(with: data),
              let arr = top as? [[String: Any]] else {
            return []
        }
        let amountKeys = [
            "xp_delta", "amount", "xp", "points", "value", "delta",
            "xp_awarded", "xp_amount", "change", "awarded_xp"
        ]
        var out: [ParsedXPStatEvent] = []
        for obj in arr {
            let gained = firstInt64(in: obj, keys: amountKeys)
            let wid = firstWorkoutId(in: obj)
            out.append(ParsedXPStatEvent(gained: gained, workoutId: wid))
        }
        return out
    }

    private func firstWorkoutId(in obj: [String: Any]) -> Int? {
        for k in ["workout_id", "workoutId", "workout", "ref_workout_id"] {
            if let n = obj[k] as? NSNumber { return n.intValue }
            if let i = obj[k] as? Int { return i }
            if let s = obj[k] as? String, let v = Int(s) { return v }
        }
        return nil
    }

    private func formatAvgXP(_ v: Double) -> String {
        guard v.isFinite else { return "—" }
        if abs(v - round(v)) < 0.05 { return String(format: "%.0f", v) }
        return String(format: "%.1f", v)
    }

    private func loadMoreXPEvents() async {
        guard xpHistoryExpanded else { return }
        guard !xpEventsFailed else { return }
        guard xpEventsCanLoadMore else { return }
        guard !xpEventsLoadingMore else { return }

        await MainActor.run { xpEventsLoadingMore = true }
        defer { Task { await MainActor.run { xpEventsLoadingMore = false } } }

        do {
            let offset = await MainActor.run { xpEvents.count }
            let newRows = try await fetchXPEventsPage(offset: offset)
            await MainActor.run {
                if newRows.isEmpty {
                    xpEventsCanLoadMore = false
                    return
                }
                let existing = Set(xpEvents.map(\.id))
                let merged = newRows.filter { !existing.contains($0.id) }
                if merged.isEmpty {
                    xpEventsCanLoadMore = false
                    return
                }
                xpEvents.append(contentsOf: merged)
                if newRows.count < xpEventsPageSize {
                    xpEventsCanLoadMore = false
                }
            }
        } catch {
            await MainActor.run { xpEventsCanLoadMore = false }
        }
    }

    private func parseXPEventsJSON(data: Data) -> [XPEventUIModel] {
        guard let top = try? JSONSerialization.jsonObject(with: data),
              let arr = top as? [[String: Any]] else {
            return []
        }
        let amountKeys = [
            "xp_delta", "amount", "xp", "points", "value", "delta",
            "xp_awarded", "xp_amount", "change", "awarded_xp"
        ]
        var out: [XPEventUIModel] = []
        for (idx, obj) in arr.enumerated() {
            guard let created = firstDate(in: obj, dateKeys: ["created_at", "inserted_at", "occurred_at"]) else {
                continue
            }
            let gained = firstInt64(in: obj, keys: amountKeys)
            let idBase = (obj["id"] as? NSNumber)?.int64Value
                ?? (obj["id"] as? Int).map(Int64.init)
                ?? Int64(idx)
            let id = "\(idBase)-\(created.timeIntervalSince1970)"
            out.append(XPEventUIModel(id: id, createdAt: created, gainedXP: gained))
        }
        return out
    }

    private func firstDate(in obj: [String: Any], dateKeys: [String]) -> Date? {
        for k in dateKeys {
            if let s = obj[k] as? String, let d = parseLastActivity(s) { return d }
        }
        return nil
    }

    private func firstInt64(in obj: [String: Any], keys: [String]) -> Int64 {
        for k in keys {
            if let n = obj[k] as? NSNumber { return n.int64Value }
            if let i = obj[k] as? Int { return Int64(i) }
            if let d = obj[k] as? Double { return Int64(d.rounded()) }
            if let s = obj[k] as? String, let v = Int64(s) { return v }
        }
        return 0
    }

    private func lastActivityRelative(_ d: Date) -> String {
        let rel = RelativeDateTimeFormatter()
        rel.unitsStyle = .abbreviated
        return rel.localizedString(for: d, relativeTo: Date())
    }

    private func parseLastActivity(_ raw: String?) -> Date? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = isoFrac.date(from: raw) { return d }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: raw) { return d }
        return nil
    }

    private func formatXP(_ value: Int64) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fk", Double(value) / 1_000) }
        return "\(value)"
    }
}
