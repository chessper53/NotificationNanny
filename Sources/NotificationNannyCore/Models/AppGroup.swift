import CoreGraphics
import Foundation
import SwiftUI

package enum BannerMode: String, Codable {
    /// Forces the native banner, ignoring custom scale.
    case native
    /// Forces the custom overlay even at scale 1.
    case custom
}

/// An optional RGB color stored as one value.
package struct BannerTint: Codable, Equatable {
    package var r: Double
    package var g: Double
    package var b: Double

    package init(r: Double, g: Double, b: Double) {
        self.r = r; self.g = g; self.b = b
    }

    package var color: Color { Color(red: r, green: g, blue: b) }
}

struct AppGroup: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var appNames: [String]
    var placement: ScreenPlacement
    var targetDisplayID: CGDirectDisplayID
    /// Stable display key paired with targetDisplayID so overrides survive numeric ID reassignment.
    /// Nil means automatic selection or legacy data.
    var targetDisplayUUID: String?
    /// nil means inherit the global banner scale from AppSettings.
    var bannerScale: Double?
    /// nil means derive from the effective scale (custom if scale != 1.0, native otherwise).
    var bannerMode: BannerMode?
    /// nil means inherit the global banner color from AppSettings.
    var bannerTint: BannerTint?
    /// nil means inherit the global banner animation from AppSettings.
    var bannerAnimation: BannerAnimation?

    var hasBannerColor: Bool { bannerTint != nil }

    init(id: UUID = UUID(), name: String, appNames: [String] = [],
         placement: ScreenPlacement = .default, targetDisplayID: CGDirectDisplayID = 0,
         targetDisplayUUID: String? = nil,
         bannerScale: Double? = nil, bannerMode: BannerMode? = nil,
         bannerTint: BannerTint? = nil, bannerAnimation: BannerAnimation? = nil) {
        self.id = id
        self.name = name
        self.appNames = appNames
        self.placement = placement
        self.targetDisplayID = targetDisplayID
        self.targetDisplayUUID = targetDisplayUUID
        self.bannerScale = bannerScale
        self.bannerMode = bannerMode
        self.bannerTint = bannerTint
        self.bannerAnimation = bannerAnimation
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, appNames, placement, targetDisplayID, targetDisplayUUID
        case bannerScale, bannerMode, bannerTint, bannerAnimation
        // Decode only: migrate legacy RGB keys.
        case bannerColorR, bannerColorG, bannerColorB
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(UUID.self, forKey: .id)
        name            = try c.decode(String.self, forKey: .name)
        appNames        = try c.decode([String].self, forKey: .appNames)
        placement       = try c.decode(ScreenPlacement.self, forKey: .placement)
        targetDisplayID = try c.decodeIfPresent(CGDirectDisplayID.self, forKey: .targetDisplayID) ?? 0
        targetDisplayUUID = try c.decodeIfPresent(String.self, forKey: .targetDisplayUUID)
        bannerScale     = try c.decodeIfPresent(Double.self, forKey: .bannerScale)
        bannerMode      = try c.decodeIfPresent(BannerMode.self, forKey: .bannerMode)
        bannerAnimation = try c.decodeIfPresent(BannerAnimation.self, forKey: .bannerAnimation)
        if let tint = try c.decodeIfPresent(BannerTint.self, forKey: .bannerTint) {
            bannerTint = tint
        } else if let r = try c.decodeIfPresent(Double.self, forKey: .bannerColorR),
                  let g = try c.decodeIfPresent(Double.self, forKey: .bannerColorG),
                  let b = try c.decodeIfPresent(Double.self, forKey: .bannerColorB) {
            bannerTint = BannerTint(r: r, g: g, b: b)
        } else {
            bannerTint = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,              forKey: .id)
        try c.encode(name,            forKey: .name)
        try c.encode(appNames,        forKey: .appNames)
        try c.encode(placement,       forKey: .placement)
        try c.encode(targetDisplayID, forKey: .targetDisplayID)
        try c.encodeIfPresent(targetDisplayUUID, forKey: .targetDisplayUUID)
        try c.encodeIfPresent(bannerScale, forKey: .bannerScale)
        try c.encodeIfPresent(bannerMode,  forKey: .bannerMode)
        try c.encodeIfPresent(bannerTint,  forKey: .bannerTint)
        try c.encodeIfPresent(bannerAnimation, forKey: .bannerAnimation)
    }
}
