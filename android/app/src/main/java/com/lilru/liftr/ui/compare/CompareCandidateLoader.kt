package com.lilru.liftr.ui.compare

import com.lilru.liftr.data.BackendContracts
import com.lilru.liftr.ui.home.WorkoutDetailRow
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import java.time.Instant
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

@Serializable
private data class CompareCandidateWire(
    @SerialName("candidate_id") val candidateId: Int,
    val title: String? = null,
    val kind: String,
    val sport: String? = null,
    val activity: String? = null,
    @SerialName("started_at") val startedAt: String,
    @SerialName("owner_username") val ownerUsername: String? = null
)

@Serializable
private data class WorkoutOwnerRow(
    val id: Int,
    @SerialName("user_id") val userId: String
)

@Serializable
private data class ProfileUsernameRow(
    @SerialName("user_id") val userId: String,
    val username: String? = null
)

@Serializable
private data class WeMuscleRow(
    @SerialName("workout_id") val workoutId: Int,
    val exercises: MuscleRef? = null
)

@Serializable
private data class MuscleRef(
    @SerialName("muscle_primary") val musclePrimary: String? = null
)

@Serializable
private data class SportOnlyRow(
    val sport: String? = null
)

@Serializable
private data class CardioBaselineRow(
    @SerialName("activity_code") val activityCode: String? = null,
    val modality: String? = null
)

data class CompareCandidateLoadResult(
    val candidates: List<CompareWorkoutCandidate>,
    val defaultOtherId: Int?
)

object CompareCandidateLoader {
    private val json = Json { ignoreUnknownKeys = true }

    private inline fun <reified T> decodeFlexibleList(raw: String): List<T> {
        val root = json.parseToJsonElement(raw)
        return when (root) {
            is JsonArray -> root.map { json.decodeFromString<T>(it.toString()) }
            is JsonObject -> listOf(json.decodeFromString<T>(root.toString()))
            else -> emptyList()
        }
    }

    suspend fun load(
        supabase: SupabaseClient,
        sessionUserId: String,
        currentWorkoutId: Int,
        workout: WorkoutDetailRow
    ): CompareCandidateLoadResult {
        val params = buildJsonObject {
            put("p_viewer", sessionUserId)
            put("p_workout", currentWorkoutId)
            put("p_limit", 120)
        }
        val res = supabase.postgrest.rpc(BackendContracts.Rpc.LIST_COMPARABLE_WORKOUTS_V1, params) { }
        val wires = decodeFlexibleList<CompareCandidateWire>(res.data)
        if (wires.isEmpty()) {
            return CompareCandidateLoadResult(emptyList(), null)
        }
        val candidates = enrichWithOwnerUsernames(supabase, wires).map { it.toCandidate() }
        val sorted = sortForPicker(
            supabase = supabase,
            baselineId = currentWorkoutId,
            kind = workout.kind,
            rows = candidates
        )
        val def = sorted.firstOrNull()?.id
        return CompareCandidateLoadResult(candidates = sorted, defaultOtherId = def)
    }

    private suspend fun enrichWithOwnerUsernames(
        supabase: SupabaseClient,
        wires: List<CompareCandidateWire>
    ): List<CompareCandidateWire> {
        if (wires.isEmpty()) return wires
        val ids = wires.map { it.candidateId }
        return runCatching {
            val wRes = supabase
                .from(BackendContracts.Tables.WORKOUTS)
                .select(columns = Columns.raw("id, user_id")) {
                    filter { isIn("id", ids) }
                }
            val owners = decodeFlexibleList<WorkoutOwnerRow>(wRes.data)
            if (owners.isEmpty()) return wires
            val idToUser = owners.associate { it.id to it.userId }
            val uids = owners.map { it.userId }.distinct()
            if (uids.isEmpty()) return wires
            val pRes = supabase
                .from(BackendContracts.Tables.PROFILES)
                .select(columns = Columns.raw("user_id, username")) {
                    filter { isIn("user_id", uids) }
                }
            val profs = decodeFlexibleList<ProfileUsernameRow>(pRes.data)
            val uidToName: Map<String, String> = profs.mapNotNull { p ->
                val n = p.username?.trim().orEmpty()
                if (n.isEmpty()) null else p.userId to n
            }.toMap()
            wires.map { w ->
                val uid = idToUser[w.candidateId] ?: return@map w
                val un = uidToName[uid] ?: return@map w
                w.copy(ownerUsername = w.ownerUsername ?: un)
            }
        }.getOrDefault(wires)
    }

    private fun CompareCandidateWire.toCandidate() = CompareWorkoutCandidate(
        id = candidateId,
        title = title,
        kind = kind,
        sport = sport,
        activity = activity,
        startedAtIso = startedAt,
        ownerUsername = ownerUsername
    )

    private fun parseStarted(c: CompareWorkoutCandidate): Instant =
        runCatching { Instant.parse(c.startedAtIso.trim()) }.getOrNull() ?: Instant.EPOCH

