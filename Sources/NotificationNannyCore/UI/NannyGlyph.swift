import AppKit
import SwiftUI

/// The app's own bell artwork, shipped as template PNGs in `Resources/Glyphs`
/// and copied into the bundle by `build-app.sh`.
///
/// The assets are black-on-transparent so `isTemplate` can do its job: AppKit
/// reads only the alpha channel and recolours the glyph for the menu bar's
/// current appearance (and for SwiftUI's `.tint`), which is why there's no
/// light/dark pair here.
package enum NannyGlyph: String, CaseIterable {
    /// Normal operation.
    case bell = "bell-nanny"
    /// Accessibility permission missing, or the app switched off / snoozed.
    case bellSlash = "bell-nanny-slash"

    package static func forState(hasPermission: Bool, isActive: Bool) -> NannyGlyph {
        hasPermission && isActive ? .bell : .bellSlash
    }

    /// Nil when the asset is missing — callers fall back to an SF Symbol rather
    /// than shipping an invisible menu-bar item. Notably nil under `swift test`,
    /// where there is no app bundle to load from.
    package func image(pointSize: CGFloat) -> NSImage? {
        guard let url = Bundle.main.url(forResource: rawValue, withExtension: "png", subdirectory: "Glyphs"),
              let image = NSImage(contentsOf: url) else { return nil }
        // The artwork is cropped to fit the slashed variant, so the bell sits
        // inside some margin; 20pt lands it at roughly the 16pt the menu bar wants.
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
