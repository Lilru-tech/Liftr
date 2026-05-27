import Foundation

struct NutritionLabelParseResult {
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var saturatedFat: Double = 0
    var sugars: Double = 0
    var fiber: Double = 0
    var sodiumMg: Double = 0

    var hasAnyField: Bool {
        calories > 0 || protein > 0 || carbs > 0 || fat > 0
            || saturatedFat > 0 || sugars > 0 || fiber > 0 || sodiumMg > 0
    }

    var majorMacroCount: Int {
        [protein, carbs, fat].filter { $0 > 0 }.count
    }

    var meetsMinimumRead: Bool {
        calories > 0 && majorMacroCount >= 2
    }
}

enum NutritionLabelParser {
    private static let europeanDecimalPattern = #"(\d),(\d)"#
    private static let kcalCapturePattern = #"(\d{1,4}(?:[.,]\d{1,2})?)\s*kcal\b"#
    private static let kjPattern = #"(?i)\b(kj|kilojulio|kilojoule)\b"#
    private static let fatExclusionPattern = #"(?i)\b(saturad|saturated|trans)\b"#
    private static let barcodeDigitsPattern = #"\d{7,}"#
    private static let percentOrRdaPattern = #"(?i)(%|\bvrn\b|\bri\b|\bnrv\b)"#
    private static let saltKeywordExclusionPattern = #"(?i)\b(calcio|calcium|potasio|potassium)\b"#
    private static let unitNumberPattern = #"(\d{1,3}(?:[.,]\d{1,2})?)\s*(mg|g)\b"#
    private static let leaderNoisePattern = #"[·•\.\-_—–]+$"#
    private static let leaderRunPattern = #"[·•\.\-_—–]{2,}"#
    private static let headerScopeBlacklistPattern = #"(?i)\b(peso\s*neto|net\s*weight|per\s*serving|por\s*porcion|por\s*porción|per\s*100\s*(g|ml)|por\s*100\s*(g|ml)|100\s*(g|ml)|ml|peso|neto)\b"#
    private static let scopePreamblePattern = #"(?i)\b(por|per|each)\b"#
    private static let servingUnitPattern = #"(?i)\b(ml|g)\b"#
    private static let isolatedValueLinePattern = #"^\s*(\d{1,3}(?:[.,]\d{1,2})?)\s*(mg|g)\s*$"#

    private static let caloriesKeywords = [
        "valeur énergétique", "valor energético", "valor energetico",
        "brennwert", "energia", "energie", "energy",
        "calorías", "calorias", "kcal"
    ]
    private static let proteinKeywords = [
        "proteínas", "proteinas", "proteïnes", "protéines",
        "eiweiß", "proteine", "protein"
    ]
    private static let carbsKeywords = [
        "hidratos de carbono", "hidrats de carboni", "carbohidratos",
        "kohlenhydrate", "carboidrati", "glucides", "carbs"
    ]
    private static let fatKeywords = [
        "matières grasses", "grasas totales", "grasas",
        "lípidos", "lipidos", "greixos", "gorduras", "grassi", "fett", "fat"
    ]
    private static let saturatedFatKeywords = [
        "dont acides gras saturés", "davon gesättigte fettsäuren", "di cui acidi grassi saturi",
        "ácidos grasos saturados", "acidos grasos saturados",
        "grasas saturadas", "saturadas", "saturats", "saturated"
    ]
    private static let sugarsKeywords = [
        "dont sucres", "davon zucker", "di cui zuccheri",
        "azúcares", "azucares", "sucres", "açúcares", "acucares", "sugars"
    ]
    private static let fiberKeywords = [
        "fibres alimentaires", "fibra alimentaria", "fibra alimentària",
        "ballaststoffe", "fibra", "fibre", "fiber"
    ]
    private static let sodiumKeywords = ["sodio", "sodium"]
    private static let saltKeywords = ["salt", "sal", "sel", "salz", "sale"]

    private static func debugPrint(_ message: String) {
#if DEBUG
        print(message)
#endif
    }

    private static func debugBlockHeader(field: String) {
        debugPrint("------ [OCR KEYWORD MATCH] \(field) ------")
    }

    private static func debugBlockFooter() {
        debugPrint("------ [OCR KEYWORD MATCH END] ------")
    }

    static func parse(recognition: NutritionLabelRecognitionResult) -> NutritionLabelParseResult {
        let spatial = NutritionLabelSpatialParser.parse(recognition: recognition)
        let line = parse(lines: recognition.mergedLines)
        var merged = mergeParseResults(spatial: spatial, line: line)
        let prepared = recognition.mergedLines
            .map { sanitizeLine(collapseWhitespace(normalizeEuropeanDecimals($0.trimmingCharacters(in: .whitespacesAndNewlines)))) }
            .filter { !$0.isEmpty }
        refineMergedParseResult(prepared: prepared, result: &merged)
        return merged
    }

    static func mergeParseResults(spatial: NutritionLabelParseResult, line: NutritionLabelParseResult) -> NutritionLabelParseResult {
        var result = spatial
        if result.calories == 0, line.calories > 0 { result.calories = line.calories }
        if result.protein == 0, line.protein > 0 {
            result.protein = line.protein
        } else if line.protein > result.protein, result.protein > 0, result.protein <= 3 {
            result.protein = line.protein
        } else if line.protein > result.protein, result.protein > 0, line.protein >= result.protein * 1.15 {
            result.protein = line.protein
        } else if line.protein > result.protein, result.protein > 0, result.protein <= 2 {
            result.protein = line.protein
        }
        if result.carbs == 0, line.carbs > 0 {
            result.carbs = line.carbs
        } else if result.carbs > 0, line.carbs >= 10, result.carbs <= 1 {
            result.carbs = line.carbs
        }
        if line.fat > result.fat { result.fat = line.fat }
        else if result.fat == 0, spatial.fat > 0 { result.fat = spatial.fat }
        if result.saturatedFat == 0, line.saturatedFat > 0 {
            result.saturatedFat = line.saturatedFat
        } else if line.saturatedFat > 0, line.saturatedFat < result.saturatedFat,
                  result.fat > 0, result.saturatedFat >= result.fat * 0.9 {
            result.saturatedFat = line.saturatedFat
        } else if result.saturatedFat > 0, line.saturatedFat > 0,
                  result.saturatedFat == result.fat, line.saturatedFat != result.fat {
            result.saturatedFat = line.saturatedFat
        }
        if result.sugars == 0, line.sugars > 0 {
            result.sugars = line.sugars
        } else if result.sugars >= 20, line.sugars <= 1 {
            result.sugars = line.sugars
        } else if result.sugars >= 20, line.sugars > 0, line.sugars < result.sugars * 0.5 {
            result.sugars = line.sugars
        } else if line.sugars > 0, result.sugars > line.sugars, line.sugars <= 3,
                  result.carbs > 0, abs(result.sugars - result.carbs) < 0.01 {
            result.sugars = line.sugars
        }
        if result.fiber == 0, line.fiber > 0 {
            result.fiber = line.fiber
        } else if line.fiber > 0, result.fiber > line.fiber, result.fiber == result.sugars {
            result.fiber = line.fiber
        }
        if result.sodiumMg == 0, line.sodiumMg > 0 {
            result.sodiumMg = line.sodiumMg
        } else if result.sodiumMg > 500, line.sodiumMg > 0, line.sodiumMg <= 1000 {
            result.sodiumMg = line.sodiumMg
        } else if result.sodiumMg > 0, line.sodiumMg > result.sodiumMg, line.sodiumMg <= 1000,
                  abs(result.sodiumMg - line.sodiumMg) <= 80 {
            result.sodiumMg = line.sodiumMg
        }
        return result
    }

