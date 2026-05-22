import SwiftUI
import UIKit

struct HomeFloatingDockOverlay: View {
    @EnvironmentObject var app: AppState

    let bottomSafeInset: CGFloat
    let showChat: Bool
    let quickStartBusyKind: WorkoutKind?
    let onQuickStrength: () -> Void
    let onQuickCardio: () -> Void
    let onQuickSport: () -> Void
    let onQuickSignInRequired: () -> Void

    @AppStorage("chatFabEdge") private var chatEdgeRaw = ""
    @AppStorage("chatFabPosition") private var chatPosition = -1.0
    @AppStorage("chatFabCorner") private var chatCornerRaw = "bottomLeading"
    @AppStorage("chatFabDragHintSeen") private var chatDragHintSeen = false

    @AppStorage("homeQuickActionsHintDismissed") private var quickHintDismissed = false
    @AppStorage("homeQuickActionsEdge") private var quickEdgeRaw = HomeFloatingDockEdge.right.rawValue
    @AppStorage("homeQuickActionsPosition") private var quickPosition = 0.64

    @AppStorage("homeFloatingDockMerged") private var dockMerged = false
    @AppStorage("homeFloatingDockMergedEdge") private var mergedEdgeRaw = HomeFloatingDockEdge.right.rawValue
    @AppStorage("homeFloatingDockMergedPosition") private var mergedPosition = 0.64

    @State private var showQuickMenu = false
    @State private var showMergedMenu = false
    @State private var presentInbox = false
    @State private var chatDragLocation: CGPoint?
    @State private var quickDragLocation: CGPoint?
    @State private var mergedDragLocation: CGPoint?
    @State private var chatDidDrag = false
    @State private var quickDidDrag = false
    @State private var mergedDidDrag = false

