package com.lilru.liftr.nutrition

import android.util.Log
import com.lilru.liftr.BuildConfig
import java.text.Normalizer
import kotlin.math.abs
import kotlin.math.round

object NutritionLabelSpatialParser {
    private const val logTag = "NutritionOCR"
    private const val rowClusterTolerance = 0.03f
    private const val yRayToleranceFraction = 0.01f
    private const val yRayTolerancePixels = 7f
    private const val ySaltRayToleranceFraction = 0.025f
    private const val ySaltRayTolerancePixels = 7f
    private const val referenceCanvasHeight = 2048f
    private val yRayTolerance: Float
        get() = minOf(yRayToleranceFraction, yRayTolerancePixels / referenceCanvasHeight)
    private val ySaltRayTolerance: Float
        get() = minOf(ySaltRayToleranceFraction, ySaltRayTolerancePixels / referenceCanvasHeight)
    private const val kjProximityX = 0.14f

    private val europeanDecimalPattern = Regex("""(\d),(\d)""")
    private val numericPrefixPattern = Regex("""^[<~≥≤\s]+""")
    private val kcalCapturePattern = Regex("""(?:[<~≥≤]\s*)?(\d{1,4}(?:[.,]\d{1,2})?)\s*kcal\b""", RegexOption.IGNORE_CASE)
    private val kjMarkerPattern = Regex("""\b(kj|kilojulio|kilojoule)\b""", RegexOption.IGNORE_CASE)
    private val fatExclusionPattern = Regex("""\b(saturad|saturated|trans|saturats|saturadas)\b""", RegexOption.IGNORE_CASE)
    private val barcodeDigitsPattern = Regex("""\d{7,}""")
    private val percentOrRdaPattern = Regex("""(%|\bvrn\b|\bri\b|\bnrv\b)""", RegexOption.IGNORE_CASE)
    private val saltKeywordExclusionPattern = Regex("""\b(calcio|calcium|potasio|potassium)\b""", RegexOption.IGNORE_CASE)
    private val unitNumberPattern = Regex("""(?:[<~≥≤]\s*)?(\d{1,3}(?:[.,]\d{1,2})?)\s*(mg|g)\b""", RegexOption.IGNORE_CASE)
    private val bareNumberPattern = Regex("""^(\d{1,4}(?:[.,]\d{1,2})?)$""")
    private val leaderRunPattern = Regex("""[·•\.\-_—–]{2,}""")
    private val trailingLeaderNoisePattern = Regex("""[·•\.\-_—–]+$""")
    private val headerScopeBlacklistPattern = Regex(
        """\b(peso\s*neto|net\s*weight|per\s*serving|por\s*porcion|por\s*porción|per\s*100\s*(g|ml)|por\s*100\s*(g|ml)|100\s*(g|ml)|ml|peso|neto)\b""",
        RegexOption.IGNORE_CASE
    )
    private val per100BlueprintPattern = Regex("""(?:\b(?:por|per)\s*100\b|\b100\s*(?:g|ml)\b)""", RegexOption.IGNORE_CASE)
    private val netWeightBlueprintPattern = Regex("""\b(?:peso\s*neto|net\s*weight)\b""", RegexOption.IGNORE_CASE)
    private val kilojouleAdjacentPattern = Regex("""\b\d{1,4}(?:[.,]\d{1,2})?\s*(?:kj|kilojulio|kilojoule)\b""", RegexOption.IGNORE_CASE)
    private val capacityMarkerPattern = Regex("""\b(?:neto|net|liquido|líquido|liquid)\b""", RegexOption.IGNORE_CASE)
    private val capacityUnitPattern = Regex("""\b(?:g|ml)\b""", RegexOption.IGNORE_CASE)
    private val subRowLeadPattern = Regex("""\b(?:dont|de\s+las\s+cuales|dos\s+quais|de\s+quais|di\s+cui|davon|of\s+which|including)\b""", RegexOption.IGNORE_CASE)
    private val subRowIndicatorPattern = Regex("""(?:^\s*-\s*|(?:^|\s)(?:de\s+las\s+cuales|dos\s+quais|de\s+quais|dont|davon|di\s+cui|of\s+which|including)\b)""", RegexOption.IGNORE_CASE)
    private val bareCapacity100Pattern = Regex("""\b100(?:[.,]0)?\s*(?:g|ml)\b""", RegexOption.IGNORE_CASE)

    private data class SpatialParseContext(var imageDigitTokenCount: Int = 0)
    private var parseContext = SpatialParseContext()

    private fun numberLookbackBeforeUnit(text: String, unit: String, lookback: Int = 12): Double? {
        val folded = foldDiacritics(normalizeEuropeanDecimals(text).lowercase())
        val idx = folded.indexOf(unit.lowercase())
        if (idx <= 0) return null
        val start = (idx - lookback).coerceAtLeast(0)
        val window = folded.substring(start, idx).trim()
        if (window.isEmpty()) return null
        val m = Regex("""(?:[<~≥≤]\s*)?(\d{1,4}(?:[.,]\d{1,2})?)\s*$""", RegexOption.IGNORE_CASE).find(window) ?: return null
        val num = m.groupValues.getOrNull(1) ?: return null
        return parseLocalizedNumber(num)
    }
    private val sugarsOnlyRowPattern = Regex("""\b(azucar|azúcar|azucares|azúcares|sucres|sugar|sugars|zucker)\b""", RegexOption.IGNORE_CASE)

