package com.lilru.liftr.ui.pets

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.lilru.liftr.data.PetRefreshBus
import com.lilru.liftr.prefs.LiftrPreferences
import com.lilru.liftr.ui.common.marginPx
import com.lilru.liftr.ui.common.petGreetingBubbleOrigin
import io.github.jan.supabase.SupabaseClient
import androidx.compose.foundation.layout.widthIn
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.unit.IntSize
import kotlin.math.hypot
import kotlin.math.roundToInt
import kotlinx.coroutines.delay

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProfilePetFloatingOverlay(
    supabase: SupabaseClient,
    bottomInsetDp: Int,
    modifier: Modifier = Modifier,
    onOpenMarket: (() -> Unit)? = null
) {
    val context = LocalContext.current
    val density = LocalDensity.current
    val vm: PetViewModel = viewModel(factory = PetViewModelFactory(supabase))
    val ui by vm.uiState.collectAsStateWithLifecycle()
    var showSheet by remember { mutableStateOf(false) }
    var showGreeting by remember { mutableStateOf(false) }
    var greetingMessage by remember { mutableStateOf("") }
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    val legacy = remember(context) { LiftrPreferences.profilePetFabLegacyNormalizedCenter(context) }
    var perimeterT by remember(context) {
        mutableFloatStateOf(LiftrPreferences.profilePetFabPerimeterT(context) ?: -1f)
    }
    var dragPreviewPoint by remember { mutableStateOf<Offset?>(null) }
    var greetingBubbleSize by remember { mutableStateOf(IntSize.Zero) }

    LaunchedEffect(Unit) {
        vm.load()
        vm.startPollingIfNeeded()
        PetRefreshBus.events.collect {
            vm.load()
            vm.reloadLogs()
            vm.startPollingIfNeeded()
        }
    }

    DisposableEffect(Unit) {
        onDispose { vm.stopPolling() }
    }

    val pet = ui.data?.pet ?: return

    LaunchedEffect(pet.id) {
        greetingMessage = PetProfileGreetings.randomOwnProfileMessage()
        showGreeting = true
        delay(5000)
        showGreeting = false
    }

    val tapThresholdPx = with(density) { 10.dp.toPx() }

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
            legacyX = legacy?.first,
            legacyY = legacy?.second,
            bounds = bounds
        )
        val anchor = dragPreviewPoint ?: ProfilePetFabPosition.pointOnPerimeter(resolvedT, bounds)
        val fabRadiusPx = with(density) { ProfilePetFabPosition.fabSize.toPx() } / 2f
        val verticalGapPx = with(density) { 8.dp.toPx() }
        val marginPx = density.marginPx()
        val positionX = (anchor.x - fabRadiusPx).roundToInt()
        val positionY = (anchor.y - fabRadiusPx).roundToInt()
        val bubbleWidthPx = if (greetingBubbleSize.width > 0) {
            greetingBubbleSize.width.toFloat()
        } else {
            widthPx - marginPx * 2f
        }
        val bubbleHeightPx = if (greetingBubbleSize.height > 0) {
            greetingBubbleSize.height.toFloat()
        } else {
            with(density) { 44.dp.toPx() }
        }
        val maxBubbleWidth = maxWidth - 24.dp
        val greetingOrigin = petGreetingBubbleOrigin(
            anchor = anchor,
            bubbleWidthPx = bubbleWidthPx,
            bubbleHeightPx = bubbleHeightPx,
            fabRadiusPx = fabRadiusPx,
            screenWidthPx = widthPx,
            screenHeightPx = heightPx,
            verticalGapPx = verticalGapPx,
            marginPx = marginPx
        )

        LaunchedEffect(bounds) {
            if (perimeterT < 0f) {
                perimeterT = resolvedT
            }
        }

        AnimatedVisibility(
            visible = showGreeting,
            enter = fadeIn() + scaleIn(),
            exit = fadeOut() + scaleOut(),
            modifier = Modifier.offset {
                IntOffset(greetingOrigin.x.roundToInt(), greetingOrigin.y.roundToInt())
            }
        ) {
            Surface(
                shape = MaterialTheme.shapes.medium,
                tonalElevation = 4.dp,
                modifier = Modifier
                    .widthIn(max = maxBubbleWidth)
                    .onGloballyPositioned { coordinates ->
                        val size = coordinates.size
                        if (size != greetingBubbleSize) {
                            greetingBubbleSize = size
                        }
                    }
            ) {
                Text(
                    text = greetingMessage,
                    modifier = Modifier.padding(8.dp),
                    style = MaterialTheme.typography.bodyMedium
                )
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
                        legacyX = legacy?.first,
                        legacyY = legacy?.second,
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
                                    showGreeting = false
                                    showSheet = true
                                } else {
                                    val snapped = livePreview
                                        ?: ProfilePetFabPosition.nearestPointOnPerimeter(
                                            startAnchor,
                                            gestureBounds
                                        )
                                    val newT = ProfilePetFabPosition.perimeterParameterFor(snapped, gestureBounds)
                                    perimeterT = newT
                                    LiftrPreferences.setProfilePetFabPerimeterT(context, newT)
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
                    .shadow(6.dp, CircleShape, spotColor = petRarityColor(pet.rarity).copy(alpha = 0.35f))
                    .clip(CircleShape)
                    .border(2.dp, petRarityColor(pet.rarity).copy(alpha = 0.7f), CircleShape),
                contentAlignment = Alignment.Center
            ) {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    shape = CircleShape,
                    color = MaterialTheme.colorScheme.surface.copy(alpha = 0.92f)
                ) {
                    PetAsyncImage(
                        pet = pet,
                        modifier = Modifier.fillMaxSize(),
                        size = ProfilePetFabPosition.fabSize,
                        contentPadding = 10.dp
                    )
                }
            }
    }

    if (showSheet) {
        ModalBottomSheet(
            onDismissRequest = {
                showSheet = false
                vm.load()
            },
            sheetState = sheetState
        ) {
            PetDetailScreen(
                vm = vm,
                supabase = supabase,
                onClose = {
                    showSheet = false
                    vm.load()
                },
                modifier = Modifier.fillMaxSize(),
                onOpenMarket = onOpenMarket?.let { openMarket ->
                    {
                        showSheet = false
                        vm.load()
                        openMarket()
                    }
                }
            )
        }
    }
}
