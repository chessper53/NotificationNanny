import SwiftUI
import AppKit

struct BackupTabView: View {
    @EnvironmentObject var settings: AppSettings

    @State private var showImportConfirmation = false
    @State private var pendingImportData: Data? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Export your settings to a file or import a previously saved backup. Everything is included: positions, scale, per-app rules, presets, and general toggles.")
                .font(.callout)
                .foregroundStyle(Color(white: 0.55))
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                Button { exportSettings() } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "square.and.arrow.up").frame(width: 20).foregroundStyle(Color.nannyAccent)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Export Settings…").font(.callout)
                            Text("Save a backup to a JSON file").font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10).contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Divider().padding(.leading, 14)

                Button { importSettings() } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "square.and.arrow.down").frame(width: 20).foregroundStyle(Color.nannyAccent)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Import Settings…").font(.callout)
                            Text("Restore from a previously exported file").font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10).contentShape(Rectangle())
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
}
