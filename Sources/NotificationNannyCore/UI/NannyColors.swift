import AppKit
import SwiftUI

// The app's colour tokens. The accent also lives in scripts/generate-icon.swift and the
// site's styles.css, and the three move together.

extension NSColor {
    static let nannyAmber      = NSColor(srgbRed: 0xE8 / 255, green: 0x83 / 255, blue: 0x3A / 255, alpha: 1)
    static let nannyAmberDeep  = NSColor(srgbRed: 0xA8 / 255, green: 0x55 / 255, blue: 0x14 / 255, alpha: 1)
    static let nannyGraphite   = NSColor(srgbRed: 0x2A / 255, green: 0x2D / 255, blue: 0x34 / 255, alpha: 1)
}

extension Color {
    /// Amber, adapting per appearance: the bright amber reads well on the dark
    /// settings window but drops under 3:1 as caption text on a light one, so
    /// light mode gets a deeper burnt amber. For text, icons and small marks;
    /// large fills use `nannyProminent`.
    static let nannyAccent = Color(nsColor: NSColor(name: "nannyAccent") { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark ? .nannyAmber : .nannyAmberDeep
    })

    /// Large accent fills: the prominent button, switches, segmented controls, a
    /// selected chip. Amber on dark, as before. On a light window a large area of
    /// the deep amber reads as brown, so light mode fills with graphite and keeps
    /// amber for the small accents.
    static let nannyProminent = nannyAdaptive(light: .nannyGraphite, dark: .nannyAmber)

    /// A wash behind a selected or highlighted item. Amber on dark, as before. On
    /// light, amber at these opacities over white turns tan, so it is a neutral
    /// grey there; the amber stays on the icon or text on top.
    static func nannyWash(_ opacity: CGFloat) -> Color {
        nannyAdaptive(light: .black.withAlphaComponent(opacity * 0.32),
                      dark: NSColor.nannyAmber.withAlphaComponent(opacity))
    }

    /// The icon of the selected sidebar item: white on dark as before, amber on
    /// light, where it carries the accent the neutral wash behind it no longer does.
    static let nannySelectedIcon = nannyAdaptive(light: .nannyAmberDeep, dark: .white)

    /// Picks a colour by the appearance the view is drawn in. The settings tokens below
    /// keep their original dark values exactly, so only light mode gains new colours.
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

    /// Cards and hairlines: a white lift on dark, a lighter black shade on light, since
    /// the same opacity of black reads much heavier against a light window.
    static func nannyRaised(_ opacity: CGFloat) -> Color {
        nannyAdaptive(light: .black.withAlphaComponent(opacity * 0.7),
                      dark: .white.withAlphaComponent(opacity))
    }

    /// A Settings card. White on the light window, as macOS's own settings lay theirs
    /// out: the lighter shade of grey it used to be left cards and window one flat sheet.
    /// Dark keeps its white lift.
    static let nannyCard = nannyAdaptive(light: .white, dark: .white.withAlphaComponent(0.06))

    /// The chosen segment of a segmented control: a white pill on light, as the system
    /// draws one; grey on grey there all but hid it.
    static let nannySegment = nannyAdaptive(light: .white, dark: .white.withAlphaComponent(0.14))

    /// The small print under a setting. One step darker on light, where tertiary grey
    /// on a light card read too faint.
    static let nannyNote = nannyAdaptive(light: .secondaryLabelColor, dark: .tertiaryLabelColor)

    /// A switch that is on: amber in both appearances. It has no text on it, so the
    /// amber that turns brown under dark text on light is fine here, and it carries the
    /// accent the graphite chips on light don't.
    static let nannySwitchOn = Color(nsColor: .nannyAmber)

    /// Recessed wells such as log views: black on both, much fainter on light.
    static func nannyInset(_ opacity: CGFloat) -> Color {
        nannyAdaptive(light: .black.withAlphaComponent(opacity * 0.35),
                      dark: .black.withAlphaComponent(opacity))
    }

    /// Muted grey text. The fixed dark greys drop under 3:1 on a light window, so light
    /// mode uses the system secondary label colour instead.
    static func nannyMuted(_ darkWhite: CGFloat) -> Color {
        nannyAdaptive(light: .secondaryLabelColor, dark: NSColor(white: darkWhite, alpha: 1))
    }
}