    private val caloriesKeywords = listOf(
        "valeur énergétique", "valor energético", "valor energetico",
        "brennwert", "energia", "energie", "energy",
        "calorías", "calorias", "kcal"
    )
    private val proteinKeywords = listOf(
        "proteínas", "proteinas", "proteïnes", "protéines",
        "eiweiß", "proteine", "protein"
    )
    private val carbsKeywords = listOf(
        "hidratos de carbono", "hidrats de carboni", "carbohidratos",
        "kohlenhydrate", "carboidrati", "glucides", "carbs"
    )
    private val fatKeywords = listOf(
        "matières grasses", "grasas totales", "grasas",
        "lípidos", "lipidos", "greixos", "gorduras", "grassi", "fett", "fat"
    )
    private val saturatedFatKeywords = listOf(
        "dont acides gras saturés", "davon gesättigte fettsäuren", "di cui acidi grassi saturi",
        "ácidos grasos saturados", "acidos grasos saturados",
        "grasas saturadas", "saturadas", "saturats", "saturated"
    )
    private val sugarsKeywords = listOf(
        "dont sucres", "davon zucker", "di cui zuccheri",
        "azúcares", "azucares", "sucres", "açúcares", "acucares", "sugars"
    )
    private val fiberKeywords = listOf(
        "fibres alimentaires", "fibra alimentaria", "fibra alimentària",
        "ballaststoffe", "fibra", "fibre", "fiber"
    )
    private val sodiumKeywords = listOf("sodio", "sodium")
    private val saltKeywords = listOf("salt", "sal", "sel", "salz", "sale")

    private data class KeywordRegion(
        val keyword: String,
        val rawContainerText: String,
        val foldedContainerText: String,
        val keywordEndOffset: Int,
        val minX: Float,
        val maxX: Float,
        val centerY: Float,
        val rightX: Float
    )

    private data class SpatialNumericToken(
        val value: Double,
        val unit: String,
        val minX: Float,
        val maxX: Float,
        val centerY: Float,
        val sourceText: String
    )

    fun parse(recognition: NutritionLabelRecognitionResult): NutritionLabelParseResult {
        val elements = recognition.elements.mapNotNull { sanitizeSpatialElement(it) }
        if (elements.size < 5) return NutritionLabelParseResult()

        parseContext = SpatialParseContext(countImageDigitTokens(elements))
        try {
        val numerics = collectNumericTokens(elements)
        val yTol = yRayTolerance
        val saltTol = ySaltRayTolerance

        var calories = 0.0
        var protein = 0.0
        var carbs = 0.0
        var fat = 0.0
        var saturatedFat = 0.0
        var sugars = 0.0
        var fiber = 0.0
        var sodiumMg = 0.0

        if (calories == 0.0) raycastCalories(elements, numerics, yTol)?.let { calories = it }
        if (protein == 0.0) raycastGramMacro("Protein", proteinKeywords, elements, yTol, excludeSaturatedRow = false)?.let { protein = it }
        if (carbs == 0.0) raycastGramMacro("Carbs", carbsKeywords, elements, yTol, excludeSaturatedRow = false, rejectSugarOnlyRows = true, isParentField = true)?.let { carbs = it }
        if (fat == 0.0) raycastGramMacro("Fat", fatKeywords, elements, yTol, excludeSaturatedRow = true, isParentField = true)?.let { fat = it }
        if (saturatedFat == 0.0) raycastGramMacro("SatFat", saturatedFatKeywords, elements, yTol, excludeSaturatedRow = false, isSubField = true, parentMacroGram = fat)?.let { saturatedFat = it }
        if (sugars == 0.0) raycastGramMacro("Sugars", sugarsKeywords, elements, yTol, excludeSaturatedRow = true, isSubField = true)?.let { sugars = it }
        if (fiber == 0.0) raycastGramMacro("Fiber", fiberKeywords, elements, yTol, excludeSaturatedRow = false)?.let { fiber = it }
        if (sodiumMg == 0.0) raycastSodiumMg("Sodium", sodiumKeywords, elements, numerics, saltTol)?.let { sodiumMg = it }
        if (sodiumMg == 0.0) raycastSaltAsSodiumMg(elements, numerics, saltTol)?.let { sodiumMg = it }

        return NutritionLabelParseResult(
            calories = calories,
            protein = protein,
            carbs = carbs,
            fat = fat,
            saturatedFat = saturatedFat,
            sugars = sugars,
            fiber = fiber,
            sodiumMg = sodiumMg
        )
        } finally {
            parseContext = SpatialParseContext()
        }
    }

    private fun dbg(message: String) {
        if (BuildConfig.DEBUG) Log.d(logTag, message)
    }

    private fun warn(message: String) {
        if (BuildConfig.DEBUG) Log.w(logTag, message)
    }

    private fun blockHeader(field: String) {
        dbg("------ [OCR SPATIAL RAYCAST] $field ------")
    }

    private fun blockFooter() {
        dbg("------ [OCR SPATIAL RAYCAST END] ------")
    }

    private fun sanitizeSpatialElement(element: NutritionLabelSpatialElement): NutritionLabelSpatialElement? {
        val text = sanitizeTokenText(element.text)
        if (text.isEmpty()) return null
        return element.copy(text = text)
    }

    private fun sanitizeTokenText(text: String): String {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return ""
        val collapsed = leaderRunPattern.replace(trimmed, " ")
        val noTrail = trailingLeaderNoisePattern.replace(collapsed, "")
        return noTrail.split(Regex("""\s+""")).filter { it.isNotEmpty() }.joinToString(" ")
    }

    private fun normalizeEuropeanDecimals(text: String): String =
        europeanDecimalPattern.replace(text, "$1.$2")

    private fun foldDiacritics(text: String): String {
        val normalized = Normalizer.normalize(text, Normalizer.Form.NFD)
        return normalized
            .replace(Regex("""\p{M}"""), "")
            .replace("ß", "ss")
            .replace("ẞ", "ss")
    }

    private fun parseLocalizedNumber(raw: String): Double? {
        var normalized = normalizeEuropeanDecimals(raw).trim()
        normalized = numericPrefixPattern.replace(normalized, "")
        normalized = normalized
            .replace("<", "")
            .replace("~", "")
            .replace("≤", "")
            .replace("≥", "")
            .trim()
        val digitIndex = normalized.indexOfFirst { it.isDigit() }
        if (digitIndex > 0) normalized = normalized.substring(digitIndex)
        normalized = normalized.replace(',', '.')
        return normalized.toDoubleOrNull()
    }

    private fun containerHasDigit(text: String): Boolean = text.any { it.isDigit() }

