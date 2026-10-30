import Foundation
import Testing
@testable import NotificationNannyCore

@Suite("Sound groups") @MainActor
struct SoundGroupTests {

    private func makeSettings() -> (AppSettings, () -> AppSettings) {
        let name = "SoundGroupTests_\(UUID().uuidString)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).json")
        let make = { AppSettings(defaults: UserDefaults(suiteName: name)!, knownAppsFileURL: url) }
        return (make(), make)
    }

    // MARK: - Model

    @Test func decodes_withoutSoundOrVolume() throws {
        let json = #"{"id":"00000000-0000-0000-0000-000000000001","name":"Chat"}"#.data(using: .utf8)!
        let g = try JSONDecoder().decode(SoundGroup.self, from: json)
        #expect(g.appNames.isEmpty)
        #expect(g.sound == nil)
        #expect(g.volume == 1)
    }

    @Test func codable_roundTrip() throws {
        for sound in [nil, .macOS, .sound("Glass"), .sound("/Users/me/ding.aiff")] as [NotificationSoundChoice?] {
            let g = SoundGroup(name: "Work", appNames: ["Slack"], sound: sound, volume: 0.4)
            let back = try JSONDecoder().decode(SoundGroup.self, from: JSONEncoder().encode(g))
            #expect(back == g)
        }
    }

    // MARK: - What plays

    @Test func nothingSet_playsNothing() {
        let (s, _) = makeSettings()
        #expect(s.notificationSound(for: "Slack") == nil)
        #expect(!s.playsAnySound)
    }

    @Test func allApps_coversAppsOutsideGroups_andFollowingGroups() {
        let (s, _) = makeSettings()
        s.allAppsSound = "Ping"
        s.allAppsSoundVolume = 0.3
        let follow = s.addSoundGroup(name: "Follow")
        s.addApp("Slack", toSoundGroup: follow)
        #expect(s.notificationSound(for: "Mail")?.sound == "Ping")
        #expect(s.notificationSound(for: "Slack")?.sound == "Ping")
        #expect(s.notificationSound(for: "Slack")?.volume == 0.3)
    }

    @Test func group_ownSound_orMacOS_overridesAllApps() {
        let (s, _) = makeSettings()
        s.allAppsSound = "Ping"
        let own = s.addSoundGroup(name: "Own")
        let quiet = s.addSoundGroup(name: "Quiet")
        s.addApp("Slack", toSoundGroup: own)
        s.addApp("Mail", toSoundGroup: quiet)
        s.updateSoundGroup(own) { $0.sound = .sound("Glass"); $0.volume = 0.7 }
        s.updateSoundGroup(quiet) { $0.sound = .macOS }
        #expect(s.notificationSound(for: "Slack")?.sound == "Glass")
        #expect(s.notificationSound(for: "Slack")?.volume == 0.7)
        #expect(s.notificationSound(for: "Mail") == nil)
    }

    // MARK: - Settings

    @Test func membership_isExclusive() {
        let (s, _) = makeSettings()
        let a = s.addSoundGroup(name: "A")
        let b = s.addSoundGroup(name: "B")
        s.addApp("Slack", toSoundGroup: a)
        s.addApp("Slack", toSoundGroup: b)
        #expect(s.soundGroup(by: a)?.appNames == [])
        #expect(s.soundGroup(for: "Slack")?.id == b)
    }

    @Test func soundGroups_independentOfExceptionGroups() {
        let (s, _) = makeSettings()
        let banner = s.addGroup(name: "Banner")
        s.addApp("Slack", toGroup: banner)
        let sound = s.addSoundGroup(name: "Sound")
        s.addApp("Slack", toSoundGroup: sound)
        #expect(s.group(for: "Slack")?.id == banner)
        #expect(s.soundGroup(for: "Slack")?.id == sound)
    }

    @Test func persists_acrossInit() {
        let (s, make) = makeSettings()
        let id = s.addSoundGroup(name: "Chat")
        s.addApp("Messages", toSoundGroup: id)
        s.updateSoundGroup(id) { $0.sound = .sound("Glass"); $0.volume = 0.5 }
        s.allAppsSound = "Ping"
        s.allAppsSoundVolume = 0.25
        s.flushPendingSaves()
        let fresh = make()
        let g = fresh.soundGroup(by: id)
        #expect(g?.appNames == ["Messages"])
        #expect(g?.sound == .sound("Glass"))
        #expect(g?.volume == 0.5)
        #expect(fresh.allAppsSound == "Ping")
        #expect(fresh.allAppsSoundVolume == 0.25)
    }

    @Test func export_roundTrips_andOldBackupsImportWithNone() throws {
        let (s, _) = makeSettings()
        let id = s.addSoundGroup(name: "Chat")
        s.updateSoundGroup(id) { $0.sound = .sound("Ping") }
        s.allAppsSound = "Glass"
        let data = try s.exportData()

        let (other, _) = makeSettings()
        try other.importData(data)
        #expect(other.soundGroups == s.soundGroups)
        #expect(other.allAppsSound == "Glass")

        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "soundGroups")
        json.removeValue(forKey: "allAppsSound")
        try other.importData(JSONSerialization.data(withJSONObject: json))
        #expect(other.soundGroups.isEmpty)
        #expect(other.allAppsSound == nil)
    }

    @Test func reset_clearsSoundGroups() {
        let (s, _) = makeSettings()
        s.addSoundGroup(name: "Chat")
        s.allAppsSound = "Ping"
        s.resetAllSettings()
        #expect(s.soundGroups.isEmpty)
        #expect(s.allAppsSound == nil)
    }

    // MARK: - Playing

    private final class Recorder {
        var played: [(String, Double)] = []
    }

    private func makeSounds(_ recorder: Recorder) -> NotificationSounds {
        NotificationSounds(logger: NannyLogger()) { recorder.played.append(($0, $1)) }
    }

    /// Slack and Teams play Glass; anything else plays nothing of ours.
    private func soundFor(_ app: String) -> (sound: String, volume: Double)? {
        ["Slack", "Teams"].contains(app) ? ("Glass", 0.6) : nil
    }

    private func banner(_ id: String, _ app: String?) -> (id: String, appName: () -> String?) {
        (id: id, appName: { app })
    }

    @Test func bannersAlreadyUp_stayQuiet() {
        let rec = Recorder()
        let sounds = makeSounds(rec)
        sounds.sweep([banner("1", "Slack")], soundFor: soundFor)
        sounds.sweep([banner("1", "Slack")], soundFor: soundFor)
        #expect(rec.played.isEmpty)
    }

    @Test func newBanner_playsOnce_atGroupVolume() {
        let rec = Recorder()
        let sounds = makeSounds(rec)
        sounds.sweep([], soundFor: soundFor)
        sounds.sweep([banner("2", "Slack")], soundFor: soundFor)
        sounds.sweep([banner("2", "Slack")], soundFor: soundFor)
        // Gone from one sweep, as mid re-layout, and back: not played again.
        sounds.sweep([], soundFor: soundFor)
        sounds.sweep([banner("2", "Slack")], soundFor: soundFor)
        #expect(rec.played.count == 1)
        #expect(rec.played.first?.0 == "Glass")
        #expect(rec.played.first?.1 == 0.6)
    }

    @Test func sameSoundTogether_playsOnce_andOthersNotAtAll() {
        let rec = Recorder()
        let sounds = makeSounds(rec)
        sounds.sweep([], soundFor: soundFor)
        sounds.sweep([banner("3", "Slack"), banner("4", "Teams"), banner("5", "Mail"), banner("6", "Notes")],
                     soundFor: soundFor)
        #expect(rec.played.map(\.0) == ["Glass"])
    }

    @Test func unreadableBanner_isTriedAgain() {
        let rec = Recorder()
        let sounds = makeSounds(rec)
        sounds.sweep([], soundFor: soundFor)
        sounds.sweep([banner("7", nil)], soundFor: soundFor)
        sounds.sweep([banner("7", "Slack")], soundFor: soundFor)
        #expect(rec.played.count == 1)
    }

    @Test func reset_takesANewBaseline() {
        let rec = Recorder()
        let sounds = makeSounds(rec)
        sounds.sweep([], soundFor: soundFor)
        sounds.reset()
        sounds.sweep([banner("8", "Slack")], soundFor: soundFor)
        #expect(rec.played.isEmpty)
    }
}
