package com.lilru.liftr.ui.nutrition

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.lilru.liftr.R
import com.lilru.liftr.prefs.LiftrPreferences
import com.lilru.liftr.ui.components.LiftrBackTopBar
import com.lilru.liftr.ui.theme.liftrAppBackgroundGradientOpaque
import androidx.compose.ui.platform.LocalContext
import kotlinx.coroutines.launch

private enum class NutritionInsightsHubTab {
    COACH,
    HIGHLIGHTS
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NutritionInsightsHubScreen(
    vm: NutritionViewModel,
    onBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    val ui by vm.uiState.collectAsState()
    val context = LocalContext.current
    val theme = remember { LiftrPreferences.backgroundTheme(context) }
    val scrollState = rememberScrollState()
    val scope = rememberCoroutineScope()
    var selectedTabIndex by rememberSaveable { mutableIntStateOf(0) }
    var rankingOverlay by remember { mutableStateOf<NutritionRankingKind?>(null) }
    val tabs = NutritionInsightsHubTab.entries

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

    Scaffold(
        modifier = modifier.fillMaxSize(),
        containerColor = androidx.compose.ui.graphics.Color.Transparent,
        topBar = {
            LiftrBackTopBar(
                title = stringResource(R.string.nutrition_insights_hub_title),
                onBack = onBack
            )
        }
    ) { padding ->
        Column(
            Modifier
                .fillMaxSize()
                .liftrAppBackgroundGradientOpaque(theme)
                .padding(padding)
                .verticalScroll(scrollState)
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            TabRow(selectedTabIndex = selectedTabIndex) {
                tabs.forEachIndexed { index, tab ->
                    Tab(
                        selected = selectedTabIndex == index,
                        onClick = { selectedTabIndex = index },
                        text = {
                            Text(
                                when (tab) {
                                    NutritionInsightsHubTab.COACH ->
                                        stringResource(R.string.nutrition_insights_tab_coach)
                                    NutritionInsightsHubTab.HIGHLIGHTS ->
                                        stringResource(R.string.nutrition_insights_tab_highlights)
                                }
                            )
                        }
                    )
                }
            }

            when (tabs[selectedTabIndex]) {
                NutritionInsightsHubTab.COACH -> {
                    Text(
                        stringResource(R.string.nutrition_insights_hub_subtitle),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Card(
                        modifier = Modifier.fillMaxWidth(),
                        colors = CardDefaults.cardColors(
                            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.45f)
                        )
                    ) {
                        NutritionInsightsRangeCard(
                            ui = ui,
                            vm = vm,
                            onAnalyze = {
                                vm.analyzeSmartInsights()
                                scope.launch {
                                    kotlinx.coroutines.delay(100)
                                    scrollState.animateScrollTo(scrollState.maxValue)
                                }
                            },
                            modifier = Modifier.padding(14.dp)
                        )
                    }
                    if (showCoachResults) {
                        NutritionSmartInsightsInlineContent(ui = ui)
                    }
                }
                NutritionInsightsHubTab.HIGHLIGHTS -> {
                    Text(
                        stringResource(R.string.nutrition_highlights_hub_subtitle),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    NutritionHighlightsContent(
                        ui = ui,
                        onRankingClick = { kind -> rankingOverlay = kind }
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NutritionInsightsEntryCard(
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Card(
        onClick = onClick,
        modifier = modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.45f)
        )
    ) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
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
    }
}
