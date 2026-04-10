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
    let value = Int(score.rounded())
    let t = workoutTint(for: kind)

    return Text("⭐️ \(value)")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.primary)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            ZStack {
                Capsule().fill(Color(.systemBackground).opacity(0.88))
                Capsule().fill(t.opacity(0.14))
            }
        )
        .overlay(Capsule().stroke(.white.opacity(0.18)))
        .shadow(color: .black.opacity(0.14), radius: 2, x: 0, y: 1)
}

func caloriesPill(kcal: Double, kind: String) -> some View {
    let value = Int(kcal.rounded())
    let t = workoutTint(for: kind)

    return Text("\(value) 🔥")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.primary)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            ZStack {
                Capsule().fill(Color(.systemBackground).opacity(0.88))
                Capsule().fill(t.opacity(0.12))
            }
        )
        .overlay(Capsule().stroke(.white.opacity(0.18)))
        .shadow(color: .black.opacity(0.14), radius: 2, x: 0, y: 1)
}

struct WorkoutFeedCardItem: Identifiable, Hashable {
    var id: Int { workoutId }
    let workoutId: Int
    let userId: UUID
    let kind: String
    let title: String?
    let state: String
    let startedAt: Date?
    let endedAt: Date?
    let caloriesKcal: Double?
    let score: Double?
    let sport: String?
    let cardioActivity: String?
    let username: String
    let avatarURL: String?
    let likeCount: Int
    let isLiked: Bool
    let coUserAvatarURLs: [String]
}

struct WorkoutFeedCard: View {
    let item: WorkoutFeedCardItem
    var dayGroupLabel: String? = nil

    var body: some View {
        ZStack {
            WorkoutCardBackground(kind: item.kind)

            VStack(alignment: .leading, spacing: dayGroupLabel == nil ? 8 : 4) {
                if let g = dayGroupLabel {
                    Text(g)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                HStack(alignment: .top, spacing: 12) {
                    ZStack(alignment: .bottomTrailing) {
                        AvatarView(urlString: item.avatarURL)
                            .frame(width: 42, height: 42)
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                        if !item.coUserAvatarURLs.isEmpty {
                            HStack(spacing: -8) {
                                ForEach(Array(item.coUserAvatarURLs.prefix(3)), id: \.self) { url in
                                    AvatarView(urlString: url)
                                        .frame(width: 18, height: 18)
                                        .clipShape(Circle())
                                        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                                }
                                if item.coUserAvatarURLs.count > 3 {
                                    Text("+\(item.coUserAvatarURLs.count - 3)")
                                        .font(.caption2.weight(.bold))
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Capsule().fill(Color(.systemBackground)))
                                        .overlay(Capsule().stroke(Color.black.opacity(0.1)))
                                }
                            }
                            .offset(x: 2, y: 2)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(item.username)
                                .font(.subheadline.weight(.semibold))
                        }

                        if item.state == "planned" {
                            Text(item.title ?? item.kind.capitalized)
                                .font(.body)
                                .italic()
                                .lineLimit(1)
                        } else {
                            Text(item.title ?? item.kind.capitalized)
                                .font(.body)
                                .lineLimit(1)
                        }

                        if let d = item.startedAt {
                            Text(relativeDate(d))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 6) {
                        HStack(spacing: 8) {
                            if let kcal = item.caloriesKcal, kcal > 0 {
                                caloriesPill(kcal: kcal, kind: item.kind)
                            }
                            if let sc = item.score {
                                scorePill(score: sc, kind: item.kind)
                            }
                        }
                    }
                }
                HStack {
                    HStack(spacing: 4) {
                        Text(item.kind.capitalized)
                        switch item.kind.lowercased() {
                        case "sport":
                            if let sport = item.sport {
                                Text(sportIcon(for: sport))
                            }
                        case "cardio":
                            Text(cardioIcon(for: item.cardioActivity))
                        case "strength":
                            Text("🏋️‍♂️")
                        default:
                            EmptyView()
                        }
                    }
                    .font(.caption2.weight(.semibold))
                    .padding(.vertical, 3)
                    .padding(.horizontal, 6)
                    .background(Capsule().fill(workoutTint(for: item.kind).opacity(0.18)))
                    .overlay(Capsule().stroke(Color.white.opacity(0.12)))

                    Spacer()

                    likesPill

                    if item.state == "planned" {
                        HStack(spacing: 4) {
                            Image(systemName: "pencil")
                            Text("Draft")
                        }
                        .font(.caption2.weight(.semibold))
                        .padding(.vertical, 3)
                        .padding(.horizontal, 6)
                        .background(Capsule().fill(Color.yellow.opacity(0.22)))
                        .overlay(Capsule().stroke(Color.white.opacity(0.12)))
                    }
                }
            }
            .opacity(item.state == "planned" ? 0.72 : 1.0)
            .padding(14)
        }
    }

    private var likesPill: some View {
        HStack(spacing: 6) {
            Image(systemName: item.isLiked ? "heart.fill" : "heart")
                .symbolRenderingMode(.palette)
                .foregroundStyle(item.isLiked ? .red : .secondary)
            Text("\(item.likeCount)")
                .font(.subheadline.weight(.semibold))
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.18)))
    }

    private func sportIcon(for sport: String) -> String {
        switch sport {
        case "padel", "tennis", "squash", "badminton", "table_tennis":
            return "🎾"
        case "football":
            return "⚽️"
        case "basketball":
            return "🏀"
        case "volleyball":
            return "🏐"
        case "running":
            return "🏃‍♂️"
        case "cycling":
            return "🚴‍♂️"
        case "rugby":
            return "🏉"
        case "hockey", "field_hockey":
            return "🏑"
        case "ice_hockey":
            return "🏒"
        case "handball":
            return "🤾‍♂️"
        case "hyrox":
            return "🔥"
        default:
            return ""
        }
    }

    private func cardioIcon(for activity: String?) -> String {
        switch (activity ?? "").lowercased() {
        case "run", "outdoor_run", "trail_run": return "🏃‍♂️"
        case "treadmill":                       return "🏃‍♀️"
        case "walk", "hike":                    return "🚶‍♂️"
        case "cycling", "road_cycling":         return "🚴‍♂️"
        case "indoor_cycling", "spinning":      return "🚲"
        case "rowerg", "rowing":                return "🚣‍♂️"
        case "ski_erg":                         return "⛷️"
        case "elliptical":                      return "🌀"
        case "stairs", "stairmaster":           return "🪜"
        case "swim_pool":                       return "🏊‍♂️"
        case "swim_open_water":                 return "🌊"
        default:                                return "❤️‍🔥"
        }
    }

    private func relativeDate(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: d, relativeTo: Date())
    }
}
