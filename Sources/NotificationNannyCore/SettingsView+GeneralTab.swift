import SwiftUI

struct GeneralTabView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var launchAtLogin: LaunchAtLogin

    @State private var showResetConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("App-wide settings for startup, timing, and notification behaviour. These apply globally and are not affected by presets or per-app rules.")
                .font(.callout)
                .foregroundStyle(Color(white: 0.55))
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                autoDismissRow
                Divider().padding(.leading, 14)
                toggleRow("Launch at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                Divider().padding(.leading, 14)
                toggleRow("Pause while screen sharing", isOn: $settings.pauseWhileStreaming)
                Divider().padding(.leading, 14)
                toggleRow("Don't move Notification Center", isOn: $settings.avoidNCPanel)
                Divider().padding(.leading, 14)
                toggleRow("Hold banners while display is asleep", isOn: $settings.holdWhileAsleep)
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

    private func toggleRow(_ label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(label).font(.callout)
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
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
                    .textFieldStyle(.roundedBorder).controlSize(.mini)
                    .multilineTextAlignment(.trailing).frame(width: 40)
                    .font(.caption2.monospacedDigit())
                Stepper("", value: $settings.autoDismissSeconds, in: 1...300, step: 1)
                    .labelsHidden().controlSize(.mini)
                Text("s").font(.caption2).foregroundStyle(.secondary)
            }
            Toggle("", isOn: Binding(
                get: { settings.autoDismissSeconds > 0 },
                set: { settings.autoDismissSeconds = $0 ? 10 : 0 }
            ))
            .labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
