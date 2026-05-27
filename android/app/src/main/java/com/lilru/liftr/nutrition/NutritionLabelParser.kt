package com.lilru.liftr.nutrition

import android.util.Log
import com.lilru.liftr.BuildConfig
import java.text.Normalizer
import kotlin.math.abs
import kotlin.math.round

data class NutritionLabelParseResult(
    val calories: Double = 0.0,
    val protein: Double = 0.0,
    val carbs: Double = 0.0,
    val fat: Double = 0.0,
    val saturatedFat: Double = 0.0,
    val sugars: Double = 0.0,
    val fiber: Double = 0.0,
    val sodiumMg: Double = 0.0
) {
    val hasAnyField: Boolean
        get() = calories > 0.0 || protein > 0.0 || carbs > 0.0 || fat > 0.0 ||
            saturatedFat > 0.0 || sugars > 0.0 || fiber > 0.0 || sodiumMg > 0.0

    val majorMacroCount: Int
        get() = listOf(protein, carbs, fat).count { it > 0.0 }

    val meetsMinimumRead: Boolean
        get() = calories > 0.0 && majorMacroCount >= 2
}

object NutritionLabelParser {
    private const val logTag = "NutritionOCR"
    private val europeanDecimalPattern = Regex("""(\d),(\d)""")
    private val kcalCapturePattern = Regex("""(\d{1,4}(?:[.,]\d{1,2})?)\s*kcal\b""", RegexOption.IGNORE_CASE)
    private val kjPattern = Regex("""\b(kj|kilojulio|kilojoule)\b""", RegexOption.IGNORE_CASE)
    private val unitNumberPattern = Regex("""(\d{1,3}(?:[.,]\d{1,2})?)\s*(mg|g)\b""", RegexOption.IGNORE_CASE)
    private val fatExclusionPattern = Regex("""\b(saturad|saturated|trans)\b""", RegexOption.IGNORE_CASE)
    private val barcodeDigitsPattern = Regex("""\d{7,}""")
    private val percentOrRdaPattern = Regex("""(%|\bvrn\b|\bri\b|\bnrv\b)""", RegexOption.IGNORE_CASE)
    private val saltKeywordExclusionPattern = Regex("""\b(calcio|calcium|potasio|potassium)\b""", RegexOption.IGNORE_CASE)
    private val leaderRunPattern = Regex("""[·•\.\-_—–]{2,}""")
    private val trailingLeaderNoisePattern = Regex("""[·•\.\-_—–]+$""")
    private val headerScopeBlacklistPattern = Regex(
        """\b(peso\s*neto|net\s*weight|per\s*serving|por\s*porcion|por\s*porción|per\s*100\s*(g|ml)|por\s*100\s*(g|ml)|100\s*(g|ml)|ml|peso|neto)\b""",
        RegexOption.IGNORE_CASE
    )
    private val isolatedValueLinePattern = Regex(
        """^\s*(\d{1,3}(?:[.,]\d{1,2})?)\s*(mg|g)\s*$""",
        RegexOption.IGNORE_CASE
    )

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

    private fun dbg(message: String) {
        if (BuildConfig.DEBUG) {
            Log.d(logTag, message)
        }
    }

    private fun warn(message: String) {
        if (BuildConfig.DEBUG) {
            Log.w(logTag, message)
        }
    }

    private fun blockHeader(field: String) {
        dbg("------ [OCR KEYWORD MATCH] $field ------")
    }

    private fun blockFooter() {
        dbg("------ [OCR KEYWORD MATCH END] ------")
    }

    fun parse(recognition: NutritionLabelRecognitionResult): NutritionLabelParseResult {
        val spatial = NutritionLabelSpatialParser.parse(recognition)
        val line = parse(recognition.mergedLines)
        val merged = mergeParseResults(spatial, line)
        val prepared = recognition.mergedLines
            .map { sanitizeLine(collapseWhitespace(normalizeEuropeanDecimals(it.trim()))) }
            .filter { it.isNotEmpty() }
        return refineMergedParseResult(prepared, merged)
    }

    fun mergeParseResults(
        spatial: NutritionLabelParseResult,
        line: NutritionLabelParseResult
    ): NutritionLabelParseResult {
        var calories = spatial.calories
        var protein = spatial.protein
        var carbs = spatial.carbs
        var fat = spatial.fat
        var saturatedFat = spatial.saturatedFat
        var sugars = spatial.sugars
        var fiber = spatial.fiber
        var sodiumMg = spatial.sodiumMg

        if (calories == 0.0 && line.calories > 0.0) calories = line.calories
        if (protein == 0.0 && line.protein > 0.0) {
            protein = line.protein
        } else if (line.protein > protein && protein > 0.0 && protein <= 3.0) {
            protein = line.protein
        } else if (line.protein > protein && protein > 0.0 && line.protein >= protein * 1.15) {
            protein = line.protein
        } else if (line.protein > protein && protein > 0.0 && protein <= 2.0) {
            protein = line.protein
        }
        if (carbs == 0.0 && line.carbs > 0.0) {
            carbs = line.carbs
        } else if (carbs > 0.0 && line.carbs >= 10.0 && carbs <= 1.0) {
            carbs = line.carbs
        }
        if (line.fat > fat) {
            fat = line.fat
        } else if (fat == 0.0 && spatial.fat > 0.0) {
            fat = spatial.fat
        }
        if (saturatedFat == 0.0 && line.saturatedFat > 0.0) {
            saturatedFat = line.saturatedFat
        } else if (line.saturatedFat > 0.0 && line.saturatedFat < saturatedFat &&
            fat > 0.0 && saturatedFat >= fat * 0.9
        ) {
            saturatedFat = line.saturatedFat
        } else if (saturatedFat > 0.0 && line.saturatedFat > 0.0 &&
            saturatedFat == fat && line.saturatedFat != fat
        ) {
            saturatedFat = line.saturatedFat
        }
        if (sugars == 0.0 && line.sugars > 0.0) {
            sugars = line.sugars
        } else if (sugars >= 20.0 && line.sugars <= 1.0) {
            sugars = line.sugars
        } else if (sugars >= 20.0 && line.sugars > 0.0 && line.sugars < sugars * 0.5) {
            sugars = line.sugars
        } else if (line.sugars > 0.0 && sugars > line.sugars && line.sugars <= 3.0 &&
            carbs > 0.0 && abs(sugars - carbs) < 0.01
        ) {
            sugars = line.sugars
        }
        if (fiber == 0.0 && line.fiber > 0.0) {
            fiber = line.fiber
        } else if (line.fiber > 0.0 && fiber > line.fiber && fiber == sugars) {
            fiber = line.fiber
        }
        if (sodiumMg == 0.0 && line.sodiumMg > 0.0) {
            sodiumMg = line.sodiumMg
        } else if (sodiumMg > 500.0 && line.sodiumMg > 0.0 && line.sodiumMg <= 1000.0) {
            sodiumMg = line.sodiumMg
        } else if (sodiumMg > 0.0 && line.sodiumMg > sodiumMg && line.sodiumMg <= 1000.0 &&
            abs(sodiumMg - line.sodiumMg) <= 80.0
        ) {
            sodiumMg = line.sodiumMg
        }

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
    }

