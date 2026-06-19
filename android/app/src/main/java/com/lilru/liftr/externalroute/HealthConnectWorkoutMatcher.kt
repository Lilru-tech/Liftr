package com.lilru.liftr.externalroute

import androidx.health.connect.client.records.ExerciseSessionRecord
import java.time.Duration
import java.time.Instant
import kotlin.math.abs

data class HealthConnectWorkoutMatchCriteria(
    val startedAt: Instant,
    val endedAt: Instant?,
    val durationSec: Int,
    val exerciseType: Int,
    val preferredSourceBundleIds: List<String>
)

object HealthConnectWorkoutMatcher {
    const val START_TOLERANCE_SEC = 5 * 60L
    const val DURATION_TOLERANCE_RATIO = 0.10
    const val DURATION_TOLERANCE_SEC = 90L

    fun durationMatches(sessionDurationSec: Long, expectedSec: Int): Boolean {
        if (expectedSec <= 0 || sessionDurationSec <= 0) return false
        val delta = abs(sessionDurationSec - expectedSec)
        val ratioThreshold = DURATION_TOLERANCE_RATIO * maxOf(expectedSec, sessionDurationSec.toInt())
        return delta <= maxOf(DURATION_TOLERANCE_SEC, ratioThreshold.toLong())
    }

    fun startTimeDeltaSec(sessionStart: Instant, expectedStart: Instant): Long =
        abs(Duration.between(expectedStart, sessionStart).seconds)

    fun matchesBasicCriteria(
        session: ExerciseSessionRecord,
        criteria: HealthConnectWorkoutMatchCriteria
    ): Boolean {
        if (session.exerciseType != criteria.exerciseType) return false
        val sessionStart = session.startTime
        if (startTimeDeltaSec(sessionStart, criteria.startedAt) > START_TOLERANCE_SEC) return false
        val end = session.endTime ?: return false
        val durationSec = Duration.between(sessionStart, end).seconds
        return durationMatches(durationSec, criteria.durationSec)
    }

    fun findBestMatch(
        sessions: List<ExerciseSessionRecord>,
        criteria: HealthConnectWorkoutMatchCriteria,
        existingRouteCounts: Map<String, Int>
    ): ExerciseSessionRecord? {
        val candidates = sessions.filter { matchesBasicCriteria(it, criteria) }
        if (candidates.isEmpty()) return null
        return candidates.maxByOrNull { session ->
            var score = 0
            val routeCount = existingRouteCounts[session.metadata.id] ?: 0
            if (routeCount == 0) score += 1000
            val bundle = session.metadata.dataOrigin.packageName
            if (criteria.preferredSourceBundleIds.contains(bundle)) score += 500
            score -= startTimeDeltaSec(session.startTime, criteria.startedAt).toInt()
            score
        }
    }
}