    private fun groupElementsIntoRows(
        elements: List<NutritionLabelSpatialElement>,
        yTolerance: Float
    ): List<List<NutritionLabelSpatialElement>> {
        val sorted = elements.sortedWith { a, b ->
            if (abs(a.centerY - b.centerY) > yTolerance) a.centerY.compareTo(b.centerY) else a.centerX.compareTo(b.centerX)
        }
        val rows = mutableListOf<MutableList<NutritionLabelSpatialElement>>()
        var currentY = 0f
        for (element in sorted) {
            val last = rows.lastOrNull()
            if (last != null && abs(element.centerY - currentY) <= yTolerance) {
                last.add(element)
                currentY = (currentY * (last.size - 1) + element.centerY) / last.size
            } else {
                rows.add(mutableListOf(element))
                currentY = element.centerY
            }
        }
        return rows.map { row -> row.sortedBy { it.centerX } }
    }

    private fun findKeywordRegions(
        elements: List<NutritionLabelSpatialElement>,
        keywords: List<String>,
        requireWordBoundaryForShort: Boolean
    ): List<KeywordRegion> {
        val sortedKeywords = keywords.sortedByDescending { it.length }
        val rows = groupElementsIntoRows(elements, rowClusterTolerance)
        val regions = mutableListOf<KeywordRegion>()

        for (row in rows) {
            val ordered = row.sortedBy { it.centerX }
            var joined = ""
            val spans = mutableListOf<Triple<Int, Int, Int>>()
            for ((index, element) in ordered.withIndex()) {
                val start = if (joined.isEmpty()) 0 else joined.length + 1
                if (joined.isNotEmpty()) joined += " "
                joined += element.text
                spans.add(Triple(index, start, joined.length))
            }
            val foldedJoined = foldDiacritics(normalizeEuropeanDecimals(joined).lowercase())

            for (keyword in sortedKeywords) {
                val k = foldDiacritics(keyword.lowercase())
                var searchFrom = 0
                while (searchFrom < foldedJoined.length) {
                    val idx = foldedJoined.indexOf(k, searchFrom)
                    if (idx < 0) break
                    val end = idx + k.length
                    if (requireWordBoundaryForShort && requiresWordBoundary(keyword) &&
                        !isWordBoundaryMatch(foldedJoined, idx, end)
                    ) {
                        searchFrom = end
                        continue
                    }
                    val matched = spans.mapNotNull { (elementIndex, start, spanEnd) ->
                        if (spanEnd > idx && start < end) ordered[elementIndex] else null
                    }
                    val boxElements = if (matched.isEmpty()) ordered else matched
                    val minX = boxElements.minOf { it.minX }
                    val maxX = boxElements.maxOf { it.maxX }
                    val minY = boxElements.minOf { it.minY }
                    val maxY = boxElements.maxOf { it.maxY }
                    val centerY = (minY + maxY) / 2f
                    regions.add(
                        KeywordRegion(
                            keyword = keyword,
                            rawContainerText = joined,
                            foldedContainerText = foldedJoined,
                            keywordEndOffset = end,
                            minX = minX,
                            maxX = maxX,
                            centerY = centerY,
                            rightX = maxX
                        )
                    )
                    searchFrom = end
                }
            }
        }
        return regions
    }

    private fun selectKeywordRegion(
        regions: List<KeywordRegion>,
        excludeSaturatedRow: Boolean,
        rejectSugarOnlyRows: Boolean = false
    ): KeywordRegion? {
        var filtered = regions
        if (excludeSaturatedRow) {
            filtered = filtered.filter { !fatExclusionPattern.containsMatchIn(it.foldedContainerText) }
        }
        if (rejectSugarOnlyRows) {
            filtered = filtered.filter { region ->
                val folded = region.foldedContainerText
                val hasSugar = sugarsOnlyRowPattern.containsMatchIn(folded)
                val hasCarb = carbsKeywords.any { folded.contains(foldDiacritics(it.lowercase())) }
                hasCarb || !hasSugar
            }
        }
        if (filtered.isEmpty()) return null
        return filtered.minByOrNull { it.centerY }
    }

    private fun candidateKeywordRegions(
        regions: List<KeywordRegion>,
        excludeSaturatedRow: Boolean,
        rejectSugarOnlyRows: Boolean = false
    ): List<KeywordRegion> {
        var filtered = regions
        if (excludeSaturatedRow) {
            filtered = filtered.filter { !fatExclusionPattern.containsMatchIn(it.foldedContainerText) }
        }
        if (rejectSugarOnlyRows) {
            filtered = filtered.filter { region ->
                val folded = region.foldedContainerText
                val hasSugar = sugarsOnlyRowPattern.containsMatchIn(folded)
                val hasCarb = carbsKeywords.any { folded.contains(foldDiacritics(it.lowercase())) }
                hasCarb || !hasSugar
            }
        }
        return filtered.sortedBy { it.centerY }
    }

