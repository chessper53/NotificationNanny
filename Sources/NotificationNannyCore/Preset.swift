import CoreGraphics
import Foundation

struct Preset: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var placements: [String: ScreenPlacement]
    var targetDisplayID: CGDirectDisplayID
    var autoDismissSeconds: Double
    var bannerScale: Double
    var bannerTint: BannerTint?
    var holdWhileAsleep: Bool
    var pauseWhileStreaming: Bool
    var appGroups: [AppGroup]
    var bannerAnimation: BannerAnimation

    init(name: String, placements: [String: ScreenPlacement],
         targetDisplayID: CGDirectDisplayID, autoDismissSeconds: Double,
         bannerScale: Double, bannerTint: BannerTint?,
         holdWhileAsleep: Bool, pauseWhileStreaming: Bool,
         appGroups: [AppGroup], bannerAnimation: BannerAnimation = .slide) {
        self.id = UUID()
        self.name = name
        self.placements = placements
        self.targetDisplayID = targetDisplayID
        self.autoDismissSeconds = autoDismissSeconds
        self.bannerScale = bannerScale
        self.bannerTint = bannerTint
        self.holdWhileAsleep = holdWhileAsleep
        self.pauseWhileStreaming = pauseWhileStreaming
        self.appGroups = appGroups
        self.bannerAnimation = bannerAnimation
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, placements, targetDisplayID, autoDismissSeconds, bannerScale
        case bannerTint, holdWhileAsleep, pauseWhileStreaming, appGroups, bannerAnimation
        // Legacy keys for migration
        case bannerColorR, bannerColorG, bannerColorB, hasBannerColor
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                 = try c.decode(UUID.self,                      forKey: .id)
        name               = try c.decode(String.self,                    forKey: .name)
        placements         = try c.decode([String: ScreenPlacement].self, forKey: .placements)
        targetDisplayID    = try c.decodeIfPresent(CGDirectDisplayID.self, forKey: .targetDisplayID) ?? 0
        autoDismissSeconds = try c.decodeIfPresent(Double.self,           forKey: .autoDismissSeconds) ?? 0
        bannerScale        = try c.decodeIfPresent(Double.self,           forKey: .bannerScale) ?? 1.0
        holdWhileAsleep    = try c.decodeIfPresent(Bool.self,             forKey: .holdWhileAsleep) ?? false
        pauseWhileStreaming = try c.decodeIfPresent(Bool.self,            forKey: .pauseWhileStreaming) ?? false
        appGroups          = try c.decodeIfPresent([AppGroup].self,       forKey: .appGroups) ?? []
        let rawAnim        = try c.decodeIfPresent(String.self,           forKey: .bannerAnimation) ?? BannerAnimation.default.rawValue
        bannerAnimation    = BannerAnimation(rawValue: rawAnim) ?? .default
        // Prefer new bannerTint key; fall back to legacy hasBannerColor + R/G/B keys.
        if let tint = try c.decodeIfPresent(BannerTint.self, forKey: .bannerTint) {
            bannerTint = tint
        } else if (try c.decodeIfPresent(Bool.self, forKey: .hasBannerColor)) == true,
                  let r = try c.decodeIfPresent(Double.self, forKey: .bannerColorR),
                  let g = try c.decodeIfPresent(Double.self, forKey: .bannerColorG),
                  let b = try c.decodeIfPresent(Double.self, forKey: .bannerColorB) {
            bannerTint = BannerTint(r: r, g: g, b: b)
        } else {
            bannerTint = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,                 forKey: .id)
        try c.encode(name,               forKey: .name)
        try c.encode(placements,         forKey: .placements)
        try c.encode(targetDisplayID,    forKey: .targetDisplayID)
        try c.encode(autoDismissSeconds, forKey: .autoDismissSeconds)
        try c.encode(bannerScale,        forKey: .bannerScale)
        try c.encodeIfPresent(bannerTint, forKey: .bannerTint)
        try c.encode(holdWhileAsleep,    forKey: .holdWhileAsleep)
        try c.encode(pauseWhileStreaming, forKey: .pauseWhileStreaming)
        try c.encode(appGroups,          forKey: .appGroups)
        try c.encode(bannerAnimation.rawValue, forKey: .bannerAnimation)
    }
}
