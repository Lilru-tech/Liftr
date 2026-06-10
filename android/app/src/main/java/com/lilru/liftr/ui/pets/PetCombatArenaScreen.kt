package com.lilru.liftr.ui.pets

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.scaleIn
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.lilru.liftr.data.PetBattlePetSnapshotWire
import com.lilru.liftr.data.PetBattleTurnWire
import com.lilru.liftr.data.PetCombatPreviewWire
import com.lilru.liftr.data.PetCombatResultWire
import com.lilru.liftr.data.PetRefreshBus
import com.lilru.liftr.data.PetService
import com.lilru.liftr.ui.theme.liftrAppBackgroundGradient
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PetCombatArenaScreen(
    supabase: SupabaseClient,
    opponentUserId: String,
    preview: PetCombatPreviewWire?,
    backgroundThemeId: String,
    onBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    var combatResult by remember { mutableStateOf<PetCombatResultWire?>(null) }
    var isLoading by remember { mutableStateOf(true) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var playbackEngine by remember { mutableStateOf<PetCombatPlaybackEngine?>(null) }
    var attackerOffset by remember { mutableFloatStateOf(0f) }
    var defenderOffset by remember { mutableFloatStateOf(0f) }
    val meId = supabase.auth.currentUserOrNull()?.id
    val scrollState = rememberScrollState()
    val stubTurnIndex = remember { MutableStateFlow(-1) }
    val stubFinished = remember { MutableStateFlow(false) }
    val stubPlaying = remember { MutableStateFlow(false) }
    val stubHitSide = remember { MutableStateFlow<PetCombatHitSide?>(null) }
    val stubStrike = remember { MutableStateFlow<PetCombatStrikeEvent?>(null) }
    val stubAttackerHp = remember { MutableStateFlow(1) }
    val stubDefenderHp = remember { MutableStateFlow(1) }

    val engine = playbackEngine
    val currentTurnIndex by (engine?.currentTurnIndex ?: stubTurnIndex).collectAsState()
    val isFinished by (engine?.isFinished ?: stubFinished).collectAsState()
    val isPlaying by (engine?.isPlaying ?: stubPlaying).collectAsState()
    val hitSide by (engine?.hitSide ?: stubHitSide).collectAsState()
    val lastStrike by (engine?.lastStrike ?: stubStrike).collectAsState()
    val attackerCurrentHp by (engine?.attackerCurrentHp ?: stubAttackerHp).collectAsState()
    val defenderCurrentHp by (engine?.defenderCurrentHp ?: stubDefenderHp).collectAsState()
    val attackerMaxHp = engine?.attackerMaxHp ?: 1
    val defenderMaxHp = engine?.defenderMaxHp ?: 1

    LaunchedEffect(hitSide) {
        when (hitSide) {
            PetCombatHitSide.Attacker -> {
                attackerOffset = 10f
                delay(450)
                attackerOffset = 0f
            }
            PetCombatHitSide.Defender -> {
                defenderOffset = -10f
                delay(450)
                defenderOffset = 0f
            }
            null -> Unit
        }
    }

    LaunchedEffect(opponentUserId) {
        isLoading = true
        errorMessage = null
        playbackEngine = null
        runCatching { PetService.executeCombat(supabase, opponentUserId) }
            .onSuccess { result ->
                combatResult = result
                val attackerMax = result.battleLog.attackerPet.resolvedMaxHp(
                    fallback = preview?.attacker?.stats?.health ?: 1
                )
                val defenderMax = result.battleLog.defenderPet.resolvedMaxHp(
                    fallback = preview?.defender?.stats?.health ?: 1
                )
                val engine = PetCombatPlaybackEngine(
                    turns = result.battleLog.turns,
                    attackerMaxHp = attackerMax,
                    defenderMaxHp = defenderMax
                )
                playbackEngine = engine
                isLoading = false
                engine.start()
            }
            .onFailure {
                errorMessage = it.message
                isLoading = false
            }
    }

    Box(
        modifier = modifier
            .fillMaxSize()
            .liftrAppBackgroundGradient(backgroundThemeId)
    ) {
        Scaffold(
            containerColor = Color.Transparent,
            topBar = {
                TopAppBar(
                    title = { Text("Pet Arena") },
                    navigationIcon = {
                        IconButton(onClick = onBack) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                        }
                    }
                )
            }
        ) { padding ->
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .verticalScroll(scrollState)
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically)
            ) {
                Row(modifier = Modifier.fillMaxWidth()) {
                    preview?.energy?.let { energy ->
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Filled.Bolt, contentDescription = null, tint = Color(0xFFFF9800))
                            Text("${energy.current}/${energy.max}", fontWeight = FontWeight.SemiBold)
                        }
                    }
                    Spacer(modifier = Modifier.weight(1f))
                    Text(
                        when {
                            isPlaying -> "Battle in progress"
                            isFinished -> "Battle complete"
                            else -> ""
                        },
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }

                when {
                    isLoading -> {
                        Box(
                            Modifier
                                .fillMaxWidth()
                                .height(240.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            CircularProgressIndicator()
                        }
                    }
                    errorMessage != null -> {
                        Text(errorMessage.orEmpty(), color = MaterialTheme.colorScheme.error)
                    }
                    combatResult != null -> {
                        val result = combatResult!!
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceEvenly,
                            verticalAlignment = Alignment.Bottom
                        ) {
                            CombatPetSprite(
                                imageUrl = result.battleLog.attackerPet.imageUrl
                                    ?: PetService.petImageUrl(
                                        result.battleLog.attackerPet.petType,
                                        result.battleLog.attackerPet.evolutionStage
                                    ),
                                name = result.battleLog.attackerPet.name,
                                level = result.battleLog.attackerPet.level,
                                currentHp = attackerCurrentHp,
                                maxHp = attackerMaxHp,
                                offsetX = attackerOffset,
                                flipped = false,
                                strike = lastStrike?.takeIf {
                                    !isFinished && it.target == PetCombatHitSide.Attacker
                                },
                                outcomeBadge = if (isFinished) {
                                    outcomeBadgeStyle(result.battleLog.attackerPet, result)
                                } else {
                                    null
                                }
                            )
                            Text("VS", fontWeight = FontWeight.Black, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            CombatPetSprite(
                                imageUrl = result.battleLog.defenderPet.imageUrl
                                    ?: PetService.petImageUrl(
                                        result.battleLog.defenderPet.petType,
                                        result.battleLog.defenderPet.evolutionStage
                                    ),
                                name = result.battleLog.defenderPet.name,
                                level = result.battleLog.defenderPet.level,
                                currentHp = defenderCurrentHp,
                                maxHp = defenderMaxHp,
                                offsetX = defenderOffset,
                                flipped = true,
                                strike = lastStrike?.takeIf {
                                    !isFinished && it.target == PetCombatHitSide.Defender
                                },
                                outcomeBadge = if (isFinished) {
                                    outcomeBadgeStyle(result.battleLog.defenderPet, result)
                                } else {
                                    null
                                }
                            )
                        }

                        val logScrollState = rememberScrollState()
                        val revealedTurns = result.battleLog.turns.take(currentTurnIndex + 1)
                        val iAmAttacker = result.battleLog.attackerPet.userId == meId
                        LaunchedEffect(revealedTurns.size) {
                            logScrollState.animateScrollTo(logScrollState.maxValue)
                        }
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(125.dp)
                                .background(
                                    MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f),
                                    RoundedCornerShape(12.dp)
                                )
                                .padding(12.dp)
                                .verticalScroll(logScrollState),
                            verticalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            if (revealedTurns.isEmpty()) {
                                Text(
                                    "The battle begins!",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                            revealedTurns.forEach { turn ->
                                Text(
                                    turn.message,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = combatLogColor(turn, iAmAttacker)
                                )
                            }
                        }

                        if (isFinished && meId != null) {
                            PetCombatVictoryCard(
                                result = result,
                                currentUserId = meId,
                                onDismiss = {
                                    PetRefreshBus.notifyPetStateDidChange()
                                    onBack()
                                },
                                modifier = Modifier.fillMaxWidth()
                            )
                        }
                    }
                }
            }
        }
    }
}