    private fun collectNumericTokens(elements: List<NutritionLabelSpatialElement>): List<SpatialNumericToken> {
        val tokens = mutableListOf<SpatialNumericToken>()
        val seen = mutableSetOf<String>()

        fun appendToken(value: Double, unit: String, box: NutritionLabelSpatialElement, source: String) {
            val key = String.format("%.4f|%s|%.4f|%.4f", value, unit, box.centerX, box.centerY)
            if (!seen.add(key)) return
            tokens.add(
                SpatialNumericToken(
                    value = value,
                    unit = unit,
                    minX = box.minX,
                    maxX = box.maxX,
                    centerY = box.centerY,
                    sourceText = source
                )
            )
        }

        for (element in elements) {
            val folded = foldDiacritics(normalizeEuropeanDecimals(element.text).lowercase())
            unitNumberPattern.find(folded)?.let { match ->
                val value = parseLocalizedNumber(match.groupValues[1]) ?: return@let
                appendToken(value, match.groupValues[2].lowercase(), element, element.text)
            }
            kcalCapturePattern.find(folded)?.let { match ->
                val value = parseLocalizedNumber(match.groupValues[1]) ?: return@let
                appendToken(value, "kcal", element, element.text)
            }
        }

        val rows = groupElementsIntoRows(elements, rowClusterTolerance)
        for (row in rows) {
            val ordered = row.sortedBy { it.centerX }
            for (index in ordered.indices) {
                if (index + 1 >= ordered.size) continue
                val left = ordered[index]
                val right = ordered[index + 1]
                val combined = "${left.text} ${right.text}"
                val folded = foldDiacritics(normalizeEuropeanDecimals(combined).lowercase())
                unitNumberPattern.find(folded)?.let { match ->
                    val value = parseLocalizedNumber(match.groupValues[1]) ?: return@let
                    appendToken(value, match.groupValues[2].lowercase(), unionBox(left, right), combined)
                }
                val leftFolded = foldDiacritics(left.text.lowercase())
                val rightUnit = foldDiacritics(right.text.lowercase())
                bareNumberPattern.find(leftFolded)?.let { match ->
                    val value = parseLocalizedNumber(match.groupValues[1]) ?: return@let
                    if (rightUnit == "g" || rightUnit == "mg") {
                        appendToken(value, rightUnit, unionBox(left, right), combined)
                    }
                    if (right.text.lowercase().contains("kcal")) {
                        appendToken(value, "kcal", unionBox(left, right), combined)
                    }
                }
            }
        }
        return tokens
    }

    private data class RegexUnitMatchWithOffset(
        val number: String,
        val unit: String,
        val matchStartOffset: Int
    )

    private fun allRegexMatches(pattern: Regex, text: String): List<RegexUnitMatchWithOffset> {
        return pattern.findAll(text).mapNotNull { match ->
            val number = match.groupValues.getOrNull(1) ?: return@mapNotNull null
            val unit = match.groupValues.getOrNull(2)?.lowercase().orEmpty()
            RegexUnitMatchWithOffset(number, unit, match.range.first)
        }.toList()
    }

    private fun logSelfContained(field: String, region: KeywordRegion, value: Double, unit: String) {
        blockHeader(field)
        dbg("Mode: self-contained")
        dbg("Keyword: '${region.keyword}' | Container: '${region.rawContainerText}'")
        dbg("Extracted: $value$unit")
        blockFooter()
    }

    private fun countImageDigitTokens(elements: List<NutritionLabelSpatialElement>): Int {
        var count = 0
        for (element in elements) {
            val folded = foldDiacritics(normalizeEuropeanDecimals(element.text).lowercase())
            count += allRegexMatches(unitNumberPattern, folded).size
            count += allRegexMatches(kcalCapturePattern, folded).size
            if (bareNumberPattern.containsMatchIn(folded)) count += 1
        }
        return count
    }

    private fun isCapacityHundredSuppressed(containerText: String, match: RegexUnitMatchWithOffset): Boolean {
        val value = parseLocalizedNumber(match.number) ?: return false
        if (kotlin.math.abs(value - 100.0) >= 0.01) return false
        val folded = foldDiacritics(normalizeEuropeanDecimals(containerText).lowercase())
        if (bareCapacity100Pattern.containsMatchIn(folded)) return true
        if (folded.contains("100 g") || folded.contains("100g") || folded.contains("100 ml") || folded.contains("100ml")) {
            return true
        }
        if (parseContext.imageDigitTokenCount <= 1) return false
        val hasCapacityPhrase = capacityMarkerPattern.containsMatchIn(folded)
        val hasUnit = capacityUnitPattern.containsMatchIn(folded)
        if (hasCapacityPhrase && hasUnit) return true
        if (hasUnit && (match.unit == "g" || match.unit == "ml")) return true
        return false
    }

    private fun isSubPropertyRow(region: KeywordRegion): Boolean {
        if (region.rawContainerText.trim().startsWith("-")) return true
        val folded = region.foldedContainerText
        if (subRowIndicatorPattern.containsMatchIn(folded)) return true
        if (subRowLeadPattern.containsMatchIn(folded)) return true
        return false
    }

    private fun validateSubFieldKeywordPrefix(region: KeywordRegion, keywords: List<String>): Boolean {
        val folded = region.foldedContainerText
        val keywordFolded = foldDiacritics(region.keyword.lowercase())
        if (!folded.contains(keywordFolded)) return false
        return keywords.any { foldDiacritics(it.lowercase()) == keywordFolded || folded.contains(foldDiacritics(it.lowercase())) }
    }

    private fun subFieldRaySkipCount(
        region: KeywordRegion,
        numerics: List<SpatialNumericToken>,
        yTolerance: Float
    ): Int {
        if (isSubPropertyRow(region)) return 1
        val band = numerics.filter { token ->
            token.unit == "g" &&
                abs(token.centerY - region.centerY) <= yTolerance &&
                token.minX >= region.rightX - 0.002f &&
                !isBlueprintSpatialToken(token)
        }.sortedBy { it.minX }
        return if (band.size > 1) 1 else 0
    }

    private fun saltFallbackFromBottomCorpus(elements: List<NutritionLabelSpatialElement>): Double? {
        val rows = groupElementsIntoRows(elements, rowClusterTolerance)
        if (rows.isEmpty()) return null
        for (row in rows.takeLast(2).reversed()) {
            val joined = row.joinToString(" ") { it.text }
            val folded = foldDiacritics(normalizeEuropeanDecimals(joined).lowercase())
            if (saltKeywordExclusionPattern.containsMatchIn(folded)) continue
            if (barcodeDigitsPattern.containsMatchIn(folded)) continue
            val hasSaltKeyword = saltKeywords.any { folded.contains(foldDiacritics(it.lowercase())) }
            val matches = allRegexMatches(unitNumberPattern, folded).filter { !isBlueprintBaselineMatch(folded, it) }
            for (match in matches) {
                val value = parseLocalizedNumber(match.number) ?: continue
                if (match.unit == "mg") {
                    if (value !in 0.0..10_000.0) continue
                    if (!hasSaltKeyword && value > 500.0) continue
                    return value
                }
                if (match.unit == "g") {
                    if (value !in 0.0..10.0) continue
                    if (!hasSaltKeyword && value > 0.5) continue
                    return round((value / 2.5) * 1000.0)
                }
            }
        }
        return null
    }

