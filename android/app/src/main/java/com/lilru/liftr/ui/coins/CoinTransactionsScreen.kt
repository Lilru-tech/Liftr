package com.lilru.liftr.ui.coins

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.ExperimentalMaterialApi
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Paid
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material.pullrefresh.PullRefreshIndicator
import androidx.compose.material.pullrefresh.pullRefresh
import androidx.compose.material.pullrefresh.rememberPullRefreshState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.lilru.liftr.data.BackendContracts
import com.lilru.liftr.data.CoinManager
import com.lilru.liftr.data.CoinSourceSlice
import com.lilru.liftr.data.CoinSourcesPeriod
import com.lilru.liftr.data.CoinSourcesTimeWindows
import com.lilru.liftr.data.SupabaseResponseDecoding
import com.lilru.liftr.ui.components.LiftrBackTopBar
import com.lilru.liftr.ui.profile.progress.DonutSegment
import com.lilru.liftr.ui.profile.progress.KindDonutChart
import com.lilru.liftr.ui.ranking.RankingInitial
import com.lilru.liftr.ui.ranking.RankingMetric
import com.lilru.liftr.ui.ranking.RankingScope
import com.lilru.liftr.ui.ranking.RankingTabScreen
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.launch
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.text.DateFormat
import java.text.NumberFormat
import java.util.Date
import kotlin.math.roundToInt

@Serializable
private data class CoinTransactionRow(
    val id: String,
    val amount: Int,
    @SerialName("action_type") val actionType: String,
    @SerialName("created_at") val createdAt: String
)

@Serializable
private data class CoinSourceRow(
    @SerialName("source_key") val sourceKey: String,
    @SerialName("total_amount") val totalAmount: Int
)

