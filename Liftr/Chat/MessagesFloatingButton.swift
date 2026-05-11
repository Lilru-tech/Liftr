import SwiftUI

enum FabCorner: String, CaseIterable {
    case bottomLeading
    case bottomTrailing
    case topLeading
    case topTrailing

    var alignment: Alignment {
        switch self {
        case .bottomLeading:  return .bottomLeading
        case .bottomTrailing: return .bottomTrailing
        case .topLeading:     return .topLeading
        case .topTrailing:    return .topTrailing
        }
    }
}

struct MessagesFloatingButton: View {
    @EnvironmentObject var app: AppState
    @AppStorage("chatFabCorner") private var storedCorner: String = FabCorner.bottomLeading.rawValue
    @AppStorage("chatFabDragHintSeen") private var chatFabDragHintSeen = false
    @State private var dragOffset: CGSize = .zero
    @State private var dragging: Bool = false
    @State private var presentInbox: Bool = false
    @State private var unreadTotal: Int = 0
    @State private var deepLinkConversation: DeepLinkPayload?

    private struct DeepLinkPayload: Identifiable, Hashable {
        let id: Int64
        let senderId: UUID?
    }

    var body: some View {
        GeometryReader { geo in
            let corner = FabCorner(rawValue: storedCorner) ?? .bottomLeading
            ZStack {
                ZStack(alignment: cornerAlignment) {
                    Color.clear
                    button
                        .offset(x: dragging ? dragOffset.width : 0,
                                y: dragging ? dragOffset.height : 0)
                        .gesture(
                            DragGesture(minimumDistance: 1)
                                .onChanged { value in
                                    if !chatFabDragHintSeen { chatFabDragHintSeen = true }
                                    dragging = true
                                    dragOffset = value.translation
                                }
                                .onEnded { value in
                                    let dropped = currentDropPoint(geo: geo, drag: value.translation)
                                    let nearest = nearestCorner(for: dropped, in: geo.size)
                                    storedCorner = nearest.rawValue
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                                        dragging = false
                                        dragOffset = .zero
                                    }
                                }
                        )
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                if !chatFabDragHintSeen {
                    fabDragHintBubble(fabCenter: fabAnchorPoint(in: geo.size, corner: corner), containerSize: geo.size)
                }
            }
        }
        .ignoresSafeArea(edges: [])
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
        .task { await refreshUnread() }
        .onChange(of: presentInbox) { _, isShown in
            if isShown { chatFabDragHintSeen = true }
            if !isShown { Task { await refreshUnread() } }
        }
    }

    private var cornerAlignment: Alignment {
        FabCorner(rawValue: storedCorner)?.alignment ?? .bottomLeading
    }

    private func fabAnchorPoint(in size: CGSize, corner: FabCorner) -> CGPoint {
        let pad: CGFloat = 16
        let buttonHalf: CGFloat = 30
        switch corner {
        case .bottomLeading:
            return CGPoint(x: pad + buttonHalf, y: size.height - pad - buttonHalf)
        case .bottomTrailing:
            return CGPoint(x: size.width - pad - buttonHalf, y: size.height - pad - buttonHalf)
        case .topLeading:
            return CGPoint(x: pad + buttonHalf, y: pad + buttonHalf)
        case .topTrailing:
            return CGPoint(x: size.width - pad - buttonHalf, y: pad + buttonHalf)
        }
    }

    private func hintBubbleCenter(from fab: CGPoint, in size: CGSize) -> CGPoint {
        let midX = size.width / 2
        let midY = size.height / 2
        let dx = midX - fab.x
        let dy = midY - fab.y
        let len = max(hypot(dx, dy), 1)
        return CGPoint(x: fab.x + dx / len * 132, y: fab.y + dy / len * 96)
    }

    private func clampedHintBubbleCenter(from fab: CGPoint, in size: CGSize, maxBubbleW: CGFloat) -> CGPoint {
        let edge: CGFloat = 12
        let halfW = min((maxBubbleW + 28) / 2, size.width / 2 - edge - 1)
        let halfH = min(108, size.height / 2 - edge - 1)
        let raw = hintBubbleCenter(from: fab, in: size)
        return CGPoint(
            x: min(max(raw.x, halfW + edge), size.width - halfW - edge),
            y: min(max(raw.y, halfH + edge), size.height - halfH - edge)
        )
    }

    @ViewBuilder
    private func fabDragHintBubble(fabCenter: CGPoint, containerSize: CGSize) -> some View {
        let maxBubbleW = min(268, max(120, containerSize.width - 24))
        let c = clampedHintBubbleCenter(from: fabCenter, in: containerSize, maxBubbleW: maxBubbleW)
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Drag this button to any corner of the screen."))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: maxBubbleW, alignment: .leading)
            Button {
                chatFabDragHintSeen = true
            } label: {
                Text(String(localized: "Got it"))
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 6)
        .position(x: c.x, y: c.y)
        .allowsHitTesting(true)
        .transition(.opacity.combined(with: .scale(scale: 0.94)))
    }

    @ViewBuilder
    private var button: some View {
        ZStack(alignment: .topTrailing) {
            Button {
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

            if unreadTotal > 0 {
                Text(unreadTotal > 99 ? "99+" : "\(unreadTotal)")
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
    
    private func currentDropPoint(geo: GeometryProxy, drag: CGSize) -> CGPoint {
        let anchor = fabAnchorPoint(in: geo.size, corner: FabCorner(rawValue: storedCorner) ?? .bottomLeading)
        return CGPoint(x: anchor.x + drag.width, y: anchor.y + drag.height)
    }

    private func nearestCorner(for point: CGPoint, in size: CGSize) -> FabCorner {
        let isLeft = point.x < size.width / 2
        let isTop  = point.y < size.height / 2
        switch (isTop, isLeft) {
        case (true,  true):  return .topLeading
        case (true,  false): return .topTrailing
        case (false, true):  return .bottomLeading
        case (false, false): return .bottomTrailing
        }
    }

    @MainActor
    private func refreshUnread() async {
        do {
            let list = try await ChatService.fetchConversations(limit: 100)
            self.unreadTotal = list.reduce(0) { $0 + $1.unread_count }
        } catch {
            self.unreadTotal = 0
        }
    }
}
