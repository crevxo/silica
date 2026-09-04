import SwiftUI

/// Two hand-picked palettes rather than system colours. The whole point of the app
/// is that the paper looks the same on every Mac, so nothing here reads from the
/// system accent or the system window background.
enum Appearance: String, Codable, CaseIterable {
    case light, dark, system

    /// `system` has no palette of its own — it resolves to one of the other two.
    var nsAppearance: NSAppearance? {
        switch self {
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        case .system: nil
        }
    }

    static var systemIsDark: Bool {
        NSApp?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}

struct Palette {
    let background: Color
    let ink: Color
    let inkSoft: Color
    let line: Color
    let pill: Color
    let pillActive: Color
    let pillBorder: Color

    let nsBackground: NSColor
    let nsInk: NSColor
    let nsInkSoft: NSColor

    static let light = Palette(
        background: Color(hex: 0xFFFFFF),
        ink: Color(hex: 0x1B1D21),
        inkSoft: Color(hex: 0x868B92),
        line: Color(hex: 0xECEEF0),
        pill: Color(hex: 0xF0F1F3),
        pillActive: Color(hex: 0xFFFFFF),
        pillBorder: Color.black.opacity(0.12),
        nsBackground: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
        nsInk: NSColor(srgbRed: 0.106, green: 0.114, blue: 0.129, alpha: 1),
        nsInkSoft: NSColor(srgbRed: 0.525, green: 0.545, blue: 0.573, alpha: 1)
    )

    static let dark = Palette(
        background: Color(hex: 0x232427),
        ink: Color(hex: 0xECEDEF),
        inkSoft: Color(hex: 0x91959C),
        line: Color(hex: 0x37383C),
        pill: Color(hex: 0x2C2D31),
        pillActive: Color(hex: 0x38393E),
        pillBorder: Color.white.opacity(0.06),
        nsBackground: NSColor(srgbRed: 0.137, green: 0.141, blue: 0.153, alpha: 1),
        nsInk: NSColor(srgbRed: 0.925, green: 0.929, blue: 0.937, alpha: 1),
        nsInkSoft: NSColor(srgbRed: 0.569, green: 0.584, blue: 0.612, alpha: 1)
    )

    static func of(_ appearance: Appearance) -> Palette {
        appearance == .light ? .light : .dark
    }
}

/// The caret is the one saturated colour in the app.
let caretBlue = NSColor(srgbRed: 0.039, green: 0.518, blue: 1.0, alpha: 1)

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette.light
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}
