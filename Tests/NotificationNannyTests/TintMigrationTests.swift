import Foundation
import Testing
@testable import NotificationNannyCore

/// `AppGroup` and `Preset` carry custom decoders that migrate the legacy
/// `bannerColorR/G/B` (+ `hasBannerColor` for Preset) representation to the newer
/// single `bannerTint`. Old backups must keep decoding correctly.
@Suite("Tint migration")
struct TintMigrationTests {

    // MARK: - AppGroup

    @Test func appGroup_prefersBannerTintKey() throws {
        let json = """
        {
            "id": "00000000-0000-0000-0000-000000000001",
            "name": "G",
            "appNames": [],
            "placement": {"position": "topRight", "xOffset": 0, "yOffset": 0},
            "bannerTint": {"r": 0.5, "g": 0.25, "b": 0.75}
        }
        """.data(using: .utf8)!
        let g = try JSONDecoder().decode(AppGroup.self, from: json)
        #expect(g.bannerTint == BannerTint(r: 0.5, g: 0.25, b: 0.75))
    }

    @Test func appGroup_migratesLegacyRGB() throws {
        let json = """
        {
            "id": "00000000-0000-0000-0000-000000000002",
            "name": "Legacy",
            "appNames": [],
            "placement": {"position": "topRight", "xOffset": 0, "yOffset": 0},
            "bannerColorR": 1.0,
            "bannerColorG": 0.0,
            "bannerColorB": 0.0
        }
        """.data(using: .utf8)!
        let g = try JSONDecoder().decode(AppGroup.self, from: json)
        #expect(g.bannerTint == BannerTint(r: 1, g: 0, b: 0))
        #expect(g.hasBannerColor)
    }

    @Test func appGroup_noColor_decodesNilTint() throws {
        let json = """
        {
            "id": "00000000-0000-0000-0000-000000000003",
            "name": "Plain",
            "appNames": [],
            "placement": {"position": "topRight", "xOffset": 0, "yOffset": 0}
        }
        """.data(using: .utf8)!
        let g = try JSONDecoder().decode(AppGroup.self, from: json)
        #expect(g.bannerTint == nil)
        #expect(!g.hasBannerColor)
    }

    @Test func appGroup_encode_omitsLegacyKeys() throws {
        let g = AppGroup(name: "G", bannerTint: BannerTint(r: 0.1, g: 0.2, b: 0.3))
        let data = try JSONEncoder().encode(g)
        let str = String(data: data, encoding: .utf8)!
        #expect(str.contains("bannerTint"))
        #expect(!str.contains("bannerColorR"))
        // Round-trips back to the same value.
        let decoded = try JSONDecoder().decode(AppGroup.self, from: data)
        #expect(decoded.bannerTint == g.bannerTint)
    }

    // MARK: - Preset

    @Test func preset_migratesLegacyRGB_whenHasColorTrue() throws {
        let json = """
        {
            "id": "00000000-0000-0000-0000-0000000000AA",
            "name": "Legacy",
            "placements": {},
            "targetDisplayID": 0,
            "autoDismissSeconds": 0,
            "bannerScale": 1.0,
            "holdWhileAsleep": false,
            "pauseWhileStreaming": false,
            "appGroups": [],
            "bannerAnimation": "Default",
            "hasBannerColor": true,
            "bannerColorR": 0.2,
            "bannerColorG": 0.4,
            "bannerColorB": 0.6
        }
        """.data(using: .utf8)!
        let p = try JSONDecoder().decode(Preset.self, from: json)
        #expect(p.bannerTint == BannerTint(r: 0.2, g: 0.4, b: 0.6))
    }

    @Test func preset_legacyRGB_ignoredWhenHasColorFalse() throws {
        let json = """
        {
            "id": "00000000-0000-0000-0000-0000000000BB",
            "name": "NoColor",
            "placements": {},
            "targetDisplayID": 0,
            "autoDismissSeconds": 0,
            "bannerScale": 1.0,
            "holdWhileAsleep": false,
            "pauseWhileStreaming": false,
            "appGroups": [],
            "bannerAnimation": "Default",
            "hasBannerColor": false,
            "bannerColorR": 0.2,
            "bannerColorG": 0.4,
            "bannerColorB": 0.6
        }
        """.data(using: .utf8)!
        let p = try JSONDecoder().decode(Preset.self, from: json)
        #expect(p.bannerTint == nil)
    }

    @Test func preset_unknownAnimation_fallsBackToDefault() throws {
        let json = """
        {
            "id": "00000000-0000-0000-0000-0000000000CC",
            "name": "FutureAnim",
            "placements": {},
            "targetDisplayID": 0,
            "autoDismissSeconds": 0,
            "bannerScale": 1.0,
            "holdWhileAsleep": false,
            "pauseWhileStreaming": false,
            "appGroups": [],
            "bannerAnimation": "WarpSpeed"
        }
        """.data(using: .utf8)!
        let p = try JSONDecoder().decode(Preset.self, from: json)
        #expect(p.bannerAnimation == .default)
    }
}
