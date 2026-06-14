import CoreGraphics
import Foundation

enum HomeFloatingDockEdge: String, CaseIterable {
    case left, right, top, bottom
}

enum HomeFloatingDock {
    static let mergeThresholdPx: CGFloat = 56
    static let unmergeOffset: Double = 0.08

    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    static func shouldMerge(
        _ a: CGPoint,
        _ b: CGPoint,
        thresholdPx: CGFloat = mergeThresholdPx
    ) -> Bool {
        distance(a, b) < thresholdPx
    }

    static func unmergePositions(
        edge: HomeFloatingDockEdge,
        mergedPosition: Double,
        offset: Double = unmergeOffset
    ) -> (chat: (HomeFloatingDockEdge, Double), quick: (HomeFloatingDockEdge, Double)) {
        let merged = min(max(mergedPosition, 0), 1)
        let chatPos = min(max(merged - offset, 0), 1)
        let quickPos = min(max(merged + offset, 0), 1)
        return ((edge, chatPos), (edge, quickPos))
    }

    static func anchorPoint(
        edge: HomeFloatingDockEdge,
        position: Double,
        in size: CGSize,
        tabSize: CGSize,
        bottomSafeInset: CGFloat
    ) -> CGPoint {
        let minX = tabSize.width / 2
        let maxX = max(minX, size.width - tabSize.width / 2)
        let minY = tabSize.height / 2 + 10
        let maxY = max(minY, size.height - tabSize.height / 2 - bottomSafeInset)
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

    static func dock(
        for point: CGPoint,
        in size: CGSize,
        tabSize: CGSize,
        bottomSafeInset: CGFloat
    ) -> (edge: HomeFloatingDockEdge, position: Double) {
        let minX = tabSize.width / 2
        let maxX = max(minX, size.width - tabSize.width / 2)
        let minY = tabSize.height / 2 + 10
        let maxY = max(minY, size.height - tabSize.height / 2 - bottomSafeInset)
        let distances: [(HomeFloatingDockEdge, CGFloat)] = [
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

    static func menuPoint(
        anchor: CGPoint,
        edge: HomeFloatingDockEdge,
        menuSize: CGSize,
        in size: CGSize,
        spacing: CGFloat = 92
    ) -> CGPoint {
        let raw: CGPoint
        switch edge {
        case .left:
            raw = CGPoint(x: anchor.x + spacing, y: anchor.y)
        case .right:
            raw = CGPoint(x: anchor.x - spacing, y: anchor.y)
        case .top:
            raw = CGPoint(x: anchor.x, y: anchor.y + spacing + 8)
        case .bottom:
            raw = CGPoint(x: anchor.x, y: anchor.y - spacing - 8)
        }

        return CGPoint(
            x: min(max(raw.x, menuSize.width / 2 + 12), size.width - menuSize.width / 2 - 12),
            y: min(max(raw.y, menuSize.height / 2 + 12), size.height - menuSize.height / 2 - 12)
        )
    }

    static func tooltipPoint(
        anchor: CGPoint,
        edge: HomeFloatingDockEdge,
        tooltipSize: CGSize,
        in size: CGSize,
        spacing: CGFloat = 134
    ) -> CGPoint {
        let origin = bubbleOrigin(
            anchor: anchor,
            edge: edge,
            bubbleSize: tooltipSize,
            tabSize: CGSize(width: 56, height: 56),
            in: size,
            spacing: spacing
        )
        return CGPoint(
            x: origin.x + tooltipSize.width / 2,
            y: origin.y + tooltipSize.height / 2
        )
    }

    static func bubbleOrigin(
        anchor: CGPoint,
        edge: HomeFloatingDockEdge,
        bubbleSize: CGSize,
        tabSize: CGSize,
        in screen: CGSize,
        spacing: CGFloat,
        margin: CGFloat = 12
    ) -> CGPoint {
        let tabHalfW = tabSize.width / 2
        let tabHalfH = tabSize.height / 2
        let raw: CGPoint

        switch edge {
        case .left:
            raw = CGPoint(
                x: anchor.x + tabHalfW + spacing,
                y: anchor.y - bubbleSize.height / 2
            )
        case .right:
            raw = CGPoint(
                x: anchor.x - tabHalfW - spacing - bubbleSize.width,
                y: anchor.y - bubbleSize.height / 2
            )
        case .top:
            raw = CGPoint(
                x: anchor.x - bubbleSize.width / 2,
                y: anchor.y + tabHalfH + spacing
            )
        case .bottom:
            raw = CGPoint(
                x: anchor.x - bubbleSize.width / 2,
                y: anchor.y - tabHalfH - spacing - bubbleSize.height
            )
        }

        let maxX = max(margin, screen.width - bubbleSize.width - margin)
        let maxY = max(margin, screen.height - bubbleSize.height - margin)

        return CGPoint(
            x: min(max(raw.x, margin), maxX),
            y: min(max(raw.y, margin), maxY)
        )
    }

    static func petGreetingOrigin(
        anchor: CGPoint,
        bubbleSize: CGSize,
        fabRadius: CGFloat,
        in screen: CGSize,
        verticalGap: CGFloat = 8,
        margin: CGFloat = 12
    ) -> CGPoint {
        let idealX = anchor.x - bubbleSize.width / 2
        let maxX = max(margin, screen.width - bubbleSize.width - margin)
        let y = anchor.y - fabRadius - verticalGap - bubbleSize.height
        let maxY = max(margin, screen.height - bubbleSize.height - margin)

        return CGPoint(
            x: min(max(idealX, margin), maxX),
            y: min(max(y, margin), maxY)
        )
    }
}
