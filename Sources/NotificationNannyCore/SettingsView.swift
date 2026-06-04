import SwiftUI
import AppKit
import UserNotifications

package struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var repositioner: NotificationRepositioner
    @EnvironmentObject var launchAtLogin: LaunchAtLogin

    private enum NavTab: Hashable { case position, exceptions, presets, general, banner, backup, logs, help }
    private enum PresetMode: Equatable { case idle, adding, renaming(UUID) }
    private enum GroupMode: Equatable  { case browsing, adding }

    @State private var activeTab: NavTab = .position
    @State private var selectedGroupID: UUID? = nil
    @State private var groupMode: GroupMode = .browsing
    @State private var newGroupName = ""
    @State private var presetMode: PresetMode = .idle
    @State private var pendingName = ""
    @State private var iconCache: [String: NSImage] = [:]
    @ObservedObject private var logger = NannyLogger.shared
    @State private var newerVersion: String? = nil
    @State private var showResetConfirmation = false
    @State private var showImportConfirmation = false
    @State private var pendingImportData: Data? = nil
    @State private var diagResults: [DiagResult]? = nil
    @State private var diagCopied = false
    @State private var permissionJustGranted = false

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
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                if !repositioner.hasAccessibilityPermission || permissionJustGranted {
                    accessibilityBanner(granted: permissionJustGranted)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if let newer = newerVersion {
                    updateBanner(version: newer)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.35), value: repositioner.hasAccessibilityPermission)
            .animation(.easeInOut(duration: 0.35), value: newerVersion)
            .onChange(of: repositioner.hasAccessibilityPermission) { _, granted in
                guard granted else { return }
                permissionJustGranted = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        permissionJustGranted = false
                    }
                }
            }
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
                sidebarItem("Logs",       systemImage: "doc.text.magnifyingglass", tab: .logs)
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
            .background(Color.black.opacity(0.5))

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
                    case .logs:       logsTab
                    case .help:       helpTab
                    }
                }
                .padding(16)
            }
            .id(activeTab)
        }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.10))
        .background(WindowSizeLock(width: 570, height: 560))
        .tint(Color.nannyAccent)
        .preferredColorScheme(.dark)
        .onAppear {
            repositioner.refreshAccessibilityStatus()
            if repositioner.hasAccessibilityPermission, !repositioner.isObserving {
                repositioner.startObserving()
            }
            Task { newerVersion = await UpdateChecker.fetchNewerVersion() }
        }
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

    private func sidebarItem(_ label: String, systemImage: String, tab: NavTab) -> some View {
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
                activeTab == tab ? Color.nannyAccent.opacity(0.25) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .foregroundStyle(activeTab == tab ? Color.white : Color(white: 0.55))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Banners (permission / update)

    private func accessibilityBanner(granted: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: granted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                .font(.callout)
                .foregroundStyle(granted ? .green : .orange)
                .animation(.easeInOut(duration: 0.2), value: granted)
            VStack(alignment: .leading, spacing: 1) {
                Text(granted ? "Accessibility access granted" : "Accessibility access required")
                    .font(.callout.weight(.semibold))
                    .animation(.easeInOut(duration: 0.2), value: granted)
                if !granted {
                    Text("NotificationNanny needs this to reposition and intercept notification banners.")
                        .font(.caption2)
                        .foregroundStyle(Color(white: 0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            if !granted {
                Button("Grant Access") {
                    repositioner.requestAccessibilityPermission()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background((granted ? Color.green : Color.orange).opacity(0.18))
        .animation(.easeInOut(duration: 0.3), value: granted)
    }

    private func updateBanner(version: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.callout)
                .foregroundStyle(.green)
            Text("v\(version) is available")
                .font(.callout.weight(.semibold))
            Spacer()
            Button("View Release") {
                NSWorkspace.shared.open(URL(string: "https://github.com/chessper53/NotificationNanny/releases/latest")!)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            Button {
                newerVersion = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(white: 0.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.green.opacity(0.12))
    }

    // MARK: - Position Tab

    private var positionTab: some View {
        let visible = defaultScreen.visibleFrame
        let isDefault = defaultPlacementBinding.wrappedValue.xOffset == 0
                     && defaultPlacementBinding.wrappedValue.yOffset == 0
        return VStack(alignment: .leading, spacing: 14) {
            Text("Choose where banners appear. Drag the indicator on the preview or use the sliders to fine-tune the position.")
                .font(.callout)
                .foregroundStyle(Color(white: 0.55))
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
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))

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
                    .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.0))
                    .padding(.top, 1)
                Text("Experimental. The custom banner replaces the system one entirely. Some notification actions like inline replies may not work. Behavior can vary between apps and macOS versions.")
                    .font(.caption)
                    .foregroundStyle(Color(white: 0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background(Color.orange.opacity(0.22), in: RoundedRectangle(cornerRadius: 8))

            // Info: when custom renderer is active
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 1)
                Text("The custom renderer is used automatically when scale ≠ 100% or a tint color is set. Otherwise notifications use the native macOS banner.")
                    .font(.caption)
                    .foregroundStyle(Color(white: 0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))

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
                    Slider(value: $settings.bannerScale, in: 0.5...2.5)
                        .onChange(of: settings.bannerScale) { _, v in
                            if abs(v - 1.0) < 0.02 { settings.bannerScale = 1.0 }
                        }
                        .controlSize(.mini)
                    Text("A").font(.body.weight(.medium)).foregroundStyle(.secondary)
                    Text("\(Int(settings.bannerScale * 100))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .trailing)
                }

            }
            .padding(12)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))

            // Background color
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Background Color")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear") { settings.clearBannerColor() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .foregroundStyle(Color.nannyAccent)
                        .disabled(!settings.hasBannerColor)
                }
                HStack(spacing: 10) {
                    ColorPicker("", selection: Binding(
                        get: { settings.bannerColor },
                        set: { settings.bannerColor = $0 }
                    ), supportsOpacity: false)
                    .labelsHidden()
                    Text(settings.hasBannerColor ? "Custom tint active — enables custom renderer" : "No tint — uses frosted glass")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))

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
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
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
        let hasCustom = settings.appGroups.first(where: { $0.id == group.id }).map {
            $0.bannerScale != nil || $0.hasBannerColor
        } ?? false
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
                        settings.appGroups[i].bannerColorR = nil
                        settings.appGroups[i].bannerColorG = nil
                        settings.appGroups[i].bannerColorB = nil
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
                    Slider(value: scaleBinding, in: 0.5...2.5)
                        .onChange(of: scaleBinding.wrappedValue) { _, v in
                            if abs(v - 1.0) < 0.02 { scaleBinding.wrappedValue = 1.0 }
                        }
                        .controlSize(.mini)
                    Text("A").font(.body.weight(.medium)).foregroundStyle(.secondary)
                    Text("\(Int(scaleBinding.wrappedValue * 100))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .trailing)
                }
                let colorBinding = Binding<Color>(
                    get: {
                        guard let g = settings.appGroups.first(where: { $0.id == group.id }),
                              let r = g.bannerColorR, let gr = g.bannerColorG, let b = g.bannerColorB
                        else { return settings.bannerColor }
                        return Color(red: r, green: gr, blue: b)
                    },
                    set: { newColor in
                        guard let i = settings.appGroups.firstIndex(where: { $0.id == group.id }) else { return }
                        let c = NSColor(newColor).usingColorSpace(.sRGB) ?? .black
                        settings.appGroups[i].bannerColorR = Double(c.redComponent)
                        settings.appGroups[i].bannerColorG = Double(c.greenComponent)
                        settings.appGroups[i].bannerColorB = Double(c.blueComponent)
                    }
                )
                HStack(spacing: 8) {
                    Text("Color").font(.caption2).foregroundStyle(.secondary)
                    ColorPicker("", selection: colorBinding, supportsOpacity: false)
                        .labelsHidden()
                    if settings.appGroups.first(where: { $0.id == group.id })?.hasBannerColor == true {
                        Button("Clear") {
                            guard let i = settings.appGroups.firstIndex(where: { $0.id == group.id }) else { return }
                            settings.appGroups[i].bannerColorR = nil
                            settings.appGroups[i].bannerColorG = nil
                            settings.appGroups[i].bannerColorB = nil
                        }
                        .buttonStyle(.borderless)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Exceptions Tab

    private var exceptionsTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Create groups of apps and give each group its own rules: position, screen, banner type, and scale. Apps not in any group use the defaults.")
                .font(.callout)
                .foregroundStyle(Color(white: 0.55))
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
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 6) {
                Text("Assigned Apps")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(white: 0.45))
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
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func exceptionBannerRow(for group: AppGroup) -> some View {
        let scaleBinding = Binding<Double>(
            get: { settings.appGroups.first(where: { $0.id == group.id })?.bannerScale ?? settings.bannerScale },
            set: { v in
                guard let i = settings.appGroups.firstIndex(where: { $0.id == group.id }) else { return }
                settings.appGroups[i].bannerScale = v
            }
        )
        let hasCustom = settings.appGroups.first(where: { $0.id == group.id })?.bannerScale != nil

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Banner Scale")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if hasCustom {
                    Button("Reset") {
                        guard let i = settings.appGroups.firstIndex(where: { $0.id == group.id }) else { return }
                        settings.appGroups[i].bannerScale = nil
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(Color.nannyAccent)
                }
            }
            HStack(spacing: 8) {
                Text("A").font(.caption2).foregroundStyle(.secondary)
                Slider(value: scaleBinding, in: 0.5...2.5)
                    .onChange(of: scaleBinding.wrappedValue) { _, v in
                        if abs(v - 1.0) < 0.02 { scaleBinding.wrappedValue = 1.0 }
                    }
                    .controlSize(.mini)
                Text("A").font(.body.weight(.medium)).foregroundStyle(.secondary)
                Text("\(Int(scaleBinding.wrappedValue * 100))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 38, alignment: .trailing)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Presets Tab

    private var presetsTab: some View {
        presetsSection
    }

    // MARK: - General Tab

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("App-wide settings for startup, timing, and notification behaviour. These apply globally and are not affected by presets or per-app rules.")
                .font(.callout)
                .foregroundStyle(Color(white: 0.55))
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
                settingsDivider
                settingsToggleRow("Hold banners while display is asleep", isOn: $settings.holdWhileAsleep)
            }
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))

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

    // MARK: - Logs Tab

    private static let logTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private var logsTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Recent activity from the notification repositioner. Useful for diagnosing issues — share the saved file in a bug report.")
                .font(.callout)
                .foregroundStyle(Color(white: 0.55))
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("\(logger.entries.count) entries")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(white: 0.45))
                Spacer()
                Button("Clear") { logger.clear() }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(Color.nannyAccent)
                    .disabled(logger.entries.isEmpty)
                Button("Save…") { saveLog() }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(Color.nannyAccent)
                    .disabled(logger.entries.isEmpty)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if logger.entries.isEmpty {
                        Text("No entries yet. Trigger a notification to start logging.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(10)
                    } else {
                        ForEach(logger.entries.reversed()) { entry in
                            logEntryRow(entry)
                        }
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: .infinity)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func logEntryRow(_ entry: LogEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(Self.logTimeFormatter.string(from: entry.timestamp))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color(white: 0.38))
                .frame(width: 80, alignment: .leading)
                .lineLimit(1)
            if entry.level != .info {
                Text(entry.level.rawValue)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(entry.level == .warn ? Color.orange : Color.red)
                    .frame(width: 38, alignment: .leading)
            } else {
                Color.clear.frame(width: 38, height: 1)
            }
            Text(entry.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color(white: 0.78))
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
    }

    private func saveLog() {
        let text = logger.exportText()
        guard let data = text.data(using: .utf8) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "NotificationNanny Log.txt"
        panel.allowedContentTypes = [.plainText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? data.write(to: url, options: .atomic)
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
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))

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
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 4) {
                Image(systemName: "lock.shield").font(.caption2)
                Text("No data is collected, transmitted or stored outside this device.")
                    .font(.caption2)
            }
            .foregroundStyle(.tertiary)
            .padding(.top, 4)

            // Diagnostics
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Diagnostics")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let results = diagResults {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(diagReportText(results), forType: .string)
                            diagCopied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { diagCopied = false }
                        } label: {
                            Label(diagCopied ? "Copied!" : "Copy Report", systemImage: diagCopied ? "checkmark" : "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .foregroundStyle(diagCopied ? .green : Color.nannyAccent)
                        .animation(.easeInOut(duration: 0.15), value: diagCopied)
                    }
                    Button {
                        diagResults = buildDiagResults()
                    } label: {
                        Label("Run Diagnostics", systemImage: "stethoscope")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if diagResults != nil {
                        Button { diagResults = nil } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                if let results = diagResults {
                    VStack(spacing: 0) {
                        ForEach(results) { result in
                            HStack(spacing: 8) {
                                Image(systemName: result.status.icon)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(result.status.color)
                                    .frame(width: 14)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(result.label)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.primary)
                                    Text(result.detail)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            if result.id != results.last?.id { settingsDivider }
                        }
                    }
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Diagnostics helpers

    private struct DiagResult: Identifiable {
        let id = UUID()
        let label: String
        let detail: String
        let status: DiagStatus
    }

    private enum DiagStatus {
        case ok, warn, fail, info
        var icon: String {
            switch self {
            case .ok:   return "checkmark.circle.fill"
            case .warn: return "exclamationmark.triangle.fill"
            case .fail: return "xmark.circle.fill"
            case .info: return "info.circle.fill"
            }
        }
        var color: Color {
            switch self {
            case .ok:   return .green
            case .warn: return .orange
            case .fail: return Color(red: 1, green: 0.3, blue: 0.3)
            case .info: return .secondary
            }
        }
    }

    @MainActor
    private func buildDiagResults() -> [DiagResult] {
        var results: [DiagResult] = []

        // App & system info
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let osVer   = ProcessInfo.processInfo.operatingSystemVersionString
        results.append(DiagResult(label: "App version",   detail: "v\(version) (\(build))", status: .info))
        results.append(DiagResult(label: "macOS version", detail: osVer,                    status: .info))

        // Install location
        let bundlePath = Bundle.main.bundlePath
        let installDetail: String
        if bundlePath.contains("/opt/homebrew") || bundlePath.contains("/usr/local/Caskroom") {
            installDetail = "Homebrew Cask — update with brew upgrade --cask notificationnanny"
        } else if bundlePath.hasPrefix("/Applications") {
            installDetail = "Direct install (/Applications)"
        } else {
            installDetail = bundlePath
        }
        results.append(DiagResult(label: "Install location", detail: installDetail, status: .info))

        // Accessibility permission
        if repositioner.hasAccessibilityPermission {
            results.append(DiagResult(label: "Accessibility", detail: "Granted", status: .ok))
        } else {
            results.append(DiagResult(label: "Accessibility", detail: "Not granted — banner repositioning disabled", status: .fail))
        }

        // Repositioner observing
        if repositioner.hasAccessibilityPermission {
            if repositioner.isObserving {
                results.append(DiagResult(label: "Repositioner", detail: "Active and observing", status: .ok))
            } else {
                results.append(DiagResult(label: "Repositioner", detail: "Permission granted but not observing", status: .warn))
            }
        }

        // Login Item
        launchAtLogin.refresh()
        if launchAtLogin.isEnabled {
            results.append(DiagResult(label: "Launch at login", detail: "Enabled", status: .ok))
        } else {
            results.append(DiagResult(label: "Launch at login", detail: "Disabled", status: .info))
        }

        // Recent errors
        let errors = NannyLogger.shared.entries.filter { $0.level == .error }.suffix(5)
        if errors.isEmpty {
            results.append(DiagResult(label: "Recent errors", detail: "None", status: .ok))
        } else {
            let fmt = DateFormatter()
            fmt.dateFormat = "HH:mm:ss"
            for e in errors {
                results.append(DiagResult(label: "Error \(fmt.string(from: e.timestamp))", detail: e.message, status: .warn))
            }
        }

        return results
    }

    private func diagReportText(_ results: [DiagResult]) -> String {
        let lines = results.map { r in
            let badge: String
            switch r.status {
            case .ok:   badge = "[OK]  "
            case .warn: badge = "[WARN]"
            case .fail: badge = "[FAIL]"
            case .info: badge = "[INFO]"
            }
            return "\(badge)  \(r.label): \(r.detail)"
        }
        let header = "NotificationNanny Diagnostics — \(Date())"
        return ([header, String(repeating: "-", count: header.count)] + lines).joined(separator: "\n")
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
        .overlay(Capsule().stroke(isSelected ? Color.clear : Color.white.opacity(0.15), lineWidth: 1))
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
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
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
            Text("Save and switch between named configurations. Presets capture your full setup including per-app rules.")
                .font(.callout)
                .foregroundStyle(Color(white: 0.55))
                .fixedSize(horizontal: false, vertical: true)

            Text("Presets")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 0) {
                if settings.presets.isEmpty {
                    Text("No presets yet.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                } else {
                    ForEach(Array(settings.presets.enumerated()), id: \.element.id) { index, preset in
                        presetRow(preset, index: index)
                        if index < settings.presets.count - 1 || settings.presets.count < 5 {
                            settingsDivider
                        }
                    }
                }

                if settings.presets.count < 5 {
                    if !settings.presets.isEmpty { settingsDivider }
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
                        Button("Cancel") { pendingName = "" }
                            .buttonStyle(.borderless)
                            .controlSize(.mini)
                    }
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
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Backup Tab

    private var backupTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Export your settings to a file or import a previously saved backup. Everything is included: positions, scale, per-app rules, presets, and general toggles.")
                .font(.callout)
                .foregroundStyle(Color(white: 0.55))
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
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
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
        pendingName = ""
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
