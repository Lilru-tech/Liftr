import SwiftUI

private let profilePetOverlayCoordinateSpace = "profilePetOverlay"

struct ProfilePetFloatingOverlay: View {
    let bannerInset: CGFloat

    @StateObject private var viewModel = PetDetailViewModel()
    @State private var showPetDetail = false
    @State private var showGreeting = false
    @State private var greetingMessage = ""
    @State private var perimeterT: CGFloat?
    @State private var dragPreviewPoint: CGPoint?

    private let fabSize: CGFloat = 90
    private let tabBarHeight: CGFloat = 49
    private let edgePadding: CGFloat = 8
    private let tapThreshold: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            if let pet = viewModel.data?.pet {
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
                    saved: perimeterT ?? ProfilePetFabPositionStore.savedPerimeterT(),
                    legacyNormalized: legacyNormalizedCenter(),
                    in: bounds
                )
                let anchor = dragPreviewPoint ?? ProfilePetFabPositionStore.point(onPerimeter: resolvedT, in: bounds)

                VStack(spacing: 8) {
                    if showGreeting {
                        Text(greetingMessage)
                            .font(.subheadline)
                            .padding(8)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                            .shadow(radius: 3)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity.combined(with: .scale))
                    }

                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                        PetAsyncImage(
                            pet: pet,
                            height: fabSize - 20,
                            padding: 10
                        )
                    }
                    .frame(width: fabSize, height: fabSize)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(pet.rarityEnum.color.opacity(0.7), lineWidth: 2)
                    )
                    .shadow(color: pet.rarityEnum.color.opacity(0.35), radius: 6)
                    .contentShape(Circle())
                    .highPriorityGesture(
                        TapGesture().onEnded {
                            showGreeting = false
                            showPetDetail = true
                        }
                    )
                    .gesture(borderDragGesture(bounds: bounds, resolvedT: resolvedT))
                }
                .frame(width: 160)
                .position(x: anchor.x, y: anchor.y)
                .animation(nil, value: anchor)
                .onAppear {
                    if perimeterT == nil {
                        perimeterT = resolvedT
                    }
                }
            }
        }
        .coordinateSpace(name: profilePetOverlayCoordinateSpace)
        .ignoresSafeArea()
        .allowsHitTesting(viewModel.data?.pet != nil)
        .zIndex(999)
        .task { await refreshPet() }
        .onAppear { Task { await refreshPet() } }
        .onReceive(NotificationCenter.default.publisher(for: .petStateDidChange)) { _ in
            Task { await refreshPet() }
        }
        .onDisappear { viewModel.stopPolling() }
        .sheet(isPresented: $showPetDetail, onDismiss: {
            Task { await refreshPet() }
        }) {
            PetDetailView(viewModel: viewModel)
        }
        .onChange(of: viewModel.data?.pet?.id) { _, newId in
            guard newId != nil, !showGreeting else { return }
            greetingMessage = PetProfileGreetings.randomOwnProfileMessage()
            withAnimation { showGreeting = true }
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await MainActor.run {
                    withAnimation { showGreeting = false }
                }
            }
        }
    }

    private func legacyNormalizedCenter() -> CGPoint? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "profilePetFabCenterX") != nil,
              defaults.object(forKey: "profilePetFabCenterY") != nil else {
            return nil
        }
        return CGPoint(
            x: defaults.double(forKey: "profilePetFabCenterX"),
            y: defaults.double(forKey: "profilePetFabCenterY")
        )
    }

    private func borderDragGesture(bounds: ProfilePetFabBounds, resolvedT: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: tapThreshold, coordinateSpace: .named(profilePetOverlayCoordinateSpace))
            .onChanged { value in
                dragPreviewPoint = ProfilePetFabPositionStore.nearestPointOnPerimeter(value.location, in: bounds)
            }
            .onEnded { value in
                dragPreviewPoint = nil
                let snapped = ProfilePetFabPositionStore.nearestPointOnPerimeter(value.location, in: bounds)
                let newT = ProfilePetFabPositionStore.perimeterParameter(for: snapped, in: bounds)
                perimeterT = newT
                ProfilePetFabPositionStore.savePerimeterT(newT)
            }
    }

    private func refreshPet() async {
        await viewModel.load()
        await viewModel.reloadLogs()
        viewModel.startPollingIfNeeded()
    }
}