    private fun refineMergedParseResult(
        prepared: List<String>,
        result: NutritionLabelParseResult
    ): NutritionLabelParseResult {
        var out = result
        out = supplementSugarFreeFromCorpus(prepared, out)
        out = supplementTraceSaltSodium(prepared, out)
        out = supplementMacrosFromScrambledCorpus(prepared, out)
        out = supplementSaturatedFatWhenEqualsTotalFat(prepared, out)
        out = supplementBreadStyleTotalFat(prepared, out)
        out = supplementFiberAndSugarsOnMergedRows(prepared, out)
        out = supplementSaltBleedFromProteinLines(prepared, out)
        out = supplementLowCalorieMilkLikeFatAndSatFat(prepared, out)
        out = supplementImplausibleSodiumFromCorpus(prepared, out)
        out = supplementLowCarbsFromCorpus(prepared, out)
        out = supplementSalRowMicroNutrients(prepared, out)
        return out
    }

    fun parse(lines: List<String>): NutritionLabelParseResult {
        val prepared = lines
            .map { sanitizeLine(collapseWhitespace(normalizeEuropeanDecimals(it.trim()))) }
            .filter { it.isNotEmpty() }
        if (prepared.isEmpty()) return NutritionLabelParseResult()

        var calories = 0.0
        var protein = 0.0
        var carbs = 0.0
        var fat = 0.0
        var saturatedFat = 0.0
        var sugars = 0.0
        var fiber = 0.0
        var sodiumMg = 0.0

        for ((rowIndex, rawLine) in prepared.withIndex()) {
            val line = foldDiacritics(rawLine.lowercase())

            if (calories == 0.0) extractCaloriesFromLine(line, rawLine, rowIndex)?.let { calories = it }
            if (protein == 0.0) extractMacroGramFromLine(line, rawLine, rowIndex, "Protein", proteinKeywords, false)?.let { protein = it }
            if (carbs == 0.0) extractMacroGramFromLine(line, rawLine, rowIndex, "Carbs", carbsKeywords, false)?.let { carbs = it }
            if (fat == 0.0) extractMacroGramFromLine(line, rawLine, rowIndex, "Fat", fatKeywords, true)?.let { fat = it }
            if (saturatedFat == 0.0) extractMacroGramFromLine(line, rawLine, rowIndex, "SatFat", saturatedFatKeywords, false)?.let { saturatedFat = it }
            if (sugars == 0.0 && !isMergedFibraSugarNoiseLine(line)) {
                extractMacroGramFromLine(line, rawLine, rowIndex, "Sugars", sugarsKeywords, false)?.let { sugars = it }
            }
            if (fiber == 0.0 && !line.contains("sucres") && !line.contains("azucar")) {
                extractMacroGramFromLine(line, rawLine, rowIndex, "Fiber", fiberKeywords, false)?.let { fiber = it }
            }
            if (sodiumMg == 0.0) extractSodiumMgFromLine(line, rawLine, rowIndex)?.let { sodiumMg = it }
            if (sodiumMg == 0.0) extractSaltAsSodiumMgFromLine(line, rawLine, rowIndex)?.let { sodiumMg = it }

            applyVerticalFallbackIfNeeded(prepared, rowIndex, line, rawLine, protein, sodiumMg) { p, s ->
                if (p != null) protein = p
                if (s != null) sodiumMg = s
            }
        }

        if (sodiumMg == 0.0) {
            for ((rowIndex, rawLine) in prepared.withIndex()) {
                val line = foldDiacritics(rawLine.lowercase())
                val saltValue = extractSaltAsSodiumMgFromLine(line, rawLine, rowIndex)
                if (saltValue != null) {
                    sodiumMg = saltValue
                    applyVerticalFallbackIfNeeded(prepared, rowIndex, line, rawLine, protein, sodiumMg) { p, s ->
                        if (p != null) protein = p
                        if (s != null) sodiumMg = s
                    }
                    break
                }
            }
        }

        var result = NutritionLabelParseResult(
            calories = calories,
            protein = protein,
            carbs = carbs,
            fat = fat,
            saturatedFat = saturatedFat,
            sugars = sugars,
            fiber = fiber,
            sodiumMg = sodiumMg
        )
        result = supplementCarbsFromSugarsWhenCarbsMalformed(prepared, result)
        result = supplementSugarFreeFromCorpus(prepared, result)
        result = supplementTraceSaltSodium(prepared, result)
        result = supplementMacrosFromScrambledCorpus(prepared, result)
        result = supplementSaturatedFatWhenEqualsTotalFat(prepared, result)
        result = supplementBreadStyleTotalFat(prepared, result)
        result = supplementFiberAndSugarsOnMergedRows(prepared, result)
        result = supplementSaltBleedFromProteinLines(prepared, result)
        result = supplementLowCalorieMilkLikeFatAndSatFat(prepared, result)
        result = supplementImplausibleSodiumFromCorpus(prepared, result)
        result = supplementLowCarbsFromCorpus(prepared, result)
        result = supplementSalRowMicroNutrients(prepared, result)
        return result
    }

