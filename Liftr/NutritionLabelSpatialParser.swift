import CoreGraphics
import Foundation

enum NutritionLabelSpatialParser {
    private static let rowClusterTolerance: CGFloat = 0.03
    private static let yRayToleranceFraction: CGFloat = 0.01
    private static let yRayTolerancePixels: CGFloat = 7.0
    private static let ySaltRayToleranceFraction: CGFloat = 0.025
    private static let ySaltRayTolerancePixels: CGFloat = 7.0
    private static let referenceCanvasHeight: CGFloat = 2048.0
    private static var yRayTolerance: CGFloat {
        min(yRayToleranceFraction, yRayTolerancePixels / referenceCanvasHeight)
    }
    private static var ySaltRayTolerance: CGFloat {
        min(ySaltRayToleranceFraction, ySaltRayTolerancePixels / referenceCanvasHeight)
    }
    private static let kjProximityX: CGFloat = 0.14
    private static let europeanDecimalPattern = #"(\d),(\d)"#
    private static let numericPrefixPattern = #"^[<~≥≤\s]+"#
    private static let kcalCapturePattern = #"(?:[<~≥≤]\s*)?(\d{1,4}(?:[.,]\d{1,2})?)\s*kcal\b"#
    private static let kjMarkerPattern = #"(?i)\b(kj|kilojulio|kilojoule)\b"#
    private static let fatExclusionPattern = #"(?i)\b(saturad|saturated|trans|saturats|saturadas)\b"#
    private static let barcodeDigitsPattern = #"\d{7,}"#
    private static let percentOrRdaPattern = #"(?i)(%|\bvrn\b|\bri\b|\bnrv\b)"#
    private static let saltKeywordExclusionPattern = #"(?i)\b(calcio|calcium|potasio|potassium)\b"#
    private static let unitNumberPattern = #"(?:[<~≥≤]\s*)?(\d{1,3}(?:[.,]\d{1,2})?)\s*(mg|g)\b"#
    private static let bareNumberPattern = #"^(\d{1,4}(?:[.,]\d{1,2})?)$"#
    private static let leaderNoisePattern = #"[·•\.\-_—–]+$"#
    private static let leaderRunPattern = #"[·•\.\-_—–]{2,}"#
    private static let headerScopeBlacklistPattern = #"(?i)\b(peso\s*neto|net\s*weight|per\s*serving|por\s*porcion|por\s*porción|per\s*100\s*(g|ml)|por\s*100\s*(g|ml)|100\s*(g|ml)|ml|peso|neto)\b"#
    private static let per100BlueprintPattern = #"(?i)(?:\b(?:por|per)\s*100\b|\b100\s*(?:g|ml)\b)"#
    private static let netWeightBlueprintPattern = #"(?i)\b(?:peso\s*neto|net\s*weight)\b"#
    private static let kilojouleAdjacentPattern = #"(?i)\b\d{1,4}(?:[.,]\d{1,2})?\s*(?:kj|kilojulio|kilojoule)\b"#
    private static let capacityMarkerPattern = #"(?i)\b(?:neto|net|liquido|líquido|liquid)\b"#
    private static let capacityUnitPattern = #"(?i)\b(?:g|ml)\b"#
    private static let subRowLeadPattern = #"(?i)\b(?:dont|de\s+las\s+cuales|dos\s+quais|de\s+quais|di\s+cui|davon|of\s+which|including)\b"#
    private static let subRowIndicatorPattern = #"(?i)(?:^\s*-\s*|(?:^|\s)(?:de\s+las\s+cuales|dos\s+quais|de\s+quais|dont|davon|di\s+cui|of\s+which|including)\b)"#
    private static let bareCapacity100Pattern = #"(?i)\b100(?:[.,]0)?\s*(?:g|ml)\b"#

    private struct SpatialParseContext {
        var imageDigitTokenCount: Int = 0
    }

    private static var parseContext = SpatialParseContext()

