package com.lilru.liftr.nutrition

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NutritionLabelParserTest {
    @Test
    fun fragmentedLinesMeetMinimumRead() {
        val lines = listOf(
            "Valor energético 234 kcal",
            "Proteïnes 8,2 g",
            "Hidrats de carboni 42 g"
        )
        val parsed = NutritionLabelParser.parse(lines)
        assertEquals(234.0, parsed.calories)
        assertEquals(8.2, parsed.protein)
        assertEquals(42.0, parsed.carbs)
        assertTrue(parsed.meetsMinimumRead)
    }

    @Test
    fun ignoresKjColumnForCalories() {
        val parsed = NutritionLabelParser.parse(listOf("1020 kJ / 245 kcal"))
        assertEquals(245.0, parsed.calories)
    }

    @Test
    fun catalanCommaDecimals() {
        val parsed = NutritionLabelParser.parse(
            listOf("Hidrats de carboni 13,7 g", "Greixos 6,5 g", "245 kcal")
        )
        assertEquals(13.7, parsed.carbs)
        assertEquals(6.5, parsed.fat)
        assertEquals(245.0, parsed.calories)
        assertTrue(parsed.meetsMinimumRead)
    }

    @Test
    fun partialMicrosStillSucceeds() {
        val parsed = NutritionLabelParser.parse(
            listOf("245 kcal", "Proteínas 12 g", "Grasas 8 g", "Fibra 2 g")
        )
        assertTrue(parsed.meetsMinimumRead)
        assertEquals(2.0, parsed.fiber)
    }

    @Test
    fun onlyFiberDoesNotMeetMinimumRead() {
        val parsed = NutritionLabelParser.parse(listOf("Fibra alimentaria 3,5 g"))
        assertEquals(3.5, parsed.fiber)
        assertFalse(parsed.meetsMinimumRead)
    }

    @Test
    fun valueBeforeKeywordLookbehind() {
        val parsed = NutritionLabelParser.parse(
            listOf("proteïnes 12 g", "hidrats de carboni 50 g", "200 kcal")
        )
        assertEquals(12.0, parsed.protein)
        assertEquals(50.0, parsed.carbs)
        assertTrue(parsed.meetsMinimumRead)
    }

    @Test
    fun lineAnchoringPreventsVerticalDrift() {
        val parsed = NutritionLabelParser.parse(
            listOf("Fibra", "2,3 g", "Proteínas 10 g", "Carbs 20 g", "200 kcal")
        )
        assertEquals(0.0, parsed.fiber)
        assertEquals(200.0, parsed.calories)
        assertEquals(10.0, parsed.protein)
        assertEquals(20.0, parsed.carbs)
    }

    @Test
    fun saltConvertsToSodiumMgWithCommaDecimal() {
        val parsed = NutritionLabelParser.parse(
            listOf("Sal 0,13 g", "Energy 200 kcal", "Protein 10 g", "Carbs 20 g")
        )
        assertEquals(52.0, parsed.sodiumMg)
    }

    @Test
    fun frenchGermanItalianLabels() {
        val parsed = NutritionLabelParser.parse(
            listOf(
                "Valeur énergétique 512 kcal",
                "Protéines 21 g",
                "Glucides 45 g",
                "Matières grasses 18 g"
            )
        )
        assertEquals(512.0, parsed.calories)
        assertEquals(21.0, parsed.protein)
        assertEquals(45.0, parsed.carbs)
        assertEquals(18.0, parsed.fat)
        assertTrue(parsed.meetsMinimumRead)
    }

    @Test
    fun germanEszettNormalization() {
        val parsed = NutritionLabelParser.parse(
            listOf(
                "Brennwert 380 kcal",
                "Eiweiß 8 g",
                "Kohlenhydrate 52 g",
                "davon gesättigte Fettsäuren 4 g"
            )
        )
        assertEquals(380.0, parsed.calories)
        assertEquals(8.0, parsed.protein)
        assertEquals(52.0, parsed.carbs)
        assertEquals(4.0, parsed.saturatedFat)
        assertTrue(parsed.meetsMinimumRead)
    }

    @Test
    fun eggsMergedProteinRow() {
        val parsed = NutritionLabelParser.parse(listOf("Proteínas 12,5 g 0 g 0 g gallinas."))
        assertEquals(12.5, parsed.protein)
    }

    @Test
    fun jarMergedProteinSalt() {
        val parsed = NutritionLabelParser.parse(listOf("00 Proteínas 2,58 g 4,4 g"))
        assertEquals(4.4, parsed.protein)
        assertEquals(1032.0, parsed.sodiumMg)
    }

    @Test
    fun breadScrambledCatalan() {
        val parsed = NutritionLabelParser.parse(
            listOf(
                "GREIXOS dels quals: 1132 kJ / 267 kcal",
                "saturats 1,0 g",
                "HIDRATS DE CARBONI 0,5 g",
                "FIBRA ALIMENTARIA dels quals sucres 2,3 g 55 g",
                "SAL PROTEÏNES 8,6 g 2,1 g",
                "Cod. 92981 - Ver.- 01/25 1,5 g"
            )
        )
        assertEquals(267.0, parsed.calories)
        assertEquals(1.0, parsed.fat)
        assertEquals(8.6, parsed.protein)
        assertEquals(55.0, parsed.carbs)
        assertEquals(2.1, parsed.fiber)
        assertEquals(2.3, parsed.sugars)
        assertEquals(600.0, parsed.sodiumMg)
    }

    @Test
    fun gumTraceSaltSodium() {
        val parsed = NutritionLabelParser.parse(
            listOf(
                "BAILES SABOR A MENTA. SIN AZUCARES.",
                "Valor Energético/Energia 170 kcal 100 g 709 kJ",
                "Hidratos de Carbono 69 g",
                "con ca de carnauba. Contem Sal 0.5 g 66 g",
                "Peso Neto/Líquido: <0,01 g"
            )
        )
        assertEquals(170.0, parsed.calories)
        assertEquals(69.0, parsed.carbs)
        assertTrue(parsed.sodiumMg <= 10.0)
    }

    @Test
    fun greenTubScrambledCorpus() {
        val parsed = NutritionLabelParser.parse(
            listOf(
                "Valor energético / Energia Valores medios / médios INFORMAÇÃO NUTRICIONAL Por 100 g",
                "Grasas / Lípidos .. .. 613 KJ",
                "Hidratos de carbono .. dos quais saturados. de las cuales saturadas",
                "149 kcal 13,7 g",
                "Proteínas . Fibra alimentaria / Fibra. dos quais açúcares. de los cuales azúcares ... 2g",
                ". 3,8 g",
                "Sal 1,5 g 1,99 . 5g 1,4 g Consumid Consume a"
            )
        )
        assertEquals(149.0, parsed.calories)
        assertEquals(13.7, parsed.fat)
        assertEquals(3.8, parsed.saturatedFat)
        assertEquals(2.0, parsed.carbs)
        assertEquals(1.99, parsed.protein)
        assertEquals(1.4, parsed.sugars)
        assertEquals(5.0, parsed.fiber)
        assertEquals(600.0, parsed.sodiumMg)
    }

    @Test
    fun mergeKeepsSpatialFatWhenLineMisses() {
        val spatial = NutritionLabelParseResult(
            calories = 149.0,
            protein = 1.5,
            carbs = 2.0,
            fat = 13.7,
            sugars = 2.0,
            fiber = 2.0,
            sodiumMg = 600.0
        )
        val line = NutritionLabelParser.parse(
            listOf(
                "149 kcal 13,7 g",
                "Sal 1,5 g 1,99 . 5g 1,4 g"
            )
        )
        val merged = NutritionLabelParser.mergeParseResults(spatial, line)
        assertEquals(13.7, merged.fat)
    }

    @Test
    fun gumSugarFreeCarbs() {
        val parsed = NutritionLabelParser.parse(
            listOf(
                "Valor Energético/Energia 170 kcal 100 g 709 kJ",
                "Hidratos de Carbono - Azúcares/Açúcares < 0,1 g 69 g",
                "Proteínas <0,5 g",
                "sin azúcares"
            )
        )
        assertEquals(170.0, parsed.calories)
        assertEquals(69.0, parsed.carbs)
        assertEquals(0.5, parsed.protein)
        assertTrue(parsed.sugars <= 0.1)
    }

    @Test
    fun milkDualColumnCorpus() {
        val parsed = NutritionLabelParser.parse(
            listOf(
                "Valor 100 ml Energético/Energia 44 kcal 188 kJ",
                "Grasas/Lípidos 0,2 g 0,5 g",
                "- Azúcares/Açúcares 4,6 g",
                "Proteínas 6,0 g",
                "Sal 0,13 g 0,33 g"
            )
        )
        assertEquals(44.0, parsed.calories)
        assertEquals(6.0, parsed.protein)
        assertEquals(0.2, parsed.fat)
        assertEquals(4.6, parsed.sugars)
        assertEquals(52.0, parsed.sodiumMg)
    }

    @Test
    fun mergePrefersLineWhenSpatialProteinZero() {
        val spatial = NutritionLabelParseResult(calories = 150.0, protein = 0.0, fat = 11.1)
        val line = NutritionLabelParser.parse(listOf("Proteínas 12,5 g 0 g 0 g"))
        val merged = NutritionLabelParser.mergeParseResults(spatial, line)
        assertEquals(12.5, merged.protein)
        assertEquals(150.0, merged.calories)
    }

    @Test
    fun eggsSaturatedFatBelowTotalFat() {
        val parsed = NutritionLabelParser.parse(
            listOf(
                "Grasas 11,1 g",
                "Saturadas 3,1 g",
                "Proteínas 12,5 g"
            )
        )
        assertEquals(11.1, parsed.fat)
        assertEquals(3.1, parsed.saturatedFat)
        assertEquals(12.5, parsed.protein)
    }

    @Test
    fun mergeOverridesSpatialSugarsWithLine() {
        val spatial = NutritionLabelParseResult(calories = 170.0, carbs = 69.0, sugars = 69.0)
        val line = NutritionLabelParser.parse(
            listOf(
                "Hidratos de Carbono - Azúcares < 0,1 g 69 g",
                "sin azúcares"
            )
        )
        val merged = NutritionLabelParser.mergeParseResults(spatial, line)
        assertTrue(merged.sugars <= 0.1)
        assertEquals(69.0, merged.carbs)
    }

    @Test
    fun mergeJarProteinAndSodiumFromLine() {
        val spatial = NutritionLabelParseResult(calories = 272.0, protein = 2.6, sodiumMg = 0.0)
        val line = NutritionLabelParser.parse(listOf("00 Proteínas 2,58 g 4,4 g"))
        val merged = NutritionLabelParser.mergeParseResults(spatial, line)
        assertEquals(4.4, merged.protein)
        assertEquals(1032.0, merged.sodiumMg)
    }

    @Test
    fun milkSaturatedFatFromDedicatedRow() {
        val parsed = NutritionLabelParser.parse(
            listOf(
                "Valor 100 ml Energético/Energia 44 kcal 188 kJ",
                "Grasas/Lípidos 0,2 g 0,5 g",
                "de las cuales saturadas 0,1 g",
                "Proteínas 6,0 g"
            )
        )
        assertEquals(0.2, parsed.fat)
        assertEquals(0.1, parsed.saturatedFat)
    }
}
