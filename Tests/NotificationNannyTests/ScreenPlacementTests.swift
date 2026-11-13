import AppKit
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

    // Preserve legacy offsets on load; only a new user drag may clamp saved placement.
    @Test func decodesLegacyOutOfRangeOffsetsUnchanged() throws {
        let legacy = #"{"position":"topLeft","xOffset":3200.0,"yOffset":-1800.0}"#
        let decoded = try JSONDecoder().decode(ScreenPlacement.self, from: Data(legacy.utf8))
        #expect(decoded.position == .topLeft)
        #expect(decoded.xOffset == 3200)
        #expect(decoded.yOffset == -1800)
    }

    @MainActor
    @Test func legacyPlacementSurvivesSettingsRoundTrip() throws {
        let suite = "NotificationNannyLegacyPlacement_\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        guard let screen = NSScreen.main else { return }
        let wild = ScreenPlacement(position: .bottomRight, xOffset: 5000, yOffset: -4000)

        let a = AppSettings(defaults: defaults)
        a.setPlacement(wild, for: screen)
        a.flushPendingSaves()

        let read = AppSettings(defaults: defaults).placement(for: screen)
        #expect(read == wild, "a placement from an older config must not be clamped or dropped")
    }
}
