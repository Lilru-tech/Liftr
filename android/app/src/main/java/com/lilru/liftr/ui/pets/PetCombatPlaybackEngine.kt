package com.lilru.liftr.ui.pets

import com.lilru.liftr.data.PetBattleTurnWire
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

enum class PetCombatHitSide {
    Attacker,
    Defender
}

data class PetCombatStrikeEvent(
    val id: Int,
    val target: PetCombatHitSide,
    val damage: Int,
    val isCritical: Boolean,
    val isDodged: Boolean
)

class PetCombatPlaybackEngine(
    private val turns: List<PetBattleTurnWire>,
    attackerMaxHp: Int,
    defenderMaxHp: Int,
    private val turnDelayMs: Long = 1000L
) {
    val attackerMaxHp: Int = maxOf(attackerMaxHp, 1)
    val defenderMaxHp: Int = maxOf(defenderMaxHp, 1)

    private val _currentTurnIndex = MutableStateFlow(-1)
    val currentTurnIndex: StateFlow<Int> = _currentTurnIndex.asStateFlow()

    private val _currentMessage = MutableStateFlow("")
    val currentMessage: StateFlow<String> = _currentMessage.asStateFlow()

    private val _isPlaying = MutableStateFlow(false)
    val isPlaying: StateFlow<Boolean> = _isPlaying.asStateFlow()

    private val _isFinished = MutableStateFlow(false)
    val isFinished: StateFlow<Boolean> = _isFinished.asStateFlow()

    private val _hitSide = MutableStateFlow<PetCombatHitSide?>(null)
    val hitSide: StateFlow<PetCombatHitSide?> = _hitSide.asStateFlow()

    private val _lastStrike = MutableStateFlow<PetCombatStrikeEvent?>(null)
    val lastStrike: StateFlow<PetCombatStrikeEvent?> = _lastStrike.asStateFlow()

    private val _attackerCurrentHp = MutableStateFlow(this.attackerMaxHp)
    val attackerCurrentHp: StateFlow<Int> = _attackerCurrentHp.asStateFlow()

    private val _defenderCurrentHp = MutableStateFlow(this.defenderMaxHp)
    val defenderCurrentHp: StateFlow<Int> = _defenderCurrentHp.asStateFlow()

    suspend fun start() {
        if (turns.isEmpty()) {
            _isFinished.value = true
            return
        }
        _isPlaying.value = true
        _isFinished.value = false
        _currentTurnIndex.value = -1
        _currentMessage.value = ""
        _attackerCurrentHp.value = attackerMaxHp
        _defenderCurrentHp.value = defenderMaxHp

        turns.forEachIndexed { index, turn ->
            delay(turnDelayMs)
            _currentTurnIndex.value = index
            _currentMessage.value = turn.message
            _attackerCurrentHp.value = turn.attackerHpAfter
            _defenderCurrentHp.value = turn.defenderHpAfter
            val isDodged = turn.action == "dodge"
            val target = if (turn.actor == "attacker") PetCombatHitSide.Defender else PetCombatHitSide.Attacker
            _lastStrike.value = PetCombatStrikeEvent(
                id = index,
                target = target,
                damage = turn.damage,
                isCritical = turn.isCritical,
                isDodged = isDodged
            )
            if (!isDodged) {
                _hitSide.value = target
            }
            delay(250)
            _hitSide.value = null
        }

        _isPlaying.value = false
        _isFinished.value = true
    }
}
