import CoreGraphics
import Foundation

struct Preset: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var placements: [String: ScreenPlacement]
    var targetDisplayID: CGDirectDisplayID
    var autoDismissSeconds: Double
    var bannerScale: Double

    init(name: String, placements: [String: ScreenPlacement],
         targetDisplayID: CGDirectDisplayID, autoDismissSeconds: Double, bannerScale: Double) {
        self.id = UUID()
        self.name = name
        self.placements = placements
        self.targetDisplayID = targetDisplayID
        self.autoDismissSeconds = autoDismissSeconds
        self.bannerScale = bannerScale
    }

    // Custom decoder so presets saved before bannerScale was added still load correctly.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id               = try c.decode(UUID.self,                    forKey: .id)
        name             = try c.decode(String.self,                  forKey: .name)
        placements       = try c.decode([String: ScreenPlacement].self, forKey: .placements)
        targetDisplayID  = try c.decodeIfPresent(CGDirectDisplayID.self, forKey: .targetDisplayID) ?? 0
        autoDismissSeconds = try c.decodeIfPresent(Double.self,       forKey: .autoDismissSeconds) ?? 0
        bannerScale      = try c.decodeIfPresent(Double.self,         forKey: .bannerScale) ?? 1.0
    }
}
