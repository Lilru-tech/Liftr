import SwiftUI
import UIKit

enum TerritoryOwnerColors {
    private static let palette: [Color] = (0..<48).map { index in
        let hue = Double(index) / 48.0
        return Color(hue: hue, saturation: 0.72, brightness: 0.88)
    }

    private static func paletteIndex(for ownerId: UUID) -> Int {
        var hash = 5381
        let bytes = withUnsafeBytes(of: ownerId.uuid) { Array($0) }
        for byte in bytes {
            hash = ((hash << 5) &+ hash) &+ Int(byte)
        }
        var secondary = 0
        for byte in bytes.reversed() {
            secondary = ((secondary << 5) &+ secondary) &+ Int(byte)
        }
        return abs(hash &+ secondary &* 17) % palette.count
    }

    static func color(for ownerId: UUID) -> Color {
        palette[paletteIndex(for: ownerId)]
    }

    static func fill(for ownerId: UUID, isMine: Bool) -> Color {
        color(for: ownerId).opacity(isMine ? 0.50 : 0.44)
    }

    static func uiColor(for ownerId: UUID) -> UIColor {
        UIColor(
            hue: CGFloat(Double(paletteIndex(for: ownerId)) / 48.0),
            saturation: 0.72,
            brightness: 0.88,
            alpha: 1.0
        )
    }

    static func uiFill(for ownerId: UUID, isMine: Bool) -> UIColor {
        uiColor(for: ownerId).withAlphaComponent(isMine ? 0.50 : 0.44)
    }

    static func stroke(for ownerId: UUID, isMine: Bool, denseOverlay: Bool = false) -> Color {
        if denseOverlay {
            return .clear
        }
        let base = color(for: ownerId)
        return isMine ? base : base.opacity(0.82)
    }

    static func strokeWidth(isMine: Bool, denseOverlay: Bool = false) -> CGFloat {
        if denseOverlay {
            return 0
        }
        return isMine ? 3.0 : 1.0
    }
}
