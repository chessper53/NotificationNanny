import SwiftUI
import AppKit

// The pieces a tab of app groups is built from: the row of groups on top, and the card
// that puts apps in one. Shared by the Banner tab's exception groups and the Sounds tab.

/// A row of chips, one per group, an optional one for everything outside them first,
/// then a button that names and adds a new group.
struct GroupScopeBar: View {
    struct Item: Identifiable {
        let id: UUID
        let name: String
    }

    /// nil for the leading chip, or for none while there are no groups.
    @Binding var selection: UUID?
    /// The leading chip, as "All apps"; nil for none.
    var allTitleKey: String? = nil
    let groups: [Item]
    let newTitleKey: String
    let deleteHelpKey: String
    /// Shown under the row until there is a group.
    let emptyNoteKey: String
    let onCreate: (String) -> UUID
    let onDelete: (UUID) -> Void

    @ObservedObject private var loc = LocalizationManager.shared
    @State private var adding = false
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            bar
            // Until there is a group, nothing on the tab says groups exist or what one is.
            if groups.isEmpty && !adding {
                SettingsNote(emptyNoteKey)
                    .padding(.leading, 2)
            }
        }
    }

    private var bar: some View {
        HStack(alignment: .center, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if let allTitleKey {
                        chip(title: loc.string(allTitleKey), selected: selection == nil) { selection = nil }
                    }
                    ForEach(groups) { group in
                        chip(title: group.name, selected: selection == group.id,
                             onDelete: { onDelete(group.id) }) { selection = group.id }
                    }
                }
                .padding(.vertical, 1)
            }

            if adding {
                HStack(spacing: 6) {
                    TextField(loc.string("Name"), text: $newName)
                        .textFieldStyle(.roundedBorder).controlSize(.small).font(.caption)
                        .frame(width: 120)
                        .onSubmit(commit)
                    Button(loc.string("Create"), action: commit)
                        .buttonStyle(.nannyProminent).controlSize(.mini)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button { newName = ""; adding = false } label: {
                        Image(systemName: "xmark").font(.caption2)
                    }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
                }
            } else {
                // Named, not a bare plus: beside "All apps" a plus alone didn't say
                // what it adds.
                Button { adding = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus").font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.nannyAccent)
                        LocalizedText(newTitleKey).font(.caption)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color.nannyRaised(0.08), in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .fixedSize()
            }
        }
    }

    private func commit() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        selection = onCreate(name)
        newName = ""
        adding = false
    }

    private func chip(title: String, selected: Bool, onDelete: (() -> Void)? = nil,
                      action: @escaping () -> Void) -> some View {
        HStack(spacing: 0) {
            Button(action: { withAnimation(.easeInOut(duration: 0.15), action) }) {
                Text(title).font(.caption).lineLimit(1)
                    .padding(.leading, 10).padding(.trailing, onDelete == nil ? 10 : 5).padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "xmark").font(.system(size: 7, weight: .bold))
                        .padding(.trailing, 8).padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .foregroundStyle(selected ? Color.white.opacity(0.7) : Color.secondary)
                .help(loc.string(deleteHelpKey))
            }
        }
        .background(selected ? Color.nannyProminent : Color.clear)
        .foregroundStyle(selected ? Color.white : Color.primary)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(selected ? Color.clear : Color.nannyRaised(0.15), lineWidth: 1))
    }
}

/// A group's apps: the ones in it, then everything else, each a click away from moving
/// in or out.
struct GroupAppPicker: View {
    /// The apps in the group.
    ///
    /// Taken from the group directly rather than from the apps seen, so an app that
    /// hasn't notified since launch, or came in with an import or preset, is still
    /// listed and can be taken out.
    let assigned: [String]
    /// Every app seen notifying.
    let knownApps: [String]
    /// The other group an app outside this one is in now, if any.
    let owner: (String) -> String?
    let noteKey: String
    let onAdd: (String) -> Void
    let onRemove: (String) -> Void

