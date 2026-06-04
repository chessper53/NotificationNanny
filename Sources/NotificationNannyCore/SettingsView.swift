import SwiftUI
import AppKit

package struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var repositioner: NotificationRepositioner
    @EnvironmentObject var launchAtLogin: LaunchAtLogin

    private enum Tab: Hashable { case position, exceptions, presets, general, banner, backup, help }
    private enum PresetMode: Equatable { case idle, adding, renaming(UUID) }
    private enum GroupMode: Equatable  { case browsing, adding }

    @State private var activeTab: Tab = .position
    @State private var selectedGroupID: UUID? = nil
    @State private var groupMode: GroupMode = .browsing
    @State private var newGroupName = ""
    @State private var presetMode: PresetMode = .idle
    @State private var pendingName = ""
    @State private var iconCache: [String: NSImage] = [:]
    @State private var showResetConfirmation = false
    @State private var showImportConfirmation = false
    @State private var pendingImportData: Data? = nil

    package init() {}

    private var screens: [NSScreen] { NSScreen.screens }

    private var defaultScreen: NSScreen {
        if settings.targetDisplayID != 0,
           let s = screens.first(where: { $0.displayID == settings.targetDisplayID }) { return s }
        return NSScreen.main ?? screens[0]
    }

    private var defaultPlacementBinding: Binding<ScreenPlacement> {
        settings.placementBinding(for: defaultScreen)
    }

    package var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            VStack(alignment: .leading, spacing: 2) {
                sidebarItem("Position",   systemImage: "scope",              tab: .position)
                sidebarItem("Exceptions", systemImage: "app.badge",          tab: .exceptions)
                sidebarItem("Banner",     systemImage: "textformat.size",    tab: .banner)
                sidebarItem("Presets",    systemImage: "star",               tab: .presets)
                sidebarItem("General",    systemImage: "gearshape",          tab: .general)
                sidebarItem("Backup",     systemImage: "tray.and.arrow.up",  tab: .backup)
                Spacer()
                sidebarItem("Help",       systemImage: "questionmark.circle", tab: .help)
                Text("v\(appVersion)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }
            .padding(8)
            .frame(width: 150)
            .frame(maxHeight: .infinity)
            .background(Color.secondary.opacity(0.05))

            Divider()

            ScrollView {
                Group {
                    switch activeTab {
                    case .position:   positionTab
                    case .banner:     bannerTab
                    case .exceptions: exceptionsTab
                    case .presets:    presetsTab
                    case .general:    generalTab
                    case .backup:     backupTab
                    case .help:       helpTab
                    }
                }
                .padding(16)
            }
            .id(activeTab)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WindowSizeLock(width: 570, height: 560))
        .tint(Color.nannyAccent)
        .onChange(of: activeTab) { _, newTab in
            presetMode = .idle
            pendingName = ""
            groupMode = .browsing
            newGroupName = ""
            if newTab == .exceptions, selectedGroupID == nil, let first = settings.appGroups.first {
                selectedGroupID = first.id
            }
        }
        .onChange(of: settings.appGroups) { _, groups in
            if let id = selectedGroupID, !groups.contains(where: { $0.id == id }) {
                selectedGroupID = nil
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private func sidebarItem(_ label: String, systemImage: String, tab: Tab) -> some View {
        Button { activeTab = tab } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .frame(width: 16, alignment: .center)
                Text(label)
                Spacer()
            }
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(
                activeTab == tab ? Color.nannyAccent.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
            .foregroundStyle(activeTab == tab ? Color.nannyAccent : Color.primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Position Tab

    private var positionTab: some View {
        let visible = defaultScreen.visibleFrame
        let isDefault = defaultPlacementBinding.wrappedValue.xOffset == 0
                     && defaultPlacementBinding.wrappedValue.yOffset == 0
        return VStack(alignment: .leading, spacing: 14) {
            Text("Choose where notification banners appear on your screen. Drag the indicator on the preview or use the sliders to fine-tune the position.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Default Position")
                        .font(.subheadline.weight(.semibold))
                    Text("\(Int(visible.width)) × \(Int(visible.height))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if screens.count > 1 {
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

            DraggableScreenTile(screen: defaultScreen, placement: defaultPlacementBinding)
                .frame(maxWidth: .infinity, alignment: .center)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Fine-tune")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset") {
                        defaultPlacementBinding.wrappedValue.xOffset = 0
                        defaultPlacementBinding.wrappedValue.yOffset = 0
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(Color.nannyAccent)
                    .disabled(isDefault)
                }
                sliderRow(title: "Horizontal", value: defaultPlacementBinding.xOffset,
                          range: -Double(visible.width)...Double(visible.width))
                sliderRow(title: "Vertical", value: defaultPlacementBinding.yOffset,
                          range: -Double(visible.height)...Double(visible.height))
            }
            .padding(12)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.12), lineWidth: 1))

            Button {
                repositioner.sendTestNotification(groupID: nil)
            } label: {
                Label("Send Test Notification", systemImage: "paperplane.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
    }

    // MARK: - Banner Tab

    private var bannerTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Experimental disclaimer
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "flask")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.top, 1)
                Text("Experimental. The custom banner replaces the system one entirely. Some notification actions like inline replies may not work. Behavior can vary between apps and macOS versions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.2), lineWidth: 1))

            // Global scale + opacity
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Default Scale")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset") { settings.bannerScale = 1.0 }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .foregroundStyle(Color.nannyAccent)
                        .disabled(abs(settings.bannerScale - 1.0) < 0.01)
                }
                HStack(spacing: 8) {
                    Text("A").font(.caption2).foregroundStyle(.secondary)
                    Slider(value: $settings.bannerScale, in: 0.5...2.5).controlSize(.mini)
                    Text("A").font(.body.weight(.medium)).foregroundStyle(.secondary)
                    Text("\(Int(settings.bannerScale * 100))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .trailing)
                }

                Divider()

                HStack {
                    Text("Opacity")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset") { settings.bannerOpacity = 1.0 }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .foregroundStyle(Color.nannyAccent)
                        .disabled(abs(settings.bannerOpacity - 1.0) < 0.01)
                }
                HStack(spacing: 8) {
                    Image(systemName: "circle").font(.caption2).foregroundStyle(.secondary)
                    Slider(value: $settings.bannerOpacity, in: 0.1...1.0).controlSize(.mini)
                    Image(systemName: "circle.fill").font(.caption2).foregroundStyle(.secondary)
                    Text("\(Int(settings.bannerOpacity * 100))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .trailing)
                }
            }
            .padding(12)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.12), lineWidth: 1))

            // Per-group overrides
            if !settings.appGroups.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Per-app overrides")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    VStack(spacing: 0) {
                        ForEach(settings.appGroups) { group in
                            groupScaleRow(for: group)
                            if group.id != settings.appGroups.last?.id {
                                settingsDivider
                            }
                        }
                    }
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.12), lineWidth: 1))
                }
            }

            Button {
                repositioner.sendTestNotification(groupID: nil)
            } label: {
                Label("Send Test Notification", systemImage: "paperplane.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
    }

    @ViewBuilder
    private func groupScaleRow(for group: AppGroup) -> some View {
        let hasCustom = settings.appGroups.first(where: { $0.id == group.id })?.bannerScale != nil
        let scaleBinding = Binding<Double>(
            get: { settings.appGroups.first(where: { $0.id == group.id })?.bannerScale ?? settings.bannerScale },
            set: { newVal in
                guard let i = settings.appGroups.firstIndex(where: { $0.id == group.id }) else { return }
                settings.appGroups[i].bannerScale = newVal
            }
        )
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(group.name).font(.callout)
                Spacer()
                if hasCustom {
                    Button("Reset") {
                        guard let i = settings.appGroups.firstIndex(where: { $0.id == group.id }) else { return }
                        settings.appGroups[i].bannerScale = nil
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(Color.nannyAccent)
                } else {
                    Text("Using default")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Button("Customize") {
                        guard let i = settings.appGroups.firstIndex(where: { $0.id == group.id }) else { return }
                        settings.appGroups[i].bannerScale = settings.bannerScale
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(Color.nannyAccent)
                }
            }
            if hasCustom {
                HStack(spacing: 8) {
                    Text("A").font(.caption2).foregroundStyle(.secondary)
                    Slider(value: scaleBinding, in: 0.5...2.5).controlSize(.mini)
                    Text("A").font(.body.weight(.medium)).foregroundStyle(.secondary)
                    Text("\(Int(scaleBinding.wrappedValue * 100))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Exceptions Tab

    private var exceptionsTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Create groups of apps and give each group its own position and screen. Apps not in any group use the defaults from the Position tab.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .center, spacing: 8) {
                if settings.appGroups.isEmpty && groupMode != .adding {
                    Text("No exceptions yet.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(settings.appGroups) { group in
                                exceptionChip(
                                    title: group.name,
                                    isSelected: selectedGroupID == group.id,
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
                        TextField("Name", text: $newGroupName)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                            .font(.caption)
                            .frame(width: 110)
                            .onSubmit { commitNewGroup() }
                        Button("Create", action: commitNewGroup)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.mini)
                            .disabled(newGroupName.trimmingCharacters(in: .whitespaces).isEmpty)
                        Button { newGroupName = ""; groupMode = .browsing } label: {
                            Image(systemName: "xmark").font(.caption2)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    }
                } else {
                    Button { groupMode = .adding } label: {
                        Image(systemName: "plus").font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }

            if let id = selectedGroupID,
               let group = settings.appGroups.first(where: { $0.id == id }) {
                exceptionDetail(for: group)
            }
        }
    }

    @ViewBuilder
    private func exceptionDetail(for group: AppGroup) -> some View {
        let exScreen: NSScreen = {
            if group.targetDisplayID != 0,
               let s = screens.first(where: { $0.displayID == group.targetDisplayID }) { return s }
            if settings.targetDisplayID != 0,
               let s = screens.first(where: { $0.displayID == settings.targetDisplayID }) { return s }
            return NSScreen.main ?? screens[0]
        }()
        let placementBinding = settings.placementBinding(for: group.id)
        let visible = exScreen.visibleFrame
        let isDefault = placementBinding.wrappedValue.xOffset == 0
                     && placementBinding.wrappedValue.yOffset == 0

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(group.name).font(.subheadline.weight(.semibold))
                Spacer()
                if screens.count > 1 {
                    let displayBinding = Binding<CGDirectDisplayID>(
                        get: { settings.appGroups.first(where: { $0.id == group.id })?.targetDisplayID ?? 0 },
                        set: { newVal in
                            guard let i = settings.appGroups.firstIndex(where: { $0.id == group.id }) else { return }
                            settings.appGroups[i].targetDisplayID = newVal
                        }
                    )
                    HStack(spacing: 4) {
                        Text("Screen:").font(.caption).foregroundStyle(.secondary)
                        Picker("", selection: displayBinding) {
                            Text("Default").tag(CGDirectDisplayID(0))
                            ForEach(screens, id: \.displayID) { screen in
                                Text(screen.nannyDisplayName).tag(screen.displayID)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .controlSize(.mini)
                    }
                }
            }

            DraggableScreenTile(screen: exScreen, placement: placementBinding)
                .frame(maxWidth: .infinity, alignment: .center)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Fine-tune")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset") {
                        placementBinding.wrappedValue.xOffset = 0
                        placementBinding.wrappedValue.yOffset = 0
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(Color.nannyAccent)
                    .disabled(isDefault)
                }
                sliderRow(title: "Horizontal", value: placementBinding.xOffset,
                          range: -Double(visible.width)...Double(visible.width))
                sliderRow(title: "Vertical", value: placementBinding.yOffset,
                          range: -Double(visible.height)...Double(visible.height))
            }
            .padding(10)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 6) {
                Text("Assigned Apps")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                appAssignmentRow(for: group)
            }

            Button {
                repositioner.sendTestNotification(groupID: group.id)
            } label: {
                Label("Test \"\(group.name)\"", systemImage: "paperplane.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(14)
        .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.12), lineWidth: 1))
    }

    // MARK: - Presets Tab

    private var presetsTab: some View {
        presetsSection
    }

    // MARK: - General Tab

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("App-wide settings for startup, auto-dismiss timing, and notification handling. These apply to all notifications and are not affected by presets or exceptions.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                autoDismissRow
                settingsDivider
                settingsToggleRow("Launch at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                settingsDivider
                settingsToggleRow("Pause while screen sharing", isOn: $settings.pauseWhileStreaming)
                settingsDivider
                settingsToggleRow("Don't move Notification Center", isOn: $settings.avoidNCPanel)
            }
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.12), lineWidth: 1))

            if let error = launchAtLogin.lastError {
                Text(error).font(.caption2).foregroundStyle(.red)
            }

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
        }
    }

    // MARK: - Help Tab

    private var helpTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Need help or have an idea?")
                .font(.subheadline.weight(.semibold))

            VStack(spacing: 0) {
                helpLinkRow(
                    title: "Report a bug",
                    description: "Something not working right",
                    systemImage: "ladybug",
                    url: "https://github.com/chessper53/NotificationNanny/issues/new?template=bug_report.md"
                )
                settingsDivider
                helpLinkRow(
                    title: "Request a feature",
                    description: "Got an idea for an improvement",
                    systemImage: "lightbulb",
                    url: "https://github.com/chessper53/NotificationNanny/issues/new?template=feature_request.md"
                )
                settingsDivider
                helpLinkRow(
                    title: "View all issues",
                    description: "Browse open and completed issues",
                    systemImage: "list.bullet",
                    url: "https://github.com/chessper53/NotificationNanny/issues?q=is%3Aissue"
                )
                settingsDivider
                helpLinkRow(
                    title: "Source code",
                    description: "NotificationNanny is open source",
                    systemImage: "chevron.left.forwardslash.chevron.right",
                    url: "https://github.com/chessper53/NotificationNanny"
                )
            }
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.12), lineWidth: 1))

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "person.crop.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 1)
                Text("I work full time, nevertheless I read every issue and try to respond to everyone.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 4) {
                Image(systemName: "lock.shield").font(.caption2)
                Text("No data is collected, transmitted or stored outside this device.")
                    .font(.caption2)
            }
            .foregroundStyle(.tertiary)
            .padding(.top, 4)
        }
    }

    private func helpLinkRow(title: String, description: String, systemImage: String, url: String) -> some View {
        Button {
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .frame(width: 20)
                    .foregroundStyle(Color.nannyAccent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.callout)
                    Text(description).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var settingsDivider: some View {
        Divider().padding(.leading, 14)
    }

    private func settingsToggleRow(_ label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(label).font(.callout)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var autoDismissRow: some View {
        HStack(spacing: 8) {
            Text("Auto-dismiss").font(.callout)
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
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Exception chip

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

    // MARK: - App assignment list

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

    // MARK: - Slider row

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

    // MARK: - Presets

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Save and switch between position layouts. Each preset captures the position, scale, and auto-dismiss delay. Exception rules and general toggles are shared across all presets.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Presets")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 0) {
                if settings.presets.isEmpty && presetMode == .idle {
                    Text("No presets yet.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                } else {
                    ForEach(Array(settings.presets.enumerated()), id: \.element.id) { index, preset in
                        presetRow(preset, index: index)
                        if index < settings.presets.count - 1 || presetMode != .idle {
                            settingsDivider
                        }
                    }
                }

                if presetMode == .adding {
                    HStack(spacing: 6) {
                        TextField("Name", text: $pendingName)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
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
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                } else if settings.presets.count < 5 {
                    if !settings.presets.isEmpty { settingsDivider }
                    Button { pendingName = ""; presetMode = .adding } label: {
                        Label("Save current as preset", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                } else {
                    settingsDivider
                    Text("5 preset limit reached")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
            }
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.12), lineWidth: 1))
        }
    }

    // MARK: - Backup Tab

    private var backupTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Export your settings to a file or import a previously saved backup. Everything is included: positions, scale, exceptions, presets, and general toggles.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                Button {
                    exportSettings()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "square.and.arrow.up")
                            .frame(width: 20)
                            .foregroundStyle(Color.nannyAccent)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Export Settings…").font(.callout)
                            Text("Save a backup to a JSON file").font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                settingsDivider
                Button {
                    importSettings()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "square.and.arrow.down")
                            .frame(width: 20)
                            .foregroundStyle(Color.nannyAccent)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Import Settings…").font(.callout)
                            Text("Restore from a previously exported file").font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.12), lineWidth: 1))
            .confirmationDialog("Replace all settings?",
                                isPresented: $showImportConfirmation,
                                titleVisibility: .visible) {
                Button("Import", role: .destructive) {
                    if let data = pendingImportData { try? settings.importData(data) }
                    pendingImportData = nil
                }
                Button("Cancel", role: .cancel) { pendingImportData = nil }
            } message: {
                Text("This will overwrite all current positions, exceptions, presets and general settings. This cannot be undone.")
            }
        }
    }

    private func exportSettings() {
        guard let data = try? settings.exportData() else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "NotificationNanny Settings.json"
        panel.allowedContentTypes = [.json]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url,
                  let data = try? Data(contentsOf: url) else { return }
            pendingImportData = data
            showImportConfirmation = true
        }
    }

    @ViewBuilder
    private func presetRow(_ preset: Preset, index: Int) -> some View {
        if presetMode == .renaming(preset.id) {
            HStack(spacing: 6) {
                TextField("", text: $pendingName)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
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
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        } else {
            HStack(spacing: 4) {
                Button(preset.name) { settings.applyPreset(preset) }
                    .buttonStyle(.borderless)
                    .font(.callout)
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
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
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
}

// Bypasses SwiftUI's content-driven window sizing by reaching into the NSWindow directly.
private struct WindowSizeLock: NSViewRepresentable {
    let width: CGFloat
    let height: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            let size = NSSize(width: width, height: height)
            window.setContentSize(size)
            window.minSize = size
            window.maxSize = size
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
