import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The sound notifications play: one for All apps, and sound groups of a few apps with
/// their own. Laid out like the Banner tab, a row of groups on top and the chosen one's
/// cards under it. Everything starts on Default, each app's own sound as macOS plays it,
/// and a new group starts on the same as All apps.
struct SoundsTabView: View {
    @EnvironmentObject var settings: AppSettings

    /// The group being edited, nil for All apps.
    @State private var scope: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupScopeBar(selection: $scope, allTitleKey: "All apps",
                          groups: settings.soundGroups.map { .init(id: $0.id, name: $0.name) },
                          newTitleKey: "New sound group",
                          deleteHelpKey: "Delete sound group",
                          emptyNoteKey: "Want some apps to sound different? Make a sound group of them, and pick its sound.",
                          onCreate: { settings.addSoundGroup(name: $0) },
                          onDelete: { settings.deleteSoundGroup($0) })
            if let scope, settings.soundGroup(by: scope) != nil {
                // Its own identity per group, so nothing carries over from one to the next.
                SoundGroupEditor(groupID: scope).id(scope)
            } else {
                allApps
            }
            if settings.playsAnySound { systemSoundCard }
        }
        .onChange(of: settings.soundGroups) { _, groups in
            if let id = scope, !groups.contains(where: { $0.id == id }) { scope = nil }
        }
    }

    private var allApps: some View {
        VStack(alignment: .leading, spacing: 14) {
            SoundPickerCard(current: settings.allAppsSound.map(NotificationSoundChoice.sound) ?? .macOS,
                            showsFollow: false,
                            playing: settings.allAppsSound,
                            volume: settings.allAppsSoundVolume,
                            noteKey: settings.allAppsSound == nil
                                ? "Default. Every app plays its own sound, as macOS does."
                                : "Every app outside a sound group plays this when its banner appears.",
                            chooseMessageKey: "Pick a sound for all apps") {
                settings.allAppsSound = $0?.soundName
            }
            if settings.allAppsSound != nil {
                SoundVolumeCard(volume: $settings.allAppsSoundVolume, sound: settings.allAppsSound)
            }
        }
    }

    /// macOS plays the app's own sound as well, and only the user can turn it off. Its
    /// way there belongs to this card, so it sits in the card's header; a full width
    /// button is for a tab's one main action.
    private var systemSoundCard: some View {
        SettingsCard {
            SettingsCardHeader(titleKey: "macOS sounds") {
                CardActionButton(titleKey: "Open Notification Settings", systemImage: "bell.badge") {
                    NotificationSoundLibrary.openNotificationSettings()
                }
            }
            SettingsNote("macOS still plays each app's own sound, and nothing outside it can hold that back. To hear only the sound picked here, open System Settings › Notifications, click the app under Application Notifications, and turn off \"Play sound for notification\".")
        }
    }
}

/// One sound group's cards: its apps, its sound, and how loud.
struct SoundGroupEditor: View {
    let groupID: UUID

    @EnvironmentObject var settings: AppSettings

    private var group: SoundGroup? { settings.soundGroup(by: groupID) }

    var body: some View {
        if let group {
            let effective = settings.allAppsSound.map { ($0, settings.allAppsSoundVolume) }
            let playing: (String, Double)? = switch group.sound {
            case nil: effective
            case .macOS: nil
            case .sound(let name): (name, group.volume)
            }
            VStack(alignment: .leading, spacing: 14) {
                GroupAppPicker(assigned: group.appNames, knownApps: settings.knownAppNames,
                               owner: { settings.soundGroup(for: $0)?.name },
                               noteKey: "Notifications from these apps play the sound below. An app is in one sound group at most.",
                               onAdd: { settings.addApp($0, toSoundGroup: group.id) },
                               onRemove: { settings.removeApp($0, fromSoundGroup: group.id) })
                SoundPickerCard(current: group.sound, showsFollow: true,
                                playing: playing?.0, volume: playing?.1 ?? 1,
                                noteKey: noteKey(group.sound),
                                chooseMessageKey: "Pick a sound for this sound group") { choice in
                    settings.updateSoundGroup(groupID) { $0.sound = choice }
                }
                if let own = group.sound?.soundName {
                    SoundVolumeCard(volume: Binding(
                        get: { settings.soundGroup(by: groupID)?.volume ?? 1 },
                        set: { v in settings.updateSoundGroup(groupID) { $0.volume = v } }
                    ), sound: own)
                }
            }
        }
    }