    @ObservedObject private var loc = LocalizationManager.shared
    @State private var appFilter = ""
    private let iconCache = AppIconCache.shared

    /// One row of the app picker. App names are unique within the picker, so the
    /// name is the identity — and it stays stable as a row moves between the
    /// assigned and available halves.
    private struct AppPick: Identifiable, Equatable {
        let name: String
        let isAssigned: Bool
        var id: String { name }
    }

    var body: some View {
        let assigned = assigned.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let query = appFilter.trimmingCharacters(in: .whitespaces)
        let available = knownApps
            .filter { !assigned.contains($0) }
            .filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }
        // One ForEach over one array, not two siblings with a conditional
        // Divider between them. Clicking a row moves it between the assigned
        // and available sets; across two ForEachs that reshuffles structural
        // identity and SwiftUI would leave rows showing another row's
        // checkmark. The separator rides along inside the row that starts the
        // available section so the identity space stays flat.
        let rows = assigned.map { AppPick(name: $0, isAssigned: true) }
                 + available.map { AppPick(name: $0, isAssigned: false) }

        SettingsCard {
            HStack(spacing: 6) {
                LocalizedText("Assigned Apps").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Text("\(assigned.count)")
                    .font(.caption2.monospacedDigit().weight(.medium))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Color.nannyWash(0.22), in: Capsule())
                Spacer()
                // Only worth the space once scanning the list by eye stops working.
                if knownApps.count > 8 { filterField }
            }

            ScrollView(showsIndicators: true) {
                // Plain VStack, not Lazy: the list tops out around twenty rows, and
                // LazyVStack was opening the scroller part-way down, hiding exactly
                // the assigned rows this section exists to show.
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(rows) { row in
                        if row.name == available.first && !assigned.isEmpty {
                            Divider().padding(.vertical, 3).padding(.horizontal, 6)
                        }
                        appRow(row.name, isAssigned: row.isAssigned)
                    }

                    if rows.isEmpty {
                        LocalizedText(knownApps.isEmpty
                            ? "No apps seen yet. Receive a notification from any app and it will appear here."
                            : "No apps match your filter.")
                            .font(.caption2).foregroundStyle(Color.nannyNote)
                            .padding(.horizontal, 6).padding(.vertical, 6)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(minHeight: 60, maxHeight: 160)
            .background(Color.nannyInset(0.15), in: RoundedRectangle(cornerRadius: 6))

            SettingsNote(noteKey)
        }
    }

    private var filterField: some View {
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
        .background(Color.nannyRaised(0.06), in: Capsule())
    }

    private func appRow(_ appName: String, isAssigned: Bool) -> some View {
        // Membership is exclusive, so this is a "will be moved out of X" warning,
        // not a conflict.
        let currentOwner = isAssigned ? nil : owner(appName)

        return Button {
            if isAssigned { onRemove(appName) } else { onAdd(appName) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isAssigned ? "checkmark.circle.fill" : "circle")
                    .font(.caption)
                    .foregroundStyle(isAssigned ? Color.nannyAccent : Color.secondary.opacity(0.5))
                if let icon = iconCache.icon(for: appName) {
                    Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                } else {
                    // Blank, not a placeholder glyph: anything drawn here sits
                    // right next to the selection circle and reads as a second
                    // checkbox. Reserving the space keeps the names aligned.
                    Color.clear.frame(width: 16, height: 16)
                }
                Text(appName).font(.caption).lineLimit(1)
                Spacer(minLength: 4)
                if let currentOwner {
                    Text(loc.string("in") + " \"\(currentOwner)\"")
                        .font(.caption2).foregroundStyle(Color.nannyNote).lineLimit(1)
                        .help(loc.string("Assigning this app here will move it out of this group."))
                }
            }
            .padding(.vertical, 3).padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isAssigned ? Color.nannyWash(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
    }
}
