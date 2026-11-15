import CoreText
import SwiftUI
import TunerCore
import UIKit

extension Color {
    /// Resolves per trait collection, so the whole palette follows the system appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(
            uiColor: UIColor { traits in
                let hex = traits.userInterfaceStyle == .dark ? dark : light
                return UIColor(
                    red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
            })
    }
}

enum Palette {
    static let body = Color(light: 0xE8E8E3, dark: 0x151514)
    static let panel = Color(light: 0xF4F4F0, dark: 0x222220)
    static let ink = Color(light: 0x1D1D1B, dark: 0xECECE6)
    static let grey = Color(light: 0x9A9A94, dark: 0x76766F)
    static let border = Color(light: 0xC9C9C2, dark: 0x3C3C38)
    static let hairline = Color(light: 0xE2E2DC, dark: 0x2C2C29)
    static let secondaryText = Color(light: 0x4A4A45, dark: 0xBEBEB7)
    static let mutedText = Color(light: 0x5E5E58, dark: 0x9E9E97)
    static let idleLetter = Color(light: 0xB4B4AD, dark: 0x4C4C47)
    static let switchOff = Color(light: 0xD6D6CF, dark: 0x3C3C38)

    static let flatMark = Color(light: 0x2F6FED, dark: 0x5B8EF6)
    static let sharpMark = Color(light: 0xFF5A00, dark: 0xFF7A33)
    static let inTuneMark = Color(light: 0x2E9E4F, dark: 0x3FBF66)
    static let flatText = Color(light: 0x1F55C4, dark: 0x93B3F9)
    static let sharpText = Color(light: 0xA93A00, dark: 0xFF9E66)
    static let inTuneText = Color(light: 0x1E7A3A, dark: 0x72D692)

    static func screenTint(_ state: TuneState) -> Color {
        switch state {
        case .idle: body
        case .flat: Color(light: 0xE4E9F2, dark: 0x131A27)
        case .sharp: Color(light: 0xF3E7DF, dark: 0x251912)
        case .inTune: Color(light: 0xE2EEE4, dark: 0x122019)
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

/// Inter Tight and IBM Plex Mono when registered, system fonts otherwise.
enum Typeface {
    enum Weight { case regular, medium, semibold, bold }

    static func ui(_ size: CGFloat, _ weight: Weight, relativeTo style: Font.TextStyle = .body) -> Font {
        let name =
            switch weight {
            case .regular, .medium: "InterTight-Medium"
            case .semibold: "InterTight-SemiBold"
            case .bold: "InterTight-Bold"
            }
        if isAvailable(name) { return .custom(name, size: size, relativeTo: style) }
        return .system(size: scaled(size, style), weight: weight.system)
    }

    static func mono(_ size: CGFloat, _ weight: Weight, relativeTo style: Font.TextStyle = .caption) -> Font {
        let name =
            switch weight {
            case .regular: "IBMPlexMono-Regular"
            case .medium: "IBMPlexMono-Medium"
            case .semibold, .bold: "IBMPlexMono-SemiBold"
            }
        if isAvailable(name) { return .custom(name, size: size, relativeTo: style) }
        return .system(size: scaled(size, style), weight: weight.system, design: .monospaced)
    }

    /// Dynamic Type scaling for the system-font fallback, matching what `.custom(relativeTo:)` does.
    private static func scaled(_ size: CGFloat, _ style: Font.TextStyle) -> CGFloat {
        let uiStyle: UIFont.TextStyle =
            switch style {
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

    private static let registration: Void = {
        guard let folder = Bundle.module.url(forResource: "Fonts", withExtension: nil),
            let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else { return }
        let fonts = files.filter { $0.pathExtension == "ttf" }
        CTFontManagerRegisterFontURLs(fonts as CFArray, .process, true, nil)
    }()

    /// The fonts ship in this package, not the app, so previews and tests render them too.
    static func registerBundledFonts() { _ = registration }
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