    private func noteKey(_ sound: NotificationSoundChoice?) -> String {
        switch sound {
        case nil: return "Same as All apps."
        case .macOS: return "Default. These apps play their own sound, as macOS does."
        case .sound: return "Plays when a banner from one of these apps appears. Sounds you add to the Sounds folder in your Library show up here too."
        }
    }
}

/// The sounds as a grid of chips: Default first, the Mac's sounds, a picked file, and a
/// chip to pick one. Picking a sound plays it.
private struct SoundPickerCard: View {
    /// nil while a group follows All apps.
    let current: NotificationSoundChoice?
    /// "Same as All apps", for a group.
    let showsFollow: Bool
    /// What plays for this card now, for Play; nil for macOS's own.
    let playing: String?
    let volume: Double
    let noteKey: String
    /// What the file picker asks for: a sound for all apps, or for this sound group.
    let chooseMessageKey: String
    let onPick: (NotificationSoundChoice?) -> Void

    @ObservedObject private var loc = LocalizationManager.shared
    /// Read once: the Library's sounds don't change while the tab is open.
    @State private var library = NotificationSoundLibrary.available()

    var body: some View {
        SettingsCard {
            SettingsCardHeader(titleKey: "Sound") {
                HStack(spacing: 12) {
                    // An action, not one of the sounds, so it sits with Play rather than
                    // among them, where its name was cut to fit a chip.
                    CardActionButton(titleKey: "Choose File…", systemImage: "folder") { chooseFile() }
                    if let playing {
                        CardActionButton(titleKey: "Play", systemImage: "play.fill") {
                            SoundPlayer.shared.play(playing, volume: volume)
                        }
                    }
                }
            }
            if showsFollow {
                FollowChip(titleKey: "Same as All apps", selected: current == nil) { onPick(nil) }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 94), spacing: 8)], spacing: 8) {
                // A bell, the app's own notification sound: the struck-through ring the
                // colours use for "none" read here as no sound at all.
                ChoiceChip(title: loc.string("Default"), systemImage: "bell", selected: current == .macOS) {
                    onPick(.macOS)
                }
                .help(loc.string("Each app's own sound, as macOS plays it"))
                ForEach(library, id: \.self) { name in
                    ChoiceChip(title: name, selected: current == .sound(name)) {
                        pick(name)
                    }
                }
                if let file = current?.soundName, NotificationSoundLibrary.isFile(file) {
                    ChoiceChip(title: NotificationSoundLibrary.displayName(of: file),
                               systemImage: "music.note", selected: true) {
                        SoundPlayer.shared.play(file, volume: volume)
                    }
                    .help(file)
                }
            }
            SettingsNote(noteKey)
        }
    }

    private func pick(_ sound: String) {
        onPick(.sound(sound))
        SoundPlayer.shared.play(sound, volume: volume)
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = loc.string(chooseMessageKey)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        pick(url.path)
    }
}

/// How loud a sound plays, heard once the slider is let go.
private struct SoundVolumeCard: View {
    @Binding var volume: Double
    let sound: String?

    var body: some View {
        SettingsCard {
            SettingsCardHeader(titleKey: "Volume") {
                SettingsTextButton(titleKey: "Reset", disabled: volume >= 0.995) { volume = 1 }
            }
            HStack(spacing: 8) {
                Image(systemName: "speaker.fill").font(.caption2).foregroundStyle(.secondary)
                Slider(value: $volume, in: 0.05...1) { editing in
                    // Heard once let go, at the new volume, not on every step of the drag.
                    if !editing, let sound { SoundPlayer.shared.play(sound, volume: volume) }
                }
                .controlSize(.mini)
                Image(systemName: "speaker.wave.3.fill").font(.caption2).foregroundStyle(.secondary)
                Text("\(Int((volume * 100).rounded()))%")
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary).frame(width: 38, alignment: .trailing)
            }
            SettingsNote("Relative to your Mac's volume.")
        }
    }
}