    private fun convertSaltTokenToSodiumMg(selected: SpatialNumericToken): Double? {
        dbg("Salt Input: value=${selected.value} unit=${selected.unit}")
        val sodiumMg = if (selected.unit == "mg") {
            dbg("Converted Sodium: value(mg)=${selected.value}")
            selected.value
        } else {
            if (selected.value > 10.0) {
                warn("WARNING: Rejected spatial salt ${selected.value}g (>10g).")
                return null
            }
            val converted = round((selected.value / 2.5) * 1000.0)
            dbg("Converted Sodium: (value/2.5)*1000 rounded = ${converted}mg")
            converted
        }
        if (sodiumMg < 0.0 || sodiumMg > 10_000.0) {
            warn("WARNING: Rejected spatial sodium from salt ${sodiumMg}mg.")
            return null
        }
        return sodiumMg
    }

    private fun isBlueprintBaselineMatch(containerText: String, match: RegexUnitMatchWithOffset): Boolean {
        if (isCapacityHundredSuppressed(containerText, match)) return true
        val folded = foldDiacritics(normalizeEuropeanDecimals(containerText).lowercase())
        val start = (match.matchStartOffset - 20).coerceAtLeast(0)
        val end = (match.matchStartOffset + match.number.length + 20).coerceAtMost(folded.length)
        val window = folded.substring(start, end)
        val value = parseLocalizedNumber(match.number) ?: return false
        if (per100BlueprintPattern.containsMatchIn(window) && kotlin.math.abs(value - 100.0) < 0.01) return true
        if (netWeightBlueprintPattern.containsMatchIn(window) && kotlin.math.abs(value - 100.0) < 0.01 && match.unit == "g") return true
        if ((match.unit == "g" || match.unit == "ml") && kotlin.math.abs(value - 100.0) < 0.01) {
            if (window.contains("por 100") || window.contains("per 100") || window.contains("100g") ||
                window.contains("100 g") || window.contains("100ml") || window.contains("100 ml")
            ) {
                return true
            }
        }
        return false
    }

    private fun isKilojouleAdjacentInContainer(containerText: String, match: RegexUnitMatchWithOffset): Boolean {
        val folded = foldDiacritics(normalizeEuropeanDecimals(containerText).lowercase())
        if (folded.contains("kcal") && match.matchStartOffset < folded.length) {
            val tail = folded.substring(match.matchStartOffset.coerceAtMost(folded.lastIndex))
            if (tail.contains("kcal")) return false
        }
        val start = (match.matchStartOffset - 8).coerceAtLeast(0)
        val end = (match.matchStartOffset + match.number.length + 12).coerceAtMost(folded.length)
        val window = folded.substring(start, end)
        return kilojouleAdjacentPattern.containsMatchIn(window) || kjMarkerPattern.containsMatchIn(window)
    }

    private fun allKeywordEndOffsetsInContainer(foldedContainer: String): List<Int> {
        val keywordLists = listOf(
            caloriesKeywords, proteinKeywords, carbsKeywords, fatKeywords,
            saturatedFatKeywords, sugarsKeywords, fiberKeywords, sodiumKeywords, saltKeywords
        )
        val ends = mutableListOf<Int>()
        for (keywords in keywordLists) {
            for (keyword in keywords.sortedByDescending { it.length }) {
                val k = foldDiacritics(keyword.lowercase())
                var searchStart = 0
                while (searchStart < foldedContainer.length) {
                    val idx = foldedContainer.indexOf(k, searchStart)
                    if (idx < 0) break
                    val endExclusive = idx + k.length
                    if (requiresWordBoundary(keyword) && !isWordBoundaryMatch(foldedContainer, idx, endExclusive)) {
                        searchStart = endExclusive
                        continue
                    }
                    ends.add(endExclusive)
                    searchStart = endExclusive
                }
            }
        }
        return ends
    }

    private fun filteredUnitMatches(
        matches: List<RegexUnitMatchWithOffset>,
        allowedUnits: Set<String>,
        containerText: String,
        rejectKilojoules: Boolean
    ): List<RegexUnitMatchWithOffset> {
        return matches.filter { match ->
            val unitAllowed = allowedUnits.isEmpty() ||
                match.unit in allowedUnits ||
                (match.unit.isEmpty() && "kcal" in allowedUnits)
            if (!unitAllowed) return@filter false
            if (isBlueprintBaselineMatch(containerText, match)) return@filter false
            if (rejectKilojoules && isKilojouleAdjacentInContainer(containerText, match)) return@filter false
            true
        }
    }

    private fun pickMatchAfterKeyword(
        matches: List<RegexUnitMatchWithOffset>,
        keywordEndOffset: Int,
        allowedUnits: Set<String>,
        containerText: String,
        rejectKilojoules: Boolean = false,
        skipCount: Int = 0
    ): RegexUnitMatchWithOffset? {
        val filtered = filteredUnitMatches(matches, allowedUnits, containerText, rejectKilojoules)
        if (filtered.isEmpty()) return null
        val peerEnds = allKeywordEndOffsetsInContainer(containerText)
        val afterKeyword = filtered.filter { it.matchStartOffset >= keywordEndOffset }.sortedBy { it.matchStartOffset }
        val pool = if (afterKeyword.isEmpty()) filtered.sortedBy { it.matchStartOffset } else afterKeyword
        val anchored = pool.filter { match ->
            val myDistance = match.matchStartOffset - keywordEndOffset
            for (peerEnd in peerEnds) {
                if (peerEnd == keywordEndOffset) continue
                if (match.matchStartOffset < peerEnd) continue
                val peerDistance = match.matchStartOffset - peerEnd
                if (peerDistance < myDistance) return@filter false
            }
            true
        }.sortedBy { it.matchStartOffset }
        val ranked = if (anchored.isEmpty()) pool else anchored
        if (skipCount >= ranked.size) return ranked.lastOrNull()
        return ranked[skipCount]
    }

