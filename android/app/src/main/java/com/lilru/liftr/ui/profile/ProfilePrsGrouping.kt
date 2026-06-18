package com.lilru.liftr.ui.profile

import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale

data class ProfilePrsListSection(
    val title: String,
    val icon: String,
    val kind: String,
    val label: String,
    val items: List<ProfilePrListRow>
)

data class ProfilePrListRow(
    val kind: String,
    val label: String,
    val metric: String,
    val value: Double,
    val achievedAt: String? = null
) {
    val listId: String
        get() = "${kind}|${label}|${metric}|${achievedAt ?: "0"}"
}

enum class PrKindFilter {
    ALL,
    STRENGTH,
    CARDIO,
    SPORT
}

object ProfilePrsGrouping {
    data class ActivityKey(val kind: String, val label: String)

    fun activityKeyForRow(pr: ProfilePrListRow): ActivityKey =
        ActivityKey(kind = pr.kind.lowercase(Locale.US), label = pr.label.lowercase(Locale.US))

    fun filterBySearch(rows: List<ProfilePrListRow>, q: String): List<ProfilePrListRow> {
        val t = q.trim()
        if (t.isEmpty()) return rows
        return rows.filter { r ->
            val display = PrFormatting.activityLabel(r.kind, r.label)
            display.contains(t, ignoreCase = true) ||
                r.label.contains(t, ignoreCase = true) ||
                r.metric.contains(t, ignoreCase = true) ||
                PrFormatting.prettyMetricName(r.metric, r.kind, r.label).contains(t, ignoreCase = true)
        }
    }

    private fun timeKey(iso: String?): Long =
        if (iso.isNullOrBlank()) 0L else {
            runCatching { Instant.parse(iso.trim()).toEpochMilli() }.getOrDefault(0L)
        }

    fun buildSections(allRows: List<ProfilePrListRow>, searchQuery: String): List<ProfilePrsListSection> {
        val rows = filterBySearch(allRows, searchQuery)
        if (rows.isEmpty()) return emptyList()
        val byActivity = rows.groupBy { activityKeyForRow(it) }
        val sortedKeys = byActivity.keys.sortedWith { a, b ->
            val ka = PrFormatting.kindSortOrder(a.kind)
            val kb = PrFormatting.kindSortOrder(b.kind)
            if (ka != kb) return@sortedWith ka.compareTo(kb)
            PrFormatting.activityLabel(a.kind, a.label)
                .compareTo(PrFormatting.activityLabel(b.kind, b.label), ignoreCase = true)
        }
        return sortedKeys.map { key ->
            val items = (byActivity[key] ?: emptyList())
                .sortedWith(
                    compareBy<ProfilePrListRow> { PrFormatting.metricSortOrder(it.metric) }
                        .thenByDescending { timeKey(it.achievedAt) }
                )
            ProfilePrsListSection(
                title = PrFormatting.activityLabel(key.kind, key.label),
                icon = PrFormatting.activityIcon(key.kind, key.label),
                kind = key.kind,
                label = key.label,
                items = items
            )
        }
    }

    fun dateOnlyMedium(iso: String?): String {
        if (iso.isNullOrBlank()) return "—"
        return runCatching {
            val instant = Instant.parse(iso.trim())
            val d = instant.atZone(ZoneId.systemDefault()).toLocalDate()
            d.format(
                DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM)
                    .withLocale(Locale.getDefault())
            )
        }.getOrElse { iso.substringBefore("T") }
    }
}
