import SwiftUI

struct OpponentPetChallengeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("skipPetCombatUnbalancedWarning") private var skipPetCombatUnbalancedWarning = false
    @AppStorage("petCombatChallengeMode") private var savedChallengeModeRaw = PetCombatChallengeMode.balanced.rawValue

    let preview: PetCombatPreview
    let defenderPet: PetCombatPetSummary
    let headToHead: PetCombatHeadToHeadSummary?
    let opponentUsername: String?
    let onChallenge: (Bool) -> Void

    @State private var showUnbalancedDialog = false
    @State private var dontShowAgain = false
    @State private var selectedMode: PetCombatChallengeMode = .balanced

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
                        Button(action: handleChallengeTap) {
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
        .overlay {
            if showUnbalancedDialog {
                PetCombatUnbalancedMatchDialog(
                    isPresented: $showUnbalancedDialog,
                    dontShowAgain: $dontShowAgain,
                    isUnderdog: preview.isAttackerUnderdog,
                    selectedMode: $selectedMode,
                    hardcoreBonusLabel: preview.hardcoreBonusLabel,
                    onCancel: { showUnbalancedDialog = false },
                    onFight: confirmChallenge
                )
            }
        }
        .onAppear {
            selectedMode = PetCombatChallengeMode(rawValue: savedChallengeModeRaw) ?? .balanced
        }
    }

    private func handleChallengeTap() {
        if !preview.isStatUnbalanced {
            dismiss()
            onChallenge(false)
            return
        }

        if skipPetCombatUnbalancedWarning {
            let mode = resolvedSavedMode()
            dismiss()
            onChallenge(mode.disableNerfChoice)
            return
        }

        selectedMode = resolvedSavedMode()
        dontShowAgain = false
        showUnbalancedDialog = true
    }

    private func confirmChallenge() {
        if dontShowAgain {
            skipPetCombatUnbalancedWarning = true
        }
        savedChallengeModeRaw = selectedMode.rawValue
        let disableNerf = preview.isAttackerUnderdog && selectedMode.disableNerfChoice
        showUnbalancedDialog = false
        dismiss()
        onChallenge(disableNerf)
    }

    private func resolvedSavedMode() -> PetCombatChallengeMode {
        if preview.isAttackerUnderdog {
            return PetCombatChallengeMode(rawValue: savedChallengeModeRaw) ?? .balanced
        }
        return .balanced
    }
}
