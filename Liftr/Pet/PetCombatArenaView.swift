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
    @State private var attackerLungeOffset: CGFloat = 0
    @State private var defenderLungeOffset: CGFloat = 0
    @State private var attackerDodgeScale: CGFloat = 1
    @State private var defenderDodgeScale: CGFloat = 1
    @State private var critFlashOpacity: Double = 0

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 16) {
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
                        battleStage(for: combatResult, availableHeight: geo.size.height)
                        battleLogTicker(availableHeight: geo.size.height)

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
        .onChange(of: playbackEngine.lastStrike?.id) { _, _ in
            guard let strike = playbackEngine.lastStrike, !playbackEngine.isFinished else { return }
            if strike.isCritical && !strike.isDodged {
                animateCritFlash()
            }
            if !strike.isDodged {
                animateLunge(from: strikeActorSide(for: strike))
            }
        }
        .onChange(of: playbackEngine.dodgePulseSide) { _, side in
            guard let side else { return }
            animateDodgePulse(on: side)
        }
    }

    private func strikeActorSide(for strike: PetCombatPlaybackEngine.PetCombatStrikeEvent) -> PetCombatPlaybackEngine.PetCombatHitSide {
        strike.target == .attacker ? .defender : .attacker
    }

    private var totalTurns: Int {
        if let total = combatResult?.battleLog.result.totalTurns, total > 0 {
            return total
        }
        return combatResult?.battleLog.turns.count ?? 0
    }

    private var arenaHeader: some View {
        HStack(alignment: .top) {
            if let preview, let energy = preview.energy {
                Label("\(energy.current)/\(energy.max)", systemImage: "bolt.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            Spacer()
            if playbackEngine.isPlaying {
                PetCombatTurnProgress(
                    currentTurn: playbackEngine.currentTurnIndex + 1,
                    totalTurns: totalTurns
                )
            } else if playbackEngine.isFinished {
                Text("Battle complete")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func battleStage(for result: PetCombatResult, availableHeight: CGFloat) -> some View {
        ZStack {
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.18),
                            Color.white.opacity(0.04),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 8,
                        endRadius: 140
                    )
                )
                .frame(height: 48)
                .offset(y: 52)

            if critFlashOpacity > 0 {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.orange.opacity(critFlashOpacity))
                    .allowsHitTesting(false)
            }

            HStack(alignment: .bottom, spacing: 24) {
                petSprite(
                    snapshot: result.battleLog.attackerPet,
                    alignment: .leading,
                    hitOffset: attackerHitOffset,
                    lungeOffset: attackerLungeOffset,
                    dodgeScale: attackerDodgeScale,
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
                    hitOffset: defenderHitOffset,
                    lungeOffset: defenderLungeOffset,
                    dodgeScale: defenderDodgeScale,
                    flipped: true,
                    isAttacker: false,
                    result: result
                )
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 28)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: min(availableHeight * 0.34, 280))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func petSprite(
        snapshot: PetBattlePetSnapshot,
        alignment: HorizontalAlignment,
        hitOffset: CGFloat,
        lungeOffset: CGFloat,
        dodgeScale: CGFloat,
        flipped: Bool,
        isAttacker: Bool,
        result: PetCombatResult
    ) -> some View {
        let currentHp = isAttacker ? playbackEngine.attackerCurrentHp : playbackEngine.defenderCurrentHp
        let maxHp = isAttacker ? playbackEngine.attackerMaxHp : playbackEngine.defenderMaxHp
        let side: PetCombatPlaybackEngine.PetCombatHitSide = isAttacker ? .attacker : .defender
        let isActive = playbackEngine.activeActor == side && playbackEngine.isPlaying

        VStack(spacing: 6) {
            if playbackEngine.isFinished, let badge = outcomeBadge(for: snapshot, in: result) {
                PetCombatOutcomeBadge(style: badge)
                    .transition(.scale.combined(with: .opacity))
            }

            ZStack {
                if isActive {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.orange.opacity(0.35),
                                    Color.orange.opacity(0.08),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 4,
                                endRadius: 68
                            )
                        )
                        .frame(width: 136, height: 136)
                        .offset(y: -8)
                        .opacity(isActive ? 1 : 0)
                        .animation(.easeOut(duration: 0.2), value: isActive)
                }

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
                .scaleEffect(x: (flipped ? -1 : 1) * dodgeScale, y: dodgeScale)
                .offset(x: hitOffset + lungeOffset)
                .animation(.easeOut(duration: 0.15), value: dodgeScale)
                .animation(.easeOut(duration: 0.18), value: lungeOffset)
                .animation(.default.repeatCount(3, autoreverses: true), value: hitOffset)

                if let strike = playbackEngine.lastStrike,
                   !playbackEngine.isFinished,
                   strike.target == side {
                    PetCombatDamagePopup(event: strike)
                        .id(strike.id)
                }
            }
            .frame(width: 120, height: 120)

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

    private func battleLogTicker(availableHeight: CGFloat) -> some View {
        let logHeight = logHeight(for: availableHeight)
        return ScrollViewReader { proxy in
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
            .frame(minHeight: 136, maxHeight: logHeight)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onChange(of: playbackEngine.currentTurnIndex) { _, index in
                withAnimation {
                    proxy.scrollTo(index, anchor: .bottom)
                }
            }
        }
    }

    private func logHeight(for availableHeight: CGFloat) -> CGFloat {
        let ratio: CGFloat = playbackEngine.isFinished ? 0.3825 : 0.34
        return max(136, availableHeight * ratio)
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
            attackerHitOffset = amplitude
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                attackerHitOffset = 0
            }
        case .defender:
            defenderHitOffset = -amplitude
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                defenderHitOffset = 0
            }
        }
    }

    private func animateLunge(from side: PetCombatPlaybackEngine.PetCombatHitSide) {
        let amplitude: CGFloat = 12
        switch side {
        case .attacker:
            attackerLungeOffset = amplitude
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                attackerLungeOffset = 0
            }
        case .defender:
            defenderLungeOffset = -amplitude
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                defenderLungeOffset = 0
            }
        }
    }

    private func animateDodgePulse(on side: PetCombatPlaybackEngine.PetCombatHitSide) {
        switch side {
        case .attacker:
            attackerDodgeScale = 1.06
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                attackerDodgeScale = 1
            }
        case .defender:
            defenderDodgeScale = 1.06
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                defenderDodgeScale = 1
            }
        }
    }

    private func animateCritFlash() {
        withAnimation(.easeOut(duration: 0.12)) {
            critFlashOpacity = 0.15
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.easeIn(duration: 0.28)) {
                critFlashOpacity = 0
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