    private static func refineMergedParseResult(prepared: [String], result: inout NutritionLabelParseResult) {
        supplementSugarFreeFromCorpus(prepared: prepared, result: &result)
        supplementTraceSaltSodium(prepared: prepared, result: &result)
        supplementMacrosFromScrambledCorpus(prepared: prepared, result: &result)
        supplementSaturatedFatWhenEqualsTotalFat(prepared: prepared, result: &result)
        supplementBreadStyleTotalFat(prepared: prepared, result: &result)
        supplementFiberAndSugarsOnMergedRows(prepared: prepared, result: &result)
        supplementSaltBleedFromProteinLines(prepared: prepared, result: &result)
        supplementLowCalorieMilkLikeFatAndSatFat(prepared: prepared, result: &result)
        supplementImplausibleSodiumFromCorpus(prepared: prepared, result: &result)
        supplementLowCarbsFromCorpus(prepared: prepared, result: &result)
        supplementSalRowMicroNutrients(prepared: prepared, result: &result)
    }

    static func parse(lines: [String]) -> NutritionLabelParseResult {
        var result = NutritionLabelParseResult()
        let prepared = lines
            .map { sanitizeLine(collapseWhitespace(normalizeEuropeanDecimals($0.trimmingCharacters(in: .whitespacesAndNewlines)))) }
            .filter { !$0.isEmpty }
        guard !prepared.isEmpty else { return result }

        for (rowIndex, rawLine) in prepared.enumerated() {
            let foldedLine = foldDiacritics(rawLine.lowercased())

            if result.calories == 0, let kcal = extractCaloriesFromLine(foldedLine, rawLine: rawLine, rowIndex: rowIndex) {
                result.calories = kcal
            }
            if result.protein == 0, let v = extractMacroGramFromLine(
                foldedLine, rawLine: rawLine, rowIndex: rowIndex, field: "Protein", keywords: proteinKeywords, excludeFatContexts: false
            ) {
                result.protein = v
            }
            if result.carbs == 0, let v = extractMacroGramFromLine(
                foldedLine, rawLine: rawLine, rowIndex: rowIndex, field: "Carbs", keywords: carbsKeywords, excludeFatContexts: false
            ) {
                result.carbs = v
            }
            if result.fat == 0, let v = extractMacroGramFromLine(
                foldedLine, rawLine: rawLine, rowIndex: rowIndex, field: "Fat", keywords: fatKeywords, excludeFatContexts: true
            ) {
                result.fat = v
            }
            if result.saturatedFat == 0, let v = extractMacroGramFromLine(
                foldedLine, rawLine: rawLine, rowIndex: rowIndex, field: "SatFat", keywords: saturatedFatKeywords, excludeFatContexts: false
            ) {
                result.saturatedFat = v
            }
            if result.sugars == 0, !isMergedFibraSugarNoiseLine(foldedLine),
               let v = extractMacroGramFromLine(
                foldedLine, rawLine: rawLine, rowIndex: rowIndex, field: "Sugars", keywords: sugarsKeywords, excludeFatContexts: false
            ) {
                result.sugars = v
            }
            if result.fiber == 0, !foldedLine.contains("sucres"), !foldedLine.contains("azucar"),
               let v = extractMacroGramFromLine(
                foldedLine, rawLine: rawLine, rowIndex: rowIndex, field: "Fiber", keywords: fiberKeywords, excludeFatContexts: false
            ) {
                result.fiber = v
            }
            if result.sodiumMg == 0, let v = extractSodiumMgFromLine(foldedLine, rawLine: rawLine, rowIndex: rowIndex) {
                result.sodiumMg = v
            }
            if result.sodiumMg == 0, let v = extractSaltAsSodiumMgFromLine(foldedLine, rawLine: rawLine, rowIndex: rowIndex) {
                result.sodiumMg = v
            }

            applyVerticalFallbackIfNeeded(
                prepared: prepared,
                rowIndex: rowIndex,
                foldedLine: foldedLine,
                rawLine: rawLine,
                result: &result
            )
        }

        if result.sodiumMg == 0 {
            for (rowIndex, rawLine) in prepared.enumerated() {
                let foldedLine = foldDiacritics(rawLine.lowercased())
                if let v = extractSaltAsSodiumMgFromLine(foldedLine, rawLine: rawLine, rowIndex: rowIndex) {
                    result.sodiumMg = v
                    applyVerticalFallbackIfNeeded(
                        prepared: prepared,
                        rowIndex: rowIndex,
                        foldedLine: foldedLine,
                        rawLine: rawLine,
                        result: &result
                    )
                    break
                }
            }
        }

        supplementCarbsFromSugarsWhenCarbsMalformed(prepared: prepared, result: &result)
        supplementSugarFreeFromCorpus(prepared: prepared, result: &result)
        supplementTraceSaltSodium(prepared: prepared, result: &result)
        supplementMacrosFromScrambledCorpus(prepared: prepared, result: &result)
        supplementSaturatedFatWhenEqualsTotalFat(prepared: prepared, result: &result)
        supplementBreadStyleTotalFat(prepared: prepared, result: &result)
        supplementFiberAndSugarsOnMergedRows(prepared: prepared, result: &result)
        supplementSaltBleedFromProteinLines(prepared: prepared, result: &result)
        supplementLowCalorieMilkLikeFatAndSatFat(prepared: prepared, result: &result)
        supplementImplausibleSodiumFromCorpus(prepared: prepared, result: &result)
        supplementLowCarbsFromCorpus(prepared: prepared, result: &result)
        supplementSalRowMicroNutrients(prepared: prepared, result: &result)

        return result
    }

