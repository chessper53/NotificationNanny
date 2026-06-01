import Foundation
import Testing
@testable import NotificationNannyCore

@Suite("AppGroup")
struct AppGroupTests {

    @Test func init_defaults() {
        let g = AppGroup(name: "Work")
        #expect(!g.id.uuidString.isEmpty)
        #expect(g.name == "Work")
        #expect(g.appNames.isEmpty)
        #expect(g.placement == .default)
        #expect(g.targetDisplayID == 0)
    }

    @Test func codable_roundTrip() throws {
        let original = AppGroup(
            id: UUID(),
            name: "Social",
            appNames: ["Slack", "Messages"],
            placement: ScreenPlacement(position: .bottomLeft, xOffset: 10, yOffset: -5),
            targetDisplayID: 42
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppGroup.self, from: data)
        #expect(decoded == original)
    }

    @Test func codable_backwardCompat_missingTargetDisplayID() throws {
        // JSON written before targetDisplayID existed must decode with 0.
        let json = """
        {
            "id": "00000000-0000-0000-0000-000000000001",
            "name": "Legacy",
            "appNames": ["Mail"],
            "placement": {"position": "topRight", "xOffset": 0, "yOffset": 0}
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppGroup.self, from: json)
        #expect(decoded.targetDisplayID == 0)
        #expect(decoded.name == "Legacy")
    }

    @Test func equatable_differentIDs() {
        let a = AppGroup(name: "A")
        let b = AppGroup(name: "A")
        #expect(a != b, "Two groups with different UUIDs must not be equal")
    }
}