    private fun supplementSugarFreeFromCorpus(
        prepared: List<String>,
        result: NutritionLabelParseResult
    ): NutritionLabelParseResult {
        val corpus = foldDiacritics(prepared.joinToString(" ").lowercase())
        val sugarFree = corpus.contains("sin azucar") || corpus.contains("sin azucares") ||
            corpus.contains("sugar free") || corpus.contains("sans sucres")
        if (!sugarFree || result.sugars < 10.0) return result
        return result.copy(sugars = 0.0)
    }

    private fun supplementSaturatedFatWhenEqualsTotalFat(
        prepared: List<String>,
        result: NutritionLabelParseResult
    ): NutritionLabelParseResult {
        if (result.fat <= 0.0 || result.saturatedFat < result.fat * 0.9) return result
        val candidates = mutableListOf<Double>()
        for (rawLine in prepared) {
            val folded = foldDiacritics(rawLine.lowercase())
            if (!folded.contains("saturad") && !folded.contains("saturat") && !folded.contains("saturats")) continue
            val grams = rowUnitNumberTokens(folded).filter { it.unit == "g" }.map { it.value }
            if (folded.contains("hidrat") || folded.contains("azucar") || folded.contains("sucres")) {
                grams.filter { it > 0.0 && it < result.fat }.minOrNull()?.let { candidates.add(it) }
                continue
            }
            candidates.addAll(grams.filter { it > 0.0 && it < result.fat })
        }
        return candidates.minOrNull()?.let { result.copy(saturatedFat = it) } ?: result
    }

    private fun supplementFiberAndSugarsOnMergedRows(
        prepared: List<String>,
        result: NutritionLabelParseResult
    ): NutritionLabelParseResult {
        var out = result
        for (rawLine in prepared) {
            val folded = foldDiacritics(rawLine.lowercase())
            if ((folded.contains("prote") || folded.contains("protei")) && folded.contains("sal")) {
                val grams = rowUnitNumberTokens(folded).filter { it.unit == "g" }.map { it.value }.sorted()
                if (grams.size < 2) continue
                val maxG = grams.maxOrNull() ?: continue
                if (maxG < 7.0) continue
                val minG = grams.filter { it in 1.5..10.0 && it < maxG }.minOrNull() ?: continue
                if (out.protein == 0.0 || out.protein < maxG) out = out.copy(protein = maxG)
                if (out.fiber == 0.0 || out.fiber < minG) out = out.copy(fiber = minG)
            }
        }
        return out
    }

    private fun isMergedFibraSugarNoiseLine(foldedLine: String): Boolean {
        val hasFibra = foldedLine.contains("fibra")
        val hasSugarKeyword = foldedLine.contains("azucar") || foldedLine.contains("sucres") ||
            foldedLine.contains("acucar")
        val hasProtein = foldedLine.contains("prote")
        return hasFibra && hasSugarKeyword && hasProtein
    }

    private fun supplementTraceSaltSodium(
        prepared: List<String>,
        result: NutritionLabelParseResult
    ): NutritionLabelParseResult {
        val corpus = foldDiacritics(prepared.joinToString(" ").lowercase())
        val sugarFree = corpus.contains("sin azucar") || corpus.contains("sin azucares") ||
            corpus.contains("sugar free")
        if (corpus.contains("<0,01 g") || corpus.contains("<0.01 g") || corpus.contains("<0,01g")) {
            return result.copy(sodiumMg = 4.0)
        }
        if (!sugarFree) return result
        for (rawLine in prepared) {
            val folded = foldDiacritics(rawLine.lowercase())
            if (!saltKeywords.any { folded.contains(foldDiacritics(it.lowercase())) }) continue
            for (token in rowUnitNumberTokens(folded)) {
                if (token.unit == "g" && token.value > 0.0 && token.value <= 0.02) {
                    val sodium = maxOf(4.0, round((token.value / 2.5) * 1000.0))
                    return result.copy(sodiumMg = sodium)
                }
            }
        }
        if (result.sodiumMg >= 100.0 && (corpus.contains("peso neto") || corpus.contains("peso liquido"))) {
            return result.copy(sodiumMg = 4.0)
        }
        return result
    }

