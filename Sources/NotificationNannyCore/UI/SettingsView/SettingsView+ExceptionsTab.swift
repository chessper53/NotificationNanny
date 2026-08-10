import SwiftUI
import AppKit

struct ExceptionsTabView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var repositioner: NotificationRepositioner

    private enum GroupMode: Equatable { case browsing, adding }

    @State private var selectedGroupID: UUID? = nil
    @State private var groupMode: GroupMode = .browsing
    @State private var newGroupName = ""
    @State private var iconCache: [String: NSImage] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Create groups of apps and give each group its own rules: position, screen, banner type, and scale. Apps not in any group use the defaults.")
                .font(.callout)
                .foregroundStyle(Color(white: 0.55))
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .center, spacing: 8) {
                if settings.appGroups.isEmpty && groupMode != .adding {
                    Text("No exceptions yet.").font(.caption).foregroundStyle(.tertiary)
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
                        TextField("Name", text: $newGroupName)
                            .textFieldStyle(.roundedBorder).controlSize(.small).font(.caption)
                            .onSubmit { commitNewGroup() }
                        Button("Create", action: commitNewGroup)
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
    }

    @ViewBuilder
    private func exceptionDetail(for group: AppGroup) -> some View {
        let screens = NSScreen.screens
        let exScreen: NSScreen = settings.resolvedTargetScreen(forGroupID: group.id)
            ?? settings.resolvedTargetScreen()
            ?? NSScreen.main ?? screens[0]
        let placementBinding = settings.placementBinding(for: group.id)
        let visible = exScreen.visibleFrame
        let isDefault = placementBinding.wrappedValue.xOffset == 0 && placementBinding.wrappedValue.yOffset == 0

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
                        Text("Screen:").font(.caption).foregroundStyle(.secondary)
                        Picker("", selection: displayBinding) {
                            Text("Default").tag(CGDirectDisplayID(0))
                            ForEach(screens, id: \.displayID) { screen in
                                Text(screen.nannyDisplayName).tag(screen.displayID)
                            }
                        }
                        .labelsHidden().pickerStyle(.menu).controlSize(.mini)
                    }
                }
            }

            DraggableScreenTile(screen: exScreen, placement: placementBinding)
                .frame(maxWidth: .infinity, alignment: .center)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Fine-tune").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset") {
                        placementBinding.wrappedValue.xOffset = 0
                        placementBinding.wrappedValue.yOffset = 0
                    }
                    .buttonStyle(.borderless).font(.caption).foregroundStyle(Color.nannyAccent).disabled(isDefault)
                }
                SettingsSliderRow(title: "Horizontal", value: placementBinding.xOffset,
                                  range: -Double(visible.width)...Double(visible.width))
                SettingsSliderRow(title: "Vertical",   value: placementBinding.yOffset,
                                  range: -Double(visible.height)...Double(visible.height))
            }
            .padding(10)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 6) {
                Text("Assigned Apps").font(.footnote.weight(.semibold)).foregroundStyle(Color(white: 0.45))
                appAssignmentRow(for: group)
            }

            Button { repositioner.sendTestNotification(groupID: group.id) } label: {
                Label("Test \"\(group.name)\"", systemImage: "paperplane.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.small)
        }
        .padding(14)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func appAssignmentRow(for group: AppGroup) -> some View {
        ScrollView(showsIndicators: true) {
            VStack(alignment: .leading, spacing: 1) {
                if settings.knownAppNames.isEmpty {
                    Text("No apps seen yet — receive a notification from any app and it will appear here.")
                        .font(.caption2).foregroundStyle(.tertiary).padding(.horizontal, 6).padding(.vertical, 6)
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
                                    Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                                }
                                Text(appName).font(.caption).lineLimit(1)
                            }
                        }
                        .toggleStyle(.checkbox).controlSize(.small)
                        .padding(.vertical, 2).padding(.horizontal, 6)
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
        // Primary: running app
        if let icon = NSWorkspace.shared.runningApplications
            .first(where: { $0.localizedName == appName })?.icon {
            DispatchQueue.main.async { iconCache[appName] = icon }
            return icon
        }
        // Fallback: directory scan
        let dirs = ["/Applications", NSHomeDirectory() + "/Applications",
                    "/System/Applications", "/System/Applications/Utilities"]
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
