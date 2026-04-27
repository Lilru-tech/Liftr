package com.lilru.liftr.ui.competition

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import com.lilru.liftr.R
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.unit.dp
import com.lilru.liftr.data.BackendContracts
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Columns
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.util.Locale

@Serializable
private data class CRowW(
    val id: Int,
    @SerialName("created_by") val createdBy: String,
    @SerialName("user_a") val userA: String,
    @SerialName("user_b") val userB: String,
    val status: String,
    @SerialName("invite_expires_at") val inviteExpiresAt: String,
    @SerialName("accepted_at") val acceptedAt: String? = null,
    @SerialName("finished_at") val finishedAt: String? = null,
    @SerialName("winner_user_id") val winnerUserId: String? = null,
    @SerialName("created_at") val createdAt: String
)

@Serializable
private data class CGoalW(
    @SerialName("competition_id") val competitionId: Int,
    @SerialName("time_limit_at") val timeLimitAt: String? = null,
    val metric: String? = null,
    @SerialName("target_value") val targetValue: Double? = null
)

@Serializable
private data class CProfW(
    @SerialName("user_id") val userId: String,
    val username: String,
    @SerialName("avatar_url") val avatarUrl: String? = null
)

@Composable
fun CompetitionDetailFromIdScreen(
    supabase: SupabaseClient,
    competitionId: Int,
    onBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    var error by remember { mutableStateOf<String?>(null) }
    var row by remember { mutableStateOf<CompetitionRowUi?>(null) }
    var goal by remember { mutableStateOf<CompetitionGoalUi?>(null) }
    var profs by remember { mutableStateOf<Map<String, ProfileLiteUi>>(emptyMap()) }
    LaunchedEffect(competitionId) {
        error = null
        runCatching {
            val c = supabase.from(BackendContracts.Tables.COMPETITIONS)
                .select {
                    filter { eq("id", competitionId) }
                }
                .decodeList<CRowW>()
                .firstOrNull() ?: error("competition not found")
            val g = supabase.from(BackendContracts.Tables.COMPETITION_GOALS)
                .select {
                    filter { eq("competition_id", competitionId) }
                }
                .decodeList<CGoalW>()
                .firstOrNull()
            val uids = listOf(c.userA, c.userB).distinct()
            val pmap = if (uids.isEmpty()) {
                emptyMap()
            } else {
                supabase.from(BackendContracts.Tables.PROFILES)
                    .select {
                        filter { isIn("user_id", uids) }
                    }
                    .decodeList<CProfW>()
                    .associate { w ->
                        w.userId to ProfileLiteUi(
                            userId = w.userId,
                            username = w.username,
                            avatarUrl = w.avatarUrl
                        )
                    }
            }
            row = c.toUi()
            goal = g?.let { gg ->
                CompetitionGoalUi(
                    competitionId = gg.competitionId,
                    timeLimitAtIso = gg.timeLimitAt,
                    metric = gg.metric,
                    targetValue = gg.targetValue
                )
            }
            profs = pmap
        }.onFailure { e ->
            error = e.message?.take(200) ?: e::class.java.simpleName
        }
    }
    when {
        error != null -> {
            Text(
                stringResource(R.string.competition_detail_load_error, error ?: ""),
                modifier = modifier.padding(16.dp)
            )
        }
        row == null -> {
            Box(modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        }
        else -> {
            CompetitionDetailScreen(
                supabase = supabase,
                competition = row!!,
                goal = goal,
                knownProfiles = profs,
                onBack = onBack,
                modifier = modifier
            )
        }
    }
}

private fun CRowW.toUi() = CompetitionRowUi(
    id = id,
    createdBy = createdBy,
    userA = userA,
    userB = userB,
    status = status.lowercase(Locale.ROOT),
    inviteExpiresAt = inviteExpiresAt,
    acceptedAt = acceptedAt,
    finishedAt = finishedAt,
    winnerUserId = winnerUserId,
    createdAt = createdAt
)
