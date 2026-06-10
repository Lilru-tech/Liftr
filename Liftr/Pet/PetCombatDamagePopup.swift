import SwiftUI

struct PetCombatDamagePopup: View {
    let event: PetCombatPlaybackEngine.PetCombatStrikeEvent

    @State private var offsetY: CGFloat = 4
    @State private var opacity: Double = 0

    var body: some View {
        Text(label)
            .font(.system(size: event.isCritical ? 24 : 18, weight: .heavy, design: .rounded))
            .foregroundStyle(color)
            .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1)
            .offset(y: offsetY)
            .opacity(opacity)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeOut(duration: 0.15)) {
                    opacity = 1
                }
                withAnimation(.easeOut(duration: 0.8)) {
                    offsetY = -34
                }
                withAnimation(.easeIn(duration: 0.3).delay(0.5)) {
                    opacity = 0
                }
            }
    }

    private var label: String {
        if event.isDodged { return "Dodged!" }
        if event.isCritical { return "\(event.damage)!" }
        return "-\(event.damage)"
    }

    private var color: Color {
        if event.isDodged { return Color(red: 0.38, green: 0.55, blue: 0.85) }
        if event.isCritical { return .orange }
        return Color(red: 0.92, green: 0.30, blue: 0.30)
    }
}
