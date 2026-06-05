import SwiftUI
import AppKit

struct PositionTabView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var repositioner: NotificationRepositioner

    private var screens: [NSScreen] { NSScreen.screens }

    private var defaultScreen: NSScreen {
        if settings.targetDisplayID != 0,
           let s = screens.first(where: { $0.displayID == settings.targetDisplayID }) { return s }
        return NSScreen.main ?? screens[0]
    }

    private var defaultPlacementBinding: Binding<ScreenPlacement> {
        settings.placementBinding(for: defaultScreen)
    }

    var body: some View {
        let visible = defaultScreen.visibleFrame
        let isDefault = defaultPlacementBinding.wrappedValue.xOffset == 0
                     && defaultPlacementBinding.wrappedValue.yOffset == 0

        VStack(alignment: .leading, spacing: 14) {
            Text("Choose where banners appear. Drag the indicator on the preview or use the sliders to fine-tune the position.")
                .font(.callout)
                .foregroundStyle(Color(white: 0.55))
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Default Position").font(.subheadline.weight(.semibold))
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
                    Text("Fine-tune").font(.caption.weight(.medium)).foregroundStyle(.secondary)
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
                SettingsSliderRow(title: "Horizontal", value: defaultPlacementBinding.xOffset,
                                  range: -Double(visible.width)...Double(visible.width))
                SettingsSliderRow(title: "Vertical",   value: defaultPlacementBinding.yOffset,
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
}
