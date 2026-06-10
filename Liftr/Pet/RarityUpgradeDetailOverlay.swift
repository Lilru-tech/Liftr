import SwiftUI

struct RarityUpgradeDetailOverlay: View {
    let item: PetMarketItemRow
    let petData: PetFullData?
    let userCoins: Int
    let onClose: () -> Void
    let onPurchaseSuccess: () -> Void

    @State private var isBuying = false
    @State private var errorMessage: String?

    private var currentRarity: PetRarity? {
        guard let pet = petData?.pet else { return nil }
        return PetRarity(databaseValue: pet.rarity)
    }

    private var nextRarity: PetRarity? {
        currentRarity?.nextTier
    }

    private var price: Int {
        currentRarity?.upgradeCost ?? item.price
    }

    private var canAfford: Bool {
        price <= userCoins
    }

    private var displayImageURL: URL? {
        PetMarketItemPresentation.make(item: item, petData: petData).imageURL
    }

    var body: some View {
        VStack(spacing: 16) {
            AsyncImage(url: displayImageURL) { phase in
                switch phase {
                case .empty:
                    ProgressView().frame(height: 100)
                case .success(let img):
                    img.resizable().scaledToFit().frame(height: 100)
                case .failure:
                    Image(systemName: "sparkles")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                        .frame(height: 100)
                @unknown default:
                    EmptyView()
                }
            }

            Text(PetMarketItemPresentation.modalTitle(item: item, petData: petData))
                .font(.title3.bold())
                .multilineTextAlignment(.center)

            if let currentRarity, let nextRarity {
                HStack(spacing: 16) {
                    PetRarityBadge(rarity: currentRarity)
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                    PetRarityBadge(rarity: nextRarity)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                if let currentRarity, let nextRarity {
                    benefitRow(
                        title: "Stat roll bonus per level",
                        from: currentRarity.formattedMultiplier(currentRarity.statMultiplier),
                        to: nextRarity.formattedMultiplier(nextRarity.statMultiplier)
                    )
                    benefitRow(
                        title: "Passive coin yield per hour",
                        from: currentRarity.formattedMultiplier(currentRarity.coinMultiplier),
                        to: nextRarity.formattedMultiplier(nextRarity.coinMultiplier)
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text("Existing stats are kept. New multipliers apply to future level-ups and coin income only.")
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
                    Text("Upgrade Rarity")
                        .font(.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canAfford || isBuying || currentRarity == nil || nextRarity == nil)

            Button("Close", action: onClose)
                .font(.subheadline)
        }
        .padding(24)
        .frame(maxWidth: 360)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(radius: 12)
    }

    @ViewBuilder
    private func benefitRow(title: String, from: String, to: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
            HStack(spacing: 6) {
                Text("\(from)×")
                    .foregroundStyle(.secondary)
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(to)×")
                    .fontWeight(.semibold)
            }
            .font(.subheadline)
        }
    }

    private func purchase() async {
        isBuying = true
        defer { isBuying = false }
        do {
            _ = try await PetService.shared.upgradeRarity()
            onPurchaseSuccess()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
