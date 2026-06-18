package com.lilru.liftr.ui.pets

import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import com.lilru.liftr.data.PetCombatHeadToHeadSummaryWire
import com.lilru.liftr.data.PetCombatPetSummaryWire
import com.lilru.liftr.data.PetCombatPreviewWire
import com.lilru.liftr.prefs.LiftrPreferences
import kotlin.math.hypot
import kotlin.math.roundToInt

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProfileOpponentPetFloatingOverlay(
    preview: PetCombatPreviewWire,
    defenderPet: PetCombatPetSummaryWire,
    headToHead: PetCombatHeadToHeadSummaryWire?,
    opponentUsername: String?,
    bottomInsetDp: Int,
    backgroundThemeId: String,
    onChallenge: () -> Unit,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val density = LocalDensity.current
    var showSheet by remember { mutableStateOf(false) }
    var perimeterT by remember(context) {
        mutableFloatStateOf(LiftrPreferences.profileOpponentPetFabPerimeterT(context) ?: -1f)
    }
    var dragPreviewPoint by remember { mutableStateOf<Offset?>(null) }

    val tapThresholdPx = with(density) { 10.dp.toPx() }
    val rarityColor = petRarityColor(defenderPet.rarity)

    BoxWithConstraints(modifier = modifier.fillMaxSize()) {
        val widthPx = with(density) { maxWidth.toPx() }
        val heightPx = with(density) { maxHeight.toPx() }
        val bounds = ProfilePetFabPosition.bounds(
            widthPx = widthPx,
            heightPx = heightPx,
            topInsetPx = 0f,
            bottomInsetPx = 0f,
            bottomInsetDp = bottomInsetDp,
            density = density
        )
        val resolvedT = ProfilePetFabPosition.resolvedPerimeterT(
            saved = perimeterT.takeIf { it >= 0f },
            legacyX = null,
            legacyY = null,
            bounds = bounds
        )
        val anchor = dragPreviewPoint ?: ProfilePetFabPosition.pointOnPerimeter(resolvedT, bounds)
        val fabRadiusPx = with(density) { ProfilePetFabPosition.fabSize.toPx() } / 2f
        val positionX = (anchor.x - fabRadiusPx).roundToInt()
        val positionY = (anchor.y - fabRadiusPx).roundToInt()

        androidx.compose.runtime.LaunchedEffect(bounds) {
            if (perimeterT < 0f) {
                perimeterT = resolvedT
            }
        }

        Box(
            modifier = Modifier
                .offset { IntOffset(positionX, positionY) }
                .size(ProfilePetFabPosition.fabSize)
                .pointerInput(perimeterT, bottomInsetDp, widthPx, heightPx, tapThresholdPx) {
                    val gestureBounds = ProfilePetFabPosition.bounds(
                        widthPx = widthPx,
                        heightPx = heightPx,
                        topInsetPx = 0f,
                        bottomInsetPx = 0f,
                        bottomInsetDp = bottomInsetDp,
                        density = this@pointerInput
                    )
                    val fabRadiusPx = ProfilePetFabPosition.fabSize.toPx() / 2f
                    val gestureResolvedT = ProfilePetFabPosition.resolvedPerimeterT(
                        saved = perimeterT.takeIf { it >= 0f },
                        legacyX = null,
                        legacyY = null,
                        bounds = gestureBounds
                    )
                    awaitEachGesture {
                        val down = awaitFirstDown(requireUnconsumed = false)
                        val pointerId = down.id
                        var isDragging = false
                        var livePreview: Offset? = null
                        val startAnchor = ProfilePetFabPosition.pointOnPerimeter(gestureResolvedT, gestureBounds)

                        while (true) {
                            val event = awaitPointerEvent()
                            val change = event.changes.firstOrNull { it.id == pointerId } ?: break
                            if (!change.pressed) {
                                dragPreviewPoint = null
                                if (!isDragging) {
                                    showSheet = true
                                } else {
                                    val snapped = livePreview
                                        ?: ProfilePetFabPosition.nearestPointOnPerimeter(
                                            startAnchor,
                                            gestureBounds
                                        )
                                    val newT = ProfilePetFabPosition.perimeterParameterFor(snapped, gestureBounds)
                                    perimeterT = newT
                                    LiftrPreferences.setProfileOpponentPetFabPerimeterT(context, newT)
                                }
                                break
                            }

                            val fingerLocal = change.position
                            if (!isDragging && hypot(fingerLocal.x - down.position.x, fingerLocal.y - down.position.y) >= tapThresholdPx) {
                                isDragging = true
                            }
                            if (isDragging) {
                                val snap = livePreview ?: startAnchor
                                val fingerGlobal = Offset(
                                    x = snap.x - fabRadiusPx + fingerLocal.x,
                                    y = snap.y - fabRadiusPx + fingerLocal.y
                                )
                                livePreview = ProfilePetFabPosition.nearestPointOnPerimeter(fingerGlobal, gestureBounds)
                                dragPreviewPoint = livePreview
                                change.consume()
                            }
                        }
                    }
                }
                .shadow(6.dp, CircleShape, spotColor = rarityColor.copy(alpha = 0.35f))
                .clip(CircleShape)
                .border(2.dp, rarityColor.copy(alpha = 0.7f), CircleShape)
        ) {
            Surface(
                modifier = Modifier.fillMaxSize(),
                shape = CircleShape,
                color = MaterialTheme.colorScheme.surface.copy(alpha = 0.92f)
            ) {
                PetCombatSummaryImage(
                    pet = defenderPet,
                    modifier = Modifier.fillMaxSize(),
                    height = ProfilePetFabPosition.fabSize,
                    contentPadding = 10.dp
                )
            }
        }
    }

    if (showSheet) {
        OpponentPetChallengeSheet(
            preview = preview,
            defenderPet = defenderPet,
            headToHead = headToHead,
            opponentUsername = opponentUsername,
            backgroundThemeId = backgroundThemeId,
            onDismiss = { showSheet = false },
            onChallenge = onChallenge
        )
    }
}
