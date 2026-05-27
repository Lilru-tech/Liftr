import Testing
@testable import Liftr

@Suite(.serialized)
struct NutritionLabelParserTests {
    @Test func fragmentedLinesMeetMinimumRead() {
        let lines = ["Valor energético 234 kcal", "Proteïnes 8,2 g", "Hidrats de carboni 42 g"]
        let parsed = NutritionLabelParser.parse(lines: lines)
        #expect(parsed.calories == 234)
        #expect(parsed.protein == 8.2)
        #expect(parsed.carbs == 42)
        #expect(parsed.meetsMinimumRead)
    }

    @Test func ignoresKjColumnForCalories() {
        let lines = ["1020 kJ / 245 kcal"]
        let parsed = NutritionLabelParser.parse(lines: lines)
        #expect(parsed.calories == 245)
    }

    @Test func catalanCommaDecimals() {
        let lines = ["Hidrats de carboni 13,7 g", "Greixos 6,5 g", "245 kcal"]
        let parsed = NutritionLabelParser.parse(lines: lines)
        #expect(parsed.carbs == 13.7)
        #expect(parsed.fat == 6.5)
        #expect(parsed.calories == 245)
        #expect(parsed.meetsMinimumRead)
    }

    @Test func partialMicrosStillSucceeds() {
        let lines = ["245 kcal", "Proteínas 12 g", "Grasas 8 g", "Fibra 2 g"]
        let parsed = NutritionLabelParser.parse(lines: lines)
        #expect(parsed.meetsMinimumRead)
        #expect(parsed.fiber == 2)
    }

    @Test func onlyFiberDoesNotMeetMinimumRead() {
        let lines = ["Fibra alimentaria 3,5 g"]
        let parsed = NutritionLabelParser.parse(lines: lines)
        #expect(parsed.fiber == 3.5)
        #expect(!parsed.meetsMinimumRead)
    }

    @Test func valueBeforeKeywordLookbehind() {
        let lines = ["proteïnes 12 g", "hidrats de carboni 50 g", "200 kcal"]
        let parsed = NutritionLabelParser.parse(lines: lines)
        #expect(parsed.protein == 12)
        #expect(parsed.carbs == 50)
        #expect(parsed.meetsMinimumRead)
    }

    @Test func frenchGermanItalianLabels() {
        let lines = [
            "Valeur énergétique 512 kcal",
            "Protéines 21 g",
            "Glucides 45 g",
            "Matières grasses 18 g"
        ]
        let parsed = NutritionLabelParser.parse(lines: lines)
        #expect(parsed.calories == 512)
        #expect(parsed.protein == 21)
        #expect(parsed.carbs == 45)
        #expect(parsed.fat == 18)
        #expect(parsed.meetsMinimumRead)
    }

    @Test func germanEszettNormalization() {
        let lines = [
            "Brennwert 380 kcal",
            "Eiweiß 8 g",
            "Kohlenhydrate 52 g",
            "davon gesättigte Fettsäuren 4 g"
        ]
        let parsed = NutritionLabelParser.parse(lines: lines)
        #expect(parsed.calories == 380)
        #expect(parsed.protein == 8)
        #expect(parsed.carbs == 52)
        #expect(parsed.saturatedFat == 4)
        #expect(parsed.meetsMinimumRead)
    }

    @Test func lineAnchoringPreventsVerticalDrift() {
        let lines = ["Fibra", "2,3 g", "Proteínas 10 g", "Carbs 20 g", "200 kcal"]
        let parsed = NutritionLabelParser.parse(lines: lines)
        #expect(parsed.fiber == 0)
        #expect(parsed.calories == 200)
        #expect(parsed.protein == 10)
        #expect(parsed.carbs == 20)
    }

    @Test func saltConvertsToSodiumMgWithCommaDecimal() {
        let lines = ["Sal 0,13 g", "Energy 200 kcal", "Protein 10 g", "Carbs 20 g"]
        let parsed = NutritionLabelParser.parse(lines: lines)
        #expect(parsed.sodiumMg == 52)
    }

    @Test func eggsMergedProteinRow() {
        let parsed = NutritionLabelParser.parse(lines: ["Proteínas 12,5 g 0 g 0 g gallinas."])
        #expect(parsed.protein == 12.5)
    }

    @Test func jarMergedProteinSalt() {
        let parsed = NutritionLabelParser.parse(lines: ["00 Proteínas 2,58 g 4,4 g"])
        #expect(parsed.protein == 4.4)
        #expect(parsed.sodiumMg == 1032)
    }

    @Test func breadScrambledCatalan() {
        let lines = [
            "GREIXOS dels quals: 1132 kJ / 267 kcal",
            "saturats 1,0 g",
            "HIDRATS DE CARBONI 0,5 g",
            "FIBRA ALIMENTARIA dels quals sucres 2,3 g 55 g",
            "SAL PROTEÏNES 8,6 g 2,1 g",
            "Cod. 92981 - Ver.- 01/25 1,5 g"
        ]
        let parsed = NutritionLabelParser.parse(lines: lines)
        #expect(parsed.calories == 267)
        #expect(parsed.protein == 8.6)
        #expect(parsed.carbs == 55)
        #expect(parsed.fat == 1.0)
        #expect(parsed.fiber == 2.1)
        #expect(parsed.sugars == 2.3)
        #expect(parsed.sodiumMg == 600)
    }