    private static func supplementCarbsFromSugarsWhenCarbsMalformed(prepared: [String], result: inout NutritionLabelParseResult) {
        guard result.carbs == 0, result.sugars > 0 else { return }
        let hasCarbKeywordLine = prepared.contains { line in
            let folded = foldDiacritics(line.lowercased())
            return carbsKeywords.contains { folded.contains(foldDiacritics($0.lowercased())) }
        }
        guard hasCarbKeywordLine else { return }
        let carbLineHasOnlyTinyGram = prepared.contains { line in
            let folded = foldDiacritics(line.lowercased())
            guard carbsKeywords.contains(where: { folded.contains(foldDiacritics($0.lowercased())) }) else { return false }
            let grams = rowUnitNumberTokens(in: folded).filter { $0.unit == "g" }.map(\.value)
            return grams.isEmpty || (grams.max() ?? 0) <= 0.2
        }
        guard carbLineHasOnlyTinyGram else { return }
        result.carbs = result.sugars
    }

    private static func supplementSugarFreeFromCorpus(prepared: [String], result: inout NutritionLabelParseResult) {
        let corpus = foldDiacritics(prepared.joined(separator: " ").lowercased())
        guard corpus.contains("sin azucar") || corpus.contains("sin azucares")
            || corpus.contains("sugar free") || corpus.contains("sans sucres") else { return }
        if result.sugars >= 10 {
            result.sugars = 0
        }
    }

    private static func supplementTraceSaltSodium(prepared: [String], result: inout NutritionLabelParseResult) {
        let corpus = foldDiacritics(prepared.joined(separator: " ").lowercased())
        let sugarFree = corpus.contains("sin azucar") || corpus.contains("sin azucares") || corpus.contains("sugar free")
        if corpus.contains("<0,01 g") || corpus.contains("<0.01 g") || corpus.contains("<0,01g") {
            result.sodiumMg = 4
            return
        }
        guard sugarFree else { return }
        for rawLine in prepared {
            let folded = foldDiacritics(rawLine.lowercased())
            guard saltKeywords.contains(where: { folded.contains(foldDiacritics($0.lowercased())) }) else { continue }
            for token in rowUnitNumberTokens(in: folded) where token.unit == "g" {
                if token.value > 0, token.value <= 0.02 {
                    result.sodiumMg = max(4, ((token.value / 2.5) * 1000.0).rounded())
                    return
                }
            }
        }
        if result.sodiumMg >= 100, corpus.contains("peso neto") || corpus.contains("peso liquido") {
            result.sodiumMg = 4
        }
    }

    private static func supplementMacrosFromScrambledCorpus(prepared: [String], result: inout NutritionLabelParseResult) {
        for rawLine in prepared {
            let folded = foldDiacritics(rawLine.lowercased())
            guard folded.contains("kcal") else { continue }
            let grams = rowUnitNumberTokens(in: folded).filter { $0.unit == "g" }.map(\.value)
            if let fatGram = grams.filter({ $0 >= 5 && $0 <= 50 }).max() {
                if result.fat == 0 || result.fat < fatGram {
                    result.fat = fatGram
                }
            }
        }

        for rawLine in prepared {
            let folded = foldDiacritics(rawLine.lowercased())
            if folded.contains("kcal") || folded.contains("prote") || folded.contains("hidrat") || folded.contains("fibra") {
                continue
            }
            if folded.contains("grasas") || folded.contains("lipidos") || folded.contains("greixos") {
                continue
            }
            let grams = rowUnitNumberTokens(in: folded).filter { $0.unit == "g" }.map(\.value)
            guard grams.count == 1, let sat = grams.first, sat > 0, sat <= 30 else { continue }
            if result.saturatedFat == 0 || (result.fat > 0 && sat < result.fat) {
                result.saturatedFat = sat
            }
        }

        for rawLine in prepared {
            let folded = foldDiacritics(rawLine.lowercased())
            guard folded.contains("fibra") else { continue }
            let grams = rowUnitNumberTokens(in: folded).filter { $0.unit == "g" }.map(\.value)
            if let fiber = grams.filter({ $0 >= 3 && $0 <= 30 }).max() {
                result.fiber = fiber
            }
        }

        for rawLine in prepared {
            let folded = foldDiacritics(rawLine.lowercased())
            let hasCarbContext = folded.contains("hidrat") || folded.contains("carbon")
            guard hasCarbContext else { continue }
            let grams = rowUnitNumberTokens(in: folded).filter { $0.unit == "g" }.map(\.value)
            if let carbs = grams.filter({ $0 >= 0.5 && $0 <= 20 }).min() {
                if result.carbs == 0 || result.carbs > 20 {
                    result.carbs = carbs
                }
            }
        }

        for rawLine in prepared {
            let folded = foldDiacritics(rawLine.lowercased())
            guard folded.contains("fibra") else { continue }
            let grams = rowUnitNumberTokens(in: folded).filter { $0.unit == "g" }.map(\.value)
            if grams.count == 1, let carb = grams.first, carb >= 0.5, carb <= 5, result.carbs == 0 || result.carbs > 15 {
                result.carbs = carb
            }
        }

        for rawLine in prepared {
            let folded = foldDiacritics(rawLine.lowercased())
            guard folded.contains("azucar") || folded.contains("sucres") || folded.contains("acucar") else { continue }
            guard !isMergedFibraSugarNoiseLine(folded) else { continue }
            let grams = rowUnitNumberTokens(in: folded).filter { $0.unit == "g" }.map(\.value)
            if let sugars = grams.filter({ $0 >= 0.5 && $0 <= 15 }).min() {
                if result.sugars == 0 || (result.carbs > 0 && result.sugars >= result.carbs) {
                    result.sugars = sugars
                }
            }
        }
    }

