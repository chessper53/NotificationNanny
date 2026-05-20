import CoreGraphics
import Foundation

struct Preset: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var placements: [String: ScreenPlacement]
    var targetDisplayID: CGDirectDisplayID
    var autoDismissSeconds: Double

    init(name: String, placements: [String: ScreenPlacement],
         targetDisplayID: CGDirectDisplayID, autoDismissSeconds: Double) {
        self.id = UUID()
        self.name = name
        self.placements = placements
        self.targetDisplayID = targetDisplayID
        self.autoDismissSeconds = autoDismissSeconds
    }
}
