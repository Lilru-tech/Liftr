package com.lilru.liftr.ui.profile

import java.util.Locale
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

data class ProfilePrsListSection(
    val title: String,
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

/**
 * Alinea con [Liftr.ProfileView.PRsListView] (secciones, orden de claves, búsqueda local).
 */
object ProfilePrsGrouping {
    private fun orderTuple(title: String): Pair<Int, String> {
        val lower = title.lowercase(Locale.US)
        return when {
            lower.startsWith("strength") -> 0 to lower
            lower.startsWith("cardio") -> 1 to lower
            lower.startsWith("sport") -> 2 to lower
            else -> 3 to lower
        }
    }

    fun sectionTitleForRow(pr: ProfilePrListRow): String {
        val k = pr.kind.replaceFirstChar { c ->
            if (c.isLowerCase()) c.titlecase(Locale.getDefault()) else c.toString()
        }
        val l = pr.label.replaceFirstChar { c ->
            if (c.isLowerCase()) c.titlecase(Locale.getDefault()) else c.toString()
        }
        return "$k · $l"
    }

    fun filterBySearch(rows: List<ProfilePrListRow>, q: String): List<ProfilePrListRow> {
        val t = q.trim()
        if (t.isEmpty()) return rows
        return rows.filter { r ->
            r.label.contains(t, ignoreCase = true) ||
                r.metric.contains(t, ignoreCase = true)
        }
    }

    private fun timeKey(iso: String?): Long =
        if (iso.isNullOrBlank()) 0L else {
            runCatching { Instant.parse(iso.trim()).toEpochMilli() }.getOrDefault(0L)
        }

    fun buildSections(allRows: List<ProfilePrListRow>, searchQuery: String): List<ProfilePrsListSection> {
        val rows = filterBySearch(allRows, searchQuery)
        if (rows.isEmpty()) return emptyList()
        val byTitle = rows.groupBy { sectionTitleForRow(it) }
        val sortedKeys = byTitle.keys.sortedWith { a, b ->
            val oa = orderTuple(a)
            val ob = orderTuple(b)
            if (oa.first != ob.first) oa.first.compareTo(ob.first) else a.compareTo(b)
        }
        return sortedKeys.map { key ->
            val items = (byTitle[key] ?: emptyList())
                .sortedByDescending { timeKey(it.achievedAt) }
            ProfilePrsListSection(title = key, items = items)
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
