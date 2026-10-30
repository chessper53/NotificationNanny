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
        VStack(alignment: .leading, spacing: 14) {
            LocalizedText("Choose where banners appear. Drag the banner on the preview. It matches your real screen exactly.")
                .font(.callout)
                .foregroundStyle(Color.nannyMuted(0.55))
                .fixedSize(horizontal: false, vertical: true)

            PositionCard(titleKey: "Default Position", screen: defaultScreen,
                         display: $settings.targetDisplayID, resolvedDisplay: settings.resolvedTargetScreen(),
                         zeroLabelKey: "Auto", placement: defaultPlacementBinding,
                         noteKey: "Every app outside an exception group shows its banners here.")

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
            .buttonStyle(.nannyProminent)
            .controlSize(.regular)
        }
    }
}
