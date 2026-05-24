import SwiftUI
import AppKit

extension Color {
    static let nannyAccent = Color(red: 0x89 / 255, green: 0x5C / 255, blue: 0x9B / 255)
}

package struct MenuBarContent: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var repositioner: NotificationRepositioner
    @EnvironmentObject var launchAtLogin: LaunchAtLogin

    private enum PresetMode: Equatable { case idle, adding, renaming(UUID) }
    private enum GroupMode: Equatable  { case browsing, adding }

    @State private var presetMode: PresetMode = .idle
    @State private var pendingName = ""

    @State private var selectedGroupID: UUID? = nil
    @State private var groupMode: GroupMode = .browsing
    @State private var newGroupName = ""

    package init() {}

    private var screens: [NSScreen] { NSScreen.screens }

    private var selectedScreen: NSScreen {
        if settings.targetDisplayID != 0,
           let s = screens.first(where: { $0.displayID == settings.targetDisplayID }) { return s }
        return NSScreen.main ?? screens[0]
    }

    /// The placement binding that the drag tile and sliders edit — either a group's or the screen default.
    private var activePlacementBinding: Binding<ScreenPlacement> {
        if let id = selectedGroupID, settings.appGroups.contains(where: { $0.id == id }) {
            return settings.placementBinding(for: id)
        }
        return settings.placementBinding(for: selectedScreen)
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            if screens.count > 1 {
                screenPickerSection
                Divider()
            }
            rulesSection
            Divider()
            positionSection
            Divider()
            offsetSection
            Divider()
            autoDismissSection
            Divider()
            presetsSection
            Divider()
            actionSection
        }
        .padding(16)
        .frame(width: 320)
        .tint(Color.nannyAccent)
        .onAppear {
            repositioner.refreshAccessibilityStatus()
            if repositioner.hasAccessibilityPermission, !repositioner.isObserving {
                repositioner.startObserving()
            }
        }
        .onChange(of: settings.appGroups) { _, groups in
            if let id = selectedGroupID, !groups.contains(where: { $0.id == id }) {
                selectedGroupID = nil
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "bell.badge.fill")
                .foregroundStyle(.tint)
                .font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text("NotificationNanny")
                    .font(.headline)
                statusLine
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $settings.isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if !repositioner.hasAccessibilityPermission {
            Label("Needs Accessibility access", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        } else if repositioner.isObserving {
            Label("Watching notifications", systemImage: "eye.fill")
        } else {
            Label("Idle", systemImage: "pause.circle")
        }
    }

    // MARK: - Screen picker

    private var screenPickerSection: some View {
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
            Spacer()
        }
    }

    // MARK: - Rules

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("App Rules")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if groupMode == .adding {
                    HStack(spacing: 6) {
                        TextField("Name", text: $newGroupName)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.mini)
                            .font(.caption)
                            .frame(width: 100)
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
                    Button {
                        groupMode = .adding
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ruleChip(title: "Default", isSelected: selectedGroupID == nil) {
                        selectedGroupID = nil
                    }
                    ForEach(settings.appGroups) { group in
                        ruleChip(
                            title: group.name,
                            isSelected: selectedGroupID == group.id,
                            onDelete: { settings.deleteGroup(group.id) }
                        ) {
                            selectedGroupID = group.id
                        }
                    }
                }
                .padding(.vertical, 1)
            }

            if let id = selectedGroupID {
                if let group = settings.appGroups.first(where: { $0.id == id }) {
                    appAssignmentRow(for: group)
                }
            }
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
                            Text(appName).font(.caption).lineLimit(1)
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
        .frame(minHeight: 60, maxHeight: 120)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
        .padding(.top, 2)
    }

    @ViewBuilder
    private func ruleChip(title: String, isSelected: Bool,
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
        .overlay(Capsule().stroke(
            isSelected ? Color.clear : Color.secondary.opacity(0.35),
            lineWidth: 1)
        )
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
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let groupName {
                    Text("Position · \(groupName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Position")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(Int(visible.width)) × \(Int(visible.height))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                if screens.count > 1 && settings.targetDisplayID != 0 {
                    Text("· \(selectedScreen.nannyDisplayName)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            DraggableScreenTile(
                screen: selectedScreen,
                placement: activePlacementBinding
            )
        }
    }

    // MARK: - Offset sliders

    private var offsetSection: some View {
        let placement = activePlacementBinding
        let visible = selectedScreen.visibleFrame
        let opacityPct = Binding<Double>(
            get: { settings.notificationOpacity * 100 },
            set: { settings.notificationOpacity = max(0.1, min(1.0, $0 / 100)) }
        )
        let isDefault = placement.wrappedValue.xOffset == 0
                     && placement.wrappedValue.yOffset == 0
                     && settings.notificationOpacity == 1.0
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Fine-tune")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reset") {
                    placement.wrappedValue.xOffset = 0
                    placement.wrappedValue.yOffset = 0
                    settings.notificationOpacity = 1.0
                }
                .buttonStyle(.borderless)
                .font(.caption2)
                .disabled(isDefault)
            }
            sliderRow(title: "Horizontal", value: placement.xOffset,
                      range: -Double(visible.width)...Double(visible.width))
            sliderRow(title: "Vertical",   value: placement.yOffset,
                      range: -Double(visible.height)...Double(visible.height))
            sliderRow(title: "Opacity", value: opacityPct, range: 10...100, suffix: "%")
        }
    }

    private func sliderRow(title: String, value: Binding<Double>,
                           range: ClosedRange<Double>, suffix: String = "px") -> some View {
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
                Text(suffix).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Auto-dismiss

    private var autoDismissSection: some View {
        HStack(spacing: 8) {
            Text("Auto-dismiss").font(.caption).foregroundStyle(.secondary)
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
        VStack(alignment: .leading, spacing: 4) {
            Text("Presets")
                .font(.caption)
                .foregroundStyle(.secondary)

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
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .disabled(index == 0)
                Button { movePreset(at: index, by: 1) } label: {
                    Image(systemName: "chevron.down").font(.caption2)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .disabled(index == settings.presets.count - 1)
                Button { beginRename(preset) } label: {
                    Image(systemName: "pencil").font(.caption2)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                Button { settings.deletePreset(preset) } label: {
                    Image(systemName: "xmark").font(.caption2)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func movePreset(at index: Int, by offset: Int) {
        let dest = index + offset
        guard dest >= 0, dest < settings.presets.count else { return }
        var updated = settings.presets
        updated.swapAt(index, dest)
        settings.presets = updated
    }

    private func beginRename(_ preset: Preset) {
        presetMode = .renaming(preset.id)
        pendingName = preset.name
    }

    private func commitRename(_ preset: Preset) {
        let trimmed = pendingName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let i = settings.presets.firstIndex(where: { $0.id == preset.id }) else {
            cancelRename(); return
        }
        var updated = settings.presets
        updated[i].name = trimmed
        settings.presets = updated
        presetMode = .idle
        pendingName = ""
    }

    private func cancelRename() {
        presetMode = .idle
        pendingName = ""
    }

    private func commitPreset() {
        let name = pendingName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        settings.saveCurrentAsPreset(name: name)
        pendingName = ""
        presetMode = .idle
    }

    // MARK: - Actions

    private var actionSection: some View {
        VStack(spacing: 8) {
            Button {
                repositioner.sendTestNotification(groupID: selectedGroupID)
            } label: {
                let groupName = selectedGroupID.flatMap { id in
                    settings.appGroups.first(where: { $0.id == id })?.name
                }
                Label(groupName.map { "Test \"\($0)\" Position" } ?? "Send Test Notification",
                      systemImage: "paperplane.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            if !repositioner.hasAccessibilityPermission {
                Button {
                    repositioner.requestAccessibilityPermission()
                } label: {
                    Label("Grant Accessibility Permission…", systemImage: "lock.shield.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Toggle("Launch at login", isOn: Binding(
                get: { launchAtLogin.isEnabled },
                set: { launchAtLogin.setEnabled($0) }
            ))
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .font(.caption)

            if let error = launchAtLogin.lastError {
                Text(error).font(.caption2).foregroundStyle(.red)
            }

            HStack {
                Button {
                    NSWorkspace.shared.open(URL(string: "https://github.com/chessper53/NotificationNanny/issues/new")!)
                } label: {
                    Text("Got any feedback?")
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
    }
}

// MARK: - Drag-to-position tile

private struct DraggableScreenTile: View {
    let screen: NSScreen
    @Binding var placement: ScreenPlacement

    private static let realBannerSize = CGSize(width: 372, height: 100)

    var body: some View {
        let visible = screen.visibleFrame
        let aspect = visible.width / max(visible.height, 1)
        let tileWidth: CGFloat = 288
        let tileHeight: CGFloat = min(220, max(100, tileWidth / aspect))
        let scale = tileWidth / visible.width
        let bannerWidth = max(36, Self.realBannerSize.width * scale)
        let bannerHeight = max(14, Self.realBannerSize.height * scale)
        let bannerCenterReal = bannerCenterInVisibleCoords(visible: visible)
        let bannerCenterTile = CGPoint(
            x: (bannerCenterReal.x - visible.minX) * scale,
            y: (bannerCenterReal.y - visible.minY) * scale
        )

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )
            Rectangle()
                .fill(Color.secondary.opacity(0.12))
                .frame(height: 6)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            BannerChip(width: bannerWidth, height: bannerHeight)
                .opacity(0.3)
                .position(
                    x: bannerCenterTile.x,
                    y: bannerCenterTile.y + (placement.position.stacksUpward ? -(bannerHeight + 4) : (bannerHeight + 4))
                )
            BannerChip(width: bannerWidth, height: bannerHeight)
                .position(x: bannerCenterTile.x, y: bannerCenterTile.y)
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { value in
                            updatePlacement(fromTilePoint: value.location,
                                            tileSize: CGSize(width: tileWidth, height: tileHeight),
                                            visible: visible)
                        }
                )
        }
        .frame(width: tileWidth, height: tileHeight)
        .contentShape(Rectangle())
        .onTapGesture { tap in
            updatePlacement(fromTilePoint: tap,
                            tileSize: CGSize(width: tileWidth, height: tileHeight),
                            visible: visible)
        }
    }

    private func bannerCenterInVisibleCoords(visible: CGRect) -> CGPoint {
        let banner = Self.realBannerSize
        let inset: CGFloat = 8
        let x: CGFloat
        switch placement.position {
        case .topLeft, .middleLeft, .bottomLeft:        x = inset
        case .topCenter, .middleCenter, .bottomCenter:  x = (visible.width - banner.width) / 2
        case .topRight, .middleRight, .bottomRight:     x = visible.width - banner.width - inset
        }
        let y: CGFloat
        switch placement.position {
        case .topLeft, .topCenter, .topRight:           y = inset
        case .middleLeft, .middleCenter, .middleRight:  y = (visible.height - banner.height) / 2
        case .bottomLeft, .bottomCenter, .bottomRight:  y = visible.height - banner.height - inset
        }
        let cx = visible.minX + x + banner.width / 2 + CGFloat(placement.xOffset)
        let cy = visible.minY + y + banner.height / 2 + CGFloat(placement.yOffset)
        return CGPoint(x: cx, y: cy)
    }

    private func updatePlacement(fromTilePoint point: CGPoint, tileSize: CGSize, visible: CGRect) {
        let scale = tileSize.width / visible.width
        let banner = Self.realBannerSize
        let inset: CGFloat = 8
        let centreX = max(inset + banner.width / 2,
                          min(visible.width - inset - banner.width / 2, point.x / scale))
        let centreY = max(inset + banner.height / 2,
                          min(visible.height - inset - banner.height / 2, point.y / scale))

        let bandX: AnchorBand
        switch centreX {
        case ..<(visible.width / 3): bandX = .start
        case (visible.width * 2 / 3)...: bandX = .end
        default: bandX = .middle
        }
        let bandY: AnchorBand
        switch centreY {
        case ..<(visible.height / 3): bandY = .start
        case (visible.height * 2 / 3)...: bandY = .end
        default: bandY = .middle
        }

        let anchor = anchorPosition(for: bandX, bandY)
        let refX: CGFloat
        switch bandX {
        case .start:  refX = inset + banner.width / 2
        case .middle: refX = visible.width / 2
        case .end:    refX = visible.width - inset - banner.width / 2
        }
        let refY: CGFloat
        switch bandY {
        case .start:  refY = inset + banner.height / 2
        case .middle: refY = visible.height / 2
        case .end:    refY = visible.height - inset - banner.height / 2
        }

        placement.position = anchor
        placement.xOffset  = Double(centreX - refX)
        placement.yOffset  = Double(centreY - refY)
    }

    private enum AnchorBand { case start, middle, end }

    private func anchorPosition(for x: AnchorBand, _ y: AnchorBand) -> NotificationPosition {
        switch (y, x) {
        case (.start,  .start):  return .topLeft
        case (.start,  .middle): return .topCenter
        case (.start,  .end):    return .topRight
        case (.middle, .start):  return .middleLeft
        case (.middle, .middle): return .middleCenter
        case (.middle, .end):    return .middleRight
        case (.end,    .start):  return .bottomLeft
        case (.end,    .middle): return .bottomCenter
        case (.end,    .end):    return .bottomRight
        }
    }
}

private struct BannerChip: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.nannyAccent.opacity(0.85))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Color.nannyAccent, lineWidth: 1)
            )
            .frame(width: width, height: height)
            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
    }
}

// MARK: - Test notification

enum TestNotification {
    static func send() {
        let stamp = Int(Date().timeIntervalSince1970) % 100000
        let script = """
        display notification "Thank you for using NotificationNanny!" with title "NotificationNanny" subtitle "Test #\(stamp)"
        """
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        try? task.run()
    }
}
