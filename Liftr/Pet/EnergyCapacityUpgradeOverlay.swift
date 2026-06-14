import SwiftUI

struct EnergyCapacityUpgradeOverlay: View {
    let item: PetMarketItemRow
    let petData: PetFullData?
    let userCoins: Int
    let onClose: () -> Void
    let onPurchaseSuccess: () -> Void

    @State private var isBuying = false
    @State private var errorMessage: String?

    private var currentMax: Int {
        petData?.energy?.max ?? 5
    }

    private var nextMax: Int {
        currentMax + 1
    }

    private var price: Int {
        PetEnergyPricing.upgradeCost(maxEnergy: currentMax)
    }

    private var canAfford: Bool {
        price <= userCoins
    }

    private var atCap: Bool {
        currentMax >= PetEnergyPricing.maxCapacity
    }

    private var displayImageURL: URL? {
        let path = PetMarketItemPresentation.make(item: item, petData: petData).imagePath ?? item.imagePath
        return PetImageURLBuilder.marketItemURL(path: path)
    }

    var body: some View {
        VStack(spacing: 16) {
            MarketItemImage(url: displayImageURL, size: 88, modalHeight: 120)

            Text(PetMarketItemPresentation.modalTitle(item: item, petData: petData))
                .font(.title3.bold())
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                energyBadge(value: currentMax, label: "Current")
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                energyBadge(value: nextMax, label: "Next")
            }

            Text("Energy regenerates 1 point every 4 hours up to your max capacity.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 4) {
                Text("Price: \(price)")
                Image(systemName: "bitcoinsign.circle.fill")
                    .foregroundStyle(.yellow)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(canAfford ? .green : .red)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await purchase() }
            } label: {
                HStack {
                    if isBuying { ProgressView().controlSize(.small) }
                    Text("Expand Capacity")
                        .font(.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(!canAfford || isBuying || atCap)

            Button("Close", action: onClose)
                .font(.subheadline)
        }
        .padding(24)
        .frame(maxWidth: 360)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(radius: 12)
    }

    @ViewBuilder
    private func energyBadge(value: Int, label: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.title2.bold())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func purchase() async {
        isBuying = true
        defer { isBuying = false }
        do {
            _ = try await PetService.shared.upgradeEnergyCapacity()
            onPurchaseSuccess()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
