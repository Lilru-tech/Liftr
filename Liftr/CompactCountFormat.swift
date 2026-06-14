import Foundation

func formatCompactCount(_ value: Int) -> String {
    formatCompactCount(Int64(value))
}

func formatCompactCount(_ value: Int64) -> String {
    if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
    if value >= 1_000 { return String(format: "%.1fk", Double(value) / 1_000) }
    return "\(value)"
}
