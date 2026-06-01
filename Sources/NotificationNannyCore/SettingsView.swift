import SwiftUI
import AppKit

package struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var repositioner: NotificationRepositioner
    @EnvironmentObject var launchAtLogin: LaunchAtLogin

    private enum PresetMode: Equatable { case idle, adding, renaming(UUID) }
    private enum GroupMode: Equatable  { case browsing, adding }

    @State private var selectedGroupID: UUID? = nil
    @State private var groupMode: GroupMode = .browsing
    @State private var newGroupName = ""
    @State private var presetMode: PresetMode = .idle
    @State private var pendingName = ""
    @State private var iconCache: [String: NSImage] = [:]
    @State private var showResetConfirmation = false

    package init() {}

    private var screens: [NSScreen] { NSScreen.screens }

    private var selectedScreen: NSScreen {
        if let id = selectedGroupID,
           let group = settings.appGroups.first(where: { $0.id == id }),
           group.targetDisplayID != 0,
           let s = screens.first(where: { $0.displayID == group.targetDisplayID }) { return s }
        if settings.targetDisplayID != 0,
           let s = screens.first(where: { $0.displayID == settings.targetDisplayID }) { return s }
        return NSScreen.main ?? screens[0]
    }

    private var activePlacementBinding: Binding<ScreenPlacement> {
        if let id = selectedGroupID, settings.appGroups.contains(where: { $0.id == id }) {
            return settings.placementBinding(for: id)
        }
        return settings.placementBinding(for: selectedScreen)
    }

    package var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                exceptionsSection
                Divider()
                positionSection
                Divider()
                autoDismissSection
                Divider()
                presetsSection
                Divider()
                generalSection
            }
            .padding(20)
        }
        .frame(width: 400)
        .frame(minHeight: 500)
        .tint(Color.nannyAccent)
        .onChange(of: settings.appGroups) { _, groups in
            if let id = selectedGroupID, !groups.contains(where: { $0.id == id }) {
                selectedGroupID = nil
            }
        }
    }

    // MARK: - Exceptions

    private var exceptionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Exceptions")
                    .font(.headline)
                Spacer()
                if groupMode == .adding {
                    HStack(spacing: 6) {
                        TextField("Name", text: $newGroupName)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.mini)
                            .font(.caption)
                            .frame(width: 120)
                            .onSubmit { commitNewGroup() }
                        Button("Create", action: commitNewGroup)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.mini)
                            .disabled(newGroupName.trimmingCharacters(in: .whitespaces).isEmpty)
                        Button("Cancel") { newGroupName = ""; groupMode = .browsing }
                            .buttonStyle(.borderless)
                            .controlSize(.mini)
                    }
                } else {
                    Button { groupMode = .adding } label: {
                        Image(systemName: "plus").font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
            }

            Text("Exceptions override the default position for specific apps.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if settings.appGroups.isEmpty && groupMode != .adding {
                Text("No exceptions yet.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(settings.appGroups) { group in
                            exceptionChip(
                                title: group.name,
                                isSelected: selectedGroupID == group.id,
                                onDelete: { settings.deleteGroup(group.id) }
                            ) {
                                selectedGroupID = selectedGroupID == group.id ? nil : group.id
                            }
                        }
                    }
                    .padding(.vertical, 1)
                }
            }

            if let id = selectedGroupID, let group = settings.appGroups.first(where: { $0.id == id }) {
                VStack(alignment: .leading, spacing: 8) {
                    if screens.count > 1 {
                        exceptionScreenPicker(for: group)
                    }
                    appAssignmentRow(for: group)
                }
                .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private func exceptionChip(title: String, isSelected: Bool,
                                onDelete: (() -> Void)? = nil,
                                action: @escaping () -> Void) -> some View {
        HStack(spacing: 0) {
            Button(action: action) {
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
                    .padding(.leading, 9)
                    .padding(.trailing, onDelete == nil ? 9 : 5)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .padding(.trailing, 7)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .foregroundStyle(isSelected ? Color.white.opacity(0.7) : Color.secondary)
            }
        }
        .background(isSelected ? Color.nannyAccent : Color.clear)
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(isSelected ? Color.clear : Color.secondary.opacity(0.35), lineWidth: 1))
    }

    private func exceptionScreenPicker(for group: AppGroup) -> some View {
        let binding = Binding<CGDirectDisplayID>(
            get: { settings.appGroups.first(where: { $0.id == group.id })?.targetDisplayID ?? 0 },
            set: { newVal in
                guard let i = settings.appGroups.firstIndex(where: { $0.id == group.id }) else { return }
                settings.appGroups[i].targetDisplayID = newVal
            }
        )
        return HStack(spacing: 8) {
            Text("Show on")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Picker("", selection: binding) {
                Text("Default").tag(CGDirectDisplayID(0))
                ForEach(screens, id: \.displayID) { screen in
                    Text(screen.nannyDisplayName).tag(screen.displayID)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.mini)
            Spacer()
        }
    }

    @ViewBuilder
    private func appAssignmentRow(for group: AppGroup) -> some View {
        ScrollView(showsIndicators: true) {
            VStack(alignment: .leading, spacing: 1) {
                if settings.knownAppNames.isEmpty {
                    Text("No apps seen yet — receive a notification from any app and it will appear here.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 6)
                } else {
                    ForEach(settings.knownAppNames, id: \.self) { appName in
                        let inThisGroup = group.appNames.contains(appName)
                        Toggle(isOn: Binding(
                            get: { inThisGroup },
                            set: { on in
                                if on { settings.addApp(appName, toGroup: group.id) }
                                else  { settings.removeApp(appName, fromGroup: group.id) }
                            }
                        )) {
                            HStack(spacing: 6) {
                                if let icon = cachedIcon(for: appName) {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: 16, height: 16)
                                }
                                Text(appName).font(.caption).lineLimit(1)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .controlSize(.small)
                        .padding(.vertical, 2)
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            inThisGroup ? Color.nannyAccent.opacity(0.08) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 4)
                        )
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .frame(minHeight: 60, maxHeight: 140)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
    }

    private func cachedIcon(for appName: String) -> NSImage? {
        if let hit = iconCache[appName] { return hit }
        let dirs = [
            "/Applications",
            NSHomeDirectory() + "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
        ]
        for dir in dirs {
            let path = "\(dir)/\(appName).app"
            if FileManager.default.fileExists(atPath: path) {
                let img = NSWorkspace.shared.icon(forFile: path)
                img.size = NSSize(width: 16, height: 16)
                DispatchQueue.main.async { iconCache[appName] = img }
                return img
            }
        }
        return nil
    }

    private func commitNewGroup() {
        let name = newGroupName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let id = settings.addGroup(name: name)
        selectedGroupID = id
        newGroupName = ""
        groupMode = .browsing
    }

    // MARK: - Position tile

    private var positionSection: some View {
        let visible = selectedScreen.visibleFrame
        let groupName = selectedGroupID.flatMap { id in settings.appGroups.first(where: { $0.id == id })?.name }
        let isDefault = activePlacementBinding.wrappedValue.xOffset == 0
                     && activePlacementBinding.wrappedValue.yOffset == 0
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(groupName.map { "Exception · \($0)" } ?? "Default Position")
                    .font(.headline)
                Spacer()
                Text("\(Int(visible.width)) × \(Int(visible.height))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            if selectedGroupID == nil && screens.count > 1 {
                HStack(spacing: 8) {
                    Text("Show on")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $settings.targetDisplayID) {
                        Text("Auto").tag(CGDirectDisplayID(0))
                        ForEach(screens, id: \.displayID) { screen in
                            Text(screen.nannyDisplayName).tag(screen.displayID)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                }
            }
            DraggableScreenTile(screen: selectedScreen, placement: activePlacementBinding)
                .frame(maxWidth: .infinity, alignment: .center)
            HStack {
                Text("Fine-tune")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reset") {
                    activePlacementBinding.wrappedValue.xOffset = 0
                    activePlacementBinding.wrappedValue.yOffset = 0
                }
                .buttonStyle(.borderless)
                .font(.caption2)
                .disabled(isDefault)
            }
            sliderRow(title: "Horizontal", value: activePlacementBinding.xOffset,
                      range: -Double(visible.width)...Double(visible.width))
            sliderRow(title: "Vertical", value: activePlacementBinding.yOffset,
                      range: -Double(visible.height)...Double(visible.height))
            Button {
                repositioner.sendTestNotification(groupID: selectedGroupID)
            } label: {
                let name = selectedGroupID.flatMap { id in settings.appGroups.first(where: { $0.id == id })?.name }
                Label(name.map { "Test \"\($0)\" Position" } ?? "Send Test Notification",
                      systemImage: "paperplane.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Slider(value: value, in: range).controlSize(.mini)
                TextField("0", value: value, format: .number.precision(.fractionLength(0)))
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.mini)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 56)
                    .font(.caption2.monospacedDigit())
                Text("px").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Auto-dismiss

    private var autoDismissSection: some View {
        HStack(spacing: 8) {
            Text("Auto-dismiss").font(.headline)
            Spacer()
            if settings.autoDismissSeconds > 0 {
                TextField("", value: $settings.autoDismissSeconds,
                          format: .number.precision(.fractionLength(0)))
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.mini)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 40)
                    .font(.caption2.monospacedDigit())
                Stepper("", value: $settings.autoDismissSeconds, in: 1...300, step: 1)
                    .labelsHidden()
                    .controlSize(.mini)
                Text("s").font(.caption2).foregroundStyle(.secondary)
            }
            Toggle("", isOn: Binding(
                get: { settings.autoDismissSeconds > 0 },
                set: { settings.autoDismissSeconds = $0 ? 10 : 0 }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
        }
    }

    // MARK: - Presets

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Presets").font(.headline)

            if settings.presets.isEmpty, presetMode == .idle {
                Text("No presets yet")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            ForEach(Array(settings.presets.enumerated()), id: \.element.id) { index, preset in
                presetRow(preset, index: index)
            }

            if presetMode == .adding {
                HStack(spacing: 6) {
                    TextField("Name", text: $pendingName)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.mini)
                        .font(.caption)
                        .onSubmit { commitPreset() }
                    Button("Save", action: commitPreset)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)
                        .disabled(pendingName.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Cancel") { pendingName = ""; presetMode = .idle }
                        .buttonStyle(.borderless)
                        .controlSize(.mini)
                }
            } else if settings.presets.count < 5 {
                Button { pendingName = ""; presetMode = .adding } label: {
                    Label("Save current as preset", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .font(.caption)
            } else {
                Text("5 preset limit reached")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private func presetRow(_ preset: Preset, index: Int) -> some View {
        if presetMode == .renaming(preset.id) {
            HStack(spacing: 6) {
                TextField("", text: $pendingName)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.mini)
                    .font(.caption)
                    .onSubmit { commitRename(preset) }
                Button("Done") { commitRename(preset) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                    .disabled(pendingName.trimmingCharacters(in: .whitespaces).isEmpty)
                Button { cancelRename() } label: {
                    Image(systemName: "xmark").font(.caption2)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
        } else {
            HStack(spacing: 4) {
                Button(preset.name) { settings.applyPreset(preset) }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
                Button { movePreset(at: index, by: -1) } label: {
                    Image(systemName: "chevron.up").font(.caption2)
                }
                .buttonStyle(.borderless).foregroundStyle(.secondary).disabled(index == 0)
                Button { movePreset(at: index, by: 1) } label: {
                    Image(systemName: "chevron.down").font(.caption2)
                }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
                .disabled(index == settings.presets.count - 1)
                Button { beginRename(preset) } label: {
                    Image(systemName: "pencil").font(.caption2)
                }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
                Button { settings.deletePreset(preset) } label: {
                    Image(systemName: "xmark").font(.caption2)
                }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
            }
        }
    }

    private func movePreset(at index: Int, by offset: Int) {
        let dest = index + offset
        guard dest >= 0, dest < settings.presets.count else { return }
        var updated = settings.presets; updated.swapAt(index, dest); settings.presets = updated
    }

    private func beginRename(_ preset: Preset) { presetMode = .renaming(preset.id); pendingName = preset.name }

    private func commitRename(_ preset: Preset) {
        let trimmed = pendingName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let i = settings.presets.firstIndex(where: { $0.id == preset.id }) else { cancelRename(); return }
        var updated = settings.presets; updated[i].name = trimmed; settings.presets = updated
        presetMode = .idle; pendingName = ""
    }

    private func cancelRename() { presetMode = .idle; pendingName = "" }

    private func commitPreset() {
        let name = pendingName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        settings.saveCurrentAsPreset(name: name)
        pendingName = ""; presetMode = .idle
    }

    // MARK: - General

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("General").font(.headline)

            Toggle("Launch at login", isOn: Binding(
                get: { launchAtLogin.isEnabled },
                set: { launchAtLogin.setEnabled($0) }
            ))
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .font(.caption)

            Toggle("Pause while screen sharing", isOn: $settings.pauseWhileStreaming)
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .font(.caption)

            if let error = launchAtLogin.lastError {
                Text(error).font(.caption2).foregroundStyle(.red)
            }

            Divider()

            Button(role: .destructive) {
                showResetConfirmation = true
            } label: {
                Label("Reset All Settings", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .confirmationDialog("Reset all settings?",
                                isPresented: $showResetConfirmation,
                                titleVisibility: .visible) {
                Button("Reset", role: .destructive) { settings.resetAllSettings() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will clear all positions, exceptions, presets and restore defaults. This cannot be undone.")
            }

            Divider()

            HStack(spacing: 4) {
                Image(systemName: "lock.shield")
                    .font(.caption2)
                Text("No data is collected, transmitted or stored outside this device.")
                    .font(.caption2)
            }
            .foregroundStyle(.tertiary)

            Button {
                NSWorkspace.shared.open(URL(string: "https://github.com/chessper53/NotificationNanny/issues/new")!)
            } label: {
                Text("Got any feedback?")
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
