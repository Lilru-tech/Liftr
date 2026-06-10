import SwiftUI

struct OpponentPetChallengeSheet: View {
    @Environment(\.dismiss) private var dismiss

    let preview: PetCombatPreview
    let defenderPet: PetCombatPetSummary
    let headToHead: PetCombatHeadToHeadSummary?
    let opponentUsername: String?
    let onChallenge: () -> Void

    private var rarity: PetRarity {
        PetRarity(databaseValue: defenderPet.rarity) ?? .common
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 10) {
                        PetCombatSummaryImage(pet: defenderPet, height: 120)

                        Text(defenderPet.displayName)
                            .font(.title3.bold())

                        PetRarityBadge(rarity: rarity)
                    }

                    if let headToHead, headToHead.totalBattles > 0 {
                        PetCombatHeadToHeadSummaryView(
                            summary: headToHead,
                            opponentUsername: opponentUsername
                        )
                    }

                    if let attacker = preview.attacker,
                       let defender = preview.defender,
                       let attackerPet = attacker.pet,
                       let defenderPet = defender.pet,
                       let attackerStats = attacker.stats,
                       let defenderStats = defender.stats {
                        PetCombatComparisonStats(
                            attackerName: attackerPet.displayName,
                            defenderName: defenderPet.displayName,
                            attackerStats: attackerStats,
                            defenderStats: defenderStats,
                            attackerLevel: attackerPet.currentLevel,
                            defenderLevel: defenderPet.currentLevel
                        )
                    }

                    if let energy = preview.energy {
                        HStack {
                            PetEnergyBadge(energy: energy, label: "Your energy")
                            Spacer()
                            Text("Challenging costs 1 energy")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    if preview.canChallenge {
                        Button {
                            dismiss()
                            onChallenge()
                        } label: {
                            Label("Challenge Pet", systemImage: "bolt.horizontal.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    } else if let reason = preview.blockReasonText {
                        Text(reason)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .gradientBG()
    }
}
