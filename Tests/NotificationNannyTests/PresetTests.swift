import Foundation
import Testing
@testable import NotificationNannyCore

@Suite("Preset")
struct PresetTests {

    @Test func codable_roundTrip() throws {
        let original = Preset(
            name: "Night mode",
            placements: ["1": ScreenPlacement(position: .bottomRight, xOffset: 0, yOffset: 0)],
            targetDisplayID: 42,
            autoDismissSeconds: 5.0
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Preset.self, from: data)
        #expect(decoded == original)
    }

    @Test func eachPreset_hasUniqueID() {
        let a = Preset(name: "A", placements: [:], targetDisplayID: 0, autoDismissSeconds: 0)
        let b = Preset(name: "B", placements: [:], targetDisplayID: 0, autoDismissSeconds: 0)
        #expect(a.id != b.id)
    }

    @Test func codable_emptyPlacements() throws {
        let original = Preset(name: "Empty", placements: [:], targetDisplayID: 0, autoDismissSeconds: 0)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Preset.self, from: data)
        #expect(decoded.placements.isEmpty)
    }
}
