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
    }

    @Test func codable_roundTrip() throws {
        let original = AppGroup(
            id: UUID(),
            name: "Social",
            appNames: ["Slack", "Messages"],
            placement: ScreenPlacement(position: .bottomLeft, xOffset: 10, yOffset: -5)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppGroup.self, from: data)
        #expect(decoded == original)
    }

    @Test func equatable_differentIDs() {
        let a = AppGroup(name: "A")
        let b = AppGroup(name: "A")
        #expect(a != b, "Two groups with different UUIDs must not be equal")
    }
}