    private fun rankedGramMatchesAfterKeyword(region: KeywordRegion, maxGrams: Double): List<RegexUnitMatchWithOffset> {
        val matches = allRegexMatches(unitNumberPattern, region.foldedContainerText)
        val filtered = filteredUnitMatches(matches, setOf("g"), region.foldedContainerText, rejectKilojoules = false)
        val peerEnds = allKeywordEndOffsetsInContainer(region.foldedContainerText)
        val afterKeyword = filtered.filter { it.matchStartOffset >= region.keywordEndOffset }.sortedBy { it.matchStartOffset }
        return afterKeyword.filter { match ->
            val value = parseLocalizedNumber(match.number) ?: return@filter false
            if (value < 0.0 || value > maxGrams) return@filter false
            val myDistance = match.matchStartOffset - region.keywordEndOffset
            for (peerEnd in peerEnds) {
                if (peerEnd == region.keywordEndOffset) continue
                if (match.matchStartOffset < peerEnd) continue
                val peerDistance = match.matchStartOffset - peerEnd
                if (peerDistance < myDistance) return@filter false
            }
            true
        }
    }

    private fun resolveSubFieldGramValue(
        field: String,
        region: KeywordRegion,
        picked: RegexUnitMatchWithOffset,
        maxGrams: Double,
        parentMacroGram: Double?
    ): Double? {
        val primary = parseLocalizedNumber(picked.number) ?: return null
        val values = rankedGramMatchesAfterKeyword(region, maxGrams).mapNotNull { parseLocalizedNumber(it.number) }
        val parent = parentMacroGram
        if (parent != null && parent > 0.0 && primary >= parent * 0.9) {
            values.filter { it > 0.0 && it < primary }.minOrNull()?.let { return it }
            return null
        }
        if (values.size > 1) {
            return values.filter { it > 0.0 }.minOrNull()
        }
        return primary
    }

    private fun resolveParentGramValue(
        field: String,
        region: KeywordRegion,
        picked: RegexUnitMatchWithOffset,
        maxGrams: Double
    ): Double? {
        val primary = parseLocalizedNumber(picked.number) ?: return null
        val values = rankedGramMatchesAfterKeyword(region, maxGrams).mapNotNull { parseLocalizedNumber(it.number) }
        if (primary == 0.0) {
            values.filter { it > 0.0 }.maxOrNull()?.let { return it }
        }
        if (field == "Protein" && primary <= 3.0 && values.size > 1) {
            val best = values.filter { it > primary }.maxOrNull()
            if (best != null && best > primary) return best
        }
        return primary
    }

    private fun isExplicitKcalToken(token: SpatialNumericToken): Boolean =
        foldDiacritics(token.sourceText.lowercase()).contains("kcal")

    private fun shouldExcludeCalorieRayToken(
        token: SpatialNumericToken,
        elements: List<NutritionLabelSpatialElement>,
        yTolerance: Float
    ): Boolean {
        if (isExplicitKcalToken(token)) return false
        return isKjBoundToken(token, elements, yTolerance)
    }

    private fun selectCalorieRaycastToken(
        keywordRegion: KeywordRegion,
        numerics: List<SpatialNumericToken>,
        elements: List<NutritionLabelSpatialElement>,
        yTolerance: Float
    ): SpatialNumericToken? {
        val onBand = numerics.filter { token ->
            token.unit == "kcal" &&
                abs(token.centerY - keywordRegion.centerY) <= yTolerance &&
                !shouldExcludeCalorieRayToken(token, elements, yTolerance)
        }
        if (onBand.isEmpty()) return null
        val toTheRight = onBand.filter { it.minX >= keywordRegion.rightX - 0.02f }
        val pool = if (toTheRight.isEmpty()) onBand else toTheRight
        return pool.minByOrNull { it.minX }
    }

    private fun isBlueprintSpatialToken(token: SpatialNumericToken): Boolean {
        val folded = foldDiacritics(normalizeEuropeanDecimals(token.sourceText).lowercase())
        val pseudo = RegexUnitMatchWithOffset(
            number = token.value.toString(),
            unit = token.unit,
            matchStartOffset = 0
        )
        return isBlueprintBaselineMatch(folded, pseudo)
    }

    private fun trySelfContainedCalories(region: KeywordRegion): Double? {
        if (!containerHasDigit(region.foldedContainerText)) return null
        val matches = allRegexMatches(kcalCapturePattern, region.foldedContainerText)
        val picked = pickMatchAfterKeyword(
            matches,
            region.keywordEndOffset,
            setOf("kcal"),
            region.foldedContainerText,
            rejectKilojoules = true
        ) ?: return null
        val value = parseLocalizedNumber(picked.number) ?: return null
        if (value <= 0.0 || value > 1000.0) return null
        return value
    }

    private fun trySelfContainedGram(
        region: KeywordRegion,
        maxGrams: Double,
        skipCount: Int = 0,
        field: String = "",
        isParentField: Boolean = false,
        isSubField: Boolean = false,
        parentMacroGram: Double? = null
    ): Double? {
        if (!containerHasDigit(region.foldedContainerText)) return null
        val matches = allRegexMatches(unitNumberPattern, region.foldedContainerText)
        val picked = pickMatchAfterKeyword(
            matches,
            region.keywordEndOffset,
            setOf("g"),
            region.foldedContainerText,
            skipCount = skipCount
        ) ?: return null
        val value = when {
            isParentField -> resolveParentGramValue(field, region, picked, maxGrams)
            isSubField -> resolveSubFieldGramValue(field, region, picked, maxGrams, parentMacroGram)
            else -> parseLocalizedNumber(picked.number)
        } ?: return null
        if (value < 0.0 || value > maxGrams) return null
        if (isParentField && value == 0.0) return null
        return value
    }

