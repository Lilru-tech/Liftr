import Foundation

func levelProgressRatio(
    totalXp: Int64,
    currentLevelThresholdXp: Int64,
    nextLevelThresholdXp: Int64
) -> Double {
    let span = nextLevelThresholdXp - currentLevelThresholdXp
    guard span > 0 else { return 0 }
    let earned = totalXp - currentLevelThresholdXp
    return min(1.0, max(0.0, Double(earned) / Double(span)))
}
