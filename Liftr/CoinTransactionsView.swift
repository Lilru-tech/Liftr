import SwiftUI
import Supabase

private struct CoinTransactionRow: Identifiable, Decodable {
    let id: UUID
    let amount: Int
    let action_type: String
    let created_at: Date
}

struct CoinTransactionsView: View {
    @ObservedObject private var coinManager = CoinManager.shared
    @State private var items: [CoinTransactionRow] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showClearConfirmation = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                balanceHeader

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
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(items) { item in
                            transactionCard(item)
                        }
                    }

                    HStack {
                        Spacer()
                        Button("Clear history") {
                            showClearConfirmation = true
                        }
                        .font(.caption)
                        .foregroundStyle(.red)
                    }
                    .padding(.top, 4)
                }
            }
            .padding()
        }
        .navigationTitle("Liftr Coins")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await loadTransactions() }
        .task { await loadTransactions() }
        .task { await coinManager.refreshBalance(notifyIfEarned: false) }
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
            Text("This removes your transaction list. Your coin balance will not change.")
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

    private func loadTransactions() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        defer { Task { await MainActor.run { isLoading = false } } }

        do {
            var params: [String: AnyJSON] = [:]
            params["p_limit"] = AnyJSON(20)
            let res = try await SupabaseManager.shared.client
                .rpc("list_my_coin_transactions_v1", params: params)
                .execute()
            let rows = try JSONDecoder.supabase().decode([CoinTransactionRow].self, from: res.data)
            await MainActor.run { items = rows }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                items = []
            }
        }
    }

    private func clearHistory() async {
        do {
            _ = try await SupabaseManager.shared.client
                .rpc("clear_my_coin_history_v1")
                .execute()
            await MainActor.run { items = [] }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }
}