    private let chatTabSize = CGSize(width: 56, height: 56)
    private let quickTabSize = CGSize(width: 56, height: 52)
    private let mergedTabSize = CGSize(width: 72, height: 52)

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            if dockMerged && showChat {
                mergedOverlay(in: size)
            } else {
                separatedOverlay(in: size)
            }
        }
        .onAppear { migrateChatDockIfNeeded() }
        .onChange(of: showChat) { _, visible in
            if !visible && dockMerged { unmerge() }
        }
        .fullScreenCover(isPresented: $presentInbox) {
            MessagesInboxView()
                .gradientBG()
                .environmentObject(app)
        }
        .onChange(of: presentInbox) { _, isShown in
            if isShown { chatDragHintSeen = true }
            if !isShown { Task { await app.refreshUnreadChatMessagesCount() } }
        }
    }

    @ViewBuilder
    private func separatedOverlay(in size: CGSize) -> some View {
        let chatPoint = chatDragLocation ?? chatAnchor(in: size)
        let quickPoint = quickDragLocation ?? quickAnchor(in: size)

        ZStack(alignment: .topLeading) {
            if showQuickMenu {
                dismissScrim { withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { showQuickMenu = false } }
                quickOnlyMenu
                    .position(HomeFloatingDock.menuPoint(
                        anchor: quickPoint,
                        edge: quickEdge,
                        menuSize: CGSize(width: 158, height: 188),
                        in: size
                    ))
                    .zIndex(2)
            }

            if !quickHintDismissed && !showQuickMenu && quickStartBusyKind == nil {
                quickTooltip
                    .position(HomeFloatingDock.tooltipPoint(
                        anchor: quickPoint,
                        edge: quickEdge,
                        tooltipSize: CGSize(width: 210, height: 44),
                        in: size
                    ))
                    .zIndex(1)
            }

            if showChat && !chatDragHintSeen {
                chatDragHint
                    .position(chatHintPoint(anchor: chatPoint, in: size))
                    .zIndex(1)
            }

            if showChat {
                chatButton
                    .position(chatPoint)
                    .zIndex(3)
                    .simultaneousGesture(chatDragGesture(in: size, otherAnchor: quickPoint))
            }

            quickButton(in: size)
                .position(quickPoint)
                .zIndex(4)
                .simultaneousGesture(quickDragGesture(in: size, otherAnchor: chatPoint))
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: showQuickMenu)
        .coordinateSpace(name: "homeFloatingDock")
    }

    @ViewBuilder
    private func mergedOverlay(in size: CGSize) -> some View {
        let point = mergedDragLocation ?? mergedAnchor(in: size)
        let edge = mergedEdge

        ZStack(alignment: .topLeading) {
            if showMergedMenu {
                dismissScrim { withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { showMergedMenu = false } }
                mergedMenu
                    .position(HomeFloatingDock.menuPoint(
                        anchor: point,
                        edge: edge,
                        menuSize: CGSize(width: 158, height: 300),
                        in: size
                    ))
                    .zIndex(2)
            }

            mergedButton
                .position(point)
                .zIndex(3)
                .simultaneousGesture(mergedDragGesture(in: size))
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: showMergedMenu)
        .coordinateSpace(name: "homeFloatingDock")
    }

    private var chatEdge: HomeFloatingDockEdge {
        if let edge = HomeFloatingDockEdge(rawValue: chatEdgeRaw) { return edge }
        return migratedChatEdge()
    }

    private var quickEdge: HomeFloatingDockEdge {
        HomeFloatingDockEdge(rawValue: quickEdgeRaw) ?? .right
    }

    private var mergedEdge: HomeFloatingDockEdge {
        HomeFloatingDockEdge(rawValue: mergedEdgeRaw) ?? .right
    }

    private var chatPositionValue: Double {
        if chatPosition >= 0 { return min(max(chatPosition, 0), 1) }
        return migratedChatPosition()
    }

    private func chatAnchor(in size: CGSize) -> CGPoint {
        HomeFloatingDock.anchorPoint(
            edge: chatEdge,
            position: chatPositionValue,
            in: size,
            tabSize: chatTabSize,
            bottomSafeInset: bottomSafeInset
        )
    }

    private func quickAnchor(in size: CGSize) -> CGPoint {
        HomeFloatingDock.anchorPoint(
            edge: quickEdge,
            position: min(max(quickPosition, 0), 1),
            in: size,
            tabSize: quickTabSize,
            bottomSafeInset: bottomSafeInset
        )
    }

    private func mergedAnchor(in size: CGSize) -> CGPoint {
        HomeFloatingDock.anchorPoint(
            edge: mergedEdge,
            position: min(max(mergedPosition, 0), 1),
            in: size,
            tabSize: mergedTabSize,
            bottomSafeInset: bottomSafeInset
        )
    }

    private func migrateChatDockIfNeeded() {
        guard chatEdgeRaw.isEmpty else { return }
        chatEdgeRaw = migratedChatEdge().rawValue
        chatPosition = migratedChatPosition()
    }

    private func migratedChatEdge() -> HomeFloatingDockEdge {
        switch chatCornerRaw {
        case "bottomLeading", "topLeading": return .left
        default: return .right
        }
    }

    private func migratedChatPosition() -> Double {
        switch chatCornerRaw {
        case "bottomLeading", "bottomTrailing": return 1.0
        default: return 0.0
        }
    }

    private func chatHintPoint(anchor: CGPoint, in size: CGSize) -> CGPoint {
        let bubbleSize = CGSize(width: 210, height: 96)
        let spacing: CGFloat = 70
        let raw: CGPoint
        switch chatEdge {
        case .left: raw = CGPoint(x: anchor.x + spacing, y: anchor.y)
        case .right: raw = CGPoint(x: anchor.x - spacing, y: anchor.y)
        case .top: raw = CGPoint(x: anchor.x, y: anchor.y + 58)
        case .bottom: raw = CGPoint(x: anchor.x, y: anchor.y - 58)
        }
        return CGPoint(
            x: min(max(raw.x, bubbleSize.width / 2 + 12), size.width - bubbleSize.width / 2 - 12),
            y: min(max(raw.y, bubbleSize.height / 2 + 12), size.height - bubbleSize.height / 2 - 12)
        )
    }

    private func chatDragGesture(in size: CGSize, otherAnchor: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .named("homeFloatingDock"))
            .onChanged { value in
                chatDidDrag = true
                showQuickMenu = false
                showMergedMenu = false
                if !chatDragHintSeen { chatDragHintSeen = true }
                chatDragLocation = value.location
            }
            .onEnded { value in
                let dock = HomeFloatingDock.dock(
                    for: value.location,
                    in: size,
                    tabSize: chatTabSize,
                    bottomSafeInset: bottomSafeInset
                )
                let anchor = HomeFloatingDock.anchorPoint(
                    edge: dock.edge,
                    position: dock.position,
                    in: size,
                    tabSize: chatTabSize,
                    bottomSafeInset: bottomSafeInset
                )
                if showChat && HomeFloatingDock.shouldMerge(anchor, otherAnchor) {
                    applyMerge(edge: dock.edge, position: dock.position)
                } else {
                    chatEdgeRaw = dock.edge.rawValue
                    chatPosition = dock.position
                }
                chatDragLocation = nil
            }
    }

    private func quickDragGesture(in size: CGSize, otherAnchor: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .named("homeFloatingDock"))
            .onChanged { value in
                quickDidDrag = true
                showQuickMenu = false
                if !quickHintDismissed { quickHintDismissed = true }
                quickDragLocation = value.location
            }
            .onEnded { value in
                let dock = HomeFloatingDock.dock(
                    for: value.location,
                    in: size,
                    tabSize: quickTabSize,
                    bottomSafeInset: bottomSafeInset
                )
                let anchor = HomeFloatingDock.anchorPoint(
                    edge: dock.edge,
                    position: dock.position,
                    in: size,
                    tabSize: quickTabSize,
                    bottomSafeInset: bottomSafeInset
                )
                if showChat && HomeFloatingDock.shouldMerge(anchor, otherAnchor) {
                    applyMerge(edge: dock.edge, position: dock.position)
                } else {
                    quickEdgeRaw = dock.edge.rawValue
                    quickPosition = dock.position
                }
                quickDragLocation = nil
                quickHintDismissed = true
            }
    }

    private func mergedDragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .named("homeFloatingDock"))
            .onChanged { value in
                mergedDidDrag = true
                showMergedMenu = false
                mergedDragLocation = value.location
            }
            .onEnded { value in
                let dock = HomeFloatingDock.dock(
                    for: value.location,
                    in: size,
                    tabSize: mergedTabSize,
                    bottomSafeInset: bottomSafeInset
                )
                mergedEdgeRaw = dock.edge.rawValue
                mergedPosition = dock.position
                mergedDragLocation = nil
            }
    }

    private func applyMerge(edge: HomeFloatingDockEdge, position: Double) {
        mergedEdgeRaw = edge.rawValue
        mergedPosition = position
        chatEdgeRaw = edge.rawValue
        chatPosition = position
        quickEdgeRaw = edge.rawValue
        quickPosition = position
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            dockMerged = true
            showQuickMenu = false
        }
        triggerMergeHaptic()
    }

    private func unmerge() {
        let split = HomeFloatingDock.unmergePositions(edge: mergedEdge, mergedPosition: mergedPosition)
        chatEdgeRaw = split.chat.0.rawValue
        chatPosition = split.chat.1
        quickEdgeRaw = split.quick.0.rawValue
        quickPosition = split.quick.1
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            dockMerged = false
            showMergedMenu = false
        }
    }

    private func triggerMergeHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
    }

    @ViewBuilder
    private func dismissScrim(onTap: @escaping () -> Void) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .ignoresSafeArea()
            .onTapGesture(perform: onTap)
    }

    @ViewBuilder
    private var chatButton: some View {
        ZStack(alignment: .topTrailing) {
            Button {
                guard !chatDidDrag else {
                    chatDidDrag = false
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
                unreadBadge
            }
        }
    }

    @ViewBuilder
    private func quickButton(in size: CGSize) -> some View {
        Button {
            guard !quickDidDrag else {
                quickDidDrag = false
                return
            }
            if app.userId == nil {
                onQuickSignInRequired()
            } else {
                quickHintDismissed = true
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    showQuickMenu.toggle()
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.yellow)
                if quickStartBusyKind != nil {
                    ProgressView()
                        .tint(.primary)
                        .scaleEffect(0.8)
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 10)
            .frame(width: quickTabSize.width, height: quickTabSize.height)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.white.opacity(0.22), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
        .disabled(quickStartBusyKind != nil)
        .accessibilityLabel("Quick actions")
    }

    @ViewBuilder
    private var mergedButton: some View {
        Button {
            guard !mergedDidDrag else {
                mergedDidDrag = false
                return
            }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                showMergedMenu.toggle()
            }
        } label: {
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: mergedTabSize.height)
                        .background(Color.accentColor)

                    Image(systemName: "bolt.fill")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.yellow)
                        .frame(width: 36, height: mergedTabSize.height)
                        .background(.ultraThinMaterial)
                }
                .frame(width: mergedTabSize.width, height: mergedTabSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(.white.opacity(0.22), lineWidth: 0.8)
                )

                if app.unreadChatMessagesCount > 0 {
                    unreadBadge
                        .offset(x: 22, y: -4)
                }

                if quickStartBusyKind != nil {
                    ProgressView()
                        .tint(.primary)
                        .scaleEffect(0.7)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                        .padding(.trailing, 8)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Messages and quick actions")
    }

    @ViewBuilder
    private var unreadBadge: some View {
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

    @ViewBuilder
    private var chatDragHint: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Drag the messages button to any side of the screen."))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                chatDragHintSeen = true
            } label: {
                Text(String(localized: "Got it"))
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: 280, alignment: .leading)
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 6)
    }

    @ViewBuilder
    private var quickTooltip: some View {
        HStack(spacing: 8) {
            Text("Start a workout from here")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Button("Got it") { quickHintDismissed = true }
                .font(.caption.weight(.bold))
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.22), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)
    }

    @ViewBuilder
    private var quickOnlyMenu: some View {
        VStack(spacing: 8) {
            Text("Quick actions")
                .font(.subheadline.weight(.semibold))
                .padding(.bottom, 2)
            quickMenuButton("Strength", action: onQuickStrength)
            quickMenuButton("Cardio", action: onQuickCardio)
            quickMenuButton("Sport", action: onQuickSport)
        }
        .padding(12)
        .frame(width: 158)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.22), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 8)
    }

    @ViewBuilder
    private var mergedMenu: some View {
        VStack(spacing: 8) {
            Button {
                showMergedMenu = false
                presentInbox = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "paperplane.fill")
                        .font(.body.weight(.semibold))
                    Text(String(localized: "Messages"))
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                    if app.unreadChatMessagesCount > 0 {
                        Text(app.unreadChatMessagesCount > 99 ? "99+" : "\(app.unreadChatMessagesCount)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red, in: Capsule())
                    }
                }
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .padding(.horizontal, 12)
                .background(.thinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)

            Divider().opacity(0.35)

            Text("Quick actions")
                .font(.subheadline.weight(.semibold))
                .padding(.bottom, 2)
            quickMenuButton("Strength", action: onQuickStrength)
            quickMenuButton("Cardio", action: onQuickCardio)
            quickMenuButton("Sport", action: onQuickSport)

            Divider().opacity(0.35)

            Button {
                unmerge()
            } label: {
                Text(String(localized: "Separate buttons"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(width: 158)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.22), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 8)
    }

    @ViewBuilder
    private func quickMenuButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            showQuickMenu = false
            showMergedMenu = false
            action()
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(.thinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(quickStartBusyKind != nil)
    }
}
