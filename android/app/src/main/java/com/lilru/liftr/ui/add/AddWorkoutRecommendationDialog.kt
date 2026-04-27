package com.lilru.liftr.ui.add

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.window.Dialog
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.lilru.liftr.R
import com.lilru.liftr.ui.add.recommendation.CardioRecommendationResult
import com.lilru.liftr.ui.add.recommendation.RecommendationDataSource
import com.lilru.liftr.ui.add.recommendation.SportRecommendationResult
import com.lilru.liftr.ui.add.recommendation.StrengthRecommendationExerciseResult
import com.lilru.liftr.ui.add.recommendation.StrengthSuggestionMode
import com.lilru.liftr.ui.add.recommendation.WorkoutRecommendationError
import java.util.Locale
import kotlinx.coroutines.launch

@Composable
fun AddWorkoutRecommendationDialog(
    kind: AddWorkoutKind,
    vm: AddWorkoutViewModel,
    onDismiss: () -> Unit,
    onAppliedCardio: (CardioRecommendationResult) -> Unit,
    onAppliedSport: (SportRecommendationResult) -> Unit
) {
    val ui by vm.uiState.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    var phase by remember { mutableStateOf<RecPhase>(RecPhase.Questions) }
    var source by remember { mutableStateOf(RecommendationDataSource.RECENT_HISTORY) }
    var strengthMode by remember {
        mutableStateOf(StrengthSuggestionMode.PRIORITIZE_UNDERTRAINED_MUSCLES)
    }
    var errorText by remember { mutableStateOf<String?>(null) }
    val context = LocalContext.current
    val preferSpanish = remember {
        Locale.getDefault().language.lowercase().startsWith("es")
    }

    val dataSources = remember(kind) {
        when (kind) {
            AddWorkoutKind.SPORT -> RecommendationDataSource.entries.toList()
            else -> RecommendationDataSource.entries.filter {
                it != RecommendationDataSource.HYROX && it != RecommendationDataSource.HYROX_RACE
            }
        }
    }

    Dialog(onDismissRequest = onDismiss) {
        Surface(
            shape = RoundedCornerShape(24.dp),
            modifier = Modifier
                .fillMaxSize()
                .padding(8.dp)
        ) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(horizontal = 12.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Box(Modifier.fillMaxWidth()) {
                    TextButton(
                        onClick = onDismiss,
                        enabled = phase !is RecPhase.Loading,
                        modifier = Modifier.align(Alignment.CenterStart)
                    ) {
                        Text(stringResource(R.string.add_recommend_close))
                    }
                    Text(
                        text = stringResource(R.string.add_recommend_title),
                        style = MaterialTheme.typography.titleLarge,
                        modifier = Modifier
                            .align(Alignment.Center)
                            .fillMaxWidth()
                            .padding(horizontal = 64.dp),
                        textAlign = TextAlign.Center
                    )
                }

                when (val p = phase) {
                    RecPhase.Questions -> {
                        Column(
                            modifier = Modifier
                                .weight(1f)
                                .verticalScroll(rememberScrollState()),
                            verticalArrangement = Arrangement.spacedBy(10.dp)
                        ) {
                            RecommendSectionIntro(text = introTextForKind(kind))
                            RecommendSectionHeader(stringResource(R.string.add_recommend_data_source))
                            RecommendationChoiceCard(
                                options = dataSources.map { RecOption(it.title, it.detail) },
                                selectedIndex = dataSources.indexOf(source).coerceAtLeast(0),
                                onSelect = { source = dataSources[it] }
                            )

                            if (kind == AddWorkoutKind.STRENGTH) {
                                RecommendSectionHeader(stringResource(R.string.add_recommend_strength_session))
                                RecommendationChoiceCard(
                                    options = StrengthSuggestionMode.entries.map {
                                        RecOption(it.title, it.detail)
                                    },
                                    selectedIndex = StrengthSuggestionMode.entries.indexOf(strengthMode)
                                        .coerceAtLeast(0),
                                    onSelect = { strengthMode = StrengthSuggestionMode.entries[it] }
                                )
                            }
                            errorText?.let { e ->
                                Text(
                                    e,
                                    color = MaterialTheme.colorScheme.error,
                                    style = MaterialTheme.typography.bodySmall
                                )
                            }
                        }
                        Button(
                            onClick = {
                                errorText = null
                                if (kind == AddWorkoutKind.STRENGTH && ui.exercises.isEmpty()) {
                                    errorText = context.getString(R.string.add_recommend_error_load_exercises)
                                    return@Button
                                }
                                phase = RecPhase.Loading
                                scope.launch {
                                    runCatching {
                                        when (kind) {
                                            AddWorkoutKind.STRENGTH -> {
                                                val rows = vm.recommendStrengthForUi(source, strengthMode, preferSpanish)
                                                phase = RecPhase.ResultStrength(rows)
                                            }

                                            AddWorkoutKind.CARDIO -> {
                                                val r = vm.recommendCardioForUi(source)
                                                phase = RecPhase.ResultCardio(r)
                                            }

                                            AddWorkoutKind.SPORT -> {
                                                val r = vm.recommendSportForUi(source)
                                                phase = RecPhase.ResultSport(r)
                                            }
                                        }
                                    }.onFailure { e ->
                                        phase = RecPhase.Questions
                                        val extra = e.message
                                            ?: (e as? WorkoutRecommendationError)?.message
                                            ?: e::class.java.simpleName
                                        errorText = listOf(
                                            context.getString(R.string.add_recommend_error_couldnt_load),
                                            extra
                                        ).joinToString("\n")
                                    }
                                }
                            },
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(vertical = 4.dp),
                            shape = RoundedCornerShape(14.dp),
                            colors = ButtonDefaults.buttonColors(
                                containerColor = MaterialTheme.colorScheme.primaryContainer
                                    .copy(alpha = 0.35f),
                                contentColor = MaterialTheme.colorScheme.primary
                            ),
                            elevation = ButtonDefaults.buttonElevation(
                                defaultElevation = 0.dp,
                                pressedElevation = 0.dp
                            )
                        ) {
                            Text(
                                stringResource(R.string.add_recommend_generate),
                                style = MaterialTheme.typography.titleMedium
                            )
                        }
                    }

                    RecPhase.Loading -> {
                        Column(
                            modifier = Modifier
                                .weight(1f)
                                .fillMaxWidth(),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.Center
                        ) {
                            Text(
                                stringResource(R.string.add_recommend_building),
                                style = MaterialTheme.typography.bodyMedium
                            )
                            Spacer(Modifier.height(12.dp))
                            CircularProgressIndicator()
                        }
                    }

                    is RecPhase.ResultStrength -> {
                        Column(
                            modifier = Modifier
                                .weight(1f)
                                .fillMaxWidth(),
                            verticalArrangement = Arrangement.spacedBy(10.dp)
                        ) {
                            StrengthRecommendationResultList(
                                rows = p.rows,
                                formatKg = ::formatKgForRec
                            )
                        }
                        RecommendationResultActionCard(
                            onApply = {
                                vm.applyStrengthRecommendation(p.rows)
                                onDismiss()
                            },
                            onBack = { phase = RecPhase.Questions }
                        )
                    }

                    is RecPhase.ResultCardio -> {
                        Column(
                            modifier = Modifier
                                .weight(1f)
                                .fillMaxWidth(),
                            verticalArrangement = Arrangement.spacedBy(10.dp)
                        ) {
                            RecommendationTextResultBody(
                                text = "${p.r.rationale}\n\nActivity: ${p.r.activityWire}\nDuration: ${p.r.durationSec} s"
                            )
                        }
                        RecommendationResultActionCard(
                            onApply = {
                                onAppliedCardio(p.r)
                                onDismiss()
                            },
                            onBack = { phase = RecPhase.Questions }
                        )
                    }

                    is RecPhase.ResultSport -> {
                        val summary = when (val sr = p.sr) {
                            is SportRecommendationResult.DurationOnly ->
                                "${sr.rationale}\n\nSuggested: ${sr.durationMin} min."

                            is SportRecommendationResult.Hyrox ->
                                "${sr.rationale}\n\n${sr.exercises.size} stations, ~${sr.durationMin} min."
                        }
                        Column(
                            modifier = Modifier
                                .weight(1f)
                                .fillMaxWidth(),
                            verticalArrangement = Arrangement.spacedBy(10.dp)
                        ) {
                            RecommendationTextResultBody(text = summary)
                        }
                        RecommendationResultActionCard(
                            onApply = {
                                onAppliedSport(p.sr)
                                onDismiss()
                            },
                            onBack = { phase = RecPhase.Questions }
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun RecommendSectionIntro(text: String) {
    Surface(
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.surfaceContainerHigh.copy(alpha = 0.55f)
    ) {
        Text(
            text = text,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            lineHeight = 18.sp,
            modifier = Modifier.padding(14.dp)
        )
    }
}

@Composable
private fun RecommendSectionHeader(title: String) {
    Text(
        text = title.uppercase(Locale.getDefault()),
        style = MaterialTheme.typography.labelMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        letterSpacing = 0.6.sp,
        modifier = Modifier
            .fillMaxWidth()
            .padding(start = 2.dp, top = 4.dp, end = 2.dp, bottom = 0.dp)
    )
}

@Composable
private fun introTextForKind(kind: AddWorkoutKind): String = when (kind) {
    AddWorkoutKind.STRENGTH -> stringResource(R.string.add_recommend_intro_strength)
    AddWorkoutKind.CARDIO -> stringResource(R.string.add_recommend_intro_cardio)
    AddWorkoutKind.SPORT -> stringResource(R.string.add_recommend_intro_sport)
}

private fun formatKgForRec(kg: Double): String =
    if (kg % 1.0 == 0.0) kg.toInt().toString() else String.format(Locale.US, "%.1f", kg)

private data class RecOption(
    val title: String,
    val detail: String
)

@Composable
private fun RecommendationChoiceCard(
    options: List<RecOption>,
    selectedIndex: Int,
    onSelect: (Int) -> Unit
) {
    val lastIdx = (options.size - 1).coerceAtLeast(0)
    val selected = selectedIndex.coerceIn(0, lastIdx)
    Surface(
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.surfaceContainerHigh.copy(alpha = 0.5f),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column {
            options.forEachIndexed { idx, option ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { onSelect(idx) }
                        .padding(horizontal = 14.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(
                        modifier = Modifier.weight(1f),
                        verticalArrangement = Arrangement.spacedBy(4.dp)
                    ) {
                        Text(
                            option.title,
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.SemiBold
                        )
                        Text(
                            option.detail,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    if (idx == selected) {
                        Icon(
                            imageVector = Icons.Filled.Check,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.size(22.dp)
                        )
                    } else {
                        Spacer(Modifier.size(22.dp))
                    }
                }
                if (idx < options.lastIndex) {
                    HorizontalDivider(
                        modifier = Modifier.padding(horizontal = 14.dp),
                        color = MaterialTheme.colorScheme.outline.copy(alpha = 0.2f)
                    )
                }
            }
        }
    }
}

@Composable
private fun StrengthRecommendationResultList(
    rows: List<StrengthRecommendationExerciseResult>,
    formatKg: (Double) -> String
) {
    val context = LocalContext.current
    Column(Modifier.fillMaxWidth()) {
        Text(
            text = stringResource(R.string.add_recommend_suggested).uppercase(Locale.getDefault()),
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            letterSpacing = 0.6.sp,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 2.dp)
                .padding(bottom = 6.dp)
        )
        Surface(
            shape = RoundedCornerShape(16.dp),
            color = MaterialTheme.colorScheme.surfaceContainerHigh.copy(alpha = 0.5f),
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(max = 480.dp)
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .padding(14.dp)
            ) {
                rows.forEachIndexed { exIdx, ex ->
                    Column(Modifier.fillMaxWidth()) {
                        Text(
                            text = ex.displayName,
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.SemiBold
                        )
                        ex.musclePrimary?.trim()?.takeIf { it.isNotEmpty() }?.let { m ->
                            Text(
                                text = m,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.padding(top = 2.dp)
                            )
                        }
                        ex.sets.forEach { s ->
                            val wStr = formatKg(s.weightKg)
                            val rpePart = s.rpe?.let { r ->
                                context.getString(R.string.add_recommend_set_rpe_suffix, r)
                            } ?: ""
                            val restPart = s.restSec?.let { sec -> " · ${sec}s rest" } ?: ""
                            val line = context.getString(
                                R.string.add_recommend_set_line,
                                s.setNumber,
                                s.reps,
                                wStr,
                                rpePart
                            ) + restPart
                            Text(
                                text = line,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurface,
                                modifier = Modifier.padding(top = 6.dp)
                            )
                        }
                    }
                    if (exIdx < rows.lastIndex) {
                        Spacer(Modifier.height(16.dp))
                        HorizontalDivider(
                            color = MaterialTheme.colorScheme.outline.copy(alpha = 0.12f)
                        )
                        Spacer(Modifier.height(16.dp))
                    }
                }
            }
        }
    }
}

@Composable
private fun RecommendationTextResultBody(text: String) {
    Surface(
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.surfaceContainerHigh.copy(alpha = 0.5f),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(120.dp, 420.dp)
                .verticalScroll(rememberScrollState())
                .padding(14.dp)
        ) {
            Text(
                text = text,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurface,
                lineHeight = 20.sp
            )
        }
    }
}

@Composable
private fun RecommendationResultActionCard(
    onApply: () -> Unit,
    onBack: () -> Unit
) {
    val applyLabel = stringResource(R.string.add_recommend_apply)
    val backLabel = stringResource(R.string.add_recommend_back_to_options)
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 2.dp),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainerHigh.copy(alpha = 0.5f)
        )
    ) {
        Column(Modifier.fillMaxWidth()) {
            TextButton(
                onClick = onApply,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(
                    text = applyLabel,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth()
                )
            }
            HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.2f))
            TextButton(
                onClick = onBack,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(
                    text = backLabel,
                    style = MaterialTheme.typography.bodyLarge,
                    textAlign = TextAlign.Center,
                    color = MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier.fillMaxWidth()
                )
            }
        }
    }
}

private sealed class RecPhase {
    data object Questions : RecPhase()
    data object Loading : RecPhase()
    data class ResultStrength(val rows: List<StrengthRecommendationExerciseResult>) : RecPhase()
    data class ResultCardio(val r: CardioRecommendationResult) : RecPhase()
    data class ResultSport(val sr: SportRecommendationResult) : RecPhase()
}