    @Test func gumSugarFreeCarbs() {
        let lines = [
            "Valor Energético/Energia 170 kcal 100 g 709 kJ",
            "Hidratos de Carbono - Azúcares/Açúcares < 0,1 g 69 g",
            "Proteínas <0,5 g",
            "sin azúcares"
        ]
        let parsed = NutritionLabelParser.parse(lines: lines)
        #expect(parsed.calories == 170)
        #expect(parsed.carbs == 69)
        #expect(parsed.protein == 0.5)
        #expect(parsed.sugars <= 0.1)
    }

    @Test func gumTraceSaltSodium() {
        let lines = [
            "BAILES SABOR A MENTA. SIN AZUCARES.",
            "Valor Energético/Energia 170 kcal 100 g 709 kJ",
            "Hidratos de Carbono 69 g",
            "con ca de carnauba. Contem Sal 0.5 g 66 g",
            "Peso Neto/Líquido: <0,01 g"
        ]
        let parsed = NutritionLabelParser.parse(lines: lines)
        #expect(parsed.calories == 170)
        #expect(parsed.carbs == 69)
        #expect(parsed.sodiumMg <= 10)
    }

    @Test func greenTubScrambledCorpus() {
        let lines = [
            "Valor energético / Energia Valores medios / médios INFORMAÇÃO NUTRICIONAL Por 100 g",
            "Grasas / Lípidos .. .. 613 KJ",
            "Hidratos de carbono .. dos quais saturados. de las cuales saturadas",
            "149 kcal 13,7 g",
            "Proteínas . Fibra alimentaria / Fibra. dos quais açúcares. de los cuales azúcares ... 2g",
            ". 3,8 g",
            "Sal 1,5 g 1,99 . 5g 1,4 g Consumid Consume a"
        ]
        let parsed = NutritionLabelParser.parse(lines: lines)
        #expect(parsed.calories == 149)
        #expect(parsed.fat == 13.7)
        #expect(parsed.saturatedFat == 3.8)
        #expect(parsed.carbs == 2)
        #expect(parsed.protein == 1.99)
        #expect(parsed.sugars == 1.4)
        #expect(parsed.fiber == 5)
        #expect(parsed.sodiumMg == 600)
    }

    @Test func mergeKeepsSpatialFatWhenLineMisses() {
        let spatial = NutritionLabelParseResult(calories: 149, protein: 1.5, carbs: 2, fat: 13.7, saturatedFat: 0, sugars: 2, fiber: 2, sodiumMg: 600)
        let line = NutritionLabelParser.parse(lines: [
            "149 kcal 13,7 g",
            "Sal 1,5 g 1,99 . 5g 1,4 g"
        ])
        let merged = NutritionLabelParser.mergeParseResults(spatial: spatial, line: line)
        #expect(merged.fat == 13.7)
    }

    @Test func milkDualColumnCorpus() {
        let lines = [
            "Valor 100 ml Energético/Energia 44 kcal 188 kJ",
            "Grasas/Lípidos 0,2 g 0,5 g",
            "- Azúcares/Açúcares 4,6 g",
            "Proteínas 6,0 g",
            "Sal 0,13 g 0,33 g"
        ]
        let parsed = NutritionLabelParser.parse(lines: lines)
        #expect(parsed.calories == 44)
        #expect(parsed.protein == 6)
        #expect(parsed.fat == 0.2)
        #expect(parsed.sugars == 4.6)
        #expect(parsed.sodiumMg == 52)
    }

    @Test func mergePrefersLineWhenSpatialProteinZero() {
        let spatial = NutritionLabelParseResult(calories: 150, protein: 0, carbs: 0, fat: 11.1)
        let line = NutritionLabelParser.parse(lines: ["Proteínas 12,5 g 0 g 0 g"])
        let merged = NutritionLabelParser.mergeParseResults(spatial: spatial, line: line)
        #expect(merged.protein == 12.5)
        #expect(merged.calories == 150)
    }

    @Test func eggsSaturatedFatBelowTotalFat() {
        let lines = [
            "Grasas 11,1 g",
            "Saturadas 3,1 g",
            "Proteínas 12,5 g"
        ]
        let parsed = NutritionLabelParser.parse(lines: lines)
        #expect(parsed.fat == 11.1)
        #expect(parsed.saturatedFat == 3.1)
        #expect(parsed.protein == 12.5)
    }

    @Test func mergeOverridesSpatialSugarsWithLine() {
        let spatial = NutritionLabelParseResult(calories: 170, carbs: 69, sugars: 69)
        let line = NutritionLabelParser.parse(lines: [
            "Hidratos de Carbono - Azúcares < 0,1 g 69 g",
            "sin azúcares"
        ])
        let merged = NutritionLabelParser.mergeParseResults(spatial: spatial, line: line)
        #expect(merged.sugars <= 0.1)
        #expect(merged.carbs == 69)
    }

    @Test func mergeJarProteinAndSodiumFromLine() {
        let spatial = NutritionLabelParseResult(calories: 272, protein: 2.6, sodiumMg: 0)
        let line = NutritionLabelParser.parse(lines: ["00 Proteínas 2,58 g 4,4 g"])
        let merged = NutritionLabelParser.mergeParseResults(spatial: spatial, line: line)
        #expect(merged.protein == 4.4)
        #expect(merged.sodiumMg == 1032)
    }

    @Test func milkSaturatedFatFromDedicatedRow() {
        let lines = [
            "Valor 100 ml Energético/Energia 44 kcal 188 kJ",
            "Grasas/Lípidos 0,2 g 0,5 g",
            "de las cuales saturadas 0,1 g",
            "Proteínas 6,0 g"
        ]
        let parsed = NutritionLabelParser.parse(lines: lines)
        #expect(parsed.fat == 0.2)
        #expect(parsed.saturatedFat == 0.1)
    }
}