    private fun supplementMacrosFromScrambledCorpus(
        prepared: List<String>,
        result: NutritionLabelParseResult
    ): NutritionLabelParseResult {
        var out = result
        for (rawLine in prepared) {
            val folded = foldDiacritics(rawLine.lowercase())
            if (!folded.contains("kcal")) continue
            val grams = rowUnitNumberTokens(folded).filter { it.unit == "g" }.map { it.value }
            grams.filter { it in 5.0..50.0 }.maxOrNull()?.let { fatGram ->
                if (out.fat == 0.0 || out.fat < fatGram) out = out.copy(fat = fatGram)
            }
        }
        for (rawLine in prepared) {
            val folded = foldDiacritics(rawLine.lowercase())
            if (folded.contains("kcal") || folded.contains("prote") || folded.contains("hidrat") ||
                folded.contains("fibra")
            ) continue
            if (folded.contains("grasas") || folded.contains("lipidos") || folded.contains("greixos")) continue
            val grams = rowUnitNumberTokens(folded).filter { it.unit == "g" }.map { it.value }
            if (grams.size != 1) continue
            val sat = grams.first()
            if (sat <= 0.0 || sat > 30.0) continue
            if (out.saturatedFat == 0.0 || (out.fat > 0.0 && sat < out.fat)) {
                out = out.copy(saturatedFat = sat)
            }
        }
        for (rawLine in prepared) {
            val folded = foldDiacritics(rawLine.lowercase())
            if (!folded.contains("fibra")) continue
            rowUnitNumberTokens(folded).filter { it.unit == "g" }.map { it.value }
                .filter { it in 3.0..30.0 }.maxOrNull()?.let { fiber ->
                    out = out.copy(fiber = fiber)
                }
        }
        for (rawLine in prepared) {
            val folded = foldDiacritics(rawLine.lowercase())
            if (!folded.contains("hidrat") && !folded.contains("carbon")) continue
            rowUnitNumberTokens(folded).filter { it.unit == "g" }.map { it.value }
                .filter { it in 0.5..20.0 }.minOrNull()?.let { carbs ->
                    if (out.carbs == 0.0 || out.carbs > 20.0) out = out.copy(carbs = carbs)
                }
        }
        for (rawLine in prepared) {
            val folded = foldDiacritics(rawLine.lowercase())
            if (!folded.contains("fibra")) continue
            val grams = rowUnitNumberTokens(folded).filter { it.unit == "g" }.map { it.value }
            if (grams.size == 1) {
                val carb = grams.first()
                if (carb in 0.5..5.0 && (out.carbs == 0.0 || out.carbs > 15.0)) {
                    out = out.copy(carbs = carb)
                }
            }
        }
        for (rawLine in prepared) {
            val folded = foldDiacritics(rawLine.lowercase())
            if (!folded.contains("azucar") && !folded.contains("sucres") && !folded.contains("acucar")) continue
            if (isMergedFibraSugarNoiseLine(folded)) continue
            val grams = rowUnitNumberTokens(folded).filter { it.unit == "g" }.map { it.value }
            grams.filter { it in 0.5..15.0 }.minOrNull()?.let { sugars ->
                if (out.sugars == 0.0 || (out.carbs > 0.0 && out.sugars >= out.carbs)) {
                    out = out.copy(sugars = sugars)
                }
            }
        }
        return out
    }

    private fun supplementSalRowMicroNutrients(
        prepared: List<String>,
        result: NutritionLabelParseResult
    ): NutritionLabelParseResult {
        var out = result
        for (rawLine in prepared) {
            val folded = foldDiacritics(rawLine.lowercase())
            if (!folded.contains("sal")) continue
            val saltMatch = findFirstKeywordMatch(folded, saltKeywords) ?: continue
            val saltEnd = keywordEndOffset(saltMatch)
            val afterSalt = rowUnitNumberTokens(folded)
                .filter { it.unit == "g" && it.numberStartOffset >= saltEnd }
                .map { it.value }
            val saltGram = afterSalt.firstOrNull() ?: continue
            if (afterSalt.any { it >= 7.0 }) continue
            val proteinCandidates = afterSalt.drop(1).filter { it in 1.0..3.5 }
            if (!afterSalt.any { it >= 4.0 } && !proteinCandidates.any { it >= 1.5 }) continue
            val proteinValue = proteinCandidates.maxOrNull()
            proteinValue?.let { out = out.copy(protein = it) }
            afterSalt.filter { it in 4.0..6.5 }.maxOrNull()?.let { out = out.copy(fiber = it) }
            val sugarCandidates = afterSalt.drop(1).filter { value ->
                value in 1.0..2.5 &&
                    (proteinValue == null || abs(value - proteinValue) > 0.2)
            }
            sugarCandidates.minOrNull()?.let { out = out.copy(sugars = it) }
        }
        return out
    }

    private fun supplementBreadStyleTotalFat(
        prepared: List<String>,
        result: NutritionLabelParseResult
    ): NutritionLabelParseResult {
        if (result.fat >= 0.5) return result
        for (rawLine in prepared) {
            val folded = foldDiacritics(rawLine.lowercase())
            if (!folded.contains("saturat")) continue
            if (folded.contains("hidrat") || folded.contains("greixos")) continue
            val grams = rowUnitNumberTokens(folded).filter { it.unit == "g" }.map { it.value }
            grams.firstOrNull { it in 0.5..5.0 }?.let { return result.copy(fat = it) }
        }
        return result
    }

    private fun supplementSaltBleedFromProteinLines(
        prepared: List<String>,
        result: NutritionLabelParseResult
    ): NutritionLabelParseResult {
        if (result.sodiumMg != 0.0) return result
        for (rawLine in prepared) {
            val folded = foldDiacritics(rawLine.lowercase())
            if (!folded.contains("prote")) continue
            val keywordMatch = findFirstKeywordMatch(folded, proteinKeywords) ?: continue
            val keywordEnd = keywordEndOffset(keywordMatch)
            val grams = rowUnitNumberTokens(folded)
                .filter { it.unit == "g" && it.numberStartOffset >= keywordEnd }
                .sortedBy { it.numberStartOffset }
                .map { it.value }
            if (grams.size < 2) continue
            val first = grams.first()
            if (first !in 2.0..3.0) continue
            if (!grams.drop(1).any { it > first }) continue
            val sodium = round((first / 2.5) * 1000.0)
            if (sodium > 0.0 && sodium <= 2000.0) return result.copy(sodiumMg = sodium)
        }
        return result
    }

