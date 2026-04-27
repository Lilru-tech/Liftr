package com.lilru.liftr.ui.add.recommendation

import kotlin.math.max
import kotlin.math.min

/**
 * iOS HyroxExerciseFormatting: [HyroxWeightTier], [officialRaceHyroxWithRuns], [sanitize].
 */
internal enum class HyroxWeightTier {
    OPEN_WOMEN,
    OPEN_MEN,
    PRO_MEN;

    val sledPushKg: Double
        get() = when (this) {
            OPEN_WOMEN -> 102.0
            OPEN_MEN -> 152.0
            PRO_MEN -> 202.0
        }

    val sledPullKg: Double
        get() = when (this) {
            OPEN_WOMEN -> 78.0
            OPEN_MEN -> 103.0
            PRO_MEN -> 153.0
        }

    val farmerCarryKgPerImplement: Double
        get() = when (this) {
            OPEN_WOMEN -> 16.0
            OPEN_MEN -> 24.0
            PRO_MEN -> 32.0
        }

    val sandbagKg: Double
        get() = when (this) {
            OPEN_WOMEN -> 10.0
            OPEN_MEN -> 20.0
            PRO_MEN -> 30.0
        }

    val wallBallKg: Double
        get() = when (this) {
            OPEN_WOMEN -> 4.0
            OPEN_MEN -> 6.0
            PRO_MEN -> 9.0
        }
}

private enum class HyroxExerciseCode(val wire: String) {
    RUN("run"),
    SKIERG("skierg"),
    BURPEE_BROAD_JUMP("burpee_broad_jump"),
    SLED_PUSH("sled_push"),
    SLED_PULL("sled_pull"),
    ROW("row"),
    FARMER_CARRY("farmer_carry"),
    SANDBAG_LUNGES("sandbag_lunges"),
    WALL_BALL("wall_ball"),
    ATLAS_CARRY("atlas_carry"),
    BOX_JUMP_OVER("box_jump_over"),
    DEAD_BALL_OVER_TRUNK("dead_ball_over_trunk")
}

internal fun inferHyroxWeightTier(
    sandbagMedian: Double?,
    wallBallMedian: Double?,
    sledPushMedian: Double?
): HyroxWeightTier {
    val v = sandbagMedian ?: wallBallMedian ?: sledPushMedian ?: return HyroxWeightTier.OPEN_MEN
    if (v < 15) return HyroxWeightTier.OPEN_WOMEN
    if (v < 26) return HyroxWeightTier.OPEN_MEN
    return HyroxWeightTier.PRO_MEN
}

internal fun officialRaceHyroxWithRuns(
    tier: HyroxWeightTier,
    runDistanceM: Int,
    stationCount: Int
): List<HyroxExerciseRecommendationResult> {
    val w = tier
    val runM = min(max(runDistanceM, 400), 5000)
    val stationsFull = officialRaceStationSequence(w)
    val n = min(8, max(3, min(stationCount, 8)))
    val picked = stationsFull.take(n)
    var order = 1
    val out = mutableListOf<HyroxExerciseRecommendationResult>()
    for (station in picked) {
        out.add(
            HyroxExerciseRecommendationResult(
                exerciseCode = HyroxExerciseCode.RUN.wire,
                customDisplayName = "",
                exerciseOrder = order++,
                distanceM = runM,
                reps = null,
                weightKg = null,
                durationSec = null,
                heightCm = null,
                implementCount = null,
                notes = null
            )
        )
        out.add(
            HyroxExerciseRecommendationResult(
                exerciseCode = station.exerciseCode,
                customDisplayName = station.customDisplayName,
                exerciseOrder = order++,
                distanceM = station.distanceM,
                reps = station.reps,
                weightKg = station.weightKg,
                durationSec = station.durationSec,
                heightCm = station.heightCm,
                implementCount = station.implementCount,
                notes = null
            )
        )
    }
    return out.map { sanitizeHyroxExerciseRecommendation(it) }
}

private data class StationLine(
    val exerciseCode: String,
    val customDisplayName: String = "",
    val distanceM: Int? = null,
    val reps: Int? = null,
    val weightKg: Double? = null,
    val durationSec: Int? = null,
    val heightCm: Int? = null,
    val implementCount: Int? = null
)

private fun officialRaceStationSequence(tier: HyroxWeightTier): List<StationLine> {
    val w = tier
    return listOf(
        StationLine(HyroxExerciseCode.SKIERG.wire, distanceM = 1000),
        StationLine(HyroxExerciseCode.SLED_PULL.wire, distanceM = 50, weightKg = w.sledPullKg),
        StationLine(HyroxExerciseCode.SLED_PUSH.wire, distanceM = 50, weightKg = w.sledPushKg),
        StationLine(HyroxExerciseCode.BURPEE_BROAD_JUMP.wire, distanceM = 80),
        StationLine(HyroxExerciseCode.ROW.wire, distanceM = 1000),
        StationLine(
            HyroxExerciseCode.FARMER_CARRY.wire,
            distanceM = 200,
            weightKg = w.farmerCarryKgPerImplement,
            implementCount = 2
        ),
        StationLine(HyroxExerciseCode.SANDBAG_LUNGES.wire, distanceM = 100, weightKg = w.sandbagKg),
        StationLine(HyroxExerciseCode.WALL_BALL.wire, reps = 100, weightKg = w.wallBallKg)
    )
}

