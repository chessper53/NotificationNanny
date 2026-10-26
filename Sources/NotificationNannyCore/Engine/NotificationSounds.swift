import AppKit

/// Plays a sound group's sound when a banner from one of its apps first shows.
///
/// macOS has no way to give an app another notification sound, and nothing outside
/// Notification Center can hold its own sound back. So this plays alongside it, and the
/// Sounds tab asks for the app's own sound to be turned off in System Settings.
///
/// A banner's `AXIdentifier` stays the same for the notification's whole life, through
/// re-layouts and piles, so a new identifier is a new notification.
@MainActor
final class NotificationSounds {
    private let logger: NannyLogger
    private let play: @MainActor (_ sound: String, _ volume: Double) -> Void
    /// Identifiers already sounded or passed over, oldest first. Never dropped for being
    /// gone from a sweep: a pile caught mid re-layout can read empty for a moment, and
    /// forgetting then would play everything up again.
    private var heard: [String] = []
    private var heardSet: Set<String> = []
    private static let maxHeard = 500
    /// Sweeps a banner's app couldn't be read in. A banner arriving back to back can show
    /// before its description is filled in; it's tried again, then passed over.
    private var unreadable: [String: Int] = [:]
    /// The banners already up when observing starts came in unheard, and stay so.
    private var baselineTaken = false

    init(logger: NannyLogger,
         play: @escaping @MainActor (_ sound: String, _ volume: Double) -> Void = { SoundPlayer.shared.play($0, volume: $1) }) {
        self.logger = logger
        self.play = play
    }

    /// Back to taking a baseline, for when observing starts again.
    func reset() {
        baselineTaken = false
        unreadable.removeAll()
    }

    /// Called with the banners up in a sweep, each with a way to read its app, which is only
    /// asked of new ones. Plays each sound once, however many of its banners arrived together.
    func sweep(_ banners: [(id: String, appName: () -> String?)],
               soundFor: (String) -> (sound: String, volume: Double)?) {
        guard baselineTaken else {
            banners.forEach { markHeard($0.id) }
            baselineTaken = true
            return
        }
        var toPlay: [String: (volume: Double, apps: [String])] = [:]
        for banner in banners where !heardSet.contains(banner.id) {
            guard let app = banner.appName() else {
                let tries = (unreadable[banner.id] ?? 0) + 1
                unreadable[banner.id] = tries
                if tries >= 5 { markHeard(banner.id) }
                continue
            }
            markHeard(banner.id)
            guard let (sound, volume) = soundFor(app) else { continue }
            let louder = max(toPlay[sound]?.volume ?? 0, volume)
            toPlay[sound] = (louder, (toPlay[sound]?.apps ?? []) + [app])
        }
        for (sound, entry) in toPlay {
            play(sound, entry.volume)
            logger.log("Played \"\(NotificationSoundLibrary.displayName(of: sound))\" for \(entry.apps.joined(separator: ", "))", tag: "Sound")
        }
    }

    private func markHeard(_ id: String) {
        unreadable.removeValue(forKey: id)
        guard heardSet.insert(id).inserted else { return }
        heard.append(id)
        if heard.count > Self.maxHeard {
            heardSet.remove(heard.removeFirst())
        }
    }
}

/// Plays a sound by name or path, cutting off the same sound if it is still playing.
@MainActor
final class SoundPlayer {
    static let shared = SoundPlayer()

    private var cache: [String: NSSound] = [:]

    /// Whether it could be found and played.
    @discardableResult
    func play(_ sound: String, volume: Double) -> Bool {
        guard let player = resolve(sound) else {
            NannyLogger.shared.log("Sound \"\(sound)\" not found", level: .warn, tag: "Sound")
            return false
        }
        if player.isPlaying { player.stop() }
        player.volume = Float(min(max(volume, 0), 1))
        return player.play()
    }

    private func resolve(_ sound: String) -> NSSound? {
        if let cached = cache[sound] { return cached }
        let found = NotificationSoundLibrary.isFile(sound)
            ? NSSound(contentsOf: URL(fileURLWithPath: sound), byReference: true)
            : NSSound(named: NSSound.Name(sound))
        if let found { cache[sound] = found }
        return found
    }
}

/// The sounds there are to pick from: macOS's alert sounds, then any in the Sounds
/// folders of the Library, the same places System Settings looks.
enum NotificationSoundLibrary {
    static let audioExtensions: Set<String> = ["aiff", "aif", "aifc", "caf", "wav", "mp3", "m4a"]

    private static var folders: [URL] {
        let fm = FileManager.default
        return [URL(fileURLWithPath: "/System/Library/Sounds")]
            + fm.urls(for: .libraryDirectory, in: .localDomainMask).map { $0.appendingPathComponent("Sounds") }
            + fm.urls(for: .libraryDirectory, in: .userDomainMask).map { $0.appendingPathComponent("Sounds") }
    }

    /// Names `NSSound(named:)` finds, in folder order, each once.
    static func available() -> [String] {
        var seen: Set<String> = []
        var names: [String] = []
        for folder in folders {
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            let inFolder = files
                .filter { audioExtensions.contains($0.pathExtension.lowercased()) }
                .map { $0.deletingPathExtension().lastPathComponent }
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            for name in inFolder where seen.insert(name).inserted { names.append(name) }
        }
        return names
    }

    /// A file picked from disk is kept as its full path; a named sound never has a slash.
    static func isFile(_ sound: String) -> Bool { sound.hasPrefix("/") }

    static func displayName(of sound: String) -> String {
        isFile(sound) ? URL(fileURLWithPath: sound).deletingPathExtension().lastPathComponent : sound
    }

    /// System Settings › Notifications, where an app's own sound is turned off.
    static func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
