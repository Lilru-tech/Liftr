import SwiftUI

enum PetRarity: String, Codable, CaseIterable, Equatable {
    case common
    case uncommon
    case rare
    case epic
    case legendary
    case mythic

    var displayName: String {
        switch self {
        case .common: return "Common"
        case .uncommon: return "Uncommon"
        case .rare: return "Rare"
        case .epic: return "Epic"
        case .legendary: return "Legendary"
        case .mythic: return "Mythic"
        }
    }

    var color: Color {
        switch self {
        case .common: return Color(hex: "#9CA3AF")
        case .uncommon: return Color(hex: "#22C55E")
        case .rare: return Color(hex: "#3B82F6")
        case .epic: return Color(hex: "#A855F7")
        case .legendary: return Color(hex: "#EF4444")
        case .mythic: return Color(hex: "#F59E0B")
        }
    }

    init?(databaseValue: String?) {
        guard let raw = databaseValue?.lowercased() else { return nil }
        self.init(rawValue: raw)
    }
}

struct PetRarityBadge: View {
    let rarity: PetRarity

    var body: some View {
        Text(rarity.displayName)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(rarity.color.opacity(0.2))
            .foregroundColor(rarity.color)
            .overlay(
                Capsule()
                    .stroke(rarity.color.opacity(0.6), lineWidth: 1)
            )
            .clipShape(Capsule())
    }
}

enum PetImageURLBuilder {
    static func imageURLCandidates(petType: String, evolutionStage: String) -> [URL] {
        let stage = evolutionStage.lowercased() == "elder" ? "elder" : evolutionStage.lowercased()
        let base = SupabaseManager.shared.supabasePublicStorageBase
        var urls: [URL] = []
        if let primary = URL(string: "\(base)/pets/\(petType.lowercased())_\(stage).png") {
            urls.append(primary)
        }
        return urls
    }

    static func imageURL(petType: String, evolutionStage: String) -> URL? {
        imageURLCandidates(petType: petType, evolutionStage: evolutionStage).first
    }

    static func marketItemURL(path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        let base = SupabaseManager.shared.supabasePublicStorageBase
        return URL(string: "\(base)/pets/\(path)")
    }
}

private extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