internal fun sanitizeHyroxExerciseRecommendation(
    ex: HyroxExerciseRecommendationResult
): HyroxExerciseRecommendationResult {
    val code = ex.exerciseCode.lowercase()
    val std = HyroxExerciseCode.entries.firstOrNull { it.wire == code }
    return if (std != null) {
        sanitizeStandard(std, ex)
    } else {
        sanitizeCustomStation(ex)
    }
}

private fun sanitizeStandard(
    t: HyroxExerciseCode,
    ex: HyroxExerciseRecommendationResult
): HyroxExerciseRecommendationResult {
    var d = ex.distanceM
    var r = ex.reps
    var w = ex.weightKg
    var dur = ex.durationSec
    var h = ex.heightCm
    var imp = ex.implementCount

    when (t) {
        HyroxExerciseCode.RUN -> {
            if (d == null || d < 200) d = 1000
            d = d?.let { min(max(it, 400), 5000) }
            if (r != null && r > 30) r = null
            w = null
            h = null
            imp = null
        }
        HyroxExerciseCode.SKIERG, HyroxExerciseCode.ROW -> {
            if (d == null || d < 200 || d > 6000) d = 1000
            d = d?.let { min(max(it, 200), 5000) }
            r = null
            w = null
            h = null
            imp = null
            if (dur != null && dur > 3600) dur = 3600
        }
        HyroxExerciseCode.SLED_PUSH, HyroxExerciseCode.SLED_PULL -> {
            if (d == null || d > 500) d = 50
            d = d?.let { min(max(it, 25), 200) }
            if (r != null && r > 20) r = null
            h = null
            imp = null
            if (w != null && (w > 350 || w < 20)) w = null
        }
        HyroxExerciseCode.BURPEE_BROAD_JUMP -> {
            d = when {
                d != null && d in 40..200 -> d
                r != null && r in 40..200 && (d == null || d < 40) -> {
                    val nr = r!!
                    r = null
                    nr
                }
                else -> {
                    r = null
                    80
                }
            }
            w = null
            h = null
            imp = null
            dur = null
        }
        HyroxExerciseCode.FARMER_CARRY -> {
            if (d == null || d > 1000) d = 200
            d = d?.let { min(max(it, 50), 400) }
            r = null
            h = null
            if (imp == null || imp == 0) imp = 2
            if (w != null && (w > 60 || w < 4)) w = null
        }
        HyroxExerciseCode.SANDBAG_LUNGES -> {
            d = if (d != null && d in 40..300) d else 100
            r = null
            h = null
            imp = null
            if (w != null) {
                val snapped = listOf(10.0, 20.0, 30.0).minBy { kotlin.math.abs(it - w) }
                w = snapped
            }
            dur = null
        }
        HyroxExerciseCode.WALL_BALL -> {
            d = null
            h = null
            imp = null
            r = if (r != null && r in 30..150) r else 100
            if (w != null) {
                w = if (w > 12 || w < 2) {
                    null
                } else {
                    listOf(4.0, 6.0, 9.0).minBy { kotlin.math.abs(it - w) }
                }
            }
        }
        HyroxExerciseCode.BOX_JUMP_OVER -> {
            if (r != null && r > 200) r = min(r, 120)
            if (h != null && (h > 200 || h < 20)) h = null
            w = null
            imp = null
            if (d != null && d > 500) d = null
        }
        else -> {
            if (r != null && r > 500) r = null
            if (d != null && d > 50_000) d = null
            if (h != null && h > 400) h = null
        }
    }

    return HyroxExerciseRecommendationResult(
        exerciseCode = ex.exerciseCode,
        customDisplayName = ex.customDisplayName,
        exerciseOrder = ex.exerciseOrder,
        distanceM = d,
        reps = r,
        weightKg = w,
        durationSec = dur,
        heightCm = h,
        implementCount = imp,
        notes = null
    )
}

private fun sanitizeCustomStation(
    ex: HyroxExerciseRecommendationResult
): HyroxExerciseRecommendationResult {
    val r = ex.reps?.let { min(it, 500) }
    val d = ex.distanceM?.let { min(it, 50_000) }
    val h = ex.heightCm?.let { min(it, 400) }
    return HyroxExerciseRecommendationResult(
        exerciseCode = ex.exerciseCode,
        customDisplayName = ex.customDisplayName,
        exerciseOrder = ex.exerciseOrder,
        distanceM = d,
        reps = r,
        weightKg = ex.weightKg,
        durationSec = ex.durationSec?.let { min(it, 36_000) },
        heightCm = h,
        implementCount = ex.implementCount?.let { min(it, 50) },
        notes = null
    )
}
