import SwiftUI

private enum ChatFabDockEdge: String {
    case left, right, top, bottom
}

private enum LegacyFabCorner: String {
    case bottomLeading
    case bottomTrailing
    case topLeading
    case topTrailing
}

struct MessagesFloatingButton: View {
    @EnvironmentObject var app: AppState
    var bottomSafeInset: CGFloat = 0

    @AppStorage("chatFabEdge") private var storedEdge: String = ""
    @AppStorage("chatFabPosition") private var storedPosition: Double = -1
    @AppStorage("chatFabCorner") private var storedCorner: String = LegacyFabCorner.bottomLeading.rawValue
    @AppStorage("chatFabDragHintSeen") private var chatFabDragHintSeen = false

    @State private var dragLocation: CGPoint?
    @State private var fabDidDrag = false
    @State private var presentInbox: Bool = false
    @State private var deepLinkConversation: DeepLinkPayload?

    private let fabSize = CGSize(width: 56, height: 56)

    private struct DeepLinkPayload: Identifiable, Hashable {
        let id: Int64
        let senderId: UUID?
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let insets = geo.safeAreaInsets
            let maxBubbleW = min(280, max(120, size.width - insets.leading - insets.trailing - 24))
            let edge = fabEdge
            let point = dragLocation ?? fabAnchorPoint(edge: edge, position: fabPosition, in: size)