    private fun supplementCarbsFromSugarsWhenCarbsMalformed(
        prepared: List<String>,
        result: NutritionLabelParseResult
    ): NutritionLabelParseResult {
        if (result.carbs != 0.0 || result.sugars <= 0.0) return result
        val hasCarbKeywordLine = prepared.any { line ->
            val folded = foldDiacritics(line.lowercase())
            carbsKeywords.any { folded.contains(foldDiacritics(it.lowercase())) }
        }
        if (!hasCarbKeywordLine) return result
        val carbLineHasOnlyTinyGram = prepared.any { line ->
            val folded = foldDiacritics(line.lowercase())
            val isCarb = carbsKeywords.any { folded.contains(foldDiacritics(it.lowercase())) }
            if (!isCarb) return@any false
            val grams = rowUnitNumberTokens(folded).filter { it.unit == "g" }.map { it.value }
            grams.isEmpty() || (grams.maxOrNull() ?: 0.0) <= 0.2
        }
        if (!carbLineHasOnlyTinyGram) return result
        return result.copy(carbs = result.sugars)
    }

    private fun supplementLowCalorieMilkLikeFatAndSatFat(
        prepared: List<String>,
        result: NutritionLabelParseResult
    ): NutritionLabelParseResult {
        if (result.calories <= 0.0 || result.calories > 100.0) return result
        var out = result

        if (out.fat == 0.0) {
            for (rawLine in prepared) {
                val folded = foldDiacritics(rawLine.lowercase())
                if (!fatKeywords.any { folded.contains(foldDiacritics(it.lowercase())) }) continue
                val grams = rowUnitNumberTokens(folded).filter { it.unit == "g" }.map { it.value }.filter { it > 0.0 && it <= 1.0 }
                grams.minOrNull()?.let {
                    out = out.copy(fat = it)
                    break
                }
            }
        }

        if (out.saturatedFat == 0.0 || (out.fat > 0.0 && out.saturatedFat >= out.fat)) {
            val candidates = mutableListOf<Double>()
            for (rawLine in prepared) {
                val folded = foldDiacritics(rawLine.lowercase())
                if (!folded.contains("saturad") && !folded.contains("saturat")) continue
                val grams = rowUnitNumberTokens(folded).filter { it.unit == "g" }.map { it.value }
                candidates.addAll(grams.filter { it > 0.0 && it <= 0.5 })
            }
            candidates.minOrNull()?.let { out = out.copy(saturatedFat = it) }
            if (out.fat > 0.0 && out.saturatedFat >= out.fat) {
                for (rawLine in prepared) {
                    val folded = foldDiacritics(rawLine.lowercase())
                    if (!fatKeywords.any { folded.contains(foldDiacritics(it.lowercase())) }) continue
                    val grams = rowUnitNumberTokens(folded).filter { it.unit == "g" }.map { it.value }.filter { it > 0.0 && it < out.fat }
                    grams.minOrNull()?.let {
                        out = out.copy(saturatedFat = it)
                        break
                    }
                }
            }
        }

        if (out.fat == 0.0 && out.saturatedFat > 0.0) {
            val pool = mutableListOf<Double>()
            for (rawLine in prepared) {
                val folded = foldDiacritics(rawLine.lowercase())
                if (folded.contains("sal") || folded.contains("salt")) continue
                val grams = rowUnitNumberTokens(folded).filter { it.unit == "g" }.map { it.value }
                pool.addAll(grams.filter { it > out.saturatedFat && it <= 1.0 })
            }
            pool.minOrNull()?.let { out = out.copy(fat = it) }
        }

        return out
    }

    private fun supplementLowCarbsFromCorpus(
        prepared: List<String>,
        result: NutritionLabelParseResult
    ): NutritionLabelParseResult {
        if (result.carbs >= 10.0) return result
        for (rawLine in prepared) {
            val folded = foldDiacritics(rawLine.lowercase())
            val hasContext = carbsKeywords.any { folded.contains(foldDiacritics(it.lowercase())) } ||
                folded.contains("hidrats") ||
                folded.contains("carbon") ||
                folded.contains("fibra")
            if (!hasContext) continue
            val gramValues = rowUnitNumberTokens(folded).filter { it.unit == "g" }.map { it.value }
            if (gramValues.size < 2) continue
            val largest = gramValues.maxOrNull() ?: continue
            if (largest < 10.0) continue
            return result.copy(carbs = largest)
        }
        return result
    }

    private fun supplementImplausibleSodiumFromCorpus(
        prepared: List<String>,
        result: NutritionLabelParseResult
    ): NutritionLabelParseResult {
        if (result.sodiumMg != 0.0 && result.sodiumMg <= 2000.0) return result
        orphanSaltGramSodiumMg(prepared)?.let { return result.copy(sodiumMg = it) }
        var bestMg: Double? = null
        for (rawLine in prepared) {
            val folded = foldDiacritics(rawLine.lowercase())
            if (folded.contains("prote") || folded.contains("saturat") || folded.contains("greixos")) continue
            if (folded.contains("hidrats") || folded.contains("fibra") || folded.contains("carbon")) continue
            for (token in rowUnitNumberTokens(folded)) {
                if (token.unit != "g") continue
                if (token.value !in 0.1..2.5) continue
                val sodium = round((token.value / 2.5) * 1000.0)
                if (sodium <= 0.0 || sodium > 1000.0) continue
                if (bestMg == null || sodium < bestMg!!) bestMg = sodium
            }
        }
        return if (bestMg != null) result.copy(sodiumMg = bestMg!!) else result
    }