    private static func numberLookbackBeforeUnit(in text: String, unit: String, lookback: Int = 12) -> Double? {
        let folded = foldDiacritics(normalizeEuropeanDecimals(text).lowercased())
        guard let unitRange = folded.range(of: unit.lowercased()) else { return nil }
        let start = folded.index(unitRange.lowerBound, offsetBy: -lookback, limitedBy: folded.startIndex) ?? folded.startIndex
        let window = String(folded[start..<unitRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !window.isEmpty else { return nil }
        guard let regex = try? NSRegularExpression(pattern: #"(?:[<~≥≤]\s*)?(\d{1,4}(?:[.,]\d{1,2})?)\s*$"#, options: []) else {
            return nil
        }
        let range = NSRange(window.startIndex..<window.endIndex, in: window)
        guard let match = regex.firstMatch(in: window, options: [], range: range),
              match.numberOfRanges > 1,
              let numberRange = Range(match.range(at: 1), in: window) else {
            return nil
        }
        return parseLocalizedNumber(String(window[numberRange]))
    }

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

    private struct KeywordRegion {
        let keyword: String
        let rawContainerText: String
        let foldedContainerText: String
        let keywordEndOffset: Int
        let minX: CGFloat
        let maxX: CGFloat
        let centerY: CGFloat
        let rightX: CGFloat
    }

    private struct SpatialNumericToken {
        let value: Double
        let unit: String
        let minX: CGFloat
        let maxX: CGFloat
        let centerY: CGFloat
        let sourceText: String
    }

    static func parse(recognition: NutritionLabelRecognitionResult) -> NutritionLabelParseResult {
        var result = NutritionLabelParseResult()
        let elements = recognition.elements.compactMap { sanitizeSpatialElement($0) }
        guard elements.count >= 5 else { return result }

        defer { parseContext = SpatialParseContext() }
        parseContext = SpatialParseContext(imageDigitTokenCount: countImageDigitTokens(from: elements))

        let numerics = collectNumericTokens(from: elements)
        let yTol = yRayTolerance

        if result.calories == 0, let calories = raycastCalories(elements: elements, numerics: numerics, yTolerance: yTol) {
            result.calories = calories
        }
        if result.protein == 0, let v = raycastGramMacro(
            field: "Protein", keywords: proteinKeywords, elements: elements,
            yTolerance: yTol, excludeSaturatedRow: false
        ) {
            result.protein = v
        }
        if result.carbs == 0, let v = raycastGramMacro(
            field: "Carbs", keywords: carbsKeywords, elements: elements,
            yTolerance: yTol, excludeSaturatedRow: false, rejectSugarOnlyRows: true, isParentField: true
        ) {
            result.carbs = v
        }
        if result.fat == 0, let v = raycastGramMacro(
            field: "Fat", keywords: fatKeywords, elements: elements,
            yTolerance: yTol, excludeSaturatedRow: true, isParentField: true
        ) {
            result.fat = v
        }
        if result.saturatedFat == 0, let v = raycastGramMacro(
            field: "SatFat", keywords: saturatedFatKeywords, elements: elements,
            yTolerance: yTol, excludeSaturatedRow: false, rejectSugarOnlyRows: false, isSubField: true,
            parentMacroGram: result.fat
        ) {
            result.saturatedFat = v
        }
        if result.sugars == 0, let v = raycastGramMacro(
            field: "Sugars", keywords: sugarsKeywords, elements: elements,
            yTolerance: yTol, excludeSaturatedRow: true, rejectSugarOnlyRows: false, isSubField: true
        ) {
            result.sugars = v
        }
        if result.fiber == 0, let v = raycastGramMacro(
            field: "Fiber", keywords: fiberKeywords, elements: elements,
            yTolerance: yTol, excludeSaturatedRow: false
        ) {
            result.fiber = v
        }
        let saltTol = ySaltRayTolerance
        if result.sodiumMg == 0, let v = raycastSodiumMg(
            field: "Sodium", keywords: sodiumKeywords, elements: elements, numerics: numerics, yTolerance: saltTol
        ) {
            result.sodiumMg = v
        }
        if result.sodiumMg == 0, let v = raycastSaltAsSodiumMg(elements: elements, numerics: numerics, yTolerance: saltTol) {
            result.sodiumMg = v
        }

        return result
    }

    private static func debugPrint(_ message: String) {
#if DEBUG
        print(message)
#endif
    }

    private static func debugBlockHeader(field: String) {
        debugPrint("------ [OCR SPATIAL RAYCAST] \(field) ------")
    }

    private static func debugBlockFooter() {
        debugPrint("------ [OCR SPATIAL RAYCAST END] ------")
    }

    private static func sanitizeSpatialElement(_ element: NutritionLabelSpatialElement) -> NutritionLabelSpatialElement? {
        let text = sanitizeTokenText(element.text)
        guard !text.isEmpty else { return nil }
        return NutritionLabelSpatialElement(
            text: text,
            minX: element.minX,
            minY: element.minY,
            maxX: element.maxX,
            maxY: element.maxY
        )
    }

    private static func sanitizeTokenText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let collapsed = trimmed.replacingOccurrences(of: leaderRunPattern, with: " ", options: .regularExpression)
        let trailing = collapsed.replacingOccurrences(of: leaderNoisePattern, with: "", options: .regularExpression)
        return trailing.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func normalizeEuropeanDecimals(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: europeanDecimalPattern, options: []) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "$1.$2")
    }

