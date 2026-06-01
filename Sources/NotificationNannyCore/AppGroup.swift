import CoreGraphics
import Foundation

struct AppGroup: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var appNames: [String]
    var placement: ScreenPlacement
    var targetDisplayID: CGDirectDisplayID

    init(id: UUID = UUID(), name: String, appNames: [String] = [],
         placement: ScreenPlacement = .default, targetDisplayID: CGDirectDisplayID = 0) {
        self.id = id
        self.name = name
        self.appNames = appNames
        self.placement = placement
        self.targetDisplayID = targetDisplayID
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, appNames, placement, targetDisplayID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(UUID.self, forKey: .id)
        name            = try c.decode(String.self, forKey: .name)
        appNames        = try c.decode([String].self, forKey: .appNames)
        placement       = try c.decode(ScreenPlacement.self, forKey: .placement)
        targetDisplayID = try c.decodeIfPresent(CGDirectDisplayID.self, forKey: .targetDisplayID) ?? 0
    }
}
