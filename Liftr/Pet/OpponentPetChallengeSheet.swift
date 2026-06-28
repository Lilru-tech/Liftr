import SwiftUI

struct OpponentPetChallengeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("skipPetCombatUnbalancedWarning") private var skipPetCombatUnbalancedWarning = false
    @AppStorage("petCombatChallengeMode") private var savedChallengeModeRaw = PetCombatChallengeMode.balanced.rawValue

    let opponentUserId: UUID
    let preview: PetCombatPreview
    let defenderPet: PetCombatPetSummary
    let headToHead: PetCombatHeadToHeadSummary?
    let opponentUsername: String?
    let onChallenge: (Bool) -> Void
    let onPreviewRefreshed: (PetCombatPreview) -> Void

    @State private var displayPreview: PetCombatPreview
    @State private var isRefreshingPreview = false
    @State private var showUnbalancedDialog = false
    @State private var dontShowAgain = false
    @State private var selectedMode: PetCombatChallengeMode = .balanced

    init(
        opponentUserId: UUID,
        preview: PetCombatPreview,
        defenderPet: PetCombatPetSummary,
        headToHead: PetCombatHeadToHeadSummary?,
        opponentUsername: String?,
        onChallenge: @escaping (Bool) -> Void,
        onPreviewRefreshed: @escaping (PetCombatPreview) -> Void
    ) {
        self.opponentUserId = opponentUserId
        self.preview = preview
        self.defenderPet = defenderPet
        self.headToHead = headToHead
        self.opponentUsername = opponentUsername
        self.onChallenge = onChallenge
        self.onPreviewRefreshed = onPreviewRefreshed
        _displayPreview = State(initialValue: preview)
    }

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

                    if let attacker = displayPreview.attacker,
                       let defender = displayPreview.defender,
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

                    if let energy = displayPreview.energy {
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

                    if isRefreshingPreview {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else if displayPreview.effectiveCanChallenge {
                        Button(action: handleChallengeTap) {
                            Label("Challenge Pet", systemImage: "bolt.horizontal.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    } else if let reason = displayPreview.blockReasonText {
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
                    isUnderdog: displayPreview.isAttackerUnderdog,
                    selectedMode: $selectedMode,
                    hardcoreBonusLabel: displayPreview.hardcoreBonusLabel,
                    onCancel: { showUnbalancedDialog = false },
                    onFight: confirmChallenge
                )
            }
        }
        .onAppear {
            selectedMode = PetCombatChallengeMode(rawValue: savedChallengeModeRaw) ?? .balanced
        }
        .task {
            await refreshPreview()
        }
    }

    private func refreshPreview() async {
        isRefreshingPreview = true
        defer { isRefreshingPreview = false }
        do {
            let fresh = try await PetService.shared.fetchCombatPreview(targetUserId: opponentUserId)
            displayPreview = fresh
            onPreviewRefreshed(fresh)
        } catch {
        }
    }

    private func handleChallengeTap() {
        if !displayPreview.isStatUnbalanced {
            dismiss()
            onChallenge(false)
            return
        }

        if skipPetCombatUnbalancedWarning && !displayPreview.isAttackerUnderdog {
            dismiss()
            onChallenge(false)
            return
        }

        selectedMode = resolvedSavedMode()
        dontShowAgain = false
        showUnbalancedDialog = true
    }

    private func confirmChallenge() {
        if dontShowAgain && !displayPreview.isAttackerUnderdog {
            skipPetCombatUnbalancedWarning = true
        }
        savedChallengeModeRaw = selectedMode.rawValue
        let disableNerf = displayPreview.isAttackerUnderdog && selectedMode.disableNerfChoice
        showUnbalancedDialog = false
        dismiss()
        onChallenge(disableNerf)
    }

    private func resolvedSavedMode() -> PetCombatChallengeMode {
        if displayPreview.isAttackerUnderdog {
            return PetCombatChallengeMode(rawValue: savedChallengeModeRaw) ?? .balanced
        }
        return .balanced
    }
}