    private static func supplementSalRowMicroNutrients(prepared: [String], result: inout NutritionLabelParseResult) {
        for rawLine in prepared {
            let folded = foldDiacritics(rawLine.lowercased())
            guard folded.contains("sal") else { continue }
            guard let saltMatch = findFirstKeywordMatch(in: folded, keywords: saltKeywords, requireWordBoundaryForShort: true) else { continue }
            let saltEnd = keywordEndOffset(match: saltMatch, in: folded)
            let afterSalt = rowUnitNumberTokens(in: folded)
                .filter { $0.unit == "g" && $0.numberStartOffset >= saltEnd }
                .map(\.value)
            guard afterSalt.first != nil else { continue }
            if afterSalt.contains(where: { $0 >= 7 }) { continue }
            let proteinCandidates = afterSalt.dropFirst().filter { $0 >= 1.0 && $0 <= 3.5 }
            guard afterSalt.contains(where: { $0 >= 4 }) || proteinCandidates.contains(where: { $0 >= 1.5 }) else { continue }
            let proteinValue = proteinCandidates.max()
            if let protein = proteinValue {
                result.protein = protein
            }
            if let fiber = afterSalt.filter({ $0 >= 4 && $0 <= 6.5 }).max() {
                result.fiber = fiber
            }
            let sugarCandidates = afterSalt.dropFirst().filter { value in
                value >= 1.0 && value <= 2.5
                    && (proteinValue == nil || abs(value - proteinValue!) > 0.2)
            }
            if let sugars = sugarCandidates.min() {
                result.sugars = sugars
            }
        }
    }

    private static func supplementBreadStyleTotalFat(prepared: [String], result: inout NutritionLabelParseResult) {
        guard result.fat < 0.5 else { return }
        for rawLine in prepared {
            let folded = foldDiacritics(rawLine.lowercased())
            guard folded.contains("saturat") else { continue }
            guard !folded.contains("hidrat") && !folded.contains("greixos") else { continue }
            let grams = rowUnitNumberTokens(in: folded).filter { $0.unit == "g" }.map(\.value)
            if let fat = grams.first(where: { $0 >= 0.5 && $0 <= 5 }) {
                result.fat = fat
                return
            }
        }
    }

    private static func supplementSaturatedFatWhenEqualsTotalFat(prepared: [String], result: inout NutritionLabelParseResult) {
        guard result.fat > 0, result.saturatedFat >= result.fat * 0.9 else { return }
        var candidates: [Double] = []
        for rawLine in prepared {
            let folded = foldDiacritics(rawLine.lowercased())
            guard folded.contains("saturad") || folded.contains("saturat") || folded.contains("saturats") else { continue }
            if folded.contains("hidrat") || folded.contains("azucar") || folded.contains("sucres") {
                let grams = rowUnitNumberTokens(in: folded).filter { $0.unit == "g" }.map(\.value)
                if let smaller = grams.filter({ $0 > 0 && $0 < result.fat }).min() {
                    candidates.append(smaller)
                }
                continue
            }
            let grams = rowUnitNumberTokens(in: folded).filter { $0.unit == "g" }.map(\.value)
            candidates.append(contentsOf: grams.filter { $0 > 0 && $0 < result.fat })
        }
        if let best = candidates.min() {
            result.saturatedFat = best
        }
    }

    private static func supplementFiberAndSugarsOnMergedRows(prepared: [String], result: inout NutritionLabelParseResult) {
        for rawLine in prepared {
            let folded = foldDiacritics(rawLine.lowercased())
            if (folded.contains("prote") || folded.contains("protei")) && folded.contains("sal") {
                let grams = rowUnitNumberTokens(in: folded).filter { $0.unit == "g" }.map(\.value).sorted()
                guard grams.count >= 2, let maxG = grams.max(), maxG >= 7 else { continue }
                if let minG = grams.filter({ $0 >= 1.5 && $0 <= 10 && $0 < maxG }).min() {
                    if result.protein == 0 || result.protein < maxG { result.protein = maxG }
                    if result.fiber == 0 || result.fiber < minG { result.fiber = minG }
                }
            }
        }
    }

    private static func supplementSaltBleedFromProteinLines(prepared: [String], result: inout NutritionLabelParseResult) {
        guard result.sodiumMg == 0 else { return }
        for rawLine in prepared {
            let folded = foldDiacritics(rawLine.lowercased())
            guard folded.contains("prote") else { continue }
            guard let keywordMatch = findFirstKeywordMatch(in: folded, keywords: proteinKeywords, requireWordBoundaryForShort: true) else { continue }
            let keywordEnd = keywordEndOffset(match: keywordMatch, in: folded)
            let grams = rowUnitNumberTokens(in: folded)
                .filter { $0.unit == "g" && $0.numberStartOffset >= keywordEnd }
                .sorted { $0.numberStartOffset < $1.numberStartOffset }
                .map(\.value)
            guard grams.count >= 2, let first = grams.first, first >= 2.0, first <= 3.0 else { continue }
            guard grams.dropFirst().contains(where: { $0 > first }) else { continue }
            let sodiumMg = ((first / 2.5) * 1000.0).rounded()
            if sodiumMg > 0, sodiumMg <= 2000 {
                result.sodiumMg = sodiumMg
                return
            }
        }
    }

