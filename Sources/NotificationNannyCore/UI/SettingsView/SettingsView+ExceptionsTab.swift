import SwiftUI
import AppKit

struct ExceptionsTabView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var repositioner: NotificationRepositioner
    @ObservedObject private var loc = LocalizationManager.shared

    private enum GroupMode: Equatable { case browsing, adding }

    /// One row of the app picker. App names are unique within the picker, so the
    /// name is the identity — and it stays stable as a row moves between the
    /// assigned and available halves.
    private struct AppPick: Identifiable, Equatable {
        let name: String
        let isAssigned: Bool
        var id: String { name }
    }

    @State private var selectedGroupID: UUID? = nil
    @State private var groupMode: GroupMode = .browsing
    @State private var newGroupName = ""
    @State private var appFilter = ""
    private let iconCache = AppIconCache.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LocalizedText("Create groups of apps and give each group its own rules: position, screen, banner type, and scale. Apps not in any group use the defaults.")
                .font(.callout)
                .foregroundStyle(Color(white: 0.55))
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .center, spacing: 8) {
                if settings.appGroups.isEmpty && groupMode != .adding {
                    LocalizedText("No exceptions yet.").font(.caption).foregroundStyle(.tertiary)
                    Spacer()
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(settings.appGroups) { group in
                                exceptionChip(
                                    title: group.name, isSelected: selectedGroupID == group.id,
                                    onDelete: { settings.deleteGroup(group.id) }
                                ) {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        selectedGroupID = selectedGroupID == group.id ? nil : group.id
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 1)
                    }
                }

                if groupMode == .adding {
                    HStack(spacing: 6) {
                        TextField(loc.string("Name"), text: $newGroupName)
                            .textFieldStyle(.roundedBorder).controlSize(.small).font(.caption)
                            .onSubmit { commitNewGroup() }
                        Button(loc.string("Create"), action: commitNewGroup)
                            .buttonStyle(.borderedProminent).controlSize(.mini)
                            .disabled(newGroupName.trimmingCharacters(in: .whitespaces).isEmpty)
                        Button { newGroupName = ""; groupMode = .browsing } label: {
                            Image(systemName: "xmark").font(.caption2)
                        }
                        .buttonStyle(.borderless).foregroundStyle(.secondary)
                    }
                } else {
                    Button { groupMode = .adding } label: {
                        Image(systemName: "plus").font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered).controlSize(.mini)
                }
            }

            if let id = selectedGroupID,
               let group = settings.appGroups.first(where: { $0.id == id }) {
                exceptionDetail(for: group)
            }
        }
        .onAppear {
            if selectedGroupID == nil, let first = settings.appGroups.first {
                selectedGroupID = first.id
            }
        }
        .onChange(of: settings.appGroups) { _, groups in
            if let id = selectedGroupID, !groups.contains(where: { $0.id == id }) {
                selectedGroupID = nil
            }
        }
        // A filter left over from the previous group would silently hide apps.
        .onChange(of: selectedGroupID) { _, _ in appFilter = "" }
    }

    @ViewBuilder
    private func exceptionDetail(for group: AppGroup) -> some View {
        let screens = NSScreen.screens
        let exScreen: NSScreen = settings.resolvedTargetScreen(forGroupID: group.id)
            ?? settings.resolvedTargetScreen()
            ?? NSScreen.main ?? screens[0]
        let placementBinding = settings.placementBinding(for: group.id)

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(group.name).font(.subheadline.weight(.semibold))
                Spacer()
                if screens.count > 1 {
                    let displayBinding = Binding<CGDirectDisplayID>(
                        get: { settings.appGroups.first(where: { $0.id == group.id })?.targetDisplayID ?? 0 },
                        set: { newVal in settings.setGroupTargetDisplay(newVal, forGroupID: group.id) }
                    )
                    HStack(spacing: 4) {
                        LocalizedText("Screen:").font(.caption).foregroundStyle(.secondary)
                        Picker("", selection: displayBinding) {
                            LocalizedText("Default").tag(CGDirectDisplayID(0))
                            ForEach(screens, id: \.displayID) { screen in
                                Text(screen.nannyDisplayName).tag(screen.displayID)
                            }
                        }
                        .labelsHidden().pickerStyle(.menu).controlSize(.mini)
                    }
                }
            }

            // Sized so the whole group panel — preview, appearance, app list and
            // the test button — clears the fixed 640pt window even while the
            // accessibility banner is taking a strip off the top.
            PlacementEditor(screen: exScreen, placement: placementBinding,
                            maxWidth: 408, maxHeight: 148)

            GroupAppearanceControls(groupID: group.id)

            appAssignmentSection(for: group)

            Button { repositioner.sendTestNotification(groupID: group.id) } label: {
                Label("Test \"\(group.name)\"", systemImage: "paperplane.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.small)
        }
        .padding(14)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    /// Apps in the group, then everything else.
    ///
    /// The previous version listed `knownAppNames` as one flat checklist, which
    /// answered "which apps exist" rather than the question actually being asked,
    /// "what is in this group" — you had to scroll a 140pt box to find out. It also
    /// hid any assigned app that wasn't in `knownAppNames` (imported groups,
    /// presets, an app that hasn't notified since launch), leaving it assigned with
    /// no way to remove it. Assigned rows now come from `group.appNames` directly,
    /// so nothing can be stranded.
    @ViewBuilder
    private func appAssignmentSection(for group: AppGroup) -> some View {
        let assigned = group.appNames.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let query = appFilter.trimmingCharacters(in: .whitespaces)
        let available = settings.knownAppNames
            .filter { !group.appNames.contains($0) }
            .filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                LocalizedText("Assigned Apps")
                    .font(.footnote.weight(.semibold)).foregroundStyle(Color(white: 0.45))
                Text("\(assigned.count)")
                    .font(.caption2.monospacedDigit().weight(.medium))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Color.nannyAccent.opacity(0.22), in: Capsule())
                Spacer()
                // Only worth the space once scanning the list by eye stops working.
                if settings.knownAppNames.count > 8 {
                    HStack(spacing: 3) {
                        Image(systemName: "magnifyingglass")
                            .font(.caption2).foregroundStyle(.tertiary)
                        TextField(loc.string("Filter"), text: $appFilter)
                            .textFieldStyle(.plain).font(.caption)
                            .frame(width: 110)
                        if !appFilter.isEmpty {
                            Button { appFilter = "" } label: {
                                Image(systemName: "xmark.circle.fill").font(.caption2)
                            }
                            .buttonStyle(.plain).foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.white.opacity(0.06), in: Capsule())
                }
            }

            // One ForEach over one array, not two siblings with a conditional
            // Divider between them. Clicking a row moves it between the assigned
            // and available sets; across two ForEachs that reshuffles structural
            // identity and SwiftUI would leave rows showing another row's
            // checkmark. The separator rides along inside the row that starts the
            // available section so the identity space stays flat.
            let rows = assigned.map { AppPick(name: $0, isAssigned: true) }
                     + available.map { AppPick(name: $0, isAssigned: false) }

            ScrollView(showsIndicators: true) {
                // Plain VStack, not Lazy: the list tops out around twenty rows, and
                // LazyVStack was opening the scroller part-way down, hiding exactly
                // the assigned rows this section exists to show.
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(rows) { row in
                        if row.name == available.first && !assigned.isEmpty {
                            Divider().padding(.vertical, 3).padding(.horizontal, 6)
                        }
                        appRow(row.name, group: group, isAssigned: row.isAssigned)
                    }

                    if rows.isEmpty {
                        LocalizedText(settings.knownAppNames.isEmpty
                            ? "No apps seen yet. Receive a notification from any app and it will appear here."
                            : "No apps match your filter.")
                            .font(.caption2).foregroundStyle(.tertiary)
                            .padding(.horizontal, 6).padding(.vertical, 6)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(minHeight: 60, maxHeight: 160)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    @ViewBuilder
    private func appRow(_ appName: String, group: AppGroup, isAssigned: Bool) -> some View {
        // Membership is exclusive — addApp pulls the name out of every other group
        // — so this is a "will be moved out of X" warning, not a conflict.
        let currentOwner = isAssigned ? nil : settings.group(for: appName).map(\.name)

        Button {
            if isAssigned { settings.removeApp(appName, fromGroup: group.id) }
            else          { settings.addApp(appName, toGroup: group.id) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isAssigned ? "checkmark.circle.fill" : "circle")
                    .font(.caption)
                    .foregroundStyle(isAssigned ? Color.nannyAccent : Color.secondary.opacity(0.5))
                if let icon = cachedIcon(for: appName) {
                    Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                } else {
                    // Blank, not a placeholder glyph: anything drawn here sits
                    // right next to the selection circle and reads as a second
                    // checkbox. Reserving the space keeps the names aligned.
                    Color.clear.frame(width: 16, height: 16)
                }
                Text(appName).font(.caption).lineLimit(1)
                if let currentOwner {
                    Spacer(minLength: 4)
                    Text(loc.string("in") + " \"\(currentOwner)\"")
                        .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                        .help(loc.string("Assigning this app here will move it out of this group."))
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 3).padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            isAssigned ? Color.nannyAccent.opacity(0.1) : Color.clear,
            in: RoundedRectangle(cornerRadius: 4)
        )
    }

    private func cachedIcon(for appName: String) -> NSImage? {
        iconCache.icon(for: appName)
    }

    @ViewBuilder
    private func exceptionChip(title: String, isSelected: Bool,
                               onDelete: (() -> Void)? = nil,
                               action: @escaping () -> Void) -> some View {
        HStack(spacing: 0) {
            Button(action: action) {
                Text(title).font(.caption).lineLimit(1)
                    .padding(.leading, 9).padding(.trailing, onDelete == nil ? 9 : 5).padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "xmark").font(.system(size: 7, weight: .bold))
                        .padding(.trailing, 7).padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .foregroundStyle(isSelected ? Color.white.opacity(0.7) : Color.secondary)
            }
        }
        .background(isSelected ? Color.nannyAccent : Color.clear)
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(isSelected ? Color.clear : Color.white.opacity(0.15), lineWidth: 1))
    }

    private func commitNewGroup() {
        let name = newGroupName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let id = settings.addGroup(name: name)
        selectedGroupID = id
        newGroupName = ""
        groupMode = .browsing
    }
}
