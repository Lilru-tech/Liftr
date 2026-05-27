import SwiftUI

struct NutritionInsightsEntryCard: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.mint)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text("Training & recovery insights")
                    .font(.subheadline.weight(.semibold))
                Text("Analyze nutrition and workouts over a custom date range.")
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

    private var showResults: Bool {
        vm.smartInsightsLoading || vm.smartInsights != nil || vm.smartInsightsError != nil
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
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

                    if showResults {
                        NutritionSmartInsightsContent(
                            loading: vm.smartInsightsLoading,
                            insights: vm.smartInsights,
                            error: vm.smartInsightsError
                        )
                        .id("insightsResults")
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
            }
            .scrollContentBackground(.hidden)
        }
        .gradientBG()
        .navigationTitle("Recovery insights")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { vm.resetSmartInsights() }
    }
}
