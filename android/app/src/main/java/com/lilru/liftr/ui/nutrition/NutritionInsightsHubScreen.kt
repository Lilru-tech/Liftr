package com.lilru.liftr.ui.nutrition

import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.TrendingUp
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.lilru.liftr.R
import com.lilru.liftr.prefs.LiftrPreferences
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.lilru.liftr.data.PremiumStatusStore
import com.lilru.liftr.ui.components.LiftrBackTopBar
import com.lilru.liftr.ui.components.LiftrBannerAd
import com.lilru.liftr.ui.components.LiftrFilterPillRow
import com.lilru.liftr.ui.components.LiftrGlassSurface
import com.lilru.liftr.ui.components.LiftrPillSelectedStyle
import com.lilru.liftr.ui.components.LiftrSectionCard
import com.lilru.liftr.ui.theme.liftrAppBackgroundGradientOpaque
import dev.chrisbanes.haze.HazeState
import kotlinx.coroutines.launch

private enum class NutritionInsightsHubTab {
    COACH,
    HIGHLIGHTS
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NutritionInsightsHubScreen(
    vm: NutritionViewModel,
    hazeState: HazeState,
    onBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    val ui by vm.uiState.collectAsState()
    val isPremium by PremiumStatusStore.isPremium.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val theme = remember { LiftrPreferences.backgroundTheme(context) }
    val scope = rememberCoroutineScope()
    var selectedTabIndex by rememberSaveable { mutableIntStateOf(0) }
    var rankingOverlay by remember { mutableStateOf<NutritionRankingKind?>(null) }
    val tabs = NutritionInsightsHubTab.entries
    val tabLabels = listOf(
        stringResource(R.string.nutrition_insights_tab_coach),
        stringResource(R.string.nutrition_insights_tab_highlights)
    )
    val listState = rememberLazyListState()

    if (rankingOverlay != null) {
        NutritionRankingDetailScreen(
            vm = vm,
            kind = rankingOverlay!!,
            onBack = {
                vm.resetRanking()
                rankingOverlay = null
            },
            modifier = modifier
        )
        return
    }

    val showCoachResults = ui.smartInsightsLoading || ui.smartInsights != null || ui.smartInsightsError != null

    DisposableEffect(Unit) {
        onDispose {
            vm.resetSmartInsights()
            vm.resetHighlights()
            vm.resetRanking()
        }
    }

    LaunchedEffect(selectedTabIndex) {
        if (tabs[selectedTabIndex] == NutritionInsightsHubTab.HIGHLIGHTS &&
            ui.highlights == null &&
            !ui.highlightsLoading &&
            ui.highlightsError == null
        ) {
            vm.loadHighlights()
        }
    }

    Box(modifier = modifier.fillMaxSize()) {
        Column(
            Modifier
                .fillMaxSize()
                .liftrAppBackgroundGradientOpaque(theme)
        ) {
            LiftrBackTopBar(
                title = stringResource(R.string.nutrition_insights_hub_title),
                onBack = onBack
            )
            LiftrFilterPillRow(
                labels = tabLabels,
                selectedIndex = selectedTabIndex,
                onSelected = { selectedTabIndex = it },
                hazeState = hazeState,
                selectedStyle = LiftrPillSelectedStyle.IosWhite,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp)
            )
            LazyColumn(
                state = listState,
                modifier = Modifier.weight(1f).fillMaxWidth(),
                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                when (tabs[selectedTabIndex]) {
                    NutritionInsightsHubTab.COACH -> {
                        item {
                            Text(
                                stringResource(R.string.nutrition_insights_hub_subtitle),
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                        item {
                            LiftrSectionCard(hazeState = hazeState) {
                                NutritionInsightsRangeCard(
                                    ui = ui,
                                    vm = vm,
                                    onAnalyze = {
                                        vm.analyzeSmartInsights()
                                        scope.launch {
                                            kotlinx.coroutines.delay(100)
                                            val resultsIndex = listState.layoutInfo.totalItemsCount - 1
                                            if (resultsIndex >= 0) {
                                                listState.animateScrollToItem(resultsIndex)
                                            }
                                        }
                                    }
                                )
                            }
                        }
                        if (showCoachResults) {
                            item {
                                NutritionSmartInsightsInlineContent(ui = ui)
                            }
                        }
                    }
                    NutritionInsightsHubTab.HIGHLIGHTS -> {
                        item {
                            Text(
                                stringResource(R.string.nutrition_highlights_hub_subtitle),
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                        item {
                            NutritionHighlightsContent(
                                ui = ui,
                                hazeState = hazeState,
                                onRankingClick = { kind -> rankingOverlay = kind }
                            )
                        }
                    }
                }
            }
            if (!isPremium) {
                LiftrBannerAd(horizontalPadding = 4.dp)
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NutritionInsightsEntryCard(
    hazeState: HazeState,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    LiftrGlassSurface(
        hazeState = hazeState,
        shape = RoundedCornerShape(16.dp),
        modifier = modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
        elevation = 4.dp,
        strokeAlpha = 0.18f
    ) {
        Row(
            modifier = Modifier.padding(14.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = Icons.Filled.TrendingUp,
                contentDescription = null,
                tint = Color(0xFF00C7BE),
                modifier = Modifier.size(28.dp)
            )
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Text(
                    stringResource(R.string.nutrition_insights_hub_title),
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    stringResource(R.string.nutrition_insights_entry_subtitle),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Icon(
                imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}