    private fun orphanSaltGramSodiumMg(prepared: List<String>): Double? {
        val nutrientMarkers = proteinKeywords + carbsKeywords + fatKeywords + saturatedFatKeywords +
            sugarsKeywords + fiberKeywords
        var bestMg: Double? = null
        for (rawLine in prepared.reversed()) {
            val folded = foldDiacritics(rawLine.lowercase())
            if (nutrientMarkers.any { folded.contains(foldDiacritics(it.lowercase())) }) continue
            if (saltKeywords.any { folded.contains(foldDiacritics(it.lowercase())) }) continue
            val grams = rowUnitNumberTokens(folded).filter { it.unit == "g" }.map { it.value }
            if (grams.size != 1) continue
            val gram = grams.first()
            if (gram !in 0.1..2.5) continue
            val sodium = round((gram / 2.5) * 1000.0)
            if (sodium > 0.0 && sodium <= 1000.0) {
                if (bestMg == null || sodium > bestMg!!) bestMg = sodium
            }
        }
        return bestMg
    }

    private data class KeywordMatch(val keyword: String, val range: IntRange)

    private data class RowNumberToken(
        val value: Double,
        val unit: String,
        val numberStartOffset: Int,
        val matchRange: IntRange
    )

    private fun sanitizeLine(text: String): String {
        val trimmed = text.trim().replace("<", "")
        if (trimmed.isEmpty()) return ""
        val collapsed = leaderRunPattern.replace(trimmed, " ")
        val noTrail = trailingLeaderNoisePattern.replace(collapsed, "")
        val commaOrphanGrams = Regex("""(\d),(\d{1,2})\s+\.""").replace(noTrail, "$1.$2 g")
        val orphanDecimalGrams = Regex("""(\d\.\d{1,2})\s+\.""").replace(commaOrphanGrams, "$1 g")
        val tightUnitGrams = Regex("""(\d(?:[.,]\d{1,2})?)(g|mg)\b""", RegexOption.IGNORE_CASE)
            .replace(orphanDecimalGrams, "$1 $2")
        return collapseWhitespace(tightUnitGrams)
    }

    fun formatFieldValue(value: Double): String {
        val rounded = (value * 10.0).round() / 10.0
        return if (rounded == rounded.toLong().toDouble()) {
            rounded.toLong().toString()
        } else {
            rounded.toString()
        }
    }

    private fun normalizeEuropeanDecimals(text: String): String =
        europeanDecimalPattern.replace(text, "$1.$2")

    private fun collapseWhitespace(text: String): String =
        text.split(Regex("""\s+""")).filter { it.isNotEmpty() }.joinToString(" ")

    private fun foldDiacritics(text: String): String {
        val normalized = Normalizer.normalize(text, Normalizer.Form.NFD)
        return normalized
            .replace(Regex("""\p{M}"""), "")
            .replace("ß", "ss")
            .replace("ẞ", "ss")
    }

    private fun parseLocalizedNumber(raw: String): Double? {
        val normalized = raw.replace("<", "").trim().replace(',', '.')
        return normalized.toDoubleOrNull()
    }

    private fun keywordEndOffset(match: KeywordMatch): Int = match.range.last + 1

    private fun rowUnitNumberTokens(foldedLine: String): List<RowNumberToken> {
        return unitNumberPattern.findAll(foldedLine).mapNotNull { m ->
            val value = parseLocalizedNumber(m.groupValues[1]) ?: return@mapNotNull null
            val unit = m.groupValues[2].lowercase()
            RowNumberToken(
                value = value,
                unit = unit,
                numberStartOffset = m.range.first,
                matchRange = m.range
            )
        }.toList()
    }

    private fun rowKcalTokens(foldedLine: String): List<RowNumberToken> {
        return kcalCapturePattern.findAll(foldedLine).mapNotNull { m ->
            val value = parseLocalizedNumber(m.groupValues[1]) ?: return@mapNotNull null
            RowNumberToken(
                value = value,
                unit = "kcal",
                numberStartOffset = m.range.first,
                matchRange = m.range
            )
        }.toList()
    }

    private fun allKeywordMatchesOnLine(foldedLine: String): List<KeywordMatch> {
        val keywordLists = listOf(
            caloriesKeywords, proteinKeywords, carbsKeywords, fatKeywords,
            saturatedFatKeywords, sugarsKeywords, fiberKeywords, sodiumKeywords, saltKeywords
        )
        return keywordLists.mapNotNull { findFirstKeywordMatch(foldedLine, it) }
    }

    private fun shortestDistanceAnchor(
        foldedLine: String,
        keywordMatch: KeywordMatch,
        candidates: List<RowNumberToken>,
        allowedUnits: Set<String>
    ): RowNumberToken? {
        val keywordEnd = keywordEndOffset(keywordMatch)
        val peerKeywords = allKeywordMatchesOnLine(foldedLine).filter { it.range != keywordMatch.range }
        val filtered = candidates.filter { token ->
            if (token.unit !in allowedUnits || token.numberStartOffset < keywordEnd) return@filter false
            val myDistance = token.numberStartOffset - keywordEnd
            for (peer in peerKeywords) {
                val peerEnd = keywordEndOffset(peer)
                if (token.numberStartOffset < peerEnd) continue
                val peerDistance = token.numberStartOffset - peerEnd
                if (peerDistance < myDistance) return@filter false
            }
            true
        }
        if (filtered.isEmpty()) return null
        return filtered.minByOrNull { it.numberStartOffset - keywordEnd }
    }

