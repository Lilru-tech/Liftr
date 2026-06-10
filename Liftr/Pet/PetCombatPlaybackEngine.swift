import Foundation
import Observation

@MainActor
@Observable
final class PetCombatPlaybackEngine {
    private(set) var currentTurnIndex: Int = -1
    private(set) var currentMessage: String = ""
    private(set) var isPlaying = false
    private(set) var isFinished = false
    private(set) var hitSide: PetCombatHitSide?
    private(set) var lastStrike: PetCombatStrikeEvent?
    private(set) var attackerCurrentHp: Int
    private(set) var defenderCurrentHp: Int
    let attackerMaxHp: Int
    let defenderMaxHp: Int

    enum PetCombatHitSide {
        case attacker
        case defender
    }

    struct PetCombatStrikeEvent: Equatable, Identifiable {
        let id: Int
        let target: PetCombatHitSide
        let damage: Int
        let isCritical: Bool
        let isDodged: Bool
    }

    private let turns: [PetBattleTurn]
    private let turnDelayNanoseconds: UInt64

    init(
        turns: [PetBattleTurn],
        attackerMaxHp: Int,
        defenderMaxHp: Int,
        turnDelayMilliseconds: Int = 1000
    ) {
        self.turns = turns
        self.attackerMaxHp = max(attackerMaxHp, 1)
        self.defenderMaxHp = max(defenderMaxHp, 1)
        self.attackerCurrentHp = self.attackerMaxHp
        self.defenderCurrentHp = self.defenderMaxHp
        self.turnDelayNanoseconds = UInt64(turnDelayMilliseconds) * 1_000_000
    }

    func start() async {
        guard !turns.isEmpty else {
            isFinished = true
            return
        }

        isPlaying = true
        isFinished = false
        currentTurnIndex = -1
        currentMessage = ""
        attackerCurrentHp = attackerMaxHp
        defenderCurrentHp = defenderMaxHp

        for (index, turn) in turns.enumerated() {
            try? await Task.sleep(nanoseconds: turnDelayNanoseconds)
            currentTurnIndex = index
            currentMessage = turn.message
            attackerCurrentHp = turn.attackerHpAfter
            defenderCurrentHp = turn.defenderHpAfter
            let isDodged = turn.action == "dodge"
            let target: PetCombatHitSide = turn.actor == "attacker" ? .defender : .attacker
            lastStrike = PetCombatStrikeEvent(
                id: index,
                target: target,
                damage: turn.damage,
                isCritical: turn.isCritical,
                isDodged: isDodged
            )
            if !isDodged {
                hitSide = target
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
            hitSide = nil
        }

        isPlaying = false
        isFinished = true
    }
}
