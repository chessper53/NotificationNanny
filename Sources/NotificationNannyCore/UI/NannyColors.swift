import AppKit
import SwiftUI

// Keep the shared accent consistent with the icon generator and website.

extension NSColor {
    static let nannyAmber      = NSColor(srgbRed: 0xE8 / 255, green: 0x83 / 255, blue: 0x3A / 255, alpha: 1)
    static let nannyAmberDeep  = NSColor(srgbRed: 0xA8 / 255, green: 0x55 / 255, blue: 0x14 / 255, alpha: 1)
    static let nannyGraphite   = NSColor(srgbRed: 0x2A / 255, green: 0x2D / 255, blue: 0x34 / 255, alpha: 1)
}

extension Color {
    /// Small amber accents use a deeper shade on light backgrounds for contrast; large fills use
    /// nannyProminent.
    static let nannyAccent = Color(nsColor: NSColor(name: "nannyAccent") { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark ? .nannyAmber : .nannyAmberDeep
    })

    /// Large selected fills use graphite on light and amber on dark. Switches use nannySwitchOn.
    static let nannyProminent = nannyAdaptive(light: .nannyGraphite, dark: .nannyAmber)

    /// Selected background wash: neutral on light, amber on dark.
    static func nannyWash(_ opacity: CGFloat) -> Color {
        nannyAdaptive(light: .black.withAlphaComponent(opacity * 0.32),
                      dark: NSColor.nannyAmber.withAlphaComponent(opacity))
    }

    /// Selected sidebar icons retain an amber accent against the neutral light wash.
    static let nannySelectedIcon = nannyAdaptive(light: .nannyAmberDeep, dark: .white)

    /// Resolve a color for the view's appearance.
    static func nannyAdaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }

    static let nannyWindow = nannyAdaptive(light: NSColor(white: 0.95, alpha: 1),
                                           dark: NSColor(white: 0.10, alpha: 1))
    static let nannySidebar = nannyAdaptive(light: .black.withAlphaComponent(0.04),
                                            dark: .black.withAlphaComponent(0.5))
    /// Text on a selected sidebar item or swatch ring: white on dark, label colour on light.
    static let nannyStrong = nannyAdaptive(light: .labelColor, dark: .white)

    /// Use a fainter black shade on light backgrounds to match the raised dark surfaces.
    static func nannyRaised(_ opacity: CGFloat) -> Color {
        nannyAdaptive(light: .black.withAlphaComponent(opacity * 0.7),
                      dark: .white.withAlphaComponent(opacity))
    }

    /// Card surfaces: white on light, a white lift on dark.
    static let nannyCard = nannyAdaptive(light: .white, dark: .white.withAlphaComponent(0.06))

    /// Selected segments use white on light for contrast against the surrounding track.
    static let nannySegment = nannyAdaptive(light: .white, dark: .white.withAlphaComponent(0.14))

    /// Small notes use stronger contrast on light cards.
    static let nannyNote = nannyAdaptive(light: .secondaryLabelColor, dark: .tertiaryLabelColor)

    /// Switches carry no text, so amber stays legible in both appearances.
    static let nannySwitchOn = Color(nsColor: .nannyAmber)

    /// Recessed wells such as log views: black on both, much fainter on light.
    static func nannyInset(_ opacity: CGFloat) -> Color {
        nannyAdaptive(light: .black.withAlphaComponent(opacity * 0.35),
                      dark: .black.withAlphaComponent(opacity))
    }

    /// Use system secondary text on light; the fixed dark shades lack contrast there.
    static func nannyMuted(_ darkWhite: CGFloat) -> Color {
        nannyAdaptive(light: .secondaryLabelColor, dark: NSColor(white: darkWhite, alpha: 1))
    }
}
