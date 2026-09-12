import SwiftUI
import AppKit

struct PositionTabView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var repositioner: NotificationRepositioner
    @ObservedObject private var loc = LocalizationManager.shared

    private var screens: [NSScreen] { NSScreen.screens }

    private var defaultScreen: NSScreen {
        settings.resolvedTargetScreen() ?? NSScreen.main ?? screens[0]
    }

    private var defaultPlacementBinding: Binding<ScreenPlacement> {
        settings.placementBinding(for: defaultScreen)
    }

    var body: some View {
        let visible = defaultScreen.visibleFrame
        let isDefault = defaultPlacementBinding.wrappedValue.xOffset == 0
                     && defaultPlacementBinding.wrappedValue.yOffset == 0

        VStack(alignment: .leading, spacing: 14) {
            LocalizedText("Choose where banners appear. Drag the indicator on the preview or use the sliders to fine-tune the position.")
                .font(.callout)
                .foregroundStyle(Color(white: 0.55))
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    LocalizedText("Default Position").font(.subheadline.weight(.semibold))
                    Text("\(Int(visible.width)) × \(Int(visible.height))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if screens.count > 1 {
                    Picker("", selection: $settings.targetDisplayID) {
                        LocalizedText("Auto").tag(CGDirectDisplayID(0))
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
                    LocalizedText("Fine-tune").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Spacer()
                    Button(loc.string("Reset")) {
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
                Label {
                    LocalizedText("Send Test Notification")
                } icon: {
                    Image(systemName: "paperplane.fill")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
    }
}
