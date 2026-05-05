package com.lilru.liftr.ui.profile

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.lilru.liftr.R
import com.lilru.liftr.ui.components.LiftrBackTopBar
import io.github.jan.supabase.SupabaseClient

@Composable
fun ComparePrsScreen(
    supabase: SupabaseClient,
    myUserId: String,
    otherUserId: String,
    otherUsername: String,
    onBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    val vm: ComparePrsViewModel = viewModel(
        key = "compare-prs-$myUserId-$otherUserId",
        factory = ComparePrsViewModelFactory(
            supabase = supabase,
            myUserId = myUserId,
            otherUserId = otherUserId
        )
    )
    val st by vm.uiState.collectAsStateWithLifecycle()
    // Match iOS: green you, red other
    val colorMe = androidx.compose.ui.graphics.Color(0xFF1B5E20)
    val colorOther = androidx.compose.ui.graphics.Color(0xFFC62828)
    val colorTie = MaterialTheme.colorScheme.tertiary
    val colorText = MaterialTheme.colorScheme.onSurface
    Column(
        modifier = modifier
            .fillMaxSize()
            .statusBarsPadding()
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        LiftrBackTopBar(onBack = onBack)
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.Top,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Column(Modifier.weight(1f)) {
                Text(
                    stringResource(R.string.compare_prs_title),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold
                )
                Row(horizontalArrangement = Arrangement.spacedBy(0.dp)) {
                    Text(
                        stringResource(R.string.compare_prs_you),
                        color = colorMe,
                        style = MaterialTheme.typography.bodySmall
                    )
                    Text(" · ", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text("vs", color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall)
                    Text(" · ", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(
                        "@$otherUsername",
                        color = colorOther,
                        style = MaterialTheme.typography.bodySmall
                    )
                }
            }
            if (st.sections.isNotEmpty()) {
                TallyPill(
                    me = st.tallyMe,
                    ties = st.tallyTies,
                    other = st.tallyOther,
                    colorMe = colorMe,
                    colorOther = colorOther,
                    colorTie = colorTie
                )
            }
        }
        if (st.loading) {
            CircularProgressIndicator(Modifier.padding(top = 16.dp).align(Alignment.CenterHorizontally))
        } else if (st.error != null) {
            Text(
                st.error!!,
                color = MaterialTheme.colorScheme.error
            )
        } else if (st.sections.isEmpty()) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 32.dp, horizontal = 8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text(
                    stringResource(R.string.compare_prs_empty_title),
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    stringResource(R.string.compare_prs_empty_body, otherUsername),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center
                )
            }
        } else {
            LazyColumn(
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                st.sections.forEach { sec ->
                    item(key = "h-${sec.title}") {
                        Text(
                            sec.title,
                            style = MaterialTheme.typography.labelLarge,
                            fontWeight = FontWeight.SemiBold,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(top = 4.dp, bottom = 2.dp)
                        )
                    }
                    items(
                        items = sec.items,
                        key = { it.id }
                    ) { r ->
                        PrCompareRow(
                            row = r,
                            colorMe = colorMe,
                            colorOther = colorOther,
                            colorTie = colorTie,
                            defaultText = colorText
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun TallyPill(
    me: Int,
    ties: Int,
    other: Int,
    colorMe: androidx.compose.ui.graphics.Color,
    colorTie: androidx.compose.ui.graphics.Color,
    colorOther: androidx.compose.ui.graphics.Color
) {
    Row(
        modifier = Modifier
            .background(
                color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.6f),
                shape = RoundedCornerShape(50)
            )
            .padding(horizontal = 10.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text("✓$me", color = colorMe, style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.SemiBold)
        Text("=$ties", color = colorTie, style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.SemiBold)
        Text("✗$other", color = colorOther, style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun PrCompareRow(
    row: ComparePrsMergedRow,
    colorMe: androidx.compose.ui.graphics.Color,
    colorOther: androidx.compose.ui.graphics.Color,
    colorTie: androidx.compose.ui.graphics.Color,
    defaultText: androidx.compose.ui.graphics.Color
) {
    val myC = when (row.winner) {
        PrWinner.Me -> colorMe
        PrWinner.Tie -> colorTie
        else -> defaultText
    }
    val othC = when (row.winner) {
        PrWinner.Other -> colorOther
        PrWinner.Tie -> colorTie
        else -> defaultText
    }
    val wMy = row.winner == PrWinner.Me
    val wO = row.winner == PrWinner.Other
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(10.dp)
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(row.label, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
                Text(
                    ComparePrsFormat.prettyMetricName(row.metric),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.Top) {
                Text(
                    ComparePrsFormat.formatValue(row.metric, row.myValue),
                    style = MaterialTheme.typography.bodySmall,
                    fontWeight = if (wMy) FontWeight.SemiBold else FontWeight.Normal,
                    color = myC
                )
                Text("·", color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall)
                Text(
                    ComparePrsFormat.formatValue(row.metric, row.otherValue),
                    style = MaterialTheme.typography.bodySmall,
                    fontWeight = if (wO) FontWeight.SemiBold else FontWeight.Normal,
                    color = othC
                )
            }
        }
    }
}