    private fun trySelfContainedSodiumMg(region: KeywordRegion): Double? {
        if (!containerHasDigit(region.foldedContainerText)) return null
        val matches = allRegexMatches(unitNumberPattern, region.foldedContainerText)
        val picked = pickMatchAfterKeyword(
            matches,
            region.keywordEndOffset,
            setOf("g", "mg"),
            region.foldedContainerText
        ) ?: return null
        val value = parseLocalizedNumber(picked.number) ?: return null
        val mg = if (picked.unit == "g") value * 1000.0 else value
        if (mg < 0.0 || mg > 10_000.0) return null
        return mg
    }

    private fun trySelfContainedSaltAsSodiumMg(region: KeywordRegion): Double? {
        if (!containerHasDigit(region.foldedContainerText)) return null
        val matches = allRegexMatches(unitNumberPattern, region.foldedContainerText)
        val picked = pickMatchAfterKeyword(
            matches,
            region.keywordEndOffset,
            setOf("g", "mg"),
            region.foldedContainerText
        ) ?: return null
        val value = parseLocalizedNumber(picked.number) ?: return null
        if (picked.unit == "mg") {
            if (value < 0.0 || value > 10_000.0) return null
            return value
        }
        if (value < 0.0 || value > 10.0) {
            if (value > 10.0) {
                warn("WARNING: Rejected spatial salt ${value}g (>10g) in self-contained.")
            }
            return null
        }
        return round((value / 2.5) * 1000.0)
    }

    private fun unionBox(
        a: NutritionLabelSpatialElement,
        b: NutritionLabelSpatialElement
    ): NutritionLabelSpatialElement {
        return NutritionLabelSpatialElement(
            text = "${a.text} ${b.text}",
            minX = minOf(a.minX, b.minX),
            minY = minOf(a.minY, b.minY),
            maxX = maxOf(a.maxX, b.maxX),
            maxY = maxOf(a.maxY, b.maxY)
        )
    }

    private fun horizontalRaycast(
        keywordRegion: KeywordRegion,
        numerics: List<SpatialNumericToken>,
        allowedUnits: Set<String>,
        yTolerance: Float,
        excludeToken: (SpatialNumericToken) -> Boolean = { false },
        skipCount: Int = 0
    ): SpatialNumericToken? {
        val candidates = numerics
            .filter { token ->
                token.unit in allowedUnits &&
                    !excludeToken(token) &&
                    !isBlueprintSpatialToken(token) &&
                    abs(token.centerY - keywordRegion.centerY) <= yTolerance &&
                    token.minX >= keywordRegion.rightX - 0.002f
            }
            .sortedBy { it.minX }
        if (skipCount >= candidates.size) return candidates.lastOrNull()
        return candidates[skipCount]
    }

    private fun logRaycast(
        field: String,
        region: KeywordRegion,
        numerics: List<SpatialNumericToken>,
        selected: SpatialNumericToken?
    ) {
        blockHeader(field)
        dbg("Keyword: '${region.keyword}' | centerY: ${"%.3f".format(region.centerY)} | rightX: ${"%.3f".format(region.rightX)}")
        dbg("Row: '${region.foldedContainerText}'")
        val hits = numerics.filter {
            abs(it.centerY - region.centerY) <= yRayTolerance && it.minX >= region.rightX - 0.002f
        }
        val tokenList = hits.joinToString(", ") {
            "[x=${"%.3f".format(it.minX)}] ${it.value}${it.unit} y=${"%.3f".format(it.centerY)}"
        }
        dbg("Ray hits: ${if (tokenList.isEmpty()) "[]" else tokenList}")
        if (selected != null) {
            dbg("Selected: '${selected.sourceText}' -> ${selected.value}${selected.unit}")
        } else {
            dbg("Selected: <none>")
        }
        blockFooter()
    }

    private fun isKjBoundToken(
        token: SpatialNumericToken,
        elements: List<NutritionLabelSpatialElement>,
        yTolerance: Float
    ): Boolean {
        val kjElements = elements.filter { kjMarkerPattern.containsMatchIn(foldDiacritics(it.text.lowercase())) }
        for (kj in kjElements) {
            if (abs(kj.centerY - token.centerY) > yTolerance) continue
            val gap = kj.minX - token.maxX
            val overlap = token.maxX >= kj.minX - 0.01f && kj.minX <= token.maxX + kjProximityX
            if (overlap || (gap >= -0.02f && gap <= kjProximityX)) return true
        }
        if (token.unit == "kcal") {
            val source = foldDiacritics(token.sourceText.lowercase())
            if (kjMarkerPattern.containsMatchIn(source) && !source.contains("kcal")) return true
        }
        return false
    }

    private fun raycastCalories(
        elements: List<NutritionLabelSpatialElement>,
        numerics: List<SpatialNumericToken>,
        yTolerance: Float
    ): Double? {
        val regions = findKeywordRegions(elements, caloriesKeywords, requireWordBoundaryForShort = true)
        for (region in candidateKeywordRegions(regions, excludeSaturatedRow = false)) {
            trySelfContainedCalories(region)?.let { value ->
                logSelfContained("Calories", region, value, "kcal")
                return value
            }
            val selected = selectCalorieRaycastToken(region, numerics, elements, yTolerance)
            logRaycast("Calories", region, numerics, selected)
            if (selected != null) {
                if (selected.value > 0.0 && selected.value <= 1000.0) return selected.value
                if (selected.value > 1000.0) {
                    warn("WARNING: Rejected spatial calories ${selected.value} (>1000 kcal).")
                }
            }
        }

        val kcalRegions = findKeywordRegions(elements, listOf("kcal"), requireWordBoundaryForShort = false)
        for (region in kcalRegions.sortedBy { it.centerY }) {
            val lookLeft = numberLookbackBeforeUnit(region.rawContainerText, "kcal")
            if (lookLeft != null && lookLeft > 0.0 && lookLeft <= 1000.0) {
                logSelfContained("Calories", region, lookLeft, "kcal")
                return lookLeft
            }
            val leftNumber = numerics.filter {
                it.unit == "kcal" &&
                    abs(it.centerY - region.centerY) <= yTolerance &&
                    it.maxX <= region.minX + 0.02f &&
                    !shouldExcludeCalorieRayToken(it, elements, yTolerance)
            }.minByOrNull { it.minX }
            if (leftNumber != null && leftNumber.value > 0.0 && leftNumber.value <= 1000.0) {
                return leftNumber.value
            }
        }

        return numerics.filter {
            it.unit == "kcal" &&
                it.value > 0.0 &&
                it.value <= 1000.0 &&
                !shouldExcludeCalorieRayToken(it, elements, yTolerance)
        }.minByOrNull { it.centerY }?.value
    }

