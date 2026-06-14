package com.lilru.liftr.climbing

import java.util.Locale
import java.util.UUID
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.add
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

enum class ClimbingEnvironment(val wire: String, val label: String) {
    INDOOR("indoor", "Indoor"),
    OUTDOOR("outdoor", "Outdoor");

    companion object {
        fun fromWire(value: String?): ClimbingEnvironment =
            entries.firstOrNull { it.wire == value?.trim()?.lowercase() } ?: INDOOR
    }
}

enum class ClimbingStyle(val wire: String, val label: String) {
    BOULDER("boulder", "Boulder"),
    TOP_ROPE("top_rope", "Top rope"),
    LEAD("lead", "Lead"),
    TRAD("trad", "Trad"),
    MIXED("mixed", "Mixed");

    companion object {
        fun fromWire(value: String?): ClimbingStyle =
            entries.firstOrNull { it.wire == value?.trim()?.lowercase() } ?: BOULDER
    }
}

enum class ClimbingGradeSystem(val wire: String, val label: String) {
    V_SCALE("v_scale", "V-scale"),
    FONT("font", "Font"),
    FRENCH("french", "French"),
    YDS("yds", "YDS");

    companion object {
        fun fromWire(value: String?): ClimbingGradeSystem =
            entries.firstOrNull { it.wire == value?.trim()?.lowercase() } ?: V_SCALE

        fun grades(system: ClimbingGradeSystem): List<String> = when (system) {
            V_SCALE -> (0..12).map { "V$it" }
            FONT -> listOf(
                "4", "4+", "5", "5+", "6A", "6A+", "6B", "6B+", "6C", "6C+", "7A", "7A+", "7B", "7B+", "7C", "7C+", "8A", "8A+", "8B", "8B+", "8C", "8C+", "9A"
            )
            FRENCH -> listOf(
                "3", "4", "4+", "5a", "5b", "5c", "6a", "6a+", "6b", "6b+", "6c", "6c+", "7a", "7a+", "7b", "7b+", "7c", "7c+", "8a", "8a+", "8b", "8b+", "8c", "8c+", "9a"
            )
            YDS -> listOf(
                "5.5", "5.6", "5.7", "5.8", "5.9", "5.10a", "5.10b", "5.10c", "5.10d",
                "5.11a", "5.11b", "5.11c", "5.11d", "5.12a", "5.12b", "5.12c", "5.12d",
                "5.13a", "5.13b", "5.13c", "5.13d", "5.14a", "5.14b", "5.14c", "5.14d", "5.15a"
            )
        }

        fun defaultForStyle(style: ClimbingStyle): ClimbingGradeSystem = when (style) {
            ClimbingStyle.BOULDER -> V_SCALE
            else -> FRENCH
        }
    }
}

data class ClimbingRouteForm(
    val id: String = UUID.randomUUID().toString(),
    val routeName: String = "",
    val style: ClimbingStyle = ClimbingStyle.BOULDER,
    val gradeSystem: ClimbingGradeSystem = ClimbingGradeSystem.V_SCALE,
    val gradeValue: String = "",
    val attempts: String = "",
    val sent: Boolean = false,
    val flash: Boolean = false,
    val notes: String = ""
)

object ClimbingRouteFormatting {
    fun displayGrade(system: ClimbingGradeSystem, value: String): String {
        val v = value.trim()
        if (v.isEmpty()) return "—"
        return when (system) {
            ClimbingGradeSystem.V_SCALE -> if (v.uppercase(Locale.US).startsWith("V")) v.uppercase(Locale.US) else "V$v"
            ClimbingGradeSystem.FONT, ClimbingGradeSystem.FRENCH -> v
            ClimbingGradeSystem.YDS -> if (v.startsWith("5.")) v else "5.$v"
        }
    }

    fun syncSessionSummary(routes: List<ClimbingRouteForm>, stats: MutableMap<String, String>) {
        val sentRoutes = routes.filter { it.sent }
        stats["routes_sent"] = sentRoutes.size.toString()
        val attempts = routes.mapNotNull { it.attempts.trim().toIntOrNull() }.sum()
        stats["routes_attempted"] = if (attempts > 0) {
            attempts.toString()
        } else {
            maxOf(sentRoutes.size, routes.size).toString()
        }
        stats["flashes"] = sentRoutes.count { it.flash }.toString()
        val best = sentRoutes.maxByOrNull { gradeRank(it) }
        if (best != null && best.gradeValue.trim().isNotEmpty()) {
            stats["highest_grade_system"] = best.gradeSystem.wire
            stats["highest_grade_value"] = best.gradeValue.trim()
        }
    }

    fun encodeRoutesJson(routes: List<ClimbingRouteForm>): String {
        if (routes.isEmpty()) return "[]"
        return buildJsonArray {
            routes.forEachIndexed { index, route ->
                add(buildJsonObject {
                    put("route_order", index + 1)
                    route.routeName.trim().takeIf { it.isNotEmpty() }?.let { put("route_name", it) }
                    put("style", route.style.wire)
                    route.gradeValue.trim().takeIf { it.isNotEmpty() }?.let { gv ->
                        put("grade_system", route.gradeSystem.wire)
                        put("grade_value", gv)
                    }
                    route.attempts.trim().toIntOrNull()?.let { put("attempts", it) }
                    put("sent", route.sent)
                    put("flash", route.flash)
                    route.notes.trim().takeIf { it.isNotEmpty() }?.let { put("notes", it) }
                })
            }
        }.toString()
    }

    fun decodeRoutesJson(text: String): List<ClimbingRouteForm> {
        val trimmed = text.trim()
        if (trimmed.isEmpty() || trimmed == "[]") return emptyList()
        val arr = runCatching { kotlinx.serialization.json.Json.parseToJsonElement(trimmed).jsonArray }
            .getOrNull() ?: return emptyList()
        return arr.mapNotNull { el ->
            val o = el as? JsonObject ?: return@mapNotNull null
            ClimbingRouteForm(
                routeName = o["route_name"]?.jsonPrimitive?.contentOrNull.orEmpty(),
                style = ClimbingStyle.fromWire(o["style"]?.jsonPrimitive?.contentOrNull),
                gradeSystem = ClimbingGradeSystem.fromWire(o["grade_system"]?.jsonPrimitive?.contentOrNull),
                gradeValue = o["grade_value"]?.jsonPrimitive?.contentOrNull.orEmpty(),
                attempts = o["attempts"]?.jsonPrimitive?.contentOrNull.orEmpty(),
                sent = o["sent"]?.jsonPrimitive?.contentOrNull?.toBooleanStrictOrNull() == true,
                flash = o["flash"]?.jsonPrimitive?.contentOrNull?.toBooleanStrictOrNull() == true,
                notes = o["notes"]?.jsonPrimitive?.contentOrNull.orEmpty()
            )
        }
    }

    private fun gradeRank(route: ClimbingRouteForm): Double {
        val v = route.gradeValue.trim()
        if (v.isEmpty()) return -1.0
        return when (route.gradeSystem) {
            ClimbingGradeSystem.V_SCALE -> {
                val n = v.replace(Regex("(?i)^V"), "")
                n.toDoubleOrNull() ?: -1.0
            }
            ClimbingGradeSystem.FONT, ClimbingGradeSystem.FRENCH -> {
                ClimbingGradeSystem.grades(route.gradeSystem).indexOf(v).toDouble()
            }
            ClimbingGradeSystem.YDS -> {
                ClimbingGradeSystem.grades(ClimbingGradeSystem.YDS).indexOf(v).toDouble()
            }
        }
    }
}
