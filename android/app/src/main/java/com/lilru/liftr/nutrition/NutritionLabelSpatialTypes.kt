package com.lilru.liftr.nutrition

data class NutritionLabelSpatialElement(
    val text: String,
    val minX: Float,
    val minY: Float,
    val maxX: Float,
    val maxY: Float
) {
    val centerX: Float get() = (minX + maxX) / 2f
    val centerY: Float get() = (minY + maxY) / 2f
    val rightX: Float get() = maxX
}

data class NutritionLabelRecognitionResult(
    val mergedLines: List<String>,
    val elements: List<NutritionLabelSpatialElement>
)
