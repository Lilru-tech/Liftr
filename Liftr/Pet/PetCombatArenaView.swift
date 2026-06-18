import SwiftUI

struct PetCombatArenaView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var app: AppState
    let opponentUserId: UUID
    let preview: PetCombatPreview?
    let disableNerfChoice: Bool

    @State private var combatResult: PetCombatResult?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var playbackEngine = PetCombatPlaybackEngine(turns: [], attackerMaxHp: 1, defenderMaxHp: 1)
    @State private var attackerHitOffset: CGFloat = 0
    @State private var defenderHitOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 20) {
                    arenaHeader

                    if isLoading {
                        ProgressView("Starting battle…")
                            .frame(maxWidth: .infinity, minHeight: 240)
                    } else if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding()
                    } else if let combatResult {
                        battleStage(for: combatResult)
                        battleLogTicker

                        if playbackEngine.isFinished, let userId = app.userId {
                            PetCombatVictoryCard(
                                result: combatResult,
                                currentUserId: userId,
                                onDismiss: {
                                    PetRefreshCenter.notifyPetStateDidChange()
                                    Task { await CoinManager.shared.refreshBalance() }
                                    dismiss()
                                }
                            )
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
        }
        .gradientBG()
        .navigationTitle("Pet Arena")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await startCombat()
        }
        .onChange(of: playbackEngine.hitSide) { _, side in
            guard let side else { return }
            animateHit(on: side)
        }
    }

    private var arenaHeader: some View {
        HStack {
            if let preview, let energy = preview.energy {
                Label("\(energy.current)/\(energy.max)", systemImage: "bolt.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            Spacer()
            if playbackEngine.isPlaying {
                Text("Battle in progress")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if playbackEngine.isFinished {
                Text("Battle complete")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func battleStage(for result: PetCombatResult) -> some View {
        HStack(alignment: .bottom, spacing: 24) {
            petSprite(
                snapshot: result.battleLog.attackerPet,
                alignment: .leading,
                offset: attackerHitOffset,
                flipped: false,
                isAttacker: true,
                result: result
            )
            Text("VS")
                .font(.headline.weight(.black))
                .foregroundStyle(.secondary)
            petSprite(
                snapshot: result.battleLog.defenderPet,
                alignment: .trailing,
                offset: defenderHitOffset,
                flipped: true,
                isAttacker: false,
                result: result
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func petSprite(
        snapshot: PetBattlePetSnapshot,
        alignment: HorizontalAlignment,
        offset: CGFloat,
        flipped: Bool,
        isAttacker: Bool,
        result: PetCombatResult
    ) -> some View {
        let currentHp = isAttacker ? playbackEngine.attackerCurrentHp : playbackEngine.defenderCurrentHp
        let maxHp = isAttacker ? playbackEngine.attackerMaxHp : playbackEngine.defenderMaxHp

        VStack(spacing: 8) {
            ZStack(alignment: .top) {
                AsyncImage(url: snapshot.imageURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(width: 120, height: 120)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(width: 120, height: 120)
                    case .failure:
                        Image(systemName: "pawprint.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                            .frame(width: 120, height: 120)
                    @unknown default:
                        EmptyView()
                    }
                }
                .scaleEffect(x: flipped ? -1 : 1, y: 1)
                .offset(x: offset)

                if let strike = playbackEngine.lastStrike,
                   !playbackEngine.isFinished,
                   strike.target == (isAttacker ? .attacker : .defender) {
                    PetCombatDamagePopup(event: strike)
                        .id(strike.id)
                }

                if playbackEngine.isFinished, let badge = outcomeBadge(for: snapshot, in: result) {
                    PetCombatOutcomeBadge(style: badge)
                        .offset(y: -8)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            Text(snapshot.name)
                .font(.caption.weight(.semibold))
                .lineLimit(1)

            PetCombatHpBar(current: currentHp, maxHp: maxHp)
                .frame(maxWidth: 110)

            Text("Lv. \(snapshot.level)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .bottom))
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: playbackEngine.isFinished)
    }

    private func outcomeBadge(for snapshot: PetBattlePetSnapshot, in result: PetCombatResult) -> PetCombatOutcomeBadge.Style? {
        if result.battleLog.result.isDraw {
            return .draw
        }
        guard let winnerUserId = result.winnerUserId else { return nil }
        if snapshot.userId == winnerUserId {
            return .victory
        }
        return .defeat
    }

    private var battleLogTicker: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    let revealedTurns = (combatResult?.battleLog.turns ?? []).prefix(max(playbackEngine.currentTurnIndex + 1, 0))
                    if revealedTurns.isEmpty {
                        Text("The battle begins!")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(Array(revealedTurns.enumerated()), id: \.offset) { index, turn in
                        Text(turn.message)
                            .font(.caption)
                            .foregroundStyle(logColor(for: turn))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(index)
                            .transition(.opacity)
                    }
                }
                .padding(12)
            }
            .frame(height: 125)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onChange(of: playbackEngine.currentTurnIndex) { _, index in
                withAnimation {
                    proxy.scrollTo(index, anchor: .bottom)
                }
            }
        }
    }

    private func logColor(for turn: PetBattleTurn) -> Color {
        if turn.action == "dodge" {
            return Color(red: 0.38, green: 0.55, blue: 0.85)
        }
        guard let myUserId = app.userId, let result = combatResult else { return .primary }
        let iAmAttacker = result.battleLog.attackerPet.userId == myUserId
        let isMyStrike = (turn.actor == "attacker") == iAmAttacker
        return isMyStrike
            ? Color(red: 0.32, green: 0.65, blue: 0.42)
            : Color(red: 0.85, green: 0.41, blue: 0.41)
    }

    private func animateHit(on side: PetCombatPlaybackEngine.PetCombatHitSide) {
        let amplitude: CGFloat = 10
        switch side {
        case .attacker:
            withAnimation(.default.repeatCount(3, autoreverses: true)) {
                attackerHitOffset = amplitude
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                attackerHitOffset = 0
            }
        case .defender:
            withAnimation(.default.repeatCount(3, autoreverses: true)) {
                defenderHitOffset = -amplitude
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                defenderHitOffset = 0
            }
        }
    }

    private func startCombat() async {
        isLoading = true
        errorMessage = nil
        do {
            let result = try await PetService.shared.executeCombat(
                targetOpponentUserId: opponentUserId,
                disableNerfChoice: disableNerfChoice
            )
            combatResult = result
            let attackerMax = result.battleLog.attackerPet.resolvedMaxHp(
                fallback: preview?.attacker?.stats?.health ?? 1
            )
            let defenderMax = result.battleLog.defenderPet.resolvedMaxHp(
                fallback: preview?.defender?.stats?.health ?? 1
            )
            playbackEngine = PetCombatPlaybackEngine(
                turns: result.battleLog.turns,
                attackerMaxHp: attackerMax,
                defenderMaxHp: defenderMax,
                turnDelayMilliseconds: 1000
            )
            isLoading = false
            await playbackEngine.start()
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}
