import AppKit
import SwiftUI

/// Bundled bell templates use the alpha channel so one asset adapts to both appearances.
package enum NannyGlyph: String, CaseIterable {
    /// Normal operation.
    case bell = "bell-nanny"
    /// Accessibility permission missing, or the app switched off / snoozed.
    case bellSlash = "bell-nanny-slash"

    package static func forState(hasPermission: Bool, isActive: Bool) -> NannyGlyph {
        hasPermission && isActive ? .bell : .bellSlash
    }

    /// Nil if the bundled asset is unavailable, including tests; callers must supply a symbol
    /// fallback.
    package func image(pointSize: CGFloat) -> NSImage? {
        guard let url = Bundle.main.url(forResource: rawValue, withExtension: "png", subdirectory: "Glyphs"),
              let image = NSImage(contentsOf: url) else { return nil }
        // Allow for artwork margins so the visible bell fits the menu bar.
        image.size = NSSize(width: pointSize, height: pointSize)
        image.isTemplate = true
        return image
    }

    /// SF Symbol used when the bundled artwork can't be loaded.
    package var fallbackSymbolName: String {
        self == .bell ? "bell.badge.fill" : "bell.slash.fill"
    }
}

extension Image {
    /// SwiftUI counterpart; renders as a template so `.foregroundStyle(.tint)` applies.
    package static func nannyGlyph(_ glyph: NannyGlyph, pointSize: CGFloat) -> Image {
        if let nsImage = glyph.image(pointSize: pointSize) {
            return Image(nsImage: nsImage).renderingMode(.template)
        }
        return Image(systemName: glyph.fallbackSymbolName)
    }
}