    private val byDateDesc: Comparator<CompareWorkoutCandidate> =
        Comparator { a, b -> parseStarted(b).compareTo(parseStarted(a)) }

    private suspend fun sortForPicker(
        supabase: SupabaseClient,
        baselineId: Int,
        kind: String?,
        rows: List<CompareWorkoutCandidate>
    ): List<CompareWorkoutCandidate> {
        if (rows.isEmpty()) return rows
        return runCatching {
            when (kind?.lowercase()) {
                "strength" -> sortStrength(supabase, baselineId, rows)
                "sport" -> sortSport(supabase, baselineId, rows)
                "cardio" -> sortCardio(supabase, baselineId, rows)
                else -> rows.sortedWith(byDateDesc)
            }
        }.getOrElse { rows.sortedWith(byDateDesc) }
    }

    private suspend fun sortStrength(
        supabase: SupabaseClient,
        baseline: Int,
        rows: List<CompareWorkoutCandidate>
    ): List<CompareWorkoutCandidate> {
        val ids = (listOf(baseline) + rows.map { it.id }).toSet().toList()
        val muscleByW = fetchPrimaryMusclesByWorkout(supabase, ids)
        val baselineMuscles = muscleByW[baseline] ?: emptySet()
        fun tier(c: CompareWorkoutCandidate): Int {
            if (baselineMuscles.isEmpty()) return 2
            val cm = muscleByW[c.id] ?: emptySet()
            if (cm.isEmpty()) return 2
            if (baselineMuscles == cm) return 0
            if (baselineMuscles.intersect(cm).isNotEmpty()) return 1
            return 2
        }
        return rows.sortedWith(compareBy<CompareWorkoutCandidate> { tier(it) }.then(byDateDesc))
    }

    private suspend fun sortSport(
        supabase: SupabaseClient,
        baseline: Int,
        rows: List<CompareWorkoutCandidate>
    ): List<CompareWorkoutCandidate> {
        val raw = runCatching { fetchBaselineSport(supabase, baseline) }.getOrNull() ?: return rows.sortedWith(byDateDesc)
        val b = raw.trim().lowercase()
        if (b.isEmpty()) return rows.sortedWith(byDateDesc)
        fun normSport(c: CompareWorkoutCandidate) = (c.sport ?: "").trim().lowercase()
        fun matches(c: CompareWorkoutCandidate) = normSport(c) == b
        return rows.sortedWith(compareBy<CompareWorkoutCandidate> { !matches(it) }.then(byDateDesc))
    }

    private suspend fun sortCardio(
        supabase: SupabaseClient,
        baseline: Int,
        rows: List<CompareWorkoutCandidate>
    ): List<CompareWorkoutCandidate> {
        val b = runCatching { fetchBaselineCardioCode(supabase, baseline) }.getOrNull()
        if (b.isNullOrEmpty()) return rows.sortedWith(byDateDesc)
        fun norm(c: CompareWorkoutCandidate) = (c.activity ?: "").trim().lowercase()
        fun matches(c: CompareWorkoutCandidate) = norm(c) == b
        return rows.sortedWith(compareBy<CompareWorkoutCandidate> { !matches(it) }.then(byDateDesc))
    }

    private suspend fun fetchPrimaryMusclesByWorkout(
        supabase: SupabaseClient,
        ids: List<Int>
    ): Map<Int, Set<String>> {
        if (ids.isEmpty()) return emptyMap()
        val wRes = supabase
            .from(BackendContracts.Tables.WORKOUT_EXERCISES)
            .select(columns = Columns.raw("workout_id, exercises(muscle_primary)")) {
                filter { isIn("workout_id", ids) }
            }
        val decoded = decodeFlexibleList<WeMuscleRow>(wRes.data)
        val map = mutableMapOf<Int, MutableSet<String>>()
        for (r in decoded) {
            val m = (r.exercises?.musclePrimary ?: "").trim().lowercase()
            if (m.isEmpty() || m == "cardio") continue
            map.getOrPut(r.workoutId) { mutableSetOf() }.add(m)
        }
        return map.mapValues { it.value }
    }

    private suspend fun fetchBaselineSport(supabase: SupabaseClient, workoutId: Int): String? {
        val r = supabase
            .from(BackendContracts.Tables.SPORT_SESSIONS)
            .select(columns = Columns.raw("sport")) {
                filter { eq("workout_id", workoutId) }
                limit(1)
            }
        return decodeFlexibleList<SportOnlyRow>(r.data).firstOrNull()?.sport
    }

    private suspend fun fetchBaselineCardioCode(supabase: SupabaseClient, workoutId: Int): String? {
        val r = supabase
            .from(BackendContracts.Tables.CARDIO_SESSIONS)
            .select(columns = Columns.raw("activity_code, modality")) {
                filter { eq("workout_id", workoutId) }
                limit(1)
            }
        val row = decodeFlexibleList<CardioBaselineRow>(r.data).firstOrNull() ?: return null
        val raw = (if (!row.activityCode.isNullOrBlank()) row.activityCode else row.modality) ?: ""
        return raw.trim().lowercase()
    }
}
