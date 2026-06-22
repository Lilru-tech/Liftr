import SwiftUI

struct PetCombatUnbalancedMatchDialog: View {
    @Binding var isPresented: Bool
    @Binding var dontShowAgain: Bool
    let isUnderdog: Bool
    @Binding var selectedMode: PetCombatChallengeMode
    let hardcoreBonusLabel: String?
    let onCancel: () -> Void
    let onFight: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }

            VStack(alignment: .leading, spacing: 16) {
                Text("Unbalanced Match Detected!")
                    .font(.headline)

                if isUnderdog {
                    Text("Choose how you want to face this stronger opponent. Handicap battles won't affect your competitive record.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Picker("Challenge mode", selection: $selectedMode) {
                        ForEach(PetCombatChallengeMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(modeDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("There is a massive stat difference. Your pet will be temporarily nerfed for this battle, and winning yields minimum rewards. This fight won't count toward your competitive record.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Toggle("Don't show this warning again", isOn: $dontShowAgain)
                        .font(.subheadline)
                }

                HStack(spacing: 12) {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)

                    Button("Fight!", action: onFight)
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
            .padding(.horizontal, 28)
        }
    }

    private var modeDescription: String {
        switch selectedMode {
        case .balanced:
            return "Balanced Mode rebalances stats for a near-even fight. Normal handicap reward rules apply."
        case .hardcore:
            if let hardcoreBonusLabel {
                return "Hardcore Mode keeps the opponent at full stats. Winning grants a dynamically scaled bonus (\(hardcoreBonusLabel))."
            }
            return "Hardcore Mode keeps the opponent at full stats. Winning grants a dynamically scaled bonus based on the stat gap."
        }
    }
}