    private fun logDistanceAnchor(
        field: String,
        rawLine: String,
        rowIndex: Int,
        keywordMatch: KeywordMatch,
        foldedLine: String,
        candidates: List<RowNumberToken>,
        selected: RowNumberToken?
    ) {
        val keywordEnd = keywordEndOffset(keywordMatch)
        blockHeader(field)
        dbg("Keyword: '${keywordMatch.keyword}'")
        dbg("Row: $rowIndex")
        dbg("Line Content: '$rawLine'")
        val tokenList = candidates.joinToString(", ") { token ->
            val dist = token.numberStartOffset - keywordEnd
            "[${token.numberStartOffset}] ${token.value}${token.unit} (dist=$dist)"
        }
        dbg("Tokens: ${if (tokenList.isEmpty()) "[]" else tokenList}")
        if (selected != null) {
            val dist = selected.numberStartOffset - keywordEnd
            dbg("Selected Token: '${selected.value}${selected.unit}' | Distance: $dist")
        } else {
            dbg("Selected Token: <none>")
        }
        blockFooter()
    }

    private fun extractCaloriesFromLine(foldedLine: String, rawLine: String, rowIndex: Int): Double? {
        if (kjPattern.containsMatchIn(foldedLine) && !foldedLine.contains("kcal")) return null
        val keywordMatch = findFirstKeywordMatch(foldedLine, caloriesKeywords)
        if (keywordMatch != null) {
            val kcalTokens = rowKcalTokens(foldedLine)
            val selected = shortestDistanceAnchor(foldedLine, keywordMatch, kcalTokens, setOf("kcal"))
            logDistanceAnchor("Calories", rawLine, rowIndex, keywordMatch, foldedLine, kcalTokens, selected)
            if (selected != null) {
                if (selected.value > 0.0 && selected.value <= 1000.0) return selected.value
                if (selected.value > 1000.0) {
                    warn("WARNING: Rejected value ${selected.value} for Calories field because it exceeds the 1000 kcal physical limit per 100g sample.")
                    dbg("Row: $rowIndex | Line Content: '$rawLine'")
                }
            }
        }
        return rowKcalTokens(foldedLine).firstOrNull { it.value > 0.0 && it.value <= 1000.0 }?.value
    }

    private fun extractMacroGramFromLine(
        foldedLine: String,
        rawLine: String,
        rowIndex: Int,
        field: String,
        keywords: List<String>,
        excludeFatContexts: Boolean
    ): Double? {
        val keywordMatch = findFirstKeywordMatch(foldedLine, keywords) ?: return null
        val rowTokens = rowUnitNumberTokens(foldedLine)
        val selected = shortestDistanceAnchor(foldedLine, keywordMatch, rowTokens, setOf("g"))
        logDistanceAnchor(field, rawLine, rowIndex, keywordMatch, foldedLine, rowTokens, selected)
        if (selected == null || selected.unit != "g") return null
        if (excludeFatContexts) {
            val trailing = foldedLine.substring(keywordMatch.range.last + 1)
            if (fatExclusionPattern.containsMatchIn(trailing)) return null
        }
        if (isHeaderScopeToken(foldedLine, selected.matchRange)) return null
        var value = selected.value
        if (field == "Protein") {
            val keywordEnd = keywordEndOffset(keywordMatch)
            val ranked = rowUnitNumberTokens(foldedLine).filter {
                it.unit == "g" && it.numberStartOffset >= keywordEnd
            }
            val values = ranked.map { it.value }
            if (value == 0.0) {
                values.filter { it > 0.0 }.maxOrNull()?.let { value = it }
            } else if (value <= 3.0 && values.size > 1) {
                values.filter { it > value }.maxOrNull()?.let { value = it }
            }
        } else if (field == "Sugars") {
            val keywordEnd = keywordEndOffset(keywordMatch)
            val grams = rowUnitNumberTokens(foldedLine)
                .filter { it.unit == "g" && it.numberStartOffset >= keywordEnd }
                .map { it.value }
            if (value >= 20.0) {
                grams.filter { it in 0.0..1.0 }.minOrNull()?.let { value = it }
            }
        } else if (field == "SatFat") {
            val keywordEnd = keywordEndOffset(keywordMatch)
            val grams = rowUnitNumberTokens(foldedLine)
                .filter { it.unit == "g" && it.numberStartOffset >= keywordEnd }
                .map { it.value }
            if (grams.size > 1) {
                grams.filter { it > 0.0 && it < value }.minOrNull()?.let { value = it }
            }
        }
        if (value < 0.0 || value > 100.0) {
            if (value > 100.0) {
                warn("WARNING: Rejected value $value for $field field because it exceeds the 100g physical limit per 100g sample.")
                dbg("Row: $rowIndex | Line Content: '$rawLine'")
            }
            return null
        }
        return value
    }

    private fun extractSodiumMgFromLine(foldedLine: String, rawLine: String, rowIndex: Int): Double? {
        val keywordMatch = findFirstKeywordMatch(foldedLine, sodiumKeywords) ?: return null
        if (barcodeDigitsPattern.containsMatchIn(foldedLine)) return null
        if (percentOrRdaPattern.containsMatchIn(foldedLine)) return null
        val rowTokens = rowUnitNumberTokens(foldedLine)
        val selected = shortestDistanceAnchor(foldedLine, keywordMatch, rowTokens, setOf("g", "mg"))
        logDistanceAnchor("Sodium", rawLine, rowIndex, keywordMatch, foldedLine, rowTokens, selected)
        if (selected == null) return null
        val mg = if (selected.unit == "g") selected.value * 1000.0 else selected.value
        if (mg < 0.0 || mg > 10_000.0) {
            warn("WARNING: Rejected value $mg for Sodium field because it exceeds the 10000mg physical limit per 100g sample.")
            dbg("Row: $rowIndex | Line Content: '$rawLine' | InputValue: ${selected.value}${selected.unit}")
            return null
        }
        return mg
    }

