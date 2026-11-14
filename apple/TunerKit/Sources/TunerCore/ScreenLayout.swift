import Foundation

/// Phone: dial 350 pt, keys full width. Wider screens: dial ≈ 62 % (≤ 520), keys ≈ 74 % (≤ 620).
public struct ScreenLayout: Sendable, Equatable {
    public let dialWidth: CGFloat
    public let keysWidth: CGFloat
    public let keyHeight: CGFloat
    public var dialScale: CGFloat { dialWidth / 350 }

    public init(width: CGFloat) {
        if width < 600 {
            dialWidth = min(350, width - 40)
            keysWidth = width - 40
            keyHeight = 64
        } else {
            dialWidth = min(width * 0.62, 520)
            keysWidth = min(width * 0.74, 620)
            keyHeight = 72
        }
    }
}
