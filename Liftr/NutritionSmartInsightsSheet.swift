import SwiftUI

struct NutritionSmartInsightsContent: View {
    let loading: Bool
    let insights: SmartNutritionRecommendation?
    let error: String?

    @State private var shimmerPhase = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if loading {
                loadingContent
            } else if let error {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .insightsCard()
            } else if let insights {
                summaryCard(insights)
                narrativeCard(insights.recommendation_text)
                if !insights.alerts.isEmpty {
                    alertsSection(insights.alerts)
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                shimmerPhase = true
            }
        }
    }

    private var loadingContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            shimmerBlock(height: 120)
            shimmerBlock(height: 72)
            shimmerBlock(height: 56)
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .padding(.top, 8)
        }
    }

    private func shimmerBlock(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.primary.opacity(shimmerPhase ? 0.14 : 0.07))
            .frame(maxWidth: .infinity)
            .frame(height: height)
    }

    private func summaryCard(_ insights: SmartNutritionRecommendation) -> some View {
        let remaining = insights.displayRemainingBudget

        return VStack(alignment: .leading, spacing: 12) {
            Label("Daily averages", systemImage: "chart.bar.fill")
                .font(.headline)

            Text("Includes your BMR (metabolism) plus workout burn.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                metricColumn(title: "Metabolism (BMR)", value: insights.displayBaseTarget, color: .blue)
                metricColumn(title: "Activity", value: insights.avg_daily_burned_kcal, color: .mint)
                metricColumn(title: "Consumed", value: insights.avg_daily_consumed_kcal, color: .orange)
            }

            Divider().opacity(0.2)

            NutritionCalorieBudgetStatusRow(
                remainingKcal: remaining,
                titleWhenUnder: "Energy budget left",
                titleWhenOver: "Over daily budget",
                hintWhenUnder: "Target + activity − food (daily avg.)",
                hintWhenOver: "Above target + activity (daily avg.)"
            )

            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
                Text("Total energy out (target + activity): \(Int(insights.displayEnergyOut.rounded())) kcal/day")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .insightsCard()
    }

    private func narrativeCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Summary", systemImage: "text.quote")
                .font(.subheadline.weight(.semibold))
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .insightsCard()
    }

    private func alertsSection(_ alerts: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Things to watch", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            ForEach(Array(alerts.enumerated()), id: \.offset) { _, alert in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(.orange)
                        .padding(.top, 6)
                    Text(alert)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func metricColumn(title: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(Int(value.rounded()))")
                .font(.subheadline.weight(.bold))
            Text("kcal")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private extension View {
    func insightsCard() -> some View {
        background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
            )
    }
}
