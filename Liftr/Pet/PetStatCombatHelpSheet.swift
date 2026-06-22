import SwiftUI

struct PetStatCombatHelpEntry: Identifiable {
    let name: String
    let effect: String

    var id: String { name }
}

enum PetStatCombatGuide {
    static let intro = "Every stat affects arena battles. Winning earns the biggest rewards, but losing still grants a small consolation reward."
    static let handicapTitle = "Stat Balancing (Handicap)"
    static let handicapDescription = "If a pet's total stats are significantly higher than the opponent, their combat stats are temporarily rebalanced for a near-even fight. Both pets use their full health stat as arena HP. Winning after being rebalanced yields minimum rewards."
    static let handicapBattlesTitle = "Handicap Battles"
    static let handicapBattlesDescription = "Fights featuring a stat gap greater than 5% will not affect your permanent Win/Loss profile record."
    static let hardcoreChallengeTitle = "Hardcore Challenge"
    static let hardcoreChallengeDescription = "As an underdog, you can choose to face un-nerfed opponents to unlock dynamically scaled massive reward multipliers based on the difficulty gap."
    static let footer = "Higher stats help more. Pet type weights which stats grow fastest on level-up. At the same level and rarity, production archetypes are tuned for close matchups."

    static let entries: [PetStatCombatHelpEntry] = [
        PetStatCombatHelpEntry(name: "Health", effect: "Your pet's max HP in the arena."),
        PetStatCombatHelpEntry(name: "Strength", effect: "Base damage dealt with each strike."),
        PetStatCombatHelpEntry(name: "Defense", effect: "Reduces damage taken, together with resistance."),
        PetStatCombatHelpEntry(name: "Resistance", effect: "Reduces damage taken, together with defense."),
        PetStatCombatHelpEntry(name: "Speed", effect: "Attacks first each round."),
        PetStatCombatHelpEntry(name: "Agility", effect: "Chance to dodge attacks (3–28%). Adds to strike damage. Breaks speed ties for turn order."),
        PetStatCombatHelpEntry(name: "Intelligence", effect: "Lowers enemy dodge chance, boosts critical hit damage, and adds to strike damage."),
        PetStatCombatHelpEntry(name: "Critical rate", effect: "Chance to land a critical hit."),
        PetStatCombatHelpEntry(name: "Stamina", effect: "Slows fatigue in long fights after round 12."),
        PetStatCombatHelpEntry(name: "Exploration", effect: "Small bonus on your first strike of the battle."),
        PetStatCombatHelpEntry(name: "Happiness", effect: "More consistent damage with a higher minimum roll.")
    ]
}

struct PetStatCombatHelpSheet: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Arena stats")
                        .font(.title2.weight(.semibold))

                    Text(PetStatCombatGuide.intro)
                        .font(.body)
                        .foregroundStyle(.secondary)

                    handicapSection

                    rulesSection(title: PetStatCombatGuide.handicapBattlesTitle, description: PetStatCombatGuide.handicapBattlesDescription)
                    rulesSection(title: PetStatCombatGuide.hardcoreChallengeTitle, description: PetStatCombatGuide.hardcoreChallengeDescription)

                    ForEach(PetStatCombatGuide.entries) { entry in
                        statRow(entry)
                    }

                    Text(PetStatCombatGuide.footer)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
            .padding(18)
            .navigationBarTitleDisplayMode(.inline)
        }
        .gradientBG()
    }

    @ViewBuilder
    private var handicapSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(PetStatCombatGuide.handicapTitle)
                .font(.subheadline.weight(.semibold))
            Text(PetStatCombatGuide.handicapDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func rulesSection(title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func statRow(_ entry: PetStatCombatHelpEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.name)
                .font(.subheadline.weight(.semibold))
            Text(entry.effect)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct PetStatCombatHelpButton: View {
    var body: some View {
        Image(systemName: "info.circle")
            .font(.body)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Arena stat guide")
    }
}
