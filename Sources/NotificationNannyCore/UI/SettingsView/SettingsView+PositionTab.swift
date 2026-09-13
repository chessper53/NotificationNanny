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

            PlacementEditor(screen: defaultScreen, placement: defaultPlacementBinding,
                            screenWidth: 236)

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
