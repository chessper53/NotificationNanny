import CoreGraphics
import Foundation

struct AppGroup: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var appNames: [String]
    var placement: ScreenPlacement
    var targetDisplayID: CGDirectDisplayID
    /// nil means inherit the global banner scale from AppSettings.
    var bannerScale: Double?

    init(id: UUID = UUID(), name: String, appNames: [String] = [],
         placement: ScreenPlacement = .default, targetDisplayID: CGDirectDisplayID = 0,
         bannerScale: Double? = nil) {
        self.id = id
        self.name = name
        self.appNames = appNames
        self.placement = placement
        self.targetDisplayID = targetDisplayID
        self.bannerScale = bannerScale
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, appNames, placement, targetDisplayID, bannerScale
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(UUID.self, forKey: .id)
        name            = try c.decode(String.self, forKey: .name)
        appNames        = try c.decode([String].self, forKey: .appNames)
        placement       = try c.decode(ScreenPlacement.self, forKey: .placement)
        targetDisplayID = try c.decodeIfPresent(CGDirectDisplayID.self, forKey: .targetDisplayID) ?? 0
        bannerScale     = try c.decodeIfPresent(Double.self, forKey: .bannerScale)
    }
}
