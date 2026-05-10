package com.lilru.liftr.ui.achievements

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Send
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.IconButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import coil.compose.AsyncImage
import com.lilru.liftr.R
import com.lilru.liftr.data.ChatRepository
import com.lilru.liftr.ui.chat.AchievementShareSnapshot
import com.lilru.liftr.ui.chat.ShareAchievementToChatSheetContent
import com.lilru.liftr.ui.components.LiftrBackTopBar
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.min
import kotlin.math.roundToInt
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AchievementsScreen(
    supabase: SupabaseClient,
    targetUserId: String,
    viewedUsername: String,
    fromNotification: Boolean = false,
    initialOpenAchievementCode: String? = null,
    onBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    val vm: AchievementsViewModel = viewModel(
        factory = AchievementsViewModelFactory(supabase, targetUserId)
    )
    val ui by vm.uiState.collectAsStateWithLifecycle()
    var selected by remember { mutableStateOf<AchievementRowUi?>(null) }
    var showSearch by remember { mutableStateOf(false) }
    val detailSheet = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val scope = rememberCoroutineScope()
    val chatRepo = remember { ChatRepository(supabase) }
    var shareAchievementSnapshot by remember { mutableStateOf<AchievementShareSnapshot?>(null) }
    var appliedInitialOpenCode by rememberSaveable { mutableStateOf(false) }
    val lockOptions = listOf(
        AchievementLockFilter.ALL to R.string.achievements_filter_all,
        AchievementLockFilter.UNLOCKED to R.string.achievements_filter_unlocked,
        AchievementLockFilter.LOCKED to R.string.achievements_filter_locked
    )
    val catOptions = AchievementCategoryFilter.entries
    val dateFmt = remember {
        DateTimeFormatter.ofLocalizedDate(java.time.format.FormatStyle.MEDIUM)
            .withLocale(Locale.getDefault())
    }

    LaunchedEffect(initialOpenAchievementCode, ui.loading, ui.items) {
        if (appliedInitialOpenCode) return@LaunchedEffect
        if (initialOpenAchievementCode == null) {
            appliedInitialOpenCode = true
            return@LaunchedEffect
        }
        if (ui.loading) return@LaunchedEffect
        if (ui.items.isEmpty()) return@LaunchedEffect
        vm.setLockFilter(AchievementLockFilter.ALL)
        vm.setCategory(AchievementCategoryFilter.ALL)
        vm.setSearch("")
        val match = ui.items.find { it.code == initialOpenAchievementCode }
        if (match != null) {
            selected = match
        }
        appliedInitialOpenCode = true
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .statusBarsPadding()
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        if (fromNotification) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                IconButton(onClick = onBack) {
                    Icon(
                        imageVector = Icons.Filled.Close,
                        contentDescription = stringResource(R.string.achievements_close)
                    )
                }
                Text(
                    stringResource(R.string.achievements_title),
                    style = MaterialTheme.typography.titleLarge,
                    modifier = Modifier.weight(1f),
                    textAlign = TextAlign.Center
                )
                TextButton(
                    onClick = { vm.recomputeAndReload() },
                    enabled = !ui.recomputeBusy
                ) {
                    if (ui.recomputeBusy) {
                        CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                    } else {
                        Text(stringResource(R.string.achievements_refresh))
                    }
                }
            }
        } else {
            LiftrBackTopBar(onBack = onBack)
            Text(
                stringResource(R.string.achievements_title_user, viewedUsername),
                style = MaterialTheme.typography.titleLarge
            )
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally)) {
                TextButton(
                    onClick = { vm.recomputeAndReload() },
                    enabled = !ui.recomputeBusy
                ) {
                    Text(stringResource(R.string.achievements_refresh))
                }
                if (ui.recomputeBusy) {
                    CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                }
            }
        }
        SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
            lockOptions.forEachIndexed { i, p ->
                SegmentedButton(
                    selected = ui.lockFilter == p.first,
                    onClick = { vm.setLockFilter(p.first) },
                    shape = SegmentedButtonDefaults.itemShape(i, lockOptions.size)
                ) { Text(stringResource(p.second)) }
            }
        }
        Row(
            Modifier
                .fillMaxWidth()
                .horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            catOptions.forEach { cat ->
                FilterChip(
                    selected = ui.category == cat,
                    onClick = { vm.setCategory(cat) },
                    label = { Text(cat.label) }
                )
            }
        }
        if (showSearch) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                OutlinedTextField(
                    value = ui.search,
                    onValueChange = { vm.setSearch(it) },
                    label = { Text(stringResource(R.string.achievements_search)) },
                    modifier = Modifier.weight(1f)
                )
                TextButton(
                    onClick = {
                        showSearch = false
                        vm.setSearch("")
                    }
                ) { Text(stringResource(R.string.search_clear)) }
            }
        } else {
            TextButton(onClick = { showSearch = true }, modifier = Modifier.align(Alignment.End)) {
                Text(stringResource(R.string.achievements_search))
            }
        }
        if (ui.loading) {
            Box(Modifier.fillMaxSize().weight(1f), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
        } else if (ui.error != null) {
            Text(ui.error!!, color = MaterialTheme.colorScheme.error)
        } else {
            val items = ui.filtered
            if (items.isEmpty()) {
                Text(
                    stringResource(R.string.achievements_empty),
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            } else {
                Box(Modifier.fillMaxSize().weight(1f)) {
                    LazyVerticalGrid(
                        columns = GridCells.Fixed(4),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                        modifier = Modifier.fillMaxSize()
                    ) {
                        items(items, key = { it.idKey }) { row ->
                            AchievementGridTile(
                                row = row,
                                onClick = { selected = row }
                            )
                        }
                    }
                }
            }
        }
    }
    if (selected != null) {
        val row = selected!!
        ModalBottomSheet(
            onDismissRequest = { selected = null },
            sheetState = detailSheet
        ) {
            Column(Modifier.fillMaxWidth().padding(20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(
                    Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(row.title, style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
                    IconButton(
                        onClick = {
                            scope.launch {
                                val me = supabase.auth.currentUserOrNull()?.id ?: return@launch
                                val prof = runCatching { chatRepo.fetchProfile(me) }.getOrNull()
                                val snap = AchievementShareSnapshot(
                                    code = row.code,
                                    achievementId = row.achievementId,
                                    title = row.title,
                                    category = row.category,
                                    description = row.description,
                                    iconUrl = row.iconUrl,
                                    ownerUserId = me,
                                    ownerUsername = prof?.username,
                                    ownerAvatarUrl = prof?.avatarUrl
                                )
                                selected = null
                                shareAchievementSnapshot = snap
                            }
                        }
                    ) {
                        Icon(
                            Icons.Filled.Send,
                            contentDescription = stringResource(R.string.achievement_share_chat_a11y)
                        )
                    }
                }
                Text(
                    prettySubtypeFromCode(row.code, row.category),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                if (row.isUnlocked) {
                    val d = row.unlockedAt?.let { parseToInstant(it) }
                    Text(
                        if (d != null) {
                            stringResource(
                                R.string.achievements_detail_unlocked,
                                dateFmt.format(d.atZone(ZoneId.systemDefault()).toLocalDate())
                            )
                        } else {
                            stringResource(R.string.achievements_detail_unlocked, "—")
                        },
                        style = MaterialTheme.typography.bodySmall
                    )
                } else {
                    Text(stringResource(R.string.achievements_detail_locked), style = MaterialTheme.typography.bodySmall)
                }
                val target = row.requirementValue ?: 0.0
                if (target > 0) {
                    val cur = row.progressCurrent
                    val frac = when {
                        row.isUnlocked -> 1f
                        cur == null -> 0f
                        else -> min(1.0, cur / target).toFloat()
                    }
                    val pct = (frac * 100f).roundToInt().coerceIn(0, 100)
                    Column(
                        Modifier
                            .fillMaxWidth()
                            .padding(top = 4.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Row(
                            Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                stringResource(R.string.achievements_progress_label),
                                style = MaterialTheme.typography.titleSmall
                            )
                            Text(
                                stringResource(R.string.achievements_progress_percent, pct),
                                style = MaterialTheme.typography.titleSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                        LinearProgressIndicator(
                            progress = { frac },
                            modifier = Modifier.fillMaxWidth().height(8.dp),
                        )
                        if (!row.isUnlocked && cur != null && target > 0) {
                            Text(
                                "${formatAchievementGoalNumber(cur)} / ${formatAchievementGoalNumber(target)}",
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                        val goalLine = when (row.requirementType?.lowercase()) {
                            "count" -> stringResource(R.string.achievements_goal_count, formatAchievementGoalNumber(target))
                            "streak" -> stringResource(R.string.achievements_goal_streak, formatAchievementGoalNumber(target))
                            else -> stringResource(R.string.achievements_goal_generic, formatAchievementGoalNumber(target))
                        }
                        Text(
                            goalLine,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        if (!row.isUnlocked && cur == null) {
                            Text(
                                stringResource(R.string.achievements_progress_live_hint),
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.outline
                            )
                        }
                    }
                }
                val pctComm = row.communityPctUnlocked
                val nComm = row.communitySampleSize
                if (pctComm != null && nComm != null && nComm > 0) {
                    Column(
                        Modifier
                            .fillMaxWidth()
                            .padding(top = 4.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp)
                    ) {
                        Text(
                            stringResource(R.string.achievements_community_headline),
                            style = MaterialTheme.typography.titleSmall
                        )
                        Text(
                            stringResource(R.string.achievements_community_body, pctComm),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
                Text(
                    (row.description?.trim()?.takeIf { it.isNotEmpty() }
                        ?: stringResource(R.string.achievements_detail_no_desc)),
                    style = MaterialTheme.typography.bodyMedium
                )
                Spacer(Modifier.height(8.dp))
                OutlinedButton(
                    onClick = { selected = null },
                    modifier = Modifier.fillMaxWidth()
                ) { Text(stringResource(R.string.feature_requests_close)) }
            }
        }
    }
    if (shareAchievementSnapshot != null) {
        val snap = shareAchievementSnapshot!!
        Dialog(
            onDismissRequest = { shareAchievementSnapshot = null },
            properties = DialogProperties(usePlatformDefaultWidth = false)
        ) {
            Surface(Modifier.fillMaxSize()) {
                ShareAchievementToChatSheetContent(
                    supabase = supabase,
                    snapshot = snap,
                    onDone = { shareAchievementSnapshot = null },
                    modifier = Modifier.fillMaxSize()
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AchievementGridTile(
    row: AchievementRowUi,
    onClick: () -> Unit
) {
    val symbol = imageVectorForAchievement(row.code, row.category)
    val a = if (row.isUnlocked) 1f else 0.35f
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier
            .padding(2.dp)
    ) {
        Card(
            onClick = onClick,
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(1f)
        ) {
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(6.dp)
            ) {
                Icon(
                    imageVector = symbol,
                    contentDescription = null,
                    modifier = Modifier
                        .fillMaxSize(0.6f)
                        .alpha(a)
                )
                if (!row.iconUrl.isNullOrBlank()) {
                    AsyncImage(
                        model = row.iconUrl,
                        contentDescription = null,
                        contentScale = ContentScale.Fit,
                        modifier = Modifier
                            .fillMaxSize(0.85f)
                            .alpha(a)
                    )
                }
            }
        }
        Text(
            row.title,
            style = MaterialTheme.typography.labelSmall,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            textAlign = TextAlign.Center,
            modifier = Modifier
                .fillMaxWidth()
                .alpha(if (row.isUnlocked) 1f else 0.6f)
        )
    }
}

private fun parseToInstant(s: String): Instant? =
    runCatching { Instant.parse(s) }.getOrNull()

private fun formatAchievementGoalNumber(v: Double): String =
    if (abs(v - v.toInt()) < 1e-6) v.toInt().toString() else String.format(java.util.Locale.US, "%.1f", v)
