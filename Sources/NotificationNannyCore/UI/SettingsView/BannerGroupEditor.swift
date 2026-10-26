import SwiftUI
import AppKit

/// The row at the top of the Banner tab: All apps, then each group, then a new one.
///
/// Groups were a tab of their own, Exceptions, but a group is the Banner tab's settings
/// for a few apps plus where those apps go, so it is edited here with the same cards.
/// Nothing about how groups are stored changed with the move.
struct BannerScopeBar: View {
    /// nil for All apps.
    @Binding var groupID: UUID?

    @EnvironmentObject var settings: AppSettings

    var body: some View {
        GroupScopeBar(selection: $groupID, allTitleKey: "All apps",
                      groups: settings.appGroups.map { .init(id: $0.id, name: $0.name) },
                      newTitleKey: "New exception group",
                      deleteHelpKey: "Delete exception group",
                      emptyNoteKey: "Want different settings for some apps? Make an exception group of them, and pick what's different.",
                      onCreate: { settings.addGroup(name: $0) },
                      onDelete: { settings.deleteGroup($0) })
    }
}

/// One group's settings, as the Banner tab's cards: its apps and where they go, then
/// what it may set apart from All apps. Each of those starts on "Same as All apps",
/// which is the group having none of its own, as it is stored.
struct BannerGroupEditor: View {
    let groupID: UUID

    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var repositioner: NotificationRepositioner
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var previewReplay = 0

    private var group: AppGroup? { settings.group(by: groupID) }

    var body: some View {
        if let group {
            VStack(alignment: .leading, spacing: 14) {
                appsCard(group)
                positionCard(group)
                scaleCard(group)
                backgroundCard(group)
                animationCard(group)

                Button { repositioner.sendTestNotification(groupID: group.id) } label: {
                    Label {
                        Text(loc.string("Send Test Notification") + " · \(group.name)")
                    } icon: {
                        Image(systemName: "paperplane.fill")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.nannyProminent).controlSize(.regular)
            }
        }
    }

    // MARK: - Where

    private func positionCard(_ group: AppGroup) -> some View {
        let screen = settings.resolvedTargetScreen(forGroupID: group.id)
            ?? settings.resolvedTargetScreen()
            ?? NSScreen.main ?? NSScreen.screens[0]
        return PositionCard(titleKey: "Position", screen: screen,
                            display: Binding(
                                get: { settings.group(by: group.id)?.targetDisplayID ?? 0 },
                                set: { settings.setGroupTargetDisplay($0, forGroupID: group.id) }
                            ),
                            resolvedDisplay: settings.resolvedTargetScreen(forGroupID: group.id),
                            zeroLabelKey: "Default", placement: settings.placementBinding(for: group.id),
                            previewHeight: 220,
                            noteKey: "This exception group's own place, on the screen picked above. Default is the screen All apps use.")
    }

    // MARK: - Looks

    private func scaleCard(_ group: AppGroup) -> some View {
        SettingsCard {
            SettingsCardHeader("Scale")
            HStack(spacing: 10) {
                FollowChip(titleKey: "Same as All apps", selected: group.bannerScale == nil) {
                    update { $0.bannerScale = nil }
                }
                SettingsScaleSlider(value: Binding(
                    get: { settings.group(by: group.id)?.bannerScale ?? settings.bannerScale },
                    set: { v in update { $0.bannerScale = v } }
                ), range: 0.5...2.5)
            }
        }
    }

    private func backgroundCard(_ group: AppGroup) -> some View {
        SettingsCard {
            SettingsCardHeader("Background Color")
            ColorSwatchRow(isDefault: false, current: group.bannerTint?.color, showsDefault: false,
                           onDefault: {},
                           onPick: { color in update { $0.bannerTint = SettingsColors.tint(of: color) } }) {
                FollowChip(titleKey: "Same as All apps", selected: group.bannerTint == nil) {
                    update { $0.bannerTint = nil }
                }
            }
        }
    }

    private func animationCard(_ group: AppGroup) -> some View {
        let effective = group.bannerAnimation ?? settings.bannerAnimation
        let tint = group.bannerTint?.color ?? (settings.hasBannerColor ? settings.bannerColor : .clear)
        return SettingsCard {
            SettingsCardHeader(titleKey: "Animation") {
                CardActionButton.replay { previewReplay &+= 1 }
            }
            AnimationPreviewPane(animation: effective, replay: previewReplay, tint: tint,
                                 textColor: settings.effectiveBannerTextColor ?? .primary)
                .animationPreviewWell { previewReplay &+= 1 }
            FollowChip(titleKey: "Same as All apps", selected: group.bannerAnimation == nil) {
                update { $0.bannerAnimation = nil }
                previewReplay &+= 1
            }
            AnimationChipGrid(selected: group.bannerAnimation) { anim in
                update { $0.bannerAnimation = anim }
                previewReplay &+= 1
            }
        }
    }

    /// One assignment to `appGroups` per edit, so observers never see a
    /// half-applied group.
    private func update(_ mutate: (inout AppGroup) -> Void) {
        guard let i = settings.appGroups.firstIndex(where: { $0.id == groupID }) else { return }
        var updated = settings.appGroups
        mutate(&updated[i])
        settings.appGroups = updated
    }

    // MARK: - Apps

    private func appsCard(_ group: AppGroup) -> some View {
        GroupAppPicker(assigned: group.appNames, knownApps: settings.knownAppNames,
                       owner: { settings.group(for: $0)?.name },
                       noteKey: "Apps in an exception group use its settings below instead of All apps'. An app is in one exception group at most.",
                       onAdd: { settings.addApp($0, toGroup: group.id) },
                       onRemove: { settings.removeApp($0, fromGroup: group.id) })
    }
}
