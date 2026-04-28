package com.lilru.liftr.ui.feature

import android.text.format.DateUtils
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.lilru.liftr.R
import com.lilru.liftr.ui.components.LiftrBackTopBar
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import java.time.Instant

@Composable
fun FeatureRequestDetailScreen(
    supabase: SupabaseClient,
    row: FeatureRequestRow,
    onBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    val vm: FeatureRequestDetailViewModel = viewModel(
        key = "fr-detail-${row.id}",
        factory = FeatureRequestDetailViewModelFactory(supabase, row.id)
    )
    val st by vm.uiState.collectAsStateWithLifecycle()
    val me = supabase.auth.currentUserOrNull()?.id

    Column(
        modifier = modifier
            .fillMaxSize()
            .statusBarsPadding()
            .padding(12.dp)
            .verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        LiftrBackTopBar(onBack = onBack)
        Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.4f)
            )
        ) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(row.title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                Text(
                    row.description,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text(
                        stringResource(R.string.feature_requests_submitted_by),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Text(
                        row.createdByUsername ?: featureShortUser(row.createdBy),
                        style = MaterialTheme.typography.labelSmall
                    )
                }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text(
                        stringResource(R.string.feature_requests_created),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Text(
                        relTimeIso(row.createdAt),
                        style = MaterialTheme.typography.labelSmall
                    )
                }
            }
        }
        Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.4f)
            )
        ) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
                    Text(
                        stringResource(R.string.feature_requests_comments_title),
                        style = MaterialTheme.typography.titleSmall
                    )
                    if (st.loading) {
                        CircularProgressIndicator(Modifier.padding(4.dp), strokeWidth = 2.dp)
                    }
                }
                if (st.error != null) {
                    Text(st.error!!, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                }
                if (!st.loading && st.comments.isEmpty()) {
                    Text(
                        stringResource(R.string.feature_requests_no_comments),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        style = MaterialTheme.typography.bodySmall
                    )
                }
                st.comments.forEach { c ->
                    Card(
                        colors = CardDefaults.cardColors(
                            containerColor = MaterialTheme.colorScheme.surface
                        )
                    ) {
                        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                Text(
                                    c.userUsername ?: featureShortUser(c.userId),
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                                Text(
                                    relTimeIso(c.createdAt),
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                            Text(c.body, style = MaterialTheme.typography.bodySmall)
                        }
                    }
                }
            }
        }
        if (me != null) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    stringResource(R.string.feature_requests_add_comment),
                    style = MaterialTheme.typography.titleSmall
                )
                OutlinedTextField(
                    value = st.commentDraft,
                    onValueChange = vm::setCommentDraft,
                    modifier = Modifier.fillMaxWidth(),
                    minLines = 3,
                    maxLines = 6,
                    label = { Text(stringResource(R.string.feature_requests_comment_hint)) },
                    keyboardOptions = KeyboardOptions(
                        capitalization = KeyboardCapitalization.Sentences
                    )
                )
                Text(
                    stringResource(R.string.feature_requests_char_count, st.commentDraft.length, 500),
                    style = MaterialTheme.typography.labelSmall
                )
                Button(
                    onClick = { vm.postComment() },
                    enabled = st.commentDraft.isNotBlank() && !st.sendingComment,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(
                        if (st.sendingComment) {
                            stringResource(R.string.feature_requests_sending_comment)
                        } else {
                            stringResource(R.string.feature_requests_post_comment)
                        }
                    )
                }
            }
        } else {
            Text(
                stringResource(R.string.feature_requests_login_to_comment),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

fun featureShortUser(id: String): String = id.take(8)

fun relTimeIso(iso: String?): String {
    if (iso.isNullOrBlank()) return "—"
    return runCatching {
        val ms = Instant.parse(iso).toEpochMilli()
        DateUtils.getRelativeTimeSpanString(
            ms,
            System.currentTimeMillis(),
            DateUtils.MINUTE_IN_MILLIS
        ).toString()
    }.getOrElse { iso.take(19) }
}