    private fun raycastGramMacro(
        field: String,
        keywords: List<String>,
        elements: List<NutritionLabelSpatialElement>,
        yTolerance: Float,
        excludeSaturatedRow: Boolean,
        rejectSugarOnlyRows: Boolean = false,
        isSubField: Boolean = false,
        isParentField: Boolean = false,
        parentMacroGram: Double? = null
    ): Double? {
        val fieldNumerics = collectNumericTokens(elements)
        val regions = findKeywordRegions(elements, keywords, requireWordBoundaryForShort = true)
        var candidates = candidateKeywordRegions(regions, excludeSaturatedRow, rejectSugarOnlyRows)
        if (isParentField) {
            candidates = candidates.filter { !isSubPropertyRow(it) }
        }
        if (isSubField) {
            candidates = candidates.filter {
                isSubPropertyRow(it) || allRegexMatches(unitNumberPattern, it.foldedContainerText).size > 1
            }
        }
        for (region in candidates) {
            if (isSubField && !validateSubFieldKeywordPrefix(region, keywords)) continue
            val skipCount = when {
                isParentField -> 0
                isSubField -> subFieldRaySkipCount(region, fieldNumerics, yTolerance)
                else -> 0
            }
            trySelfContainedGram(region, 100.0, skipCount, field, isParentField, isSubField, parentMacroGram)?.let { value ->
                logSelfContained(field, region, value, "g")
                return value
            }
            val rayTolerance = if (isParentField) minOf(yTolerance * 1.5f, rowClusterTolerance * 2f) else yTolerance
            val selected = horizontalRaycast(region, fieldNumerics, setOf("g"), rayTolerance, skipCount = skipCount)
            logRaycast(field, region, fieldNumerics, selected)
            if (selected == null || selected.unit != "g") continue
            if (isHeaderScopeViolation(region)) continue
            if (selected.value < 0.0 || selected.value > 100.0) {
                if (selected.value > 100.0) {
                    warn("WARNING: Rejected spatial $field ${selected.value}g (>100g).")
                }
                continue
            }
            val parent = parentMacroGram
            if (isSubField && parent != null && parent > 0.0 && selected.value >= parent * 0.9) continue
            return selected.value
        }
        return null
    }

    private fun raycastSodiumMg(
        field: String,
        keywords: List<String>,
        elements: List<NutritionLabelSpatialElement>,
        numerics: List<SpatialNumericToken>,
        yTolerance: Float
    ): Double? {
        val region = findKeywordRegions(elements, keywords, requireWordBoundaryForShort = true)
            .minByOrNull { it.centerY } ?: return null
        if (barcodeDigitsPattern.containsMatchIn(region.foldedContainerText)) return null
        if (percentOrRdaPattern.containsMatchIn(region.foldedContainerText)) return null
        trySelfContainedSodiumMg(region)?.let { value ->
            logSelfContained(field, region, value, "mg")
            return value
        }
        val selected = horizontalRaycast(region, numerics, setOf("g", "mg"), yTolerance)
        logRaycast(field, region, numerics, selected)
        if (selected == null) return null
        val mg = if (selected.unit == "g") selected.value * 1000.0 else selected.value
        if (mg < 0.0 || mg > 10_000.0) {
            warn("WARNING: Rejected spatial sodium ${mg}mg.")
            return null
        }
        return mg
    }

    private fun raycastSaltAsSodiumMg(
        elements: List<NutritionLabelSpatialElement>,
        numerics: List<SpatialNumericToken>,
        yTolerance: Float
    ): Double? {
        val regions = findKeywordRegions(elements, saltKeywords, requireWordBoundaryForShort = true)
        for (region in regions.sortedBy { it.centerY }) {
            if (saltKeywordExclusionPattern.containsMatchIn(region.foldedContainerText)) continue
            if (barcodeDigitsPattern.containsMatchIn(region.foldedContainerText)) continue
            if (percentOrRdaPattern.containsMatchIn(region.foldedContainerText)) continue
            trySelfContainedSaltAsSodiumMg(region)?.let { value ->
                logSelfContained("SaltToSodium", region, value, "mg")
                return value
            }
            val selected = horizontalRaycast(region, numerics, setOf("g", "mg"), yTolerance)
            logRaycast("SaltToSodium", region, numerics, selected)
            if (selected != null) {
                convertSaltTokenToSodiumMg(selected)?.let { return it }
            }
        }
        saltFallbackFromBottomCorpus(elements)?.let { fallback ->
            dbg("SaltToSodium bottom-corpus fallback -> ${fallback}mg")
            return fallback
        }
        return null
    }

    private fun isHeaderScopeViolation(region: KeywordRegion): Boolean {
        return headerScopeBlacklistPattern.containsMatchIn(region.foldedContainerText)
    }

    private fun requiresWordBoundary(keyword: String): Boolean {
        return when (keyword.lowercase()) {
            "fat", "sal", "sel", "salz", "sale" -> true
            else -> false
        }
    }

    private fun isWordBoundaryMatch(text: String, start: Int, endExclusive: Int): Boolean {
        if (start > 0) {
            val before = text[start - 1]
            if (before.isLetterOrDigit()) return false
        }
        if (endExclusive < text.length) {
            val after = text[endExclusive]
            if (after.isLetterOrDigit()) return false
        }
        return true
    }
}
