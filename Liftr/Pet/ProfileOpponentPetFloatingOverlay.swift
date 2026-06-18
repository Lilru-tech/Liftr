import SwiftUI

private let profileOpponentPetOverlayCoordinateSpace = "profileOpponentPetOverlay"

enum ProfileOpponentPetFabPositionStore {
    private static let perimeterKey = "profileOpponentPetFabPerimeterT"

    static func savedPerimeterT() -> CGFloat? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: perimeterKey) != nil else { return nil }
        let t = defaults.double(forKey: perimeterKey)
        guard t >= 0, t <= 1 else { return nil }
        return CGFloat(t)
    }

    static func savePerimeterT(_ t: CGFloat) {
        let clamped = min(1, max(0, t))
        UserDefaults.standard.set(Double(clamped), forKey: perimeterKey)
    }
}

struct ProfileOpponentPetFloatingOverlay: View {
    let preview: PetCombatPreview
    let defenderPet: PetCombatPetSummary
    let headToHead: PetCombatHeadToHeadSummary?
    let opponentUsername: String?
    let bannerInset: CGFloat
    let onChallenge: (Bool) -> Void

    @State private var showChallengeSheet = false
    @State private var perimeterT: CGFloat?
    @State private var dragPreviewPoint: CGPoint?

    private let fabSize: CGFloat = 90
    private let tabBarHeight: CGFloat = 49
    private let edgePadding: CGFloat = 8
    private let tapThreshold: CGFloat = 10

    private var rarity: PetRarity {
        PetRarity(databaseValue: defenderPet.rarity) ?? .common
    }

    var body: some View {
        GeometryReader { geo in
            let bounds = ProfilePetFabPositionStore.bounds(
                in: geo.size,
                safeAreaTop: geo.safeAreaInsets.top,
                safeAreaBottom: geo.safeAreaInsets.bottom,
                tabBarHeight: tabBarHeight,
                bannerInset: bannerInset,
                fabRadius: fabSize / 2,
                padding: edgePadding
            )
            let resolvedT = ProfilePetFabPositionStore.resolvedPerimeterT(
                saved: perimeterT ?? ProfileOpponentPetFabPositionStore.savedPerimeterT(),
                legacyNormalized: nil,
                in: bounds
            )
            let anchor = dragPreviewPoint ?? ProfilePetFabPositionStore.point(onPerimeter: resolvedT, in: bounds)

            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                PetCombatSummaryImage(
                    pet: defenderPet,
                    height: fabSize - 20,
                    padding: 10
                )
            }
            .frame(width: fabSize, height: fabSize)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(rarity.color.opacity(0.7), lineWidth: 2)
            )
            .shadow(color: rarity.color.opacity(0.35), radius: 6)
            .contentShape(Circle())
            .highPriorityGesture(
                TapGesture().onEnded {
                    showChallengeSheet = true
                }
            )
            .gesture(borderDragGesture(bounds: bounds, resolvedT: resolvedT))
            .position(x: anchor.x, y: anchor.y)
            .animation(nil, value: anchor)
            .onAppear {
                if perimeterT == nil {
                    perimeterT = resolvedT
                }
            }
        }
        .coordinateSpace(name: profileOpponentPetOverlayCoordinateSpace)
        .ignoresSafeArea()
        .zIndex(999)
        .sheet(isPresented: $showChallengeSheet) {
            OpponentPetChallengeSheet(
                preview: preview,
                defenderPet: defenderPet,
                headToHead: headToHead,
                opponentUsername: opponentUsername,
                onChallenge: onChallenge
            )
        }
    }

    private func borderDragGesture(bounds: ProfilePetFabBounds, resolvedT: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: tapThreshold, coordinateSpace: .named(profileOpponentPetOverlayCoordinateSpace))
            .onChanged { value in
                dragPreviewPoint = ProfilePetFabPositionStore.nearestPointOnPerimeter(value.location, in: bounds)
            }
            .onEnded { value in
                dragPreviewPoint = nil
                let snapped = ProfilePetFabPositionStore.nearestPointOnPerimeter(value.location, in: bounds)
                let newT = ProfilePetFabPositionStore.perimeterParameter(for: snapped, in: bounds)
                perimeterT = newT
                ProfileOpponentPetFabPositionStore.savePerimeterT(newT)
            }
    }
}
