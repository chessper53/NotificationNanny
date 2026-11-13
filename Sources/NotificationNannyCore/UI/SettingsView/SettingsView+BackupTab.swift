import SwiftUI
import AppKit

struct BackupTabView: View {
    @EnvironmentObject var settings: AppSettings
    @ObservedObject private var loc = LocalizationManager.shared

    @State private var showImportConfirmation = false
    @State private var pendingImportData: Data? = nil
    /// What went wrong, a key of Localizable.strings, for the alert; nil while nothing did.
    @State private var failureKey: String? = nil
    @State private var failureTitleKey = "Import failed"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LocalizedText("Export your settings to a file or import a previously saved backup. Everything is included: positions, scale, per-app rules, presets, and general toggles.")
                .font(.callout)
                .foregroundStyle(Color.nannyMuted(0.55))
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                Button { exportSettings() } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "square.and.arrow.up").frame(width: 20).foregroundStyle(Color.nannyAccent)
                        VStack(alignment: .leading, spacing: 1) {
                            LocalizedText("Export Settings…").font(.callout)
                            LocalizedText("Save a backup to a JSON file").font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .settingsListRow().contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Divider().padding(.leading, 14)

                Button { importSettings() } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "square.and.arrow.down").frame(width: 20).foregroundStyle(Color.nannyAccent)
                        VStack(alignment: .leading, spacing: 1) {
                            LocalizedText("Import Settings…").font(.callout)
                            LocalizedText("Restore from a previously exported file").font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .settingsListRow().contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .settingsCardBackground()
            .alert(loc.string(failureTitleKey), isPresented: Binding(get: { failureKey != nil }, set: { if !$0 { failureKey = nil } })) {
                Button(loc.string("OK"), role: .cancel) { failureKey = nil }
            } message: {
                if let failureKey { LocalizedText(failureKey) }
            }
            .confirmationDialog(loc.string("Replace all settings?"),
                                isPresented: $showImportConfirmation,
                                titleVisibility: .visible) {
                Button(loc.string("Import"), role: .destructive) {
                    if let data = pendingImportData {
                        do { try settings.importData(data) } catch { fail("Import failed", error) }
                    }
                    pendingImportData = nil
                }
                Button(loc.string("Cancel"), role: .cancel) { pendingImportData = nil }
            } message: {
                LocalizedText("This will overwrite all current positions, exceptions, presets and general settings. This cannot be undone.")
            }
        }
    }

    /// Shows what went wrong: a failed import or export used to do nothing at all.
    private func fail(_ titleKey: String, _ error: Error) {
        failureTitleKey = titleKey
        failureKey = (error as? AppSettings.BackupError)?.messageKey
            ?? (titleKey == "Export failed" ? "The backup couldn't be saved." : "This file couldn't be read.")
        NannyLogger.shared.log("\(titleKey): \(error.localizedDescription)", level: .warn, tag: "Backup")
    }

    private func exportSettings() {
        let data: Data
        do { data = try settings.exportData() } catch { return fail("Export failed", error) }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "NotificationNanny Settings.json"
        panel.allowedContentTypes = [.json]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do { try data.write(to: url, options: .atomic) } catch { fail("Export failed", error) }
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            // Checked before asking to replace everything: a file that can't be imported
            // says so now, rather than after the question.
            do {
                let data = try Data(contentsOf: url)
                _ = try settings.validatedBackup(data)
                pendingImportData = data
                showImportConfirmation = true
            } catch {
                fail("Import failed", error)
            }
        }
    }
}
