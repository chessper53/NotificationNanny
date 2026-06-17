import SwiftUI
import AppKit

struct HelpTabView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var repositioner: NotificationRepositioner
    @EnvironmentObject var launchAtLogin: LaunchAtLogin

    @State private var bugReportPrepared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Need help or have an idea?").font(.subheadline.weight(.semibold))

            VStack(spacing: 0) {
                // Report a bug — auto-attaches diagnostics + recent logs to the prefilled issue,
                // and copies the full report to the clipboard as a fallback for long logs.
                helpRow(title: "Report a bug",
                        description: bugReportPrepared
                            ? "Diagnostics attached · full log copied to clipboard"
                            : "Auto-attaches diagnostics & logs",
                        systemImage: bugReportPrepared ? "checkmark.circle.fill" : "ladybug",
                        accent: bugReportPrepared ? .green : Color.nannyAccent,
                        action: reportBug)
                Divider().padding(.leading, 14)
                helpRow(title: "Request a feature", description: "Got an idea for an improvement",
                        systemImage: "lightbulb") {
                    open("https://github.com/chessper53/NotificationNanny/issues/new?template=feature_request.md")
                }
                Divider().padding(.leading, 14)
                helpRow(title: "View all issues", description: "Browse open and completed issues",
                        systemImage: "list.bullet") {
                    open("https://github.com/chessper53/NotificationNanny/issues?q=is%3Aissue")
                }
                Divider().padding(.leading, 14)
                helpRow(title: "Source code", description: "NotificationNanny is open source",
                        systemImage: "chevron.left.forwardslash.chevron.right") {
                    open("https://github.com/chessper53/NotificationNanny")
                }
            }
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "wrench.and.screwdriver").font(.caption).foregroundStyle(.secondary).padding(.top, 1)
                Text("Diagnostics and activity logs now live in the **Diagnostics** tab — handy if you want to inspect them before filing a report.")
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "person.crop.circle").font(.caption).foregroundStyle(.secondary).padding(.top, 1)
                Text("I work full time, nevertheless I read every issue and try to respond to everyone.")
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 4) {
                Image(systemName: "lock.shield").font(.caption2)
                Text("Diagnostics are only attached when you file a report. Nothing is collected or transmitted otherwise.")
                    .font(.caption2)
            }
            .foregroundStyle(.tertiary).padding(.top, 4)

            Spacer()
        }
    }

    // MARK: - Actions

    private func reportBug() {
        let items = Diagnostics.collect(settings: settings, repositioner: repositioner, launchAtLogin: launchAtLogin)
        // Full report on the clipboard covers logs too long to fit in the URL.
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Diagnostics.fullReport(items), forType: .string)
        if let url = Diagnostics.bugReportURL(items: items) { NSWorkspace.shared.open(url) }
        withAnimation(.easeInOut(duration: 0.15)) { bugReportPrepared = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation(.easeInOut(duration: 0.3)) { bugReportPrepared = false }
        }
    }

    private func open(_ url: String) {
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    }

    // MARK: - Rows

    private func helpRow(title: String, description: String, systemImage: String,
                         accent: Color = Color.nannyAccent, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage).frame(width: 20).foregroundStyle(accent)
                    .animation(.easeInOut(duration: 0.15), value: systemImage)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.callout)
                    Text(description).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14).padding(.vertical, 10).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
