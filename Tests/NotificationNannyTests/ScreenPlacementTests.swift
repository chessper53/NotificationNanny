import Foundation
import Testing
@testable import NotificationNannyCore

@Suite("ScreenPlacement")
struct ScreenPlacementTests {

    @Test func default_isTopRight_zeroOffsets() {
        let p = ScreenPlacement.default
        #expect(p.position == .topRight)
        #expect(p.xOffset == 0)
        #expect(p.yOffset == 0)
    }

    @Test func codable_roundTrip() throws {
        let original = ScreenPlacement(position: .middleCenter, xOffset: 12.5, yOffset: -8.0)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ScreenPlacement.self, from: data)
        #expect(decoded == original)
    }

    @Test func codable_allPositions() throws {
        for position in NotificationPosition.allCases {
            let original = ScreenPlacement(position: position, xOffset: 0, yOffset: 0)
            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(ScreenPlacement.self, from: data)
            #expect(decoded.position == position, "Failed round-trip for \(position)")
        }
    }
}
