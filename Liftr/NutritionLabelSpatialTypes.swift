import CoreGraphics
import Foundation

struct NutritionLabelSpatialElement: Equatable {
    let text: String
    let minX: CGFloat
    let minY: CGFloat
    let maxX: CGFloat
    let maxY: CGFloat

    var centerX: CGFloat { (minX + maxX) / 2 }
    var centerY: CGFloat { (minY + maxY) / 2 }
    var rightX: CGFloat { maxX }
    var width: CGFloat { maxX - minX }
    var height: CGFloat { maxY - minY }
}

struct NutritionLabelRecognitionResult: Equatable {
    let mergedLines: [String]
    let elements: [NutritionLabelSpatialElement]
}
