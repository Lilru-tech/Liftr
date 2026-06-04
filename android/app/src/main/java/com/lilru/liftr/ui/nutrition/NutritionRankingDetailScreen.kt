package com.lilru.liftr.ui.nutrition

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.lilru.liftr.R
import com.lilru.liftr.prefs.LiftrPreferences
import com.lilru.liftr.ui.components.LiftrBackTopBar
import com.lilru.liftr.ui.theme.liftrAppBackgroundGradientOpaque
import androidx.compose.ui.platform.LocalContext
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import kotlin.math.roundToInt

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NutritionRankingDetailScreen(
    vm: NutritionViewModel,
    kind: NutritionRankingKind,
    onBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    val ui by vm.uiState.collectAsState()
    val ranking = ui.ranking
    val context = LocalContext.current
    val theme = remember { LiftrPreferences.backgroundTheme(context) }

    LaunchedEffect(kind) {
        vm.loadRanking(kind)
    }

    Scaffold(
        modifier = modifier.fillMaxSize(),
        containerColor = androidx.compose.ui.graphics.Color.Transparent,
        topBar = {
            LiftrBackTopBar(
                title = rankingTitle(kind),
                onBack = onBack
            )
        }
    ) { padding ->
        when {
            ranking.isLoading && ranking.rows.isEmpty() -> {
                Column(
                    Modifier
                        .fillMaxSize()
                        .liftrAppBackgroundGradientOpaque(theme)
                        .padding(padding),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center
                ) {
                    CircularProgressIndicator()
                }
            }
            ranking.error != null && ranking.rows.isEmpty() -> {
                Column(
                    Modifier
                        .fillMaxSize()
                        .liftrAppBackgroundGradientOpaque(theme)
                        .padding(padding)
                        .padding(16.dp)
                ) {
                    Text(
                        ranking.error ?: stringResource(R.string.nutrition_ranking_load_error),
                        color = MaterialTheme.colorScheme.error,
                        style = MaterialTheme.typography.bodyMedium
                    )
                }
            }
            ranking.rows.isEmpty() -> {
                Column(
                    Modifier
                        .fillMaxSize()
                        .liftrAppBackgroundGradientOpaque(theme)
                        .padding(padding)
                        .padding(16.dp)
                ) {
                    Text(
                        stringResource(R.string.nutrition_ranking_empty),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            else -> {
                LazyColumn(
                    Modifier
                        .fillMaxSize()
                        .liftrAppBackgroundGradientOpaque(theme)
                        .padding(padding)
                ) {
                    itemsIndexed(
                        items = ranking.rows,
                        key = { _, row -> row.rankPosition }
                    ) { index, row ->
                        if (index >= ranking.rows.size - 3) {
                            LaunchedEffect(index, ranking.rows.size) {
                                vm.loadMoreRanking(kind)
                            }
                        }
                        NutritionRankingRowItem(kind = kind, row = row)
                        if (index < ranking.rows.lastIndex) {
                            HorizontalDivider(
                                modifier = Modifier.padding(start = 56.dp),
                                color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.35f)
                            )
                        }
                    }
                    if (ranking.isLoadingMore) {
                        item(key = "loading_more") {
                            Row(
                                Modifier
                                    .fillMaxWidth()
                                    .padding(vertical = 16.dp),
                                horizontalArrangement = Arrangement.Center
                            ) {
                                CircularProgressIndicator()
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun rankingTitle(kind: NutritionRankingKind): String {
    return stringResource(
        when (kind) {
            NutritionRankingKind.HIGHEST_CALORIE_DAYS -> R.string.nutrition_ranking_top_calorie_days
            NutritionRankingKind.HIGHEST_CALORIE_MEALS -> R.string.nutrition_ranking_top_calorie_meals
            NutritionRankingKind.MOST_LOGGED_INGREDIENTS -> R.string.nutrition_ranking_most_logged_ingredients
            NutritionRankingKind.MOST_LOGGED_RECIPES -> R.string.nutrition_ranking_most_logged_recipes
            NutritionRankingKind.HEAVIEST_MEALS -> R.string.nutrition_ranking_heaviest_meals
        }
    )
}

@Composable
private fun NutritionRankingRowItem(
    kind: NutritionRankingKind,
    row: NutritionRankingRowUi
) {
    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text(
            row.rankPosition.toString(),
            modifier = Modifier.padding(end = 4.dp),
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Column(
            Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Text(
                displayRankingTitle(kind, row.title),
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold
            )
            row.subtitle?.takeIf { it.isNotBlank() }?.let { subtitle ->
                Text(
                    displayRankingSubtitle(kind, subtitle),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
        Text(
            formatRankingValue(row),
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.primary
        )
    }
}

@Composable
private fun displayRankingTitle(kind: NutritionRankingKind, title: String): String {
    return if (kind == NutritionRankingKind.HIGHEST_CALORIE_DAYS) {
        formatRankingDate(title)
    } else {
        title
    }
}

@Composable
private fun displayRankingSubtitle(kind: NutritionRankingKind, subtitle: String): String {
    return if (kind == NutritionRankingKind.HIGHEST_CALORIE_MEALS ||
        kind == NutritionRankingKind.HEAVIEST_MEALS
    ) {
        formatRankingDate(subtitle)
    } else {
        subtitle
    }
}

@Composable
private fun formatRankingValue(row: NutritionRankingRowUi): String {
    return when (row.unitLabel) {
        "kcal" -> stringResource(R.string.nutrition_kcal_format, row.valueNumeric.roundToInt())
        "g" -> formatRankingGrams(row.valueNumeric)
        "times" -> {
            val count = row.valueNumeric.roundToInt()
            if (count == 1) {
                stringResource(R.string.nutrition_ranking_times_one)
            } else {
                stringResource(R.string.nutrition_ranking_times_many, count)
            }
        }
        else -> "${row.valueNumeric.roundToInt()} ${row.unitLabel}"
    }
}

private fun formatRankingGrams(grams: Double): String {
    return if (grams >= 1000) {
        String.format("%.1f kg", grams / 1000.0)
    } else {
        "${grams.roundToInt()} g"
    }
}

private fun formatRankingDate(iso: String): String {
    return runCatching {
        LocalDate.parse(iso).format(DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM))
    }.getOrElse { iso }
}
