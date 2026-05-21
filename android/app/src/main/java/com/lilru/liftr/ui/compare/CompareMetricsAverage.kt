package com.lilru.liftr.ui.compare

internal fun averageCompareMetricRows(perSession: List<List<CompareMetricRow>>): List<CompareMetricRow> {
    if (perSession.isEmpty()) return emptyList()
    val leftByKey = perSession.first().associate { it.key to it.left }
    val units = mutableMapOf<String, String>()
    val rightAcc = mutableMapOf<String, MutableList<Double>>()
    for (rows in perSession) {
        for (r in rows) {
            units[r.key] = r.unit
            rightAcc.getOrPut(r.key) { mutableListOf() }.add(r.right)
        }
    }
    val keys = (leftByKey.keys + rightAcc.keys).sorted()
    return keys.mapNotNull { key ->
        val left = leftByKey[key] ?: return@mapNotNull null
        val rights = rightAcc[key] ?: return@mapNotNull null
        if (rights.isEmpty()) return@mapNotNull null
        CompareMetricRow(
            key = key,
            unit = units[key] ?: "count",
            left = left,
            right = rights.average()
        )
    }
}
