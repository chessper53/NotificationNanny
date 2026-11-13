import Foundation

package enum NotificationSoundChoice: Codable, Hashable {
    /// The app's own sound, as macOS plays it; nothing from NotificationNanny.
    case macOS
    /// A named sound or an absolute path to a chosen sound file.
    case sound(String)

    /// Stored as one string, empty for `.macOS`: no sound is named "" and no path is empty.
    package init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = value.isEmpty ? .macOS : .sound(value)
    }

    package func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .macOS: try c.encode("")
        case .sound(let name): try c.encode(name)
        }
    }

    package var soundName: String? {
        if case .sound(let name) = self { return name }
        return nil
    }
}

/// Sound overrides independent of placement groups. Each app may belong to one sound group.
package struct SoundGroup: Identifiable, Codable, Equatable {
    package var id: UUID
    package var name: String
    package var appNames: [String]
    /// nil means the same as All apps.
    package var sound: NotificationSoundChoice?
    /// Volume multiplier from 0 to 1; All apps' volume applies when the sound is inherited.
    package var volume: Double

    package init(id: UUID = UUID(), name: String, appNames: [String] = [],
                 sound: NotificationSoundChoice? = nil, volume: Double = 1) {
        self.id = id
        self.name = name
        self.appNames = appNames
        self.sound = sound
        self.volume = volume
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, appNames, sound, volume
    }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id       = try c.decode(UUID.self, forKey: .id)
        name     = try c.decode(String.self, forKey: .name)
        appNames = try c.decodeIfPresent([String].self, forKey: .appNames) ?? []
        sound    = try c.decodeIfPresent(NotificationSoundChoice.self, forKey: .sound)
        volume   = try c.decodeIfPresent(Double.self, forKey: .volume) ?? 1
    }
}
