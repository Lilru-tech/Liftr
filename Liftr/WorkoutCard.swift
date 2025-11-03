import SwiftUI

enum WorkoutTint {
    static let strength = Color(red: 0.00, green: 0.62, blue: 0.27)
    static let cardio   = Color(red: 0.00, green: 0.38, blue: 0.82)
    static let sport    = Color(red: 0.88, green: 0.44, blue: 0.00)
    static let neutral  = Color(red: 0.35, green: 0.40, blue: 0.45)
}

func workoutTint(for kind: String) -> Color {
    switch kind.lowercased() {
    case "strength": return WorkoutTint.strength
    case "cardio":   return WorkoutTint.cardio
    case "sport":    return WorkoutTint.sport
    default:         return WorkoutTint.neutral
    }
}

struct WorkoutCardBackground: View {
    let kind: String
    var body: some View {
        let base = workoutTint(for: kind)
        return RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        base.opacity(0.28),
                        base.opacity(0.14)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white.opacity(0.18), lineWidth: 0.8)
            )
            .shadow(color: base.opacity(0.25), radius: 10, y: 4)
    }
}

func scorePill(score: Double, kind: String) -> some View {
    let t = workoutTint(for: kind)
    return Text(String(format: "%.0f", score))
        .font(.subheadline.weight(.semibold))
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Capsule().fill(t.opacity(0.15)))
        .overlay(Capsule().stroke(Color.white.opacity(0.18)))
}
