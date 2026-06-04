import CoreGraphics
import Foundation

package enum BannerMode: String, Codable {
    /// Always use the macOS system banner — ignores any scale setting.
    case native
    /// Always use the custom overlay — even at scale 1.0.
    case custom
}

struct AppGroup: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var appNames: [String]
    var placement: ScreenPlacement
    var targetDisplayID: CGDirectDisplayID
    /// nil means inherit the global banner scale from AppSettings.
    var bannerScale: Double?
    /// nil means derive from the effective scale (custom if scale != 1.0, native otherwise).
    var bannerMode: BannerMode?
    /// nil means inherit the global banner color from AppSettings.
    var bannerColorR: Double?
    var bannerColorG: Double?
    var bannerColorB: Double?

    var hasBannerColor: Bool { bannerColorR != nil }

    init(id: UUID = UUID(), name: String, appNames: [String] = [],
         placement: ScreenPlacement = .default, targetDisplayID: CGDirectDisplayID = 0,
         bannerScale: Double? = nil, bannerMode: BannerMode? = nil) {
        self.id = id
        self.name = name
        self.appNames = appNames
        self.placement = placement
        self.targetDisplayID = targetDisplayID
        self.bannerScale = bannerScale
        self.bannerMode = bannerMode
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, appNames, placement, targetDisplayID, bannerScale, bannerMode
        case bannerColorR, bannerColorG, bannerColorB
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(UUID.self, forKey: .id)
        name            = try c.decode(String.self, forKey: .name)
        appNames        = try c.decode([String].self, forKey: .appNames)
        placement       = try c.decode(ScreenPlacement.self, forKey: .placement)
        targetDisplayID = try c.decodeIfPresent(CGDirectDisplayID.self, forKey: .targetDisplayID) ?? 0
        bannerScale     = try c.decodeIfPresent(Double.self, forKey: .bannerScale)
        bannerMode      = try c.decodeIfPresent(BannerMode.self, forKey: .bannerMode)
        bannerColorR    = try c.decodeIfPresent(Double.self, forKey: .bannerColorR)
        bannerColorG    = try c.decodeIfPresent(Double.self, forKey: .bannerColorG)
        bannerColorB    = try c.decodeIfPresent(Double.self, forKey: .bannerColorB)
    }
}