    private static func foldDiacritics(_ text: String) -> String {
        text
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: "ß", with: "ss")
            .replacingOccurrences(of: "ẞ", with: "ss")
    }

    private static func parseLocalizedNumber(_ raw: String) -> Double? {
        var normalized = normalizeEuropeanDecimals(raw)
            .trimmingCharacters(in: .whitespaces)
        if let regex = try? NSRegularExpression(pattern: numericPrefixPattern, options: []) {
            let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
            normalized = regex.stringByReplacingMatches(in: normalized, options: [], range: range, withTemplate: "")
        }
        normalized = normalized
            .replacingOccurrences(of: "<", with: "")
            .replacingOccurrences(of: "~", with: "")
            .replacingOccurrences(of: "≤", with: "")
            .replacingOccurrences(of: "≥", with: "")
            .trimmingCharacters(in: .whitespaces)
        if let digitRange = normalized.range(of: #"\d"#, options: .regularExpression) {
            normalized = String(normalized[digitRange.lowerBound...])
        }
        normalized = normalized.replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    private static func containerHasDigit(_ text: String) -> Bool {
        text.contains(where: \.isNumber)
    }

    private static func groupElementsIntoRows(
        _ elements: [NutritionLabelSpatialElement],
        yTolerance: CGFloat
    ) -> [[NutritionLabelSpatialElement]] {
        let sorted = elements.sorted { a, b in
            if abs(a.centerY - b.centerY) > yTolerance { return a.centerY < b.centerY }
            return a.centerX < b.centerX
        }
        var rows: [[NutritionLabelSpatialElement]] = []
        var current: [NutritionLabelSpatialElement] = []
        var currentY: CGFloat = 0
        for element in sorted {
            if current.isEmpty {
                current = [element]
                currentY = element.centerY
            } else if abs(element.centerY - currentY) <= yTolerance {
                current.append(element)
                currentY = (currentY * CGFloat(current.count - 1) + element.centerY) / CGFloat(current.count)
            } else {
                rows.append(current.sorted { $0.centerX < $1.centerX })
                current = [element]
                currentY = element.centerY
            }
        }
        if !current.isEmpty {
            rows.append(current.sorted { $0.centerX < $1.centerX })
        }
        return rows
    }

    private static func rowJoinedText(_ row: [NutritionLabelSpatialElement]) -> String {
        row.map(\.text).joined(separator: " ")
    }

    private static func findKeywordRegions(
        elements: [NutritionLabelSpatialElement],
        keywords: [String],
        requireWordBoundaryForShort: Bool
    ) -> [KeywordRegion] {
        let sortedKeywords = keywords.sorted { $0.count > $1.count }
        let rows = groupElementsIntoRows(elements, yTolerance: rowClusterTolerance)
        var regions: [KeywordRegion] = []

        for row in rows {
            let ordered = row.sorted { $0.centerX < $1.centerX }
            var joined = ""
            var spans: [(elementIndex: Int, start: Int, end: Int)] = []
            for (index, element) in ordered.enumerated() {
                let start = joined.isEmpty ? 0 : joined.count + 1
                if !joined.isEmpty { joined += " " }
                joined += element.text
                spans.append((index, start, joined.count))
            }
            let foldedJoined = foldDiacritics(normalizeEuropeanDecimals(joined).lowercased())

            for keyword in sortedKeywords {
                let k = foldDiacritics(keyword.lowercased())
                var searchStart = foldedJoined.startIndex
                while searchStart < foldedJoined.endIndex {
                    guard let range = foldedJoined[searchStart...].range(of: k) else { break }
                    if requireWordBoundaryForShort, shouldRequireWordBoundary(keyword) {
                        if !isWordBoundaryMatch(in: foldedJoined, range: range) {
                            searchStart = range.upperBound
                            continue
                        }
                    }
                    let startOffset = foldedJoined.distance(from: foldedJoined.startIndex, to: range.lowerBound)
                    let endOffset = foldedJoined.distance(from: foldedJoined.startIndex, to: range.upperBound)
                    let matched = spans.compactMap { span -> NutritionLabelSpatialElement? in
                        guard span.end > startOffset, span.start < endOffset else { return nil }
                        return ordered[span.elementIndex]
                    }
                    let boxElements = matched.isEmpty ? ordered : matched
                    let minX = boxElements.map(\.minX).min() ?? ordered.first!.minX
                    let maxX = boxElements.map(\.maxX).max() ?? ordered.last!.maxX
                    let minY = boxElements.map(\.minY).min() ?? ordered.map(\.minY).min()!
                    let maxY = boxElements.map(\.maxY).max() ?? ordered.map(\.maxY).max()!
                    let centerY = (minY + maxY) / 2
                    regions.append(KeywordRegion(
                        keyword: keyword,
                        rawContainerText: joined,
                        foldedContainerText: foldedJoined,
                        keywordEndOffset: endOffset,
                        minX: minX,
                        maxX: maxX,
                        centerY: centerY,
                        rightX: maxX
                    ))
                    searchStart = range.upperBound
                }
            }
        }
        return regions
    }

    private static let sugarsOnlyRowPattern = #"(?i)\b(azucar|azúcar|azucares|azúcares|sucres|sugar|sugars|zucker)\b"#

    private static func selectKeywordRegion(
        from regions: [KeywordRegion],
        excludeSaturatedRow: Bool,
        rejectSugarOnlyRows: Bool = false
    ) -> KeywordRegion? {
        var filtered = regions
        if excludeSaturatedRow {
            filtered = filtered.filter { region in
                region.foldedContainerText.range(of: fatExclusionPattern, options: .regularExpression) == nil
            }
        }
        if rejectSugarOnlyRows {
            filtered = filtered.filter { region in
                let folded = region.foldedContainerText
                let hasSugar = folded.range(of: sugarsOnlyRowPattern, options: .regularExpression) != nil
                let hasCarb = carbsKeywords.contains { folded.contains(foldDiacritics($0.lowercased())) }
                return hasCarb || !hasSugar
            }
        }
        guard !filtered.isEmpty else { return nil }
        return filtered.min { $0.centerY < $1.centerY }
    }

    private static func candidateKeywordRegions(
        from regions: [KeywordRegion],
        excludeSaturatedRow: Bool,
        rejectSugarOnlyRows: Bool = false
    ) -> [KeywordRegion] {
        var filtered = regions
        if excludeSaturatedRow {
            filtered = filtered.filter { region in
                region.foldedContainerText.range(of: fatExclusionPattern, options: .regularExpression) == nil
            }
        }
        if rejectSugarOnlyRows {
            filtered = filtered.filter { region in
                let folded = region.foldedContainerText
                let hasSugar = folded.range(of: sugarsOnlyRowPattern, options: .regularExpression) != nil
                let hasCarb = carbsKeywords.contains { folded.contains(foldDiacritics($0.lowercased())) }
                return hasCarb || !hasSugar
            }
        }
        return filtered.sorted { $0.centerY < $1.centerY }
    }

    private static func collectNumericTokens(from elements: [NutritionLabelSpatialElement]) -> [SpatialNumericToken] {
        var tokens: [SpatialNumericToken] = []
        var seen = Set<String>()

        func appendToken(value: Double, unit: String, box: NutritionLabelSpatialElement, source: String) {
            let key = String(format: "%.4f|%@|%.4f|%.4f", value, unit, box.centerX, box.centerY)
            guard seen.insert(key).inserted else { return }
            tokens.append(SpatialNumericToken(
                value: value,
                unit: unit,
                minX: box.minX,
                maxX: box.maxX,
                centerY: box.centerY,
                sourceText: source
            ))
        }

        for element in elements {
            let folded = foldDiacritics(normalizeEuropeanDecimals(element.text).lowercased())
            if let unitMatch = firstRegexMatch(pattern: unitNumberPattern, in: folded) {
                if let value = parseLocalizedNumber(unitMatch.number) {
                    appendToken(value: value, unit: unitMatch.unit, box: element, source: element.text)
                }
            }
            if let kcalMatch = firstRegexMatch(pattern: kcalCapturePattern, in: folded) {
                if let value = parseLocalizedNumber(kcalMatch.number) {
                    appendToken(value: value, unit: "kcal", box: element, source: element.text)
                }
            }
        }

        let rows = groupElementsIntoRows(elements, yTolerance: rowClusterTolerance)
        for row in rows {
            let ordered = row.sorted { $0.centerX < $1.centerX }
            for index in 0..<ordered.count {
                let left = ordered[index]
                if index + 1 < ordered.count {
                    let right = ordered[index + 1]
                    let combined = "\(left.text) \(right.text)"
                    let folded = foldDiacritics(normalizeEuropeanDecimals(combined).lowercased())
                    if let unitMatch = firstRegexMatch(pattern: unitNumberPattern, in: folded) {
                        if let value = parseLocalizedNumber(unitMatch.number) {
                            let box = unionBox(left, right)
                            appendToken(value: value, unit: unitMatch.unit, box: box, source: combined)
                        }
                    }
                    if let bare = firstRegexMatch(pattern: bareNumberPattern, in: foldDiacritics(left.text.lowercased())),
                       foldDiacritics(right.text.lowercased()) == "g" || foldDiacritics(right.text.lowercased()) == "mg",
                       let value = parseLocalizedNumber(bare.number) {
                        let box = unionBox(left, right)
                        appendToken(value: value, unit: right.text.lowercased(), box: box, source: combined)
                    }
                    if let bare = firstRegexMatch(pattern: bareNumberPattern, in: foldDiacritics(left.text.lowercased())),
                       right.text.lowercased().contains("kcal"),
                       let value = parseLocalizedNumber(bare.number) {
                        let box = unionBox(left, right)
                        appendToken(value: value, unit: "kcal", box: box, source: combined)
                    }
                }
            }
        }
        return tokens
    }

    private struct RegexUnitMatch {
        let number: String
        let unit: String
    }

    private static func firstRegexMatch(pattern: String, in text: String) -> RegexUnitMatch? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        if match.numberOfRanges > 2,
           let numberRange = Range(match.range(at: 1), in: text),
           let unitRange = Range(match.range(at: 2), in: text) {
            return RegexUnitMatch(number: String(text[numberRange]), unit: String(text[unitRange]).lowercased())
        }
        if match.numberOfRanges > 1, let numberRange = Range(match.range(at: 1), in: text) {
            return RegexUnitMatch(number: String(text[numberRange]), unit: "")
        }
        return nil
    }

    private struct RegexUnitMatchWithOffset {
        let number: String
        let unit: String
        let matchStartOffset: Int
    }

    private static func allRegexMatches(pattern: String, in text: String) -> [RegexUnitMatchWithOffset] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: range)
        var out: [RegexUnitMatchWithOffset] = []
        for match in matches {
            guard match.numberOfRanges > 1,
                  let numberRange = Range(match.range(at: 1), in: text) else { continue }
            let unit: String
            if match.numberOfRanges > 2, let unitRange = Range(match.range(at: 2), in: text) {
                unit = String(text[unitRange]).lowercased()
            } else {
                unit = ""
            }
            let start = text.distance(from: text.startIndex, to: numberRange.lowerBound)
            out.append(RegexUnitMatchWithOffset(
                number: String(text[numberRange]),
                unit: unit,
                matchStartOffset: start
            ))
        }
        return out
    }

    private static func logSelfContained(field: String, region: KeywordRegion, value: Double, unit: String) {
        debugBlockHeader(field: field)
        debugPrint("Mode: self-contained")
        debugPrint("Keyword: '\(region.keyword)' | Container: '\(region.rawContainerText)'")
        debugPrint("Extracted: \(value)\(unit)")
        debugBlockFooter()
    }

    private static func countImageDigitTokens(from elements: [NutritionLabelSpatialElement]) -> Int {
        var count = 0
        for element in elements {
            let folded = foldDiacritics(normalizeEuropeanDecimals(element.text).lowercased())
            count += allRegexMatches(pattern: unitNumberPattern, in: folded).count
            count += allRegexMatches(pattern: kcalCapturePattern, in: folded).count
            if firstRegexMatch(pattern: bareNumberPattern, in: folded) != nil {
                count += 1
            }
        }
        return count
    }

    private static func isCapacityHundredSuppressed(containerText: String, match: RegexUnitMatchWithOffset) -> Bool {
        guard let value = parseLocalizedNumber(match.number), abs(value - 100) < 0.01 else { return false }
        let folded = foldDiacritics(normalizeEuropeanDecimals(containerText).lowercased())
        if folded.range(of: bareCapacity100Pattern, options: .regularExpression) != nil {
            return true
        }
        if folded.contains("100 g") || folded.contains("100g") || folded.contains("100 ml") || folded.contains("100ml") {
            return true
        }
        if parseContext.imageDigitTokenCount <= 1 { return false }
        let hasCapacityPhrase = folded.range(of: capacityMarkerPattern, options: .regularExpression) != nil
        let hasUnit = folded.range(of: capacityUnitPattern, options: .regularExpression) != nil
        if hasCapacityPhrase && hasUnit { return true }
        if hasUnit && (match.unit == "g" || match.unit == "ml") { return true }
        return false
    }

    private static func isSubPropertyRow(_ region: KeywordRegion) -> Bool {
        let trimmed = region.rawContainerText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("-") { return true }
        let folded = region.foldedContainerText
        if folded.range(of: subRowIndicatorPattern, options: .regularExpression) != nil { return true }
        if folded.range(of: subRowLeadPattern, options: .regularExpression) != nil { return true }
        return false
    }

    private static func validateSubFieldKeywordPrefix(region: KeywordRegion, keywords: [String]) -> Bool {
        let folded = region.foldedContainerText
        let keywordFolded = foldDiacritics(region.keyword.lowercased())
        guard folded.contains(keywordFolded) else { return false }
        return keywords.contains { foldDiacritics($0.lowercased()) == keywordFolded }
            || keywords.contains { folded.contains(foldDiacritics($0.lowercased())) }
    }

    private static func subFieldRaySkipCount(
        region: KeywordRegion,
        numerics: [SpatialNumericToken],
        yTolerance: CGFloat
    ) -> Int {
        if isSubPropertyRow(region) { return 1 }
        let band = numerics.filter { token in
            token.unit == "g" &&
            abs(token.centerY - region.centerY) <= yTolerance &&
            token.minX >= region.rightX - 0.02 &&
            !isBlueprintSpatialToken(token)
        }.sorted { $0.minX < $1.minX }
        return band.count > 1 ? 1 : 0
    }

    private static func saltFallbackFromBottomCorpus(
        elements: [NutritionLabelSpatialElement]
    ) -> Double? {
        let rows = groupElementsIntoRows(elements, yTolerance: rowClusterTolerance)
        guard !rows.isEmpty else { return nil }
        let bottomRows = rows.suffix(2)
        for row in bottomRows.reversed() {
            let joined = row.map(\.text).joined(separator: " ")
            let folded = foldDiacritics(normalizeEuropeanDecimals(joined).lowercased())
            if folded.range(of: saltKeywordExclusionPattern, options: .regularExpression) != nil { continue }
            if folded.range(of: barcodeDigitsPattern, options: .regularExpression) != nil { continue }
            let hasSaltKeyword = saltKeywords.contains { folded.contains(foldDiacritics($0.lowercased())) }
            let matches = allRegexMatches(pattern: unitNumberPattern, in: folded).filter { match in
                !isBlueprintBaselineMatch(containerText: folded, match: match)
            }
            for match in matches {
                guard let value = parseLocalizedNumber(match.number) else { continue }
                if match.unit == "mg" {
                    guard value >= 0, value <= 10_000 else { continue }
                    if !hasSaltKeyword, value > 500 { continue }
                    return value
                }
                if match.unit == "g" {
                    guard value >= 0, value <= 10 else { continue }
                    if !hasSaltKeyword, value > 0.5 { continue }
                    return ((value / 2.5) * 1000.0).rounded()
                }
            }
        }
        return nil
    }

    private static func isBlueprintBaselineMatch(containerText: String, match: RegexUnitMatchWithOffset) -> Bool {
        if isCapacityHundredSuppressed(containerText: containerText, match: match) { return true }
        let folded = foldDiacritics(normalizeEuropeanDecimals(containerText).lowercased())
        let start = max(0, match.matchStartOffset - 20)
        let end = min(folded.count, match.matchStartOffset + match.number.count + 20)
        let startIndex = folded.index(folded.startIndex, offsetBy: start)
        let endIndex = folded.index(folded.startIndex, offsetBy: end)
        let window = String(folded[startIndex..<endIndex])
        if window.range(of: per100BlueprintPattern, options: .regularExpression) != nil {
            if let value = parseLocalizedNumber(match.number), abs(value - 100) < 0.01 {
                return true
            }
        }
        if window.range(of: netWeightBlueprintPattern, options: .regularExpression) != nil {
            if let value = parseLocalizedNumber(match.number), abs(value - 100) < 0.01, match.unit == "g" {
                return true
            }
        }
        if match.unit == "g" || match.unit == "ml" {
            if let value = parseLocalizedNumber(match.number), abs(value - 100) < 0.01 {
                if window.contains("por 100") || window.contains("per 100") || window.contains("100g") || window.contains("100 g") || window.contains("100ml") || window.contains("100 ml") {
                    return true
                }
            }
        }
        return false
    }

    private static func isKilojouleAdjacentInContainer(containerText: String, match: RegexUnitMatchWithOffset) -> Bool {
        let folded = foldDiacritics(normalizeEuropeanDecimals(containerText).lowercased())
        if folded.range(of: "kcal", options: .caseInsensitive) != nil,
           match.matchStartOffset < folded.count {
            let matchStart = folded.index(folded.startIndex, offsetBy: min(match.matchStartOffset, folded.count))
            let tail = String(folded[matchStart...])
            if tail.range(of: "kcal", options: .caseInsensitive) != nil {
                return false
            }
        }
        let start = max(0, match.matchStartOffset - 8)
        let end = min(folded.count, match.matchStartOffset + match.number.count + 12)
        let startIndex = folded.index(folded.startIndex, offsetBy: start)
        let endIndex = folded.index(folded.startIndex, offsetBy: end)
        let window = String(folded[startIndex..<endIndex])
        return window.range(of: kilojouleAdjacentPattern, options: .regularExpression) != nil
            || window.range(of: kjMarkerPattern, options: .regularExpression) != nil
    }

    private static func allKeywordEndOffsetsInContainer(_ foldedContainer: String) -> [Int] {
        let keywordLists = [
            caloriesKeywords, proteinKeywords, carbsKeywords, fatKeywords,
            saturatedFatKeywords, sugarsKeywords, fiberKeywords, sodiumKeywords, saltKeywords
        ]
        var ends: [Int] = []
        for keywords in keywordLists {
            let sorted = keywords.sorted { $0.count > $1.count }
            for keyword in sorted {
                let k = foldDiacritics(keyword.lowercased())
                var searchStart = foldedContainer.startIndex
                while searchStart < foldedContainer.endIndex {
                    guard let range = foldedContainer[searchStart...].range(of: k) else { break }
                    if shouldRequireWordBoundary(keyword), !isWordBoundaryMatch(in: foldedContainer, range: range) {
                        searchStart = range.upperBound
                        continue
                    }
                    let endOffset = foldedContainer.distance(from: foldedContainer.startIndex, to: range.upperBound)
                    ends.append(endOffset)
                    searchStart = range.upperBound
                }
            }
        }
        return ends
    }

    private static func filteredUnitMatches(
        _ matches: [RegexUnitMatchWithOffset],
        allowedUnits: Set<String>,
        containerText: String,
        rejectKilojoules: Bool
    ) -> [RegexUnitMatchWithOffset] {
        matches.filter { match in
            if !allowedUnits.isEmpty {
                let unitAllowed = allowedUnits.contains(match.unit) || (match.unit.isEmpty && allowedUnits.contains("kcal"))
                if !unitAllowed { return false }
            }
            if isBlueprintBaselineMatch(containerText: containerText, match: match) { return false }
            if rejectKilojoules && isKilojouleAdjacentInContainer(containerText: containerText, match: match) { return false }
            return true
        }
    }

    private static func pickMatchAfterKeyword(
        _ matches: [RegexUnitMatchWithOffset],
        keywordEndOffset: Int,
        allowedUnits: Set<String>,
        containerText: String,
        rejectKilojoules: Bool = false,
        skipCount: Int = 0
    ) -> RegexUnitMatchWithOffset? {
        let filtered = filteredUnitMatches(
            matches,
            allowedUnits: allowedUnits,
            containerText: containerText,
            rejectKilojoules: rejectKilojoules
        )
        guard !filtered.isEmpty else { return nil }
        let peerEnds = allKeywordEndOffsetsInContainer(containerText)
        let afterKeyword = filtered
            .filter { $0.matchStartOffset >= keywordEndOffset }
            .sorted { $0.matchStartOffset < $1.matchStartOffset }
        let pool = afterKeyword.isEmpty
            ? filtered.sorted { $0.matchStartOffset < $1.matchStartOffset }
            : afterKeyword
        let anchored = pool.filter { match in
            let myDistance = match.matchStartOffset - keywordEndOffset
            for peerEnd in peerEnds where peerEnd != keywordEndOffset {
                if match.matchStartOffset < peerEnd { continue }
                let peerDistance = match.matchStartOffset - peerEnd
                if peerDistance < myDistance { return false }
            }
            return true
        }.sorted { $0.matchStartOffset < $1.matchStartOffset }
        let ranked = anchored.isEmpty ? pool : anchored
        guard skipCount < ranked.count else { return ranked.last }
        return ranked[skipCount]
    }

    private static func rankedGramMatchesAfterKeyword(
        region: KeywordRegion,
        maxGrams: Double
    ) -> [RegexUnitMatchWithOffset] {
        let matches = allRegexMatches(pattern: unitNumberPattern, in: region.foldedContainerText)
        let filtered = filteredUnitMatches(
            matches,
            allowedUnits: ["g"],
            containerText: region.foldedContainerText,
            rejectKilojoules: false
        )
        let peerEnds = allKeywordEndOffsetsInContainer(region.foldedContainerText)
        let afterKeyword = filtered
            .filter { $0.matchStartOffset >= region.keywordEndOffset }
            .sorted { $0.matchStartOffset < $1.matchStartOffset }
        return afterKeyword.filter { match in
            guard let value = parseLocalizedNumber(match.number), value >= 0, value <= maxGrams else { return false }
            let myDistance = match.matchStartOffset - region.keywordEndOffset
            for peerEnd in peerEnds where peerEnd != region.keywordEndOffset {
                if match.matchStartOffset < peerEnd { continue }
                let peerDistance = match.matchStartOffset - peerEnd
                if peerDistance < myDistance { return false }
            }
            return true
        }
    }

    private static func resolveSubFieldGramValue(
        field: String,
        region: KeywordRegion,
        picked: RegexUnitMatchWithOffset,
        maxGrams: Double,
        parentMacroGram: Double?
    ) -> Double? {
        guard let primary = parseLocalizedNumber(picked.number) else { return nil }
        let ranked = rankedGramMatchesAfterKeyword(region: region, maxGrams: maxGrams)
        let values = ranked.compactMap { parseLocalizedNumber($0.number) }
        if let parent = parentMacroGram, parent > 0, primary >= parent * 0.9 {
            if let smaller = values.filter({ $0 > 0 && $0 < primary }).min() {
                return smaller
            }
            return nil
        }
        if values.count > 1, let smallest = values.filter({ $0 > 0 }).min() {
            return smallest
        }
        return primary
    }

    private static func resolveParentGramValue(
        field: String,
        region: KeywordRegion,
        picked: RegexUnitMatchWithOffset,
        maxGrams: Double
    ) -> Double? {
        guard let primary = parseLocalizedNumber(picked.number) else { return nil }
        let ranked = rankedGramMatchesAfterKeyword(region: region, maxGrams: maxGrams)
        let values = ranked.compactMap { parseLocalizedNumber($0.number) }
        if primary == 0, let largest = values.filter({ $0 > 0 }).max() {
            return largest
        }
        if field == "Protein", primary <= 3, values.count > 1 {
            let later = values.filter { v in
                guard let pickedValue = parseLocalizedNumber(picked.number) else { return false }
                return v > pickedValue
            }
            if let best = later.max(), best > primary {
                return best
            }
        }
        return primary
    }

    private static func isExplicitKcalToken(_ token: SpatialNumericToken) -> Bool {
        foldDiacritics(token.sourceText.lowercased()).contains("kcal")
    }

    private static func shouldExcludeCalorieRayToken(
        _ token: SpatialNumericToken,
        elements: [NutritionLabelSpatialElement],
        yTolerance: CGFloat
    ) -> Bool {
        if isExplicitKcalToken(token) { return false }
        return isKjBoundToken(token, elements: elements, yTolerance: yTolerance)
    }

    private static func selectCalorieRaycastToken(
        keywordRegion: KeywordRegion,
        numerics: [SpatialNumericToken],
        elements: [NutritionLabelSpatialElement],
        yTolerance: CGFloat
    ) -> SpatialNumericToken? {
        let onBand = numerics.filter { token in
            token.unit == "kcal" &&
            abs(token.centerY - keywordRegion.centerY) <= yTolerance &&
            !shouldExcludeCalorieRayToken(token, elements: elements, yTolerance: yTolerance)
        }
        guard !onBand.isEmpty else { return nil }
        let toTheRight = onBand.filter { $0.minX >= keywordRegion.rightX - 0.02 }
        let pool = toTheRight.isEmpty ? onBand : toTheRight
        return pool.min { $0.minX < $1.minX }
    }

    private static func isBlueprintSpatialToken(_ token: SpatialNumericToken) -> Bool {
        let folded = foldDiacritics(normalizeEuropeanDecimals(token.sourceText).lowercased())
        let pseudo = RegexUnitMatchWithOffset(
            number: String(token.value),
            unit: token.unit,
            matchStartOffset: 0
        )
        return isBlueprintBaselineMatch(containerText: folded, match: pseudo)
    }

    private static func trySelfContainedCalories(
        region: KeywordRegion
    ) -> Double? {
        guard containerHasDigit(region.foldedContainerText) else { return nil }
        let matches = allRegexMatches(pattern: kcalCapturePattern, in: region.foldedContainerText)
        guard let picked = pickMatchAfterKeyword(
            matches,
            keywordEndOffset: region.keywordEndOffset,
            allowedUnits: ["kcal"],
            containerText: region.foldedContainerText,
            rejectKilojoules: true
        ),
              let value = parseLocalizedNumber(picked.number) else { return nil }
        guard value > 0, value <= 1000 else { return nil }
        return value
    }

    private static func trySelfContainedGram(
        region: KeywordRegion,
        maxGrams: Double,
        skipCount: Int = 0,
        field: String = "",
        isParentField: Bool = false,
        isSubField: Bool = false,
        parentMacroGram: Double? = nil
    ) -> Double? {
        guard containerHasDigit(region.foldedContainerText) else { return nil }
        let matches = allRegexMatches(pattern: unitNumberPattern, in: region.foldedContainerText)
        guard let picked = pickMatchAfterKeyword(
            matches,
            keywordEndOffset: region.keywordEndOffset,
            allowedUnits: ["g"],
            containerText: region.foldedContainerText,
            skipCount: skipCount
        ) else { return nil }
        let value: Double?
        if isParentField {
            value = resolveParentGramValue(field: field, region: region, picked: picked, maxGrams: maxGrams)
        } else if isSubField {
            value = resolveSubFieldGramValue(
                field: field, region: region, picked: picked, maxGrams: maxGrams, parentMacroGram: parentMacroGram
            )
        } else {
            value = parseLocalizedNumber(picked.number)
        }
        guard let value, value >= 0, value <= maxGrams else { return nil }
        if isParentField, value == 0 { return nil }
        return value
    }

    private static func trySelfContainedSodiumMg(region: KeywordRegion) -> Double? {
        guard containerHasDigit(region.foldedContainerText) else { return nil }
        let matches = allRegexMatches(pattern: unitNumberPattern, in: region.foldedContainerText)
        guard let picked = pickMatchAfterKeyword(
            matches,
            keywordEndOffset: region.keywordEndOffset,
            allowedUnits: ["g", "mg"],
            containerText: region.foldedContainerText
        ),
              let value = parseLocalizedNumber(picked.number) else { return nil }
        let mg = picked.unit == "g" ? value * 1000.0 : value
        guard mg >= 0, mg <= 10_000 else { return nil }
        return mg
    }

    private static func trySelfContainedSaltAsSodiumMg(region: KeywordRegion) -> Double? {
        guard containerHasDigit(region.foldedContainerText) else { return nil }
        let matches = allRegexMatches(pattern: unitNumberPattern, in: region.foldedContainerText)
        guard let picked = pickMatchAfterKeyword(
            matches,
            keywordEndOffset: region.keywordEndOffset,
            allowedUnits: ["g", "mg"],
            containerText: region.foldedContainerText
        ),
              let value = parseLocalizedNumber(picked.number) else { return nil }
        if picked.unit == "mg" {
            guard value >= 0, value <= 10_000 else { return nil }
            return value
        }
        guard value >= 0, value <= 10 else {
            if value > 10 {
                debugPrint("WARNING: Rejected spatial salt \(value)g (>10g) in self-contained.")
            }
            return nil
        }
        return ((value / 2.5) * 1000.0).rounded()
    }

    private static func unionBox(
        _ a: NutritionLabelSpatialElement,
        _ b: NutritionLabelSpatialElement
    ) -> NutritionLabelSpatialElement {
        NutritionLabelSpatialElement(
            text: "\(a.text) \(b.text)",
            minX: min(a.minX, b.minX),
            minY: min(a.minY, b.minY),
            maxX: max(a.maxX, b.maxX),
            maxY: max(a.maxY, b.maxY)
        )
    }

    private static func horizontalRaycast(
        keywordRegion: KeywordRegion,
        numerics: [SpatialNumericToken],
        allowedUnits: Set<String>,
        yTolerance: CGFloat,
        excludeToken: (SpatialNumericToken) -> Bool = { _ in false },
        skipCount: Int = 0
    ) -> SpatialNumericToken? {
        let candidates = numerics.filter { token in
            allowedUnits.contains(token.unit) &&
            !excludeToken(token) &&
            !isBlueprintSpatialToken(token) &&
            abs(token.centerY - keywordRegion.centerY) <= yTolerance &&
            token.minX >= keywordRegion.rightX - 0.002
        }.sorted { $0.minX < $1.minX }
        guard skipCount < candidates.count else { return candidates.last }
        return candidates[skipCount]
    }

    private static func logRaycast(
        field: String,
        region: KeywordRegion,
        numerics: [SpatialNumericToken],
        selected: SpatialNumericToken?
    ) {
        debugBlockHeader(field: field)
        debugPrint("Keyword: '\(region.keyword)' | centerY: \(String(format: "%.3f", region.centerY)) | rightX: \(String(format: "%.3f", region.rightX))")
        debugPrint("Row: '\(region.foldedContainerText)'")
        let hits = numerics.filter {
            abs($0.centerY - region.centerY) <= yRayTolerance && $0.minX >= region.rightX - 0.002
        }
        let tokenList = hits.map {
            "[x=\(String(format: "%.3f", $0.minX))] \($0.value)\($0.unit) y=\(String(format: "%.3f", $0.centerY))"
        }.joined(separator: ", ")
        debugPrint("Ray hits: \(tokenList.isEmpty ? "[]" : tokenList)")
        if let selected {
            debugPrint("Selected: '\(selected.sourceText)' -> \(selected.value)\(selected.unit)")
        } else {
            debugPrint("Selected: <none>")
        }
        debugBlockFooter()
    }

    private static func isKjBoundToken(_ token: SpatialNumericToken, elements: [NutritionLabelSpatialElement], yTolerance: CGFloat) -> Bool {
        let kjElements = elements.filter { element in
            foldDiacritics(element.text.lowercased()).range(of: kjMarkerPattern, options: .regularExpression) != nil
        }
        for kj in kjElements {
            guard abs(kj.centerY - token.centerY) <= yTolerance else { continue }
            let gap = kj.minX - token.maxX
            let overlap = token.maxX >= kj.minX - 0.01 && kj.minX <= token.maxX + kjProximityX
            if overlap || (gap >= -0.02 && gap <= kjProximityX) {
                return true
            }
        }
        if token.unit == "kcal" {
            let source = foldDiacritics(token.sourceText.lowercased())
            if source.range(of: kjMarkerPattern, options: .regularExpression) != nil,
               source.range(of: "kcal", options: .caseInsensitive) == nil {
                return true
            }
        }
        return false
    }

    private static func raycastCalories(
        elements: [NutritionLabelSpatialElement],
        numerics: [SpatialNumericToken],
        yTolerance: CGFloat
    ) -> Double? {
        let regions = findKeywordRegions(
            elements: elements,
            keywords: caloriesKeywords,
            requireWordBoundaryForShort: true
        )
        for region in candidateKeywordRegions(from: regions, excludeSaturatedRow: false) {
            if let selfContained = trySelfContainedCalories(region: region) {
                logSelfContained(field: "Calories", region: region, value: selfContained, unit: "kcal")
                return selfContained
            }
            let selected = selectCalorieRaycastToken(
                keywordRegion: region,
                numerics: numerics,
                elements: elements,
                yTolerance: yTolerance
            )
            logRaycast(field: "Calories", region: region, numerics: numerics, selected: selected)
            if let selected, selected.value > 0, selected.value <= 1000 {
                return selected.value
            }
            if let selected, selected.value > 1000 {
                debugPrint("WARNING: Rejected spatial calories \(selected.value) (>1000 kcal).")
            }
        }

        let kcalRegions = findKeywordRegions(
            elements: elements,
            keywords: ["kcal"],
            requireWordBoundaryForShort: false
        )
        for region in kcalRegions.sorted(by: { $0.centerY < $1.centerY }) {
            if let lookLeft = numberLookbackBeforeUnit(in: region.rawContainerText, unit: "kcal"),
               lookLeft > 0, lookLeft <= 1000 {
                logSelfContained(field: "Calories", region: region, value: lookLeft, unit: "kcal")
                return lookLeft
            }
            if let leftNumber = numerics.filter({
                $0.unit == "kcal" &&
                abs($0.centerY - region.centerY) <= yTolerance &&
                $0.maxX <= region.minX + 0.02 &&
                !shouldExcludeCalorieRayToken($0, elements: elements, yTolerance: yTolerance)
            }).min(by: { $0.minX < $1.minX }),
            leftNumber.value > 0, leftNumber.value <= 1000 {
                return leftNumber.value
            }
        }

        let fallback = numerics.filter {
            $0.unit == "kcal" &&
            $0.value > 0 &&
            $0.value <= 1000 &&
            !shouldExcludeCalorieRayToken($0, elements: elements, yTolerance: yTolerance)
        }.min { $0.centerY < $1.centerY }
        return fallback?.value
    }

    private static func raycastGramMacro(
        field: String,
        keywords: [String],
        elements: [NutritionLabelSpatialElement],
        yTolerance: CGFloat,
        excludeSaturatedRow: Bool,
        rejectSugarOnlyRows: Bool = false,
        isSubField: Bool = false,
        isParentField: Bool = false,
        parentMacroGram: Double? = nil
    ) -> Double? {
        let fieldNumerics = collectNumericTokens(from: elements)
        let regions = findKeywordRegions(
            elements: elements,
            keywords: keywords,
            requireWordBoundaryForShort: true
        )
        var candidates = candidateKeywordRegions(
            from: regions,
            excludeSaturatedRow: excludeSaturatedRow,
            rejectSugarOnlyRows: rejectSugarOnlyRows
        )
        if isParentField {
            candidates = candidates.filter { !isSubPropertyRow($0) }
        }
        if isSubField {
            candidates = candidates.filter { isSubPropertyRow($0) || allRegexMatches(pattern: unitNumberPattern, in: $0.foldedContainerText).count > 1 }
        }
        for region in candidates {
            if isSubField, !validateSubFieldKeywordPrefix(region: region, keywords: keywords) {
                continue
            }
            if !containerHasDigit(region.foldedContainerText) && fieldNumerics.isEmpty {
                continue
            }
            let skipCount: Int
            if isParentField {
                skipCount = 0
            } else if isSubField {
                skipCount = subFieldRaySkipCount(region: region, numerics: fieldNumerics, yTolerance: yTolerance)
            } else {
                skipCount = 0
            }
            if let selfContained = trySelfContainedGram(
                region: region,
                maxGrams: 100,
                skipCount: skipCount,
                field: field,
                isParentField: isParentField,
                isSubField: isSubField,
                parentMacroGram: parentMacroGram
            ) {
                logSelfContained(field: field, region: region, value: selfContained, unit: "g")
                return selfContained
            }
            let rayTolerance = isParentField ? min(yTolerance * 1.5, rowClusterTolerance * 2) : yTolerance
            let selected = horizontalRaycast(
                keywordRegion: region,
                numerics: fieldNumerics,
                allowedUnits: ["g"],
                yTolerance: rayTolerance,
                skipCount: skipCount
            )
            logRaycast(field: field, region: region, numerics: fieldNumerics, selected: selected)
            guard let selected, selected.unit == "g" else { continue }
            if isHeaderScopeViolation(region: region, token: selected) { continue }
            guard selected.value >= 0, selected.value <= 100 else {
                if selected.value > 100 {
                    debugPrint("WARNING: Rejected spatial \(field) \(selected.value)g (>100g).")
                }
                continue
            }
            if isSubField, let parent = parentMacroGram, parent > 0, selected.value >= parent * 0.9 {
                continue
            }
            return selected.value
        }
        return nil
    }

    private static func raycastSodiumMg(
        field: String,
        keywords: [String],
        elements: [NutritionLabelSpatialElement],
        numerics: [SpatialNumericToken],
        yTolerance: CGFloat
    ) -> Double? {
        let regions = findKeywordRegions(
            elements: elements,
            keywords: keywords,
            requireWordBoundaryForShort: true
        )
        guard let region = regions.min(by: { $0.centerY < $1.centerY }) else { return nil }
        if region.foldedContainerText.range(of: barcodeDigitsPattern, options: .regularExpression) != nil { return nil }
        if region.foldedContainerText.range(of: percentOrRdaPattern, options: .regularExpression) != nil { return nil }
        if let selfContained = trySelfContainedSodiumMg(region: region) {
            logSelfContained(field: field, region: region, value: selfContained, unit: "mg")
            return selfContained
        }
        let selected = horizontalRaycast(
            keywordRegion: region,
            numerics: numerics,
            allowedUnits: ["g", "mg"],
            yTolerance: yTolerance
        )
        logRaycast(field: field, region: region, numerics: numerics, selected: selected)
        guard let selected else { return nil }
        let mg = selected.unit == "g" ? selected.value * 1000.0 : selected.value
        guard mg >= 0, mg <= 10_000 else {
            debugPrint("WARNING: Rejected spatial sodium \(mg)mg.")
            return nil
        }
        return mg
    }

    private static func raycastSaltAsSodiumMg(
        elements: [NutritionLabelSpatialElement],
        numerics: [SpatialNumericToken],
        yTolerance: CGFloat
    ) -> Double? {
        let regions = findKeywordRegions(
            elements: elements,
            keywords: saltKeywords,
            requireWordBoundaryForShort: true
        )
        for region in regions.sorted(by: { $0.centerY < $1.centerY }) {
            if region.foldedContainerText.range(of: saltKeywordExclusionPattern, options: .regularExpression) != nil { continue }
            if region.foldedContainerText.range(of: barcodeDigitsPattern, options: .regularExpression) != nil { continue }
            if region.foldedContainerText.range(of: percentOrRdaPattern, options: .regularExpression) != nil { continue }
            if let selfContained = trySelfContainedSaltAsSodiumMg(region: region) {
                logSelfContained(field: "SaltToSodium", region: region, value: selfContained, unit: "mg")
                return selfContained
            }
            let selected = horizontalRaycast(
                keywordRegion: region,
                numerics: numerics,
                allowedUnits: ["g", "mg"],
                yTolerance: yTolerance
            )
            logRaycast(field: "SaltToSodium", region: region, numerics: numerics, selected: selected)
            if let selected {
                if let sodiumMg = convertSaltTokenToSodiumMg(selected) {
                    return sodiumMg
                }
            }
        }
        if let fallback = saltFallbackFromBottomCorpus(elements: elements) {
            debugPrint("SaltToSodium bottom-corpus fallback -> \(fallback)mg")
            return fallback
        }
        return nil
    }

    private static func convertSaltTokenToSodiumMg(_ selected: SpatialNumericToken) -> Double? {
        debugPrint("Salt Input: value=\(selected.value) unit=\(selected.unit)")
        let sodiumMg: Double
        if selected.unit == "mg" {
            sodiumMg = selected.value
            debugPrint("Converted Sodium: value(mg)=\(sodiumMg)")
        } else {
            if selected.value > 10 {
                debugPrint("WARNING: Rejected spatial salt \(selected.value)g (>10g).")
                return nil
            }
            sodiumMg = ((selected.value / 2.5) * 1000.0).rounded()
            debugPrint("Converted Sodium: (value/2.5)*1000 rounded = \(sodiumMg)mg")
        }
        guard sodiumMg >= 0, sodiumMg <= 10_000 else {
            debugPrint("WARNING: Rejected spatial sodium from salt \(sodiumMg)mg.")
            return nil
        }
        return sodiumMg
    }

    private static func isHeaderScopeViolation(region: KeywordRegion, token: SpatialNumericToken) -> Bool {
        let window = region.foldedContainerText
        if window.range(of: headerScopeBlacklistPattern, options: .regularExpression) != nil {
            return true
        }
        return false
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