@OptIn(ExperimentalMaterialApi::class)
@Composable
fun CoinTransactionsScreen(
    supabase: SupabaseClient,
    onBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    var items by remember { mutableStateOf<List<CoinTransactionRow>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    var showClearDialog by remember { mutableStateOf(false) }
    var showRanking by remember { mutableStateOf(false) }
    var sourcesPeriod by remember { mutableStateOf(CoinSourcesPeriod.ALL_TIME) }
    var sourceSlices by remember { mutableStateOf<List<CoinSourceSlice>>(emptyList()) }
    var sourcesLoading by remember { mutableStateOf(true) }
    var sourcesError by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val balance = CoinManager.balance

    suspend fun loadSources() {
        sourcesLoading = true
        sourcesError = null
        runCatching {
            val window = CoinSourcesTimeWindows.forPeriod(sourcesPeriod)
            val params = buildJsonObject {
                window.start?.toString()?.let { put("p_start", it) }
                window.endExclusive?.toString()?.let { put("p_end", it) }
            }
            val res = supabase.postgrest.rpc(
                BackendContracts.Rpc.GET_MY_COIN_SOURCES_V1,
                params
            ) { }
            SupabaseResponseDecoding.decodeListOrObject<CoinSourceRow>(res.data).map {
                CoinSourceSlice(sourceKey = it.sourceKey, totalAmount = it.totalAmount)
            }
        }.onSuccess {
            sourceSlices = it
            sourcesLoading = false
        }.onFailure {
            sourcesError = it.message
            sourceSlices = emptyList()
            sourcesLoading = false
        }
    }

    suspend fun load() {
        loading = true
        error = null
        runCatching {
            val res = supabase.postgrest.rpc(
                BackendContracts.Rpc.LIST_MY_COIN_TRANSACTIONS_V1,
                buildJsonObject { put("p_limit", 20) }
            ) { }
            SupabaseResponseDecoding.decodeListOrObject<CoinTransactionRow>(res.data)
        }.onSuccess {
            items = it
            loading = false
        }.onFailure {
            error = it.message
            items = emptyList()
            loading = false
        }
    }

    LaunchedEffect(supabase) {
        CoinManager.refreshBalance(supabase, notifyIfEarned = false)
        load()
        loadSources()
    }

    LaunchedEffect(sourcesPeriod) {
        loadSources()
    }

    val refreshing = (loading && items.isNotEmpty()) || (sourcesLoading && sourceSlices.isNotEmpty())
    val pullState = rememberPullRefreshState(refreshing, onRefresh = {
        scope.launch {
            load()
            loadSources()
        }
    })

    if (showRanking) {
        RankingTabScreen(
            supabase = supabase,
            onOpenAddWithPendingDuplicate = {},
            rankingInitial = RankingInitial(metric = RankingMetric.COINS, scope = RankingScope.GLOBAL),
            embedBack = { showRanking = false },
            modifier = modifier
        )
        return
    }

    if (showClearDialog) {
        AlertDialog(
            onDismissRequest = { showClearDialog = false },
            title = { Text("Clear transaction history?") },
            text = {
                Text("This removes your transaction list. Your coin balance will not change.")
            },
            confirmButton = {
                TextButton(onClick = {
                    showClearDialog = false
                    scope.launch {
                        runCatching {
                            supabase.postgrest.rpc(
                                BackendContracts.Rpc.CLEAR_MY_COIN_HISTORY_V1,
                                buildJsonObject { }
                            ) { }
                        }.onSuccess {
                            items = emptyList()
                            sourceSlices = emptyList()
                        }.onFailure { e ->
                            error = e.message
                        }
                    }
                }) {
                    Text("Clear history", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { showClearDialog = false }) {
                    Text("Cancel")
                }
            }
        )
    }

    Column(modifier = modifier.fillMaxSize()) {
        LiftrBackTopBar(title = "Liftr Coins", onBack = onBack)
        BoxPullRefresh(
            modifier = Modifier.fillMaxSize(),
            state = pullState,
            refreshing = refreshing
        ) {
            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .pullRefresh(pullState)
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                item {
                    Card(modifier = Modifier.fillMaxWidth()) {
                        Column(
                            modifier = Modifier.padding(16.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text("Balance", style = MaterialTheme.typography.titleMedium)
                                TextButton(onClick = { showRanking = true }) {
                                    Text("View ranking")
                                }
                            }
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(8.dp)
                            ) {
                                Icon(Icons.Filled.Paid, contentDescription = null, tint = Color(0xFFFFC107))
                                Text(
                                    NumberFormat.getIntegerInstance().format(balance),
                                    style = MaterialTheme.typography.headlineSmall,
                                    fontWeight = FontWeight.Bold
                                )
                                Text("Liftr Coins", style = MaterialTheme.typography.bodyMedium)
                            }
                        }
                    }
                }

                item {
                    CoinSourcesCard(
                        period = sourcesPeriod,
                        onPeriodChange = { sourcesPeriod = it },
                        slices = sourceSlices,
                        loading = sourcesLoading,
                        error = sourcesError
                    )
                }

                when {
                    loading && items.isEmpty() -> item {
                        CircularProgressIndicator(modifier = Modifier.padding(24.dp))
                    }
                    error != null -> item {
                        Text(error!!, color = MaterialTheme.colorScheme.error)
                    }
                    items.isEmpty() -> item {
                        Text("No transactions yet.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    else -> {
                        items(items, key = { it.id }) { row ->
                            Card(modifier = Modifier.fillMaxWidth()) {
                                Column(modifier = Modifier.padding(12.dp)) {
                                    Row(
                                        modifier = Modifier.fillMaxWidth(),
                                        horizontalArrangement = Arrangement.SpaceBetween
                                    ) {
                                        Text(CoinManager.displayLabel(row.actionType))
                                        Text(
                                            CoinManager.formattedAmount(row.amount),
                                            color = if (row.amount >= 0) Color(0xFF2E7D32) else Color(0xFFC62828),
                                            fontWeight = FontWeight.SemiBold
                                        )
                                    }
                                    Text(
                                        formatCreatedAt(row.createdAt),
                                        style = MaterialTheme.typography.labelSmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                            }
                        }
                        item {
                            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                                TextButton(onClick = { showClearDialog = true }) {
                                    Text("Clear history", color = MaterialTheme.colorScheme.error)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CoinSourcesCard(
    period: CoinSourcesPeriod,
    onPeriodChange: (CoinSourcesPeriod) -> Unit,
    slices: List<CoinSourceSlice>,
    loading: Boolean,
    error: String?
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text("Sources", style = MaterialTheme.typography.titleMedium)

            SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                CoinSourcesPeriod.entries.forEachIndexed { index, p ->
                    SegmentedButton(
                        selected = period == p,
                        onClick = { onPeriodChange(p) },
                        shape = SegmentedButtonDefaults.itemShape(
                            index = index,
                            count = CoinSourcesPeriod.entries.size
                        )
                    ) {
                        Text(p.label, style = MaterialTheme.typography.labelSmall)
                    }
                }
            }

            when {
                loading && slices.isEmpty() -> {
                    CircularProgressIndicator(
                        modifier = Modifier
                            .align(Alignment.CenterHorizontally)
                            .padding(vertical = 24.dp)
                    )
                }
                error != null -> {
                    Text(error, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                }
                slices.isEmpty() -> {
                    Text(
                        "No coins earned in this period.",
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        style = MaterialTheme.typography.bodyMedium
                    )
                }
                else -> {
                    val total = slices.sumOf { it.totalAmount }.toDouble()
                    val segments = slices.map {
                        DonutSegment(
                            label = it.label,
                            value = it.totalAmount.toDouble(),
                            color = it.color
                        )
                    }
                    KindDonutChart(
                        segments = segments,
                        centerTitle = "Earned",
                        modifier = Modifier.fillMaxWidth()
                    )
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        slices.forEach { slice ->
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                androidx.compose.foundation.Canvas(
                                    modifier = Modifier
                                        .size(8.dp)
                                        .clip(CircleShape)
                                ) {
                                    drawCircle(slice.color)
                                }
                                Text(
                                    slice.label,
                                    style = MaterialTheme.typography.bodyMedium,
                                    modifier = Modifier.padding(start = 8.dp)
                                )
                                Spacer(modifier = Modifier.weight(1f))
                                if (total > 0) {
                                    Text(
                                        "${((slice.totalAmount / total) * 100).roundToInt()}%",
                                        style = MaterialTheme.typography.labelSmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                                Text(
                                    CoinManager.formattedAmount(slice.totalAmount),
                                    style = MaterialTheme.typography.bodyMedium,
                                    fontWeight = FontWeight.SemiBold,
                                    color = Color(0xFF2E7D32),
                                    modifier = Modifier.padding(start = 8.dp)
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@OptIn(androidx.compose.material.ExperimentalMaterialApi::class)
@Composable
private fun BoxPullRefresh(
    modifier: Modifier,
    state: androidx.compose.material.pullrefresh.PullRefreshState,
    refreshing: Boolean,
    content: @Composable () -> Unit
) {
    androidx.compose.foundation.layout.Box(modifier = modifier) {
        content()
        PullRefreshIndicator(
            refreshing = refreshing,
            state = state,
            modifier = Modifier.align(Alignment.TopCenter)
        )
    }
}

private fun formatCreatedAt(raw: String): String {
    val instant = runCatching { java.time.Instant.parse(raw) }.getOrNull() ?: return raw
    return DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT)
        .format(Date.from(instant))
}