private enum class PetCombatOutcomeStyle {
    Victory,
    Defeat,
    Draw
}

private val CombatLogGreen = Color(0xFF52A66B)
private val CombatLogRed = Color(0xFFD96A6A)
private val CombatLogBlue = Color(0xFF6A8FD9)

private fun combatLogColor(turn: PetBattleTurnWire, iAmAttacker: Boolean): Color {
    if (turn.action == "dodge") return CombatLogBlue
    val isMyStrike = (turn.actor == "attacker") == iAmAttacker
    return if (isMyStrike) CombatLogGreen else CombatLogRed
}

private fun outcomeBadgeStyle(
    snapshot: PetBattlePetSnapshotWire,
    result: PetCombatResultWire
): PetCombatOutcomeStyle? {
    if (result.battleLog.result.isDraw) return PetCombatOutcomeStyle.Draw
    val winnerUserId = result.winnerUserId ?: return null
    return if (snapshot.userId == winnerUserId) {
        PetCombatOutcomeStyle.Victory
    } else {
        PetCombatOutcomeStyle.Defeat
    }
}

@Composable
private fun CombatPetSprite(
    imageUrl: String,
    name: String,
    level: Int,
    currentHp: Int,
    maxHp: Int,
    offsetX: Float,
    flipped: Boolean,
    strike: PetCombatStrikeEvent?,
    outcomeBadge: PetCombatOutcomeStyle?
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier.width(120.dp)
    ) {
        Box(contentAlignment = Alignment.TopCenter) {
            AsyncImage(
                model = imageUrl,
                contentDescription = null,
                modifier = Modifier
                    .height(120.dp)
                    .offset(x = offsetX.dp)
                    .graphicsLayer(scaleX = if (flipped) -1f else 1f)
            )
            strike?.let {
                key(it.id) {
                    CombatDamagePopup(event = it)
                }
            }
            androidx.compose.animation.AnimatedVisibility(
                visible = outcomeBadge != null,
                enter = fadeIn() + scaleIn()
            ) {
                outcomeBadge?.let {
                    PetCombatOutcomeBadge(
                        style = it,
                        modifier = Modifier.offset(y = (-8).dp)
                    )
                }
            }
        }
        Text(
            name,
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.SemiBold,
            maxLines = 1
        )
        PetCombatHpBar(
            current = currentHp,
            max = maxHp,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 4.dp, vertical = 4.dp)
        )
        Text("Lv. $level", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun CombatDamagePopup(event: PetCombatStrikeEvent) {
    var started by remember { mutableStateOf(false) }
    val offsetY by animateFloatAsState(
        targetValue = if (started) -34f else 4f,
        animationSpec = tween(durationMillis = 800, easing = FastOutSlowInEasing),
        label = "damageOffset"
    )
    val alpha by animateFloatAsState(
        targetValue = if (started) 0f else 1f,
        animationSpec = tween(durationMillis = 300, delayMillis = 500),
        label = "damageAlpha"
    )
    LaunchedEffect(Unit) { started = true }

    val (label, color) = when {
        event.isDodged -> "Dodged!" to CombatLogBlue
        event.isCritical -> "${event.damage}!" to Color(0xFFFF9800)
        else -> "-${event.damage}" to Color(0xFFE54848)
    }

    Text(
        text = label,
        fontWeight = FontWeight.Black,
        fontSize = if (event.isCritical) 22.sp else 17.sp,
        color = color,
        modifier = Modifier
            .offset(y = offsetY.dp)
            .graphicsLayer(alpha = alpha)
    )
}

@Composable
private fun PetCombatOutcomeBadge(
    style: PetCombatOutcomeStyle,
    modifier: Modifier = Modifier
) {
    val (label, background, foreground) = when (style) {
        PetCombatOutcomeStyle.Victory -> Triple("Victory", Color(0xFFFACC15).copy(alpha = 0.95f), Color(0xFF713F12))
        PetCombatOutcomeStyle.Defeat -> Triple("Defeat", Color.White.copy(alpha = 0.22f), MaterialTheme.colorScheme.onSurfaceVariant)
        PetCombatOutcomeStyle.Draw -> Triple("Draw", Color(0xFFFF9800).copy(alpha = 0.85f), Color.White)
    }
    Text(
        text = label,
        modifier = modifier
            .background(background, RoundedCornerShape(50))
            .padding(horizontal = 10.dp, vertical = 5.dp),
        style = MaterialTheme.typography.labelSmall,
        fontWeight = FontWeight.Bold,
        color = foreground
    )
}

@Composable
fun PetCombatVictoryCard(
    result: PetCombatResultWire,
    currentUserId: String,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier
) {
    val didWin = result.winnerUserId == currentUserId
    val rewards = result.attackerRewards
    Row(
        modifier = modifier
            .background(
                MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f),
                RoundedCornerShape(12.dp)
            )
            .padding(12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                when {
                    result.battleLog.result.isDraw -> "Draw"
                    didWin -> "Victory"
                    else -> "Defeat"
                },
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.Bold
            )
            if (rewards.xp > 0 || rewards.coins > 0) {
                Text(
                    "+${rewards.xp} XP · +${rewards.coins} coins",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            } else {
                Text(
                    "No rewards this time.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            result.energy?.let {
                Text(
                    "Energy ${it.current}/${it.max}",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
        Button(onClick = onDismiss) {
            Text("Done")
        }
    }
}