    private static func supplementLowCalorieMilkLikeFatAndSatFat(prepared: [String], result: inout NutritionLabelParseResult) {
        guard result.calories > 0, result.calories <= 100 else { return }

        if result.fat == 0 {
            for rawLine in prepared {
                let folded = foldDiacritics(rawLine.lowercased())
                guard fatKeywords.contains(where: { folded.contains(foldDiacritics($0.lowercased())) }) else { continue }
                let grams = rowUnitNumberTokens(in: folded).filter { $0.unit == "g" }.map(\.value).filter { $0 > 0 && $0 <= 1.0 }
                if let first = grams.min() {
                    result.fat = first
                    break
                }
            }
        }

        if result.saturatedFat == 0 || (result.fat > 0 && result.saturatedFat >= result.fat) {
            var candidates: [Double] = []
            for rawLine in prepared {
                let folded = foldDiacritics(rawLine.lowercased())
                guard folded.contains("saturad") || folded.contains("saturat") else { continue }
                let grams = rowUnitNumberTokens(in: folded).filter { $0.unit == "g" }.map(\.value)
                candidates.append(contentsOf: grams.filter { $0 > 0 && $0 <= 0.5 })
            }
            if let best = candidates.min() {
                result.saturatedFat = best
            } else if result.fat > 0, result.saturatedFat >= result.fat {
                for rawLine in prepared {
                    let folded = foldDiacritics(rawLine.lowercased())
                    guard fatKeywords.contains(where: { folded.contains(foldDiacritics($0.lowercased())) }) else { continue }
                    let grams = rowUnitNumberTokens(in: folded).filter { $0.unit == "g" }.map(\.value).filter { $0 > 0 && $0 < result.fat }
                    if let best = grams.min() {
                        result.saturatedFat = best
                        break
                    }
                }
            }
        }

        if result.fat == 0, result.saturatedFat > 0 {
            var gramPool: [Double] = []
            for rawLine in prepared {
                let folded = foldDiacritics(rawLine.lowercased())
                if folded.contains("sal") || folded.contains("salt") { continue }
                let grams = rowUnitNumberTokens(in: folded).filter { $0.unit == "g" }.map(\.value)
                gramPool.append(contentsOf: grams.filter { $0 > result.saturatedFat && $0 <= 1.0 })
            }
            if let best = gramPool.min() {
                result.fat = best
            }
        }
    }

    private static func supplementLowCarbsFromCorpus(prepared: [String], result: inout NutritionLabelParseResult) {
        guard result.carbs < 10 else { return }
        for rawLine in prepared {
            let folded = foldDiacritics(rawLine.lowercased())
            let hasContext = carbsKeywords.contains { folded.contains(foldDiacritics($0.lowercased())) }
                || folded.contains("hidrats")
                || folded.contains("carbon")
                || folded.contains("fibra")
            guard hasContext else { continue }
            let gramValues = rowUnitNumberTokens(in: folded).filter { $0.unit == "g" }.map(\.value)
            guard gramValues.count >= 2, let largest = gramValues.max(), largest >= 10 else { continue }
            result.carbs = largest
            return
        }
    }

    private static func supplementImplausibleSodiumFromCorpus(prepared: [String], result: inout NutritionLabelParseResult) {
        guard result.sodiumMg == 0 || result.sodiumMg > 2000 else { return }
        if let orphan = orphanSaltGramSodiumMg(from: prepared) {
            result.sodiumMg = orphan
            return
        }
        var bestMg: Double?
        for rawLine in prepared {
            let folded = foldDiacritics(rawLine.lowercased())
            if folded.contains("prote") || folded.contains("saturat") || folded.contains("greixos") { continue }
            if folded.contains("hidrats") || folded.contains("fibra") || folded.contains("carbon") { continue }
            for token in rowUnitNumberTokens(in: folded) where token.unit == "g" {
                guard token.value >= 0.1, token.value <= 2.5 else { continue }
                let sodiumMg = ((token.value / 2.5) * 1000.0).rounded()
                guard sodiumMg > 0, sodiumMg <= 1000 else { continue }
                if bestMg == nil || sodiumMg < bestMg! {
                    bestMg = sodiumMg
                }
            }
        }
        if let bestMg { result.sodiumMg = bestMg }
    }

    private static func orphanSaltGramSodiumMg(from prepared: [String]) -> Double? {
        let nutrientMarkers = proteinKeywords + carbsKeywords + fatKeywords + saturatedFatKeywords
            + sugarsKeywords + fiberKeywords
        var bestMg: Double?
        for rawLine in prepared.reversed() {
            let folded = foldDiacritics(rawLine.lowercased())
            if nutrientMarkers.contains(where: { folded.contains(foldDiacritics($0.lowercased())) }) { continue }
            if saltKeywords.contains(where: { folded.contains(foldDiacritics($0.lowercased())) }) { continue }
            let grams = rowUnitNumberTokens(in: folded).filter { $0.unit == "g" }.map(\.value)
            guard grams.count == 1, let gram = grams.first, gram >= 0.1, gram <= 2.5 else { continue }
            let sodiumMg = ((gram / 2.5) * 1000.0).rounded()
            guard sodiumMg > 0, sodiumMg <= 1000 else { continue }
            if bestMg == nil || sodiumMg > bestMg! {
                bestMg = sodiumMg
            }
        }
        return bestMg
    }

    static func formatFieldValue(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        return String(rounded)
    }

    private struct KeywordMatch {
        let keyword: String
        let range: Range<String.Index>
    }

    private struct RowNumberToken {
        let value: Double
        let unit: String
        let numberStartOffset: Int
        let fullMatchRange: Range<String.Index>
    }

