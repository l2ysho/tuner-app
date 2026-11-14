import SwiftUI
import UIKit

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity)
    }
}

enum Palette {
    static let body = Color(hex: 0xE8E8E3)
    static let panel = Color(hex: 0xF4F4F0)
    static let ink = Color(hex: 0x1D1D1B)
    static let grey = Color(hex: 0x9A9A94)
    static let border = Color(hex: 0xC9C9C2)
    static let hairline = Color(hex: 0xE2E2DC)
    static let secondaryText = Color(hex: 0x4A4A45)
    static let mutedText = Color(hex: 0x5E5E58)
    static let idleLetter = Color(hex: 0xB4B4AD)
    static let switchOff = Color(hex: 0xD6D6CF)

    static let flatMark = Color(hex: 0x2F6FED)
    static let sharpMark = Color(hex: 0xFF5A00)
    static let inTuneMark = Color(hex: 0x2E9E4F)
    static let flatText = Color(hex: 0x1F55C4)
    static let sharpText = Color(hex: 0xA93A00)
    static let inTuneText = Color(hex: 0x1E7A3A)

    static func screenTint(_ state: TuneState) -> Color {
        switch state {
        case .idle: body
        case .flat: Color(hex: 0xE4E9F2)
        case .sharp: Color(hex: 0xF3E7DF)
        case .inTune: Color(hex: 0xE2EEE4)
        }
    }

    static func mark(_ state: TuneState) -> Color {
        switch state {
        case .idle: grey
        case .flat: flatMark
        case .sharp: sharpMark
        case .inTune: inTuneMark
        }
    }

    static func text(_ state: TuneState) -> Color {
        switch state {
        case .idle: mutedText
        case .flat: flatText
        case .sharp: sharpText
        case .inTune: inTuneText
        }
    }
}

/// Inter Tight and IBM Plex Mono when bundled (apple/Tuner/Fonts), system fonts otherwise.
enum Typeface {
    enum Weight { case regular, medium, semibold, bold }

    static func ui(_ size: CGFloat, _ weight: Weight, relativeTo style: Font.TextStyle = .body) -> Font {
        let name = switch weight {
        case .regular, .medium: "InterTight-Medium"
        case .semibold: "InterTight-SemiBold"
        case .bold: "InterTight-Bold"
        }
        if isAvailable(name) { return .custom(name, size: size, relativeTo: style) }
        return .system(size: scaled(size, style), weight: weight.system)
    }

    static func mono(_ size: CGFloat, _ weight: Weight, relativeTo style: Font.TextStyle = .caption) -> Font {
        let name = switch weight {
        case .regular: "IBMPlexMono-Regular"
        case .medium: "IBMPlexMono-Medium"
        case .semibold, .bold: "IBMPlexMono-SemiBold"
        }
        if isAvailable(name) { return .custom(name, size: size, relativeTo: style) }
        return .system(size: scaled(size, style), weight: weight.system, design: .monospaced)
    }

    /// Dynamic Type scaling for the system-font fallback, matching what `.custom(relativeTo:)` does.
    private static func scaled(_ size: CGFloat, _ style: Font.TextStyle) -> CGFloat {
        let uiStyle: UIFont.TextStyle = switch style {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
        return UIFontMetrics(forTextStyle: uiStyle).scaledValue(for: size)
    }

    /// Fixed-size display type (the note letter); it does not follow Dynamic Type.
    static func display(_ size: CGFloat, _ weight: Weight) -> Font {
        let name = weight == .bold ? "InterTight-Bold" : "InterTight-SemiBold"
        if isAvailable(name) { return .custom(name, fixedSize: size) }
        return .system(size: size, weight: weight.system)
    }

    static func displayDescender(_ size: CGFloat, _ weight: Weight) -> CGFloat {
        let name = weight == .bold ? "InterTight-Bold" : "InterTight-SemiBold"
        let font = UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight.uiKit)
        return font.descender
    }

    private static func isAvailable(_ name: String) -> Bool { UIFont(name: name, size: 12) != nil }
}

extension Typeface.Weight {
    var system: Font.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
    }

    var uiKit: UIFont.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
    }
}

/// Mono caps label used for section headers and footers ("PRESETS", "NO ADS · …").
struct CapsLabel: View {
    let text: String
    var size: CGFloat = 10

    var body: some View {
        Text(text)
            .font(Typeface.mono(size, .medium, relativeTo: .caption2))
            .tracking(size * 0.14)
            .foregroundStyle(Palette.mutedText)
    }
}
