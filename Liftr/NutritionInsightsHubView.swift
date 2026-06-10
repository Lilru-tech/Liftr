import SwiftUI

enum NutritionInsightsHubTab: String, CaseIterable, Identifiable {
    case coach
    case highlights

    var id: String { rawValue }

    var title: String {
        switch self {
        case .coach: return "Coach"
        case .highlights: return "Highlights"
        }
    }
}

struct NutritionInsightsEntryCard: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.mint)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text("Nutrition insights")
                    .font(.subheadline.weight(.semibold))
                Text("Training coach and all-time personal highlights from your diary.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
        )
    }
}

struct NutritionInsightsHubView: View {
    @ObservedObject var vm: NutritionViewModel
    @Binding var insightsPath: NavigationPath
    @State private var selectedTab: NutritionInsightsHubTab = .coach

    private var showCoachResults: Bool {
        vm.smartInsightsLoading || vm.smartInsights != nil || vm.smartInsightsError != nil
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Section", selection: $selectedTab) {
                        ForEach(NutritionInsightsHubTab.allCases) { tab in
                            Text(tab.title).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch selectedTab {
                    case .coach:
                        coachTab(proxy: proxy)
                    case .highlights:
                        highlightsTab
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
            }
            .scrollContentBackground(.hidden)
        }
        .gradientBG()
        .navigationTitle("Nutrition insights")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedTab) { _, tab in
            if tab == .highlights, vm.highlights == nil, !vm.highlightsLoading, vm.highlightsError == nil {
                Task { await vm.loadHighlights() }
            }
        }
        .task {
            if selectedTab == .highlights, vm.highlights == nil, !vm.highlightsLoading {
                await vm.loadHighlights()
            }
        }
    }

    private func openRanking(_ kind: NutritionRankingKind) {
        #if DEBUG
        print("[NutritionInsights] append ranking kind=\(kind.rawValue) pathCount=\(insightsPath.count)")
        #endif
        insightsPath.append(NutritionInsightsRoute.ranking(kind))
    }

    @ViewBuilder
    private func coachTab(proxy: ScrollViewProxy) -> some View {
        Text("Review how your logged meals and published workouts align over time. Pick a window (up to 10 weeks), then run the analysis.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        VStack(alignment: .leading, spacing: 12) {
            NutritionInsightsRangeSection(vm: vm) {
                Task {
                    await vm.analyzeSmartInsights()
                    withAnimation {
                        proxy.scrollTo("insightsResults", anchor: .top)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
        )

        if showCoachResults {
            NutritionSmartInsightsContent(
                loading: vm.smartInsightsLoading,
                insights: vm.smartInsights,
                error: vm.smartInsightsError
            )
            .id("insightsResults")
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var highlightsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("All-time stats from your nutrition diary — peak days, favorite foods, and logging habits.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            NutritionHighlightsContent(
                loading: vm.highlightsLoading,
                highlights: vm.highlights,
                error: vm.highlightsError,
                coinsBalance: vm.coinsBalance,
                showCoinsBalance: true,
                onOpenRanking: openRanking
            )
        }
        .refreshable {
            await vm.loadHighlights()
        }
    }
}
