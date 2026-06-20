import SwiftUI
import Charts
import Supabase

private struct CoinTransactionRow: Identifiable, Decodable {
    let id: UUID
    let amount: Int
    let action_type: String
    let created_at: Date
}

private struct CoinSourceRow: Decodable {
    let source_key: String
    let total_amount: Int
}

struct CoinTransactionsView: View {
    @ObservedObject private var coinManager = CoinManager.shared
    @AppStorage(LogFilterPreferences.coinDisabledStorageKey) private var disabledCategoriesRaw = ""
    @State private var items: [CoinTransactionRow] = []
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var hasMore = true
    @State private var listOffset = 0
    @State private var errorMessage: String?
    @State private var showClearConfirmation = false
    @State private var showFilterSheet = false
    @State private var sourcesPeriod: CoinSourcesPeriod = .allTime
    @State private var sourceSlices: [CoinSourceSlice] = []
    @State private var sourcesLoading = true
    @State private var sourcesError: String?

    private let pageSize = 20

    private var disabledCategories: Set<String> {
        LogFilterPreferences.decodeDisabledCategories(disabledCategoriesRaw)
    }

    private var filteredItems: [CoinTransactionRow] {
        items.filter { CoinLogFilterCategory.isVisible(actionType: $0.action_type, disabledKeys: disabledCategories) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                balanceHeader
                sourcesCard
                transactionsSection
            }
            .padding()
        }
        .navigationTitle("Liftr Coins")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await reloadTransactions()
            await loadSources()
        }
        .task {
            await reloadTransactions()
            await loadSources()
        }
        .task { await coinManager.refreshBalance(notifyIfEarned: false) }
        .onChange(of: sourcesPeriod) { _, _ in
            Task { await loadSources() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .coinTransactionsShouldRefresh)) { _ in
            Task { await reloadTransactions() }
        }
        .onChange(of: disabledCategoriesRaw) { _, newValue in
            let keys = LogFilterPreferences.decodeDisabledCategories(newValue)
            Task { await reloadTransactions(matchingDisabledCategories: keys) }
        }
        .sheet(isPresented: $showFilterSheet) {
            CoinLogFilterSheet(
                disabledCategories: Binding(
                    get: { disabledCategories },
                    set: { disabledCategoriesRaw = LogFilterPreferences.encodeDisabledCategories($0) }
                )
            )
            .presentationDetents([.medium, .large])
        }
        .confirmationDialog(
            "Clear transaction history?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear history", role: .destructive) {
                Task { await clearHistory() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes your transaction list. Your coin balance will not change. Pet activity logs are not affected.")
        }
    }

    @ViewBuilder
    private var transactionsSection: some View {
        HStack {
            Text("Transactions")
                .font(.headline)
            Spacer()
            Button {
                showFilterSheet = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Transaction filters")
        }

        if isLoading && items.isEmpty {
            ProgressView("Loading transactions...")
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
        } else if let errorMessage {
            Text(errorMessage)
                .foregroundStyle(.red)
                .padding()
        } else if items.isEmpty {
            Text("No transactions yet.")
                .foregroundStyle(.secondary)
                .padding()
        } else if filteredItems.isEmpty {
            Text("No transactions match your filters.")
                .foregroundStyle(.secondary)
                .padding()
        } else {
            LazyVStack(spacing: 8) {
                ForEach(filteredItems) { item in
                    transactionCard(item)
                }
            }

            if hasMore {
                HStack {
                    Spacer()
                    Button {
                        Task { await loadMoreTransactions() }
                    } label: {
                        if isLoadingMore {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Load more transactions…")
                        }
                    }
                    .font(.caption)
                    .disabled(isLoadingMore)
                }
                .padding(.top, 4)
            }

            VStack(alignment: .trailing, spacing: 4) {
                Button("Clear history") {
                    showClearConfirmation = true
                }
                .font(.caption)
                .foregroundStyle(.red)

                Text("Clearing coin history does not remove pet activity logs.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.top, 4)
        }
    }

    private var balanceHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Balance")
                    .font(.headline)
                Spacer()
                NavigationLink {
                    RankingView(presetMetric: .coins)
                        .gradientBG()
                } label: {
                    Text("View ranking")
                        .font(.caption.weight(.semibold))
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "bitcoinsign.circle.fill")
                    .foregroundStyle(Color.yellow.opacity(0.95))
                Text("\(coinManager.balance)")
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                Text("Liftr Coins")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var sourcesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sources")
                .font(.headline)

            Picker("Period", selection: $sourcesPeriod) {
                ForEach(CoinSourcesPeriod.allCases) { period in
                    Text(period.label).tag(period)
                }
            }
            .pickerStyle(.segmented)

            if sourcesLoading && sourceSlices.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else if let sourcesError {
                Text(sourcesError)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if sourceSlices.isEmpty {
                Text("No coins earned in this period.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            } else {
                CoinSourcesDonutChart(slices: sourceSlices)
                sourcesBreakdownList
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var sourcesBreakdownList: some View {
        let total = sourceSlices.reduce(0) { $0 + $1.totalAmount }
        return VStack(spacing: 8) {
            ForEach(sourceSlices) { slice in
                HStack(spacing: 8) {
                    Circle()
                        .fill(slice.color)
                        .frame(width: 8, height: 8)
                    Text(slice.label)
                        .font(.subheadline)
                    Spacer()
                    if total > 0 {
                        Text("\(Int(round(Double(slice.totalAmount) / Double(total) * 100)))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Text(CoinManager.formattedAmount(slice.totalAmount))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                        .monospacedDigit()
                }
            }
        }
        .padding(.top, 4)
    }

    private func transactionCard(_ item: CoinTransactionRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(CoinManager.displayLabel(for: item.action_type))
                    .font(.body)
                Spacer()
                Text(CoinManager.formattedAmount(item.amount))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(item.amount >= 0 ? .green : .red)
            }
            Text(item.created_at.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func reloadTransactions(matchingDisabledCategories disabledKeys: Set<String>? = nil) async {
        let activeDisabledKeys = disabledKeys ?? disabledCategories
        let allCategoriesDisabled = activeDisabledKeys.count >= CoinLogFilterCategory.allCases.count
        let maxPages = 5

        await MainActor.run {
            isLoading = true
            errorMessage = nil
            listOffset = 0
            hasMore = true
            items = []
        }

        do {
            var pagesLoaded = 0
            var offset = 0
            while pagesLoaded < maxPages {
                let rows = try await fetchTransactions(offset: offset)
                await MainActor.run {
                    items.append(contentsOf: rows)
                    listOffset = offset + rows.count
                    hasMore = rows.count >= pageSize
                }
                offset += rows.count
                pagesLoaded += 1

                if allCategoriesDisabled {
                    break
                }

                let visibleCount = items.filter {
                    CoinLogFilterCategory.isVisible(actionType: $0.action_type, disabledKeys: activeDisabledKeys)
                }.count
                if visibleCount >= pageSize || rows.count < pageSize {
                    break
                }
            }
            await MainActor.run { isLoading = false }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                items = []
                hasMore = false
                isLoading = false
            }
        }
    }

    private func loadMoreTransactions() async {
        guard hasMore, !isLoadingMore else { return }
        await MainActor.run { isLoadingMore = true }
        defer { Task { await MainActor.run { isLoadingMore = false } } }

        do {
            let rows = try await fetchTransactions(offset: listOffset)
            await MainActor.run {
                items.append(contentsOf: rows)
                listOffset += rows.count
                hasMore = rows.count >= pageSize
            }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    private func fetchTransactions(offset: Int) async throws -> [CoinTransactionRow] {
        var params: [String: AnyJSON] = [:]
        params["p_limit"] = try AnyJSON(pageSize)
        params["p_offset"] = try AnyJSON(offset)
        let res = try await SupabaseManager.shared.client
            .rpc("list_my_coin_transactions_v1", params: params)
            .execute()
        return try JSONDecoder.supabase().decode([CoinTransactionRow].self, from: res.data)
    }

    private func loadSources() async {
        await MainActor.run {
            sourcesLoading = true
            sourcesError = nil
        }
        defer { Task { await MainActor.run { sourcesLoading = false } } }

        do {
            var params: [String: AnyJSON] = [:]
            let window = CoinManager.coinSourcesTimeWindow(for: sourcesPeriod)
            if let start = window.start, let end = window.end {
                let iso = ISO8601DateFormatter()
                iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                iso.timeZone = .current
                params["p_start"] = try AnyJSON(iso.string(from: start))
                params["p_end"] = try AnyJSON(iso.string(from: end))
            }
            let res = try await SupabaseManager.shared.client
                .rpc("get_my_coin_sources_v1", params: params)
                .execute()
            let rows = try JSONDecoder.supabase().decode([CoinSourceRow].self, from: res.data)
            let slices = rows.map {
                CoinSourceSlice(sourceKey: $0.source_key, totalAmount: $0.total_amount)
            }
            await MainActor.run { sourceSlices = slices }
        } catch {
            await MainActor.run {
                sourcesError = error.localizedDescription
                sourceSlices = []
            }
        }
    }

    private func clearHistory() async {
        do {
            _ = try await SupabaseManager.shared.client
                .rpc("clear_my_coin_history_v1")
                .execute()
            await MainActor.run {
                items = []
                listOffset = 0
                hasMore = false
                sourceSlices = []
            }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }
}

private struct CoinSourcesDonutChart: View {
    let slices: [CoinSourceSlice]

    private var total: Int {
        slices.reduce(0) { $0 + $1.totalAmount }
    }

    var body: some View {
        ZStack {
            if #available(iOS 17.0, *) {
                Chart(slices) { slice in
                    SectorMark(
                        angle: .value("Coins", slice.totalAmount),
                        innerRadius: .ratio(0.55),
                        angularInset: 1.5
                    )
                    .foregroundStyle(slice.color)
                }
                .frame(height: 220)
                .chartLegend(.hidden)
                .chartPlotStyle { plotArea in
                    plotArea
                        .background(Color.gray.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            } else {
                Chart(slices) { slice in
                    BarMark(
                        x: .value("Source", slice.label),
                        y: .value("Coins", slice.totalAmount)
                    )
                    .foregroundStyle(slice.color)
                }
                .frame(height: 220)
                .chartPlotStyle { plotArea in
                    plotArea
                        .background(Color.gray.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }

            VStack(spacing: 2) {
                Text("\(total)")
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                Text("Earned")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