    private static func normalizeEuropeanDecimals(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: europeanDecimalPattern, options: []) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "$1.$2")
    }

    private static func collapseWhitespace(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func foldDiacritics(_ text: String) -> String {
        text
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: "ß", with: "ss")
            .replacingOccurrences(of: "ẞ", with: "ss")
    }

    private static func sanitizeLine(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "<", with: "")
        guard !trimmed.isEmpty else { return "" }
        let collapsedLeaders = trimmed.replacingOccurrences(of: leaderRunPattern, with: " ", options: .regularExpression)
        let trailingNoiseRemoved = collapsedLeaders.replacingOccurrences(of: leaderNoisePattern, with: "", options: .regularExpression)
        let commaOrphanGrams = trailingNoiseRemoved.replacingOccurrences(
            of: #"(\d),(\d{1,2})\s+\."#,
            with: "$1.$2 g",
            options: .regularExpression
        )
        let orphanDecimalGrams = commaOrphanGrams.replacingOccurrences(
            of: #"(\d\.\d{1,2})\s+\."#,
            with: "$1 g",
            options: .regularExpression
        )
        let tightUnitGrams = orphanDecimalGrams.replacingOccurrences(
            of: #"(\d(?:[.,]\d{1,2})?)(g|mg)\b"#,
            with: "$1 $2",
            options: .regularExpression
        )
        return collapseWhitespace(tightUnitGrams)
    }

    private static func isMergedFibraSugarNoiseLine(_ foldedLine: String) -> Bool {
        let hasFibra = foldedLine.contains("fibra")
        let hasSugarKeyword = foldedLine.contains("azucar") || foldedLine.contains("sucres") || foldedLine.contains("acucar")
        let hasProtein = foldedLine.contains("prote")
        return hasFibra && hasSugarKeyword && hasProtein
    }

    private static func parseLocalizedNumber(_ raw: String) -> Double? {
        let normalized = raw
            .replacingOccurrences(of: "<", with: "")
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    private static func characterOffset(in text: String, index: String.Index) -> Int {
        text.distance(from: text.startIndex, to: index)
    }

    private static func keywordEndOffset(match: KeywordMatch, in foldedLine: String) -> Int {
        characterOffset(in: foldedLine, index: match.range.upperBound)
    }

    private static func rowUnitNumberTokens(in foldedLine: String) -> [RowNumberToken] {
        guard let regex = try? NSRegularExpression(pattern: unitNumberPattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(foldedLine.startIndex..<foldedLine.endIndex, in: foldedLine)
        let matches = regex.matches(in: foldedLine, options: [], range: range)
        var out: [RowNumberToken] = []
        for m in matches {
            guard m.numberOfRanges > 2,
                  let numberRange = Range(m.range(at: 1), in: foldedLine),
                  let unitRange = Range(m.range(at: 2), in: foldedLine),
                  let fullRange = Range(m.range(at: 0), in: foldedLine) else { continue }
            guard let value = parseLocalizedNumber(String(foldedLine[numberRange])) else { continue }
            let unit = String(foldedLine[unitRange]).lowercased()
            out.append(RowNumberToken(
                value: value,
                unit: unit,
                numberStartOffset: characterOffset(in: foldedLine, index: numberRange.lowerBound),
                fullMatchRange: fullRange
            ))
        }
        return out
    }

    private static func rowKcalTokens(in foldedLine: String) -> [RowNumberToken] {
        guard let regex = try? NSRegularExpression(pattern: kcalCapturePattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(foldedLine.startIndex..<foldedLine.endIndex, in: foldedLine)
        let matches = regex.matches(in: foldedLine, options: [], range: range)
        var out: [RowNumberToken] = []
        for m in matches {
            guard m.numberOfRanges > 1,
                  let numberRange = Range(m.range(at: 1), in: foldedLine),
                  let fullRange = Range(m.range(at: 0), in: foldedLine) else { continue }
            guard let value = parseLocalizedNumber(String(foldedLine[numberRange])) else { continue }
            out.append(RowNumberToken(
                value: value,
                unit: "kcal",
                numberStartOffset: characterOffset(in: foldedLine, index: numberRange.lowerBound),
                fullMatchRange: fullRange
            ))
        }
        return out
    }

    private static func allKeywordMatchesOnLine(in foldedLine: String) -> [KeywordMatch] {
        let keywordLists = [
            caloriesKeywords, proteinKeywords, carbsKeywords, fatKeywords,
            saturatedFatKeywords, sugarsKeywords, fiberKeywords, sodiumKeywords, saltKeywords
        ]
        var matches: [KeywordMatch] = []
        for keywords in keywordLists {
            if let m = findFirstKeywordMatch(in: foldedLine, keywords: keywords, requireWordBoundaryForShort: true) {
                matches.append(m)
            }
        }
        return matches
    }

    private static func shortestDistanceAnchor(
        foldedLine: String,
        keywordMatch: KeywordMatch,
        candidates: [RowNumberToken],
        allowedUnits: Set<String>
    ) -> RowNumberToken? {
        let keywordEnd = keywordEndOffset(match: keywordMatch, in: foldedLine)
        let peerKeywords = allKeywordMatchesOnLine(in: foldedLine).filter { $0.range != keywordMatch.range }
        let filtered = candidates.filter { token in
            guard allowedUnits.contains(token.unit), token.numberStartOffset >= keywordEnd else { return false }
            let myDistance = token.numberStartOffset - keywordEnd
            for peer in peerKeywords {
                let peerEnd = keywordEndOffset(match: peer, in: foldedLine)
                guard token.numberStartOffset >= peerEnd else { continue }
                let peerDistance = token.numberStartOffset - peerEnd
                if peerDistance < myDistance { return false }
            }
            return true
        }
        guard !filtered.isEmpty else { return nil }
        return filtered.min { a, b in
            (a.numberStartOffset - keywordEnd) < (b.numberStartOffset - keywordEnd)
        }
    }

    private static func logDistanceAnchor(
        field: String,
        rawLine: String,
        rowIndex: Int,
        keywordMatch: KeywordMatch,
        candidates: [RowNumberToken],
        selected: RowNumberToken?
    ) {
        let keywordEnd = keywordEndOffset(match: keywordMatch, in: foldDiacritics(rawLine.lowercased()))
        debugBlockHeader(field: field)
        debugPrint("Keyword: '\(keywordMatch.keyword)'")
        debugPrint("Row: \(rowIndex)")
        debugPrint("Line Content: '\(rawLine)'")
        let tokenList = candidates.map { token in
            let dist = token.numberStartOffset - keywordEnd
            return "[\(token.numberStartOffset)] \(token.value)\(token.unit) (dist=\(dist))"
        }.joined(separator: ", ")
        debugPrint("Tokens: \(tokenList.isEmpty ? "[]" : tokenList)")
        if let selected {
            let dist = selected.numberStartOffset - keywordEnd
            debugPrint("Selected Token: '\(selected.value)\(selected.unit)' | Distance: \(dist)")
        } else {
            debugPrint("Selected Token: <none>")
        }
        debugBlockFooter()
    }

    private static func extractCaloriesFromLine(_ foldedLine: String, rawLine: String, rowIndex: Int) -> Double? {
        guard foldedLine.range(of: kjPattern, options: .regularExpression) == nil || foldedLine.contains("kcal") else {
            return nil
        }
        if let keywordMatch = findFirstKeywordMatch(in: foldedLine, keywords: caloriesKeywords, requireWordBoundaryForShort: true) {
            let kcalTokens = rowKcalTokens(in: foldedLine)
            let selected = shortestDistanceAnchor(
                foldedLine: foldedLine,
                keywordMatch: keywordMatch,
                candidates: kcalTokens,
                allowedUnits: ["kcal"]
            )
            logDistanceAnchor(
                field: "Calories",
                rawLine: rawLine,
                rowIndex: rowIndex,
                keywordMatch: keywordMatch,
                candidates: kcalTokens,
                selected: selected
            )
            if let selected, selected.value > 0, selected.value <= 1000 {
                return selected.value
            }
            if let selected, selected.value > 1000 {
                debugPrint("WARNING: Rejected value \(selected.value) for Calories field because it exceeds the 1000 kcal physical limit per 100g sample.")
                debugPrint("Row: \(rowIndex) | Line Content: '\(rawLine)'")
            }
        }
        for m in rowKcalTokens(in: foldedLine) {
            if m.value > 0, m.value <= 1000 { return m.value }
        }
        return nil
    }

    private static func extractMacroGramFromLine(
        _ foldedLine: String,
        rawLine: String,
        rowIndex: Int,
        field: String,
        keywords: [String],
        excludeFatContexts: Bool
    ) -> Double? {
        guard let keywordMatch = findFirstKeywordMatch(in: foldedLine, keywords: keywords, requireWordBoundaryForShort: true) else {
            return nil
        }
        let rowTokens = rowUnitNumberTokens(in: foldedLine)
        let selected = shortestDistanceAnchor(
            foldedLine: foldedLine,
            keywordMatch: keywordMatch,
            candidates: rowTokens,
            allowedUnits: ["g"]
        )
        logDistanceAnchor(
            field: field,
            rawLine: rawLine,
            rowIndex: rowIndex,
            keywordMatch: keywordMatch,
            candidates: rowTokens,
            selected: selected
        )
        guard let selected, selected.unit == "g" else { return nil }
        if excludeFatContexts {
            let trailing = String(foldedLine[keywordMatch.range.upperBound...])
            if trailing.range(of: fatExclusionPattern, options: .regularExpression) != nil {
                return nil
            }
        }
        if isHeaderScopeToken(trailing: foldedLine, matchSpan: selected.fullMatchRange) { return nil }
        var value = selected.value
        if field == "Protein" {
            let ranked = rowUnitNumberTokens(in: foldedLine).filter { token in
                token.unit == "g" && token.numberStartOffset >= keywordEndOffset(match: keywordMatch, in: foldedLine)
            }
            let values = ranked.map(\.value)
            if value == 0, let largest = values.filter({ $0 > 0 }).max() {
                value = largest
            } else if value <= 3, values.count > 1, let larger = values.filter({ $0 > value }).max() {
                value = larger
            }
        } else if field == "Sugars" {
            let keywordEnd = keywordEndOffset(match: keywordMatch, in: foldedLine)
            let grams = rowUnitNumberTokens(in: foldedLine)
                .filter { $0.unit == "g" && $0.numberStartOffset >= keywordEnd }
                .map(\.value)
            if value >= 20, let small = grams.filter({ $0 >= 0 && $0 <= 1 }).min() {
                value = small
            }
        } else if field == "SatFat" {
            let keywordEnd = keywordEndOffset(match: keywordMatch, in: foldedLine)
            let grams = rowUnitNumberTokens(in: foldedLine)
                .filter { $0.unit == "g" && $0.numberStartOffset >= keywordEnd }
                .map(\.value)
            if grams.count > 1, let smaller = grams.filter({ $0 > 0 && $0 < value }).min() {
                value = smaller
            }
        }
        guard value >= 0, value <= 100 else {
            if value > 100 {
                debugPrint("WARNING: Rejected value \(value) for \(field) field because it exceeds the 100g physical limit per 100g sample.")
                debugPrint("Row: \(rowIndex) | Line Content: '\(rawLine)'")
            }
            return nil
        }
        return value
    }

    private static func extractSodiumMgFromLine(_ foldedLine: String, rawLine: String, rowIndex: Int) -> Double? {
        guard let keywordMatch = findFirstKeywordMatch(in: foldedLine, keywords: sodiumKeywords, requireWordBoundaryForShort: true) else {
            return nil
        }
        if foldedLine.range(of: barcodeDigitsPattern, options: .regularExpression) != nil { return nil }
        if foldedLine.range(of: percentOrRdaPattern, options: .regularExpression) != nil { return nil }
        let rowTokens = rowUnitNumberTokens(in: foldedLine)
        let selected = shortestDistanceAnchor(
            foldedLine: foldedLine,
            keywordMatch: keywordMatch,
            candidates: rowTokens,
            allowedUnits: ["g", "mg"]
        )
        logDistanceAnchor(
            field: "Sodium",
            rawLine: rawLine,
            rowIndex: rowIndex,
            keywordMatch: keywordMatch,
            candidates: rowTokens,
            selected: selected
        )
        guard let selected else { return nil }
        let mg = selected.unit == "g" ? selected.value * 1000.0 : selected.value
        guard mg >= 0, mg <= 10_000 else {
            debugPrint("WARNING: Rejected value \(mg) for Sodium field because it exceeds the 10000mg physical limit per 100g sample.")
            debugPrint("Row: \(rowIndex) | Line Content: '\(rawLine)' | InputValue: \(selected.value)\(selected.unit)")
            return nil
        }
        return mg
    }

    private static func extractSaltAsSodiumMgFromLine(_ foldedLine: String, rawLine: String, rowIndex: Int) -> Double? {
        guard let keywordMatch = findFirstKeywordMatch(in: foldedLine, keywords: saltKeywords, requireWordBoundaryForShort: true) else {
            return nil
        }
        if foldedLine.range(of: saltKeywordExclusionPattern, options: .regularExpression) != nil { return nil }
        if foldedLine.range(of: barcodeDigitsPattern, options: .regularExpression) != nil { return nil }
        if foldedLine.range(of: percentOrRdaPattern, options: .regularExpression) != nil { return nil }
        let rowTokens = rowUnitNumberTokens(in: foldedLine)
        let selected = shortestDistanceAnchor(
            foldedLine: foldedLine,
            keywordMatch: keywordMatch,
            candidates: rowTokens,
            allowedUnits: ["g", "mg"]
        )
        logDistanceAnchor(
            field: "SaltToSodium",
            rawLine: rawLine,
            rowIndex: rowIndex,
            keywordMatch: keywordMatch,
            candidates: rowTokens,
            selected: selected
        )
        guard let selected else { return nil }
        debugPrint("Salt Input: value=\(selected.value) unit=\(selected.unit)")
        let sodiumMg: Double
        if selected.unit == "mg" {
            sodiumMg = selected.value
            debugPrint("Converted Sodium: value(mg)=\(sodiumMg)")
        } else {
            if selected.value > 10 {
                debugPrint("WARNING: Rejected value \(selected.value)g for Salt field because it exceeds the 10g salt physical limit per 100g sample.")
                debugPrint("Row: \(rowIndex) | Line Content: '\(rawLine)'")
                return nil
            }
            sodiumMg = ((selected.value / 2.5) * 1000.0).rounded()
            debugPrint("Converted Sodium: (value/2.5)*1000 rounded = \(sodiumMg)mg")
        }
        guard sodiumMg >= 0, sodiumMg <= 10_000 else {
            debugPrint("WARNING: Rejected value \(sodiumMg) for Sodium field because it exceeds the 10000mg physical limit per 100g sample.")
            debugPrint("Row: \(rowIndex) | Line Content: '\(rawLine)' | SaltInput: \(selected.value)\(selected.unit)")
            return nil
        }
        return sodiumMg
    }

    private static func isIsolatedSingleValueLine(_ rawLine: String) -> Bool {
        let folded = foldDiacritics(rawLine.lowercased())
        guard let regex = try? NSRegularExpression(pattern: isolatedValueLinePattern, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(folded.startIndex..<folded.endIndex, in: folded)
        return regex.firstMatch(in: folded, options: [], range: range) != nil
    }

    private static func firstUnitValueFromIsolatedLine(_ foldedLine: String) -> (value: Double, unit: String)? {
        guard let regex = try? NSRegularExpression(pattern: isolatedValueLinePattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(foldedLine.startIndex..<foldedLine.endIndex, in: foldedLine)
        guard let m = regex.firstMatch(in: foldedLine, options: [], range: range),
              m.numberOfRanges > 2,
              let numberRange = Range(m.range(at: 1), in: foldedLine),
              let unitRange = Range(m.range(at: 2), in: foldedLine) else { return nil }
        guard let v = parseLocalizedNumber(String(foldedLine[numberRange])) else { return nil }
        let unit = String(foldedLine[unitRange]).lowercased()
        return (v, unit)
    }

    private static func applyVerticalFallbackIfNeeded(
        prepared: [String],
        rowIndex: Int,
        foldedLine: String,
        rawLine: String,
        result: inout NutritionLabelParseResult
    ) {
        guard rowIndex + 1 < prepared.count else { return }
        let nextRaw = prepared[rowIndex + 1]
        guard isIsolatedSingleValueLine(nextRaw) else { return }
        let nextFolded = foldDiacritics(nextRaw.lowercased())
        guard let fallback = firstUnitValueFromIsolatedLine(nextFolded) else { return }

        if result.protein == 0,
           let proteinMatch = findFirstKeywordMatch(in: foldedLine, keywords: proteinKeywords, requireWordBoundaryForShort: true),
           shortestDistanceAnchor(
               foldedLine: foldedLine,
               keywordMatch: proteinMatch,
               candidates: rowUnitNumberTokens(in: foldedLine),
               allowedUnits: ["g"]
           ) == nil,
           fallback.unit == "g",
           fallback.value >= 0, fallback.value <= 100 {
            debugPrint("VerticalFallback: Protein Row \(rowIndex) -> Row \(rowIndex + 1) '\(nextRaw)' -> \(fallback.value)g")
            result.protein = fallback.value
        }

        if result.sodiumMg == 0,
           let saltMatch = findFirstKeywordMatch(in: foldedLine, keywords: saltKeywords, requireWordBoundaryForShort: true),
           shortestDistanceAnchor(
               foldedLine: foldedLine,
               keywordMatch: saltMatch,
               candidates: rowUnitNumberTokens(in: foldedLine),
               allowedUnits: ["g", "mg"]
           ) == nil {
            let saltG = fallback.unit == "mg" ? (fallback.value / 1000.0) : fallback.value
            if saltG >= 0, saltG <= 10 {
                let sodiumMg = ((saltG / 2.5) * 1000.0).rounded()
                debugPrint("VerticalFallback: Salt Row \(rowIndex) -> Row \(rowIndex + 1) '\(nextRaw)' -> \(sodiumMg)mg")
                result.sodiumMg = sodiumMg
            }
        }
    }

    private static func isHeaderScopeToken(trailing: String, matchSpan: Range<String.Index>) -> Bool {
        let start = trailing.index(matchSpan.lowerBound, offsetBy: -18, limitedBy: trailing.startIndex) ?? trailing.startIndex
        let end = trailing.index(matchSpan.upperBound, offsetBy: 18, limitedBy: trailing.endIndex) ?? trailing.endIndex
        let window = String(trailing[start..<end])
        if window.range(of: headerScopeBlacklistPattern, options: .regularExpression) != nil {
            return true
        }
        if window.range(of: scopePreamblePattern, options: .regularExpression) != nil,
           window.range(of: servingUnitPattern, options: .regularExpression) != nil,
           window.contains("100") {
            return true
        }
        return false
    }

    private static func findFirstKeywordMatch(in foldedLine: String, keywords: [String], requireWordBoundaryForShort: Bool) -> KeywordMatch? {
        let sorted = keywords.sorted { $0.count > $1.count }
        var earliest: KeywordMatch?
        for keyword in sorted {
            let k = foldDiacritics(keyword.lowercased())
            guard let range = foldedLine.range(of: k) else { continue }
            if requireWordBoundaryForShort, shouldRequireWordBoundary(keyword) {
                if !isWordBoundaryMatch(in: foldedLine, range: range) { continue }
            }
            if let e = earliest {
                if range.lowerBound < e.range.lowerBound {
                    earliest = KeywordMatch(keyword: keyword, range: range)
                }
            } else {
                earliest = KeywordMatch(keyword: keyword, range: range)
            }
        }
        return earliest
    }

    private static func shouldRequireWordBoundary(_ keyword: String) -> Bool {
        let lower = keyword.lowercased()
        return lower == "fat" || lower == "sal" || lower == "sel" || lower == "salz" || lower == "sale"
    }

    private static func isWordBoundaryMatch(in text: String, range: Range<String.Index>) -> Bool {
        if range.lowerBound > text.startIndex {
            let before = text[text.index(before: range.lowerBound)]
            if before.isLetter || before.isNumber { return false }
        }
        if range.upperBound < text.endIndex {
            let after = text[range.upperBound]
            if after.isLetter || after.isNumber { return false }
        }
        return true
    }
}
