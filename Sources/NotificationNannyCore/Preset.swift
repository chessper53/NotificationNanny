import CoreGraphics
import Foundation

struct Preset: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var placements: [String: ScreenPlacement]
    var targetDisplayID: CGDirectDisplayID
    var autoDismissSeconds: Double
    var bannerScale: Double
    var bannerColorR: Double
    var bannerColorG: Double
    var bannerColorB: Double
    var hasBannerColor: Bool
    var holdWhileAsleep: Bool
    var pauseWhileStreaming: Bool
    var appGroups: [AppGroup]
    var bannerAnimation: BannerAnimation

    init(name: String, placements: [String: ScreenPlacement],
         targetDisplayID: CGDirectDisplayID, autoDismissSeconds: Double,
         bannerScale: Double, bannerColorR: Double, bannerColorG: Double, bannerColorB: Double,
         hasBannerColor: Bool, holdWhileAsleep: Bool, pauseWhileStreaming: Bool,
         appGroups: [AppGroup], bannerAnimation: BannerAnimation = .slide) {
        self.id = UUID()
        self.name = name
        self.placements = placements
        self.targetDisplayID = targetDisplayID
        self.autoDismissSeconds = autoDismissSeconds
        self.bannerScale = bannerScale
        self.bannerColorR = bannerColorR
        self.bannerColorG = bannerColorG
        self.bannerColorB = bannerColorB
        self.hasBannerColor = hasBannerColor
        self.holdWhileAsleep = holdWhileAsleep
        self.pauseWhileStreaming = pauseWhileStreaming
        self.appGroups = appGroups
        self.bannerAnimation = bannerAnimation
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                 = try c.decode(UUID.self,                      forKey: .id)
        name               = try c.decode(String.self,                    forKey: .name)
        placements         = try c.decode([String: ScreenPlacement].self, forKey: .placements)
        targetDisplayID    = try c.decodeIfPresent(CGDirectDisplayID.self, forKey: .targetDisplayID) ?? 0
        autoDismissSeconds = try c.decodeIfPresent(Double.self,           forKey: .autoDismissSeconds) ?? 0
        bannerScale        = try c.decodeIfPresent(Double.self,           forKey: .bannerScale) ?? 1.0
        bannerColorR       = try c.decodeIfPresent(Double.self,           forKey: .bannerColorR) ?? 0.0
        bannerColorG       = try c.decodeIfPresent(Double.self,           forKey: .bannerColorG) ?? 0.0
        bannerColorB       = try c.decodeIfPresent(Double.self,           forKey: .bannerColorB) ?? 0.0
        hasBannerColor     = try c.decodeIfPresent(Bool.self,             forKey: .hasBannerColor) ?? false
        holdWhileAsleep    = try c.decodeIfPresent(Bool.self,             forKey: .holdWhileAsleep) ?? false
        pauseWhileStreaming = try c.decodeIfPresent(Bool.self,            forKey: .pauseWhileStreaming) ?? false
        appGroups          = try c.decodeIfPresent([AppGroup].self,       forKey: .appGroups) ?? []
        let rawAnim        = try c.decodeIfPresent(String.self,           forKey: .bannerAnimation) ?? BannerAnimation.slide.rawValue
        bannerAnimation    = BannerAnimation(rawValue: rawAnim) ?? .slide
    }
}