    private fun extractSaltAsSodiumMgFromLine(foldedLine: String, rawLine: String, rowIndex: Int): Double? {
        val keywordMatch = findFirstKeywordMatch(foldedLine, saltKeywords) ?: return null
        if (saltKeywordExclusionPattern.containsMatchIn(foldedLine)) return null
        if (barcodeDigitsPattern.containsMatchIn(foldedLine)) return null
        if (percentOrRdaPattern.containsMatchIn(foldedLine)) return null
        val rowTokens = rowUnitNumberTokens(foldedLine)
        val selected = shortestDistanceAnchor(foldedLine, keywordMatch, rowTokens, setOf("g", "mg"))
        logDistanceAnchor("SaltToSodium", rawLine, rowIndex, keywordMatch, foldedLine, rowTokens, selected)
        if (selected == null) return null
        dbg("Salt Input: value=${selected.value} unit=${selected.unit}")
        val sodiumMg = if (selected.unit == "mg") {
            dbg("Converted Sodium: value(mg)=${selected.value}")
            selected.value
        } else {
            if (selected.value > 10.0) {
                warn("WARNING: Rejected value ${selected.value} for Salt field because it exceeds the 10g salt physical limit per 100g sample.")
                dbg("Row: $rowIndex | Line Content: '$rawLine'")
                return null
            }
            val converted = (selected.value / 2.5) * 1000.0
            val rounded = round(converted)
            dbg("Converted Sodium: (value/2.5)*1000 rounded = ${rounded}mg")
            rounded
        }
        if (sodiumMg < 0.0 || sodiumMg > 10_000.0) {
            warn("WARNING: Rejected value $sodiumMg for Sodium field because it exceeds the 10000mg physical limit per 100g sample.")
            dbg("Row: $rowIndex | Line Content: '$rawLine' | SaltInput: ${selected.value}${selected.unit}")
            return null
        }
        return sodiumMg
    }

    private fun isIsolatedSingleValueLine(rawLine: String): Boolean {
        val folded = foldDiacritics(rawLine.lowercase())
        return isolatedValueLinePattern.containsMatchIn(folded)
    }

    private fun firstUnitValueFromIsolatedLine(foldedLine: String): RowNumberToken? {
        val m = isolatedValueLinePattern.find(foldedLine) ?: return null
        val value = parseLocalizedNumber(m.groupValues[1]) ?: return null
        val unit = m.groupValues[2].lowercase()
        return RowNumberToken(value, unit, m.range.first, m.range)
    }

    private fun applyVerticalFallbackIfNeeded(
        prepared: List<String>,
        rowIndex: Int,
        foldedLine: String,
        rawLine: String,
        currentProtein: Double,
        currentSodiumMg: Double,
        apply: (protein: Double?, sodiumMg: Double?) -> Unit
    ) {
        if (rowIndex + 1 >= prepared.size) return
        val nextRaw = prepared[rowIndex + 1]
        if (!isIsolatedSingleValueLine(nextRaw)) return
        val nextFolded = foldDiacritics(nextRaw.lowercase())
        val fallback = firstUnitValueFromIsolatedLine(nextFolded) ?: return

        var proteinFallback: Double? = null
        var sodiumFallback: Double? = null

        val proteinMatch = findFirstKeywordMatch(foldedLine, proteinKeywords)
        if (currentProtein == 0.0 &&
            proteinMatch != null &&
            shortestDistanceAnchor(foldedLine, proteinMatch, rowUnitNumberTokens(foldedLine), setOf("g")) == null &&
            fallback.unit == "g" &&
            fallback.value in 0.0..100.0
        ) {
            dbg("VerticalFallback: Protein Row $rowIndex -> Row ${rowIndex + 1} '$nextRaw' -> ${fallback.value}g")
            proteinFallback = fallback.value
        }

        val saltMatch = findFirstKeywordMatch(foldedLine, saltKeywords)
        if (currentSodiumMg == 0.0 &&
            saltMatch != null &&
            shortestDistanceAnchor(foldedLine, saltMatch, rowUnitNumberTokens(foldedLine), setOf("g", "mg")) == null
        ) {
            val saltG = if (fallback.unit == "mg") fallback.value / 1000.0 else fallback.value
            if (saltG in 0.0..10.0) {
                val converted = round((saltG / 2.5) * 1000.0)
                dbg("VerticalFallback: Salt Row $rowIndex -> Row ${rowIndex + 1} '$nextRaw' -> ${converted}mg")
                sodiumFallback = converted
            }
        }

        if (proteinFallback != null || sodiumFallback != null) {
            apply(proteinFallback, sodiumFallback)
        }
    }

    private fun isHeaderScopeToken(foldedLine: String, span: IntRange): Boolean {
        val start = (span.first - 18).coerceAtLeast(0)
        val end = (span.last + 18).coerceAtMost(foldedLine.length - 1)
        if (end <= start) return false
        val window = foldedLine.substring(start, end + 1)
        if (headerScopeBlacklistPattern.containsMatchIn(window)) return true
        val hasPerPor = window.contains("per") || window.contains("por")
        val has100 = window.contains("100")
        val hasUnit = window.contains("g") || window.contains("ml")
        return hasPerPor && has100 && hasUnit
    }

    private fun findFirstKeywordMatch(foldedLine: String, keywords: List<String>): KeywordMatch? {
        val sorted = keywords.sortedByDescending { it.length }
        var best: KeywordMatch? = null
        for (keyword in sorted) {
            val k = foldDiacritics(keyword.lowercase())
            val idx = foldedLine.indexOf(k)
            if (idx < 0) continue
            val end = idx + k.length - 1
            if (requiresWordBoundary(keyword) && !isWordBoundaryMatch(foldedLine, idx, end + 1)) continue
            val r = idx..end
            if (best == null || r.first < best!!.range.first) best = KeywordMatch(keyword, r)
        }
        return best
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