            ZStack(alignment: .topLeading) {
                Color.clear

                if !chatFabDragHintSeen {
                    fabDragHintBubbleContent(maxWidth: maxBubbleW)
                        .position(fabDragHintPoint(anchor: point, edge: edge, in: size))
                        .zIndex(1)
                }

                button
                    .position(point)
                    .zIndex(2)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 10, coordinateSpace: .named("chatFabOverlay"))
                            .onChanged { value in
                                fabDidDrag = true
                                if !chatFabDragHintSeen { chatFabDragHintSeen = true }
                                dragLocation = value.location
                            }
                            .onEnded { value in
                                let dock = fabDock(for: value.location, in: size)
                                storedEdge = dock.edge.rawValue
                                storedPosition = dock.position
                                dragLocation = nil
                                chatFabDragHintSeen = true
                            }
                    )
            }
            .coordinateSpace(name: "chatFabOverlay")
        }
        .ignoresSafeArea(edges: [])
        .onAppear { migrateFromCornerIfNeeded() }
        .fullScreenCover(isPresented: $presentInbox) {
            MessagesInboxView()
                .gradientBG()
                .environmentObject(app)
        }
        .fullScreenCover(item: $deepLinkConversation) { payload in
            NavigationStack {
                DeepLinkedChatThread(conversationId: payload.id,
                                     senderId: payload.senderId)
                    .environmentObject(app)
            }
            .gradientBG()
        }
        .onChange(of: presentInbox) { _, isShown in
            if isShown { chatFabDragHintSeen = true }
            if !isShown { Task { await app.refreshUnreadChatMessagesCount() } }
        }
    }

    private var fabEdge: ChatFabDockEdge {
        if let edge = ChatFabDockEdge(rawValue: storedEdge) {
            return edge
        }
        return migratedEdgeFromCorner()
    }

    private var fabPosition: Double {
        if storedPosition >= 0 {
            return min(max(storedPosition, 0), 1)
        }
        return migratedPositionFromCorner()
    }

    private func migrateFromCornerIfNeeded() {
        guard storedEdge.isEmpty else { return }
        let edge = migratedEdgeFromCorner()
        let position = migratedPositionFromCorner()
        storedEdge = edge.rawValue
        storedPosition = position
    }

    private func migratedEdgeFromCorner() -> ChatFabDockEdge {
        switch LegacyFabCorner(rawValue: storedCorner) ?? .bottomLeading {
        case .bottomLeading: return .left
        case .bottomTrailing: return .right
        case .topLeading: return .left
        case .topTrailing: return .right
        }
    }

    private func migratedPositionFromCorner() -> Double {
        switch LegacyFabCorner(rawValue: storedCorner) ?? .bottomLeading {
        case .bottomLeading, .bottomTrailing: return 1.0
        case .topLeading, .topTrailing: return 0.0
        }
    }

    private func fabAnchorPoint(
        edge: ChatFabDockEdge,
        position: Double,
        in size: CGSize
    ) -> CGPoint {
        let minX = fabSize.width / 2
        let maxX = max(minX, size.width - fabSize.width / 2)
        let minY = fabSize.height / 2 + 10
        let maxY = max(minY, size.height - fabSize.height / 2 - bottomSafeInset)
        let fraction = min(max(position, 0), 1)

        switch edge {
        case .left:
            return CGPoint(x: minX, y: minY + (maxY - minY) * fraction)
        case .right:
            return CGPoint(x: maxX, y: minY + (maxY - minY) * fraction)
        case .top:
            return CGPoint(x: minX + (maxX - minX) * fraction, y: minY)
        case .bottom:
            return CGPoint(x: minX + (maxX - minX) * fraction, y: maxY)
        }
    }

    private func fabDock(
        for point: CGPoint,
        in size: CGSize
    ) -> (edge: ChatFabDockEdge, position: Double) {
        let minX = fabSize.width / 2
        let maxX = max(minX, size.width - fabSize.width / 2)
        let minY = fabSize.height / 2 + 10
        let maxY = max(minY, size.height - fabSize.height / 2 - bottomSafeInset)
        let distances: [(ChatFabDockEdge, CGFloat)] = [
            (.left, abs(point.x - minX)),
            (.right, abs(point.x - maxX)),
            (.top, abs(point.y - minY)),
            (.bottom, abs(point.y - maxY))
        ]
        let edge = distances.min { $0.1 < $1.1 }?.0 ?? .right

        switch edge {
        case .left, .right:
            let ratio = (point.y - minY) / max(maxY - minY, 1)
            return (edge, Double(min(max(ratio, 0), 1)))
        case .top, .bottom:
            let ratio = (point.x - minX) / max(maxX - minX, 1)
            return (edge, Double(min(max(ratio, 0), 1)))
        }
    }

    private func fabDragHintPoint(
        anchor: CGPoint,
        edge: ChatFabDockEdge,
        in size: CGSize
    ) -> CGPoint {
        let bubbleSize = CGSize(width: 210, height: 96)
        let spacing: CGFloat = 70
        let raw: CGPoint

        switch edge {
        case .left:
            raw = CGPoint(x: anchor.x + spacing, y: anchor.y)
        case .right:
            raw = CGPoint(x: anchor.x - spacing, y: anchor.y)
        case .top:
            raw = CGPoint(x: anchor.x, y: anchor.y + 58)
        case .bottom:
            raw = CGPoint(x: anchor.x, y: anchor.y - 58)
        }

        return CGPoint(
            x: min(max(raw.x, bubbleSize.width / 2 + 12), size.width - bubbleSize.width / 2 - 12),
            y: min(max(raw.y, bubbleSize.height / 2 + 12), size.height - bubbleSize.height / 2 - 12)
        )
    }

    @ViewBuilder
    private func fabDragHintBubbleContent(maxWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Drag the messages button to any side of the screen."))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: maxWidth, alignment: .leading)
            Button {
                chatFabDragHintSeen = true
            } label: {
                Text(String(localized: "Got it"))
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: maxWidth, alignment: .leading)
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 6)
        .allowsHitTesting(true)
        .transition(.opacity.combined(with: .scale(scale: 0.94)))
    }

    @ViewBuilder
    private var button: some View {
        ZStack(alignment: .topTrailing) {
            Button {
                guard !fabDidDrag else {
                    fabDidDrag = false
                    return
                }
                presentInbox = true
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(14)
                    .background(
                        Circle()
                            .fill(Color.accentColor)
                            .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 3)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open messages")

            if app.unreadChatMessagesCount > 0 {
                Text(app.unreadChatMessagesCount > 99 ? "99+" : "\(app.unreadChatMessagesCount)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red, in: Capsule())
                    .overlay(Capsule().stroke(.white, lineWidth: 1.5))
                    .offset(x: 6, y: -4)
                    .allowsHitTesting(false)
            }
        }
    }
}
