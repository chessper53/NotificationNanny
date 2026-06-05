import SwiftUI
import AppKit

struct HelpTabView: View {
    @EnvironmentObject var repositioner: NotificationRepositioner
    @EnvironmentObject var launchAtLogin: LaunchAtLogin

    @State private var diagResults: [DiagResult]? = nil
    @State private var diagCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Need help or have an idea?").font(.subheadline.weight(.semibold))

            VStack(spacing: 0) {
                helpLinkRow(title: "Report a bug", description: "Something not working right",
                            systemImage: "ladybug",
                            url: "https://github.com/chessper53/NotificationNanny/issues/new?template=bug_report.md")
                Divider().padding(.leading, 14)
                helpLinkRow(title: "Request a feature", description: "Got an idea for an improvement",
                            systemImage: "lightbulb",
                            url: "https://github.com/chessper53/NotificationNanny/issues/new?template=feature_request.md")
                Divider().padding(.leading, 14)
                helpLinkRow(title: "View all issues", description: "Browse open and completed issues",
                            systemImage: "list.bullet",
                            url: "https://github.com/chessper53/NotificationNanny/issues?q=is%3Aissue")
                Divider().padding(.leading, 14)
                helpLinkRow(title: "Source code", description: "NotificationNanny is open source",
                            systemImage: "chevron.left.forwardslash.chevron.right",
                            url: "https://github.com/chessper53/NotificationNanny")
            }
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "person.crop.circle").font(.caption).foregroundStyle(.secondary).padding(.top, 1)
                Text("I work full time, nevertheless I read every issue and try to respond to everyone.")
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 4) {
                Image(systemName: "lock.shield").font(.caption2)
                Text("No data is collected, transmitted or stored outside this device.").font(.caption2)
            }
            .foregroundStyle(.tertiary).padding(.top, 4)

            // Diagnostics
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Diagnostics").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Spacer()
                    if let results = diagResults {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(diagReportText(results), forType: .string)
                            diagCopied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { diagCopied = false }
                        } label: {
                            Label(diagCopied ? "Copied!" : "Copy Report",
                                  systemImage: diagCopied ? "checkmark" : "doc.on.doc")
                        }
                        .buttonStyle(.borderless).font(.caption)
                        .foregroundStyle(diagCopied ? .green : Color.nannyAccent)
                        .animation(.easeInOut(duration: 0.15), value: diagCopied)
                    }
                    Button { diagResults = buildDiagResults() } label: {
                        Label("Run Diagnostics", systemImage: "stethoscope")
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    if diagResults != nil {
                        Button { diagResults = nil } label: { Image(systemName: "xmark") }
                            .buttonStyle(.borderless).font(.caption).foregroundStyle(.secondary)
                    }
                }

                if let results = diagResults {
                    VStack(spacing: 0) {
                        ForEach(results) { result in
                            HStack(spacing: 8) {
                                Image(systemName: result.status.icon)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(result.status.color)
                                    .frame(width: 14)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(result.label).font(.caption.weight(.medium)).foregroundStyle(.primary)
                                    Text(result.detail).font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            if result.id != results.last?.id { Divider().padding(.leading, 14) }
                        }
                    }
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func helpLinkRow(title: String, description: String, systemImage: String, url: String) -> some View {
        Button {
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage).frame(width: 20).foregroundStyle(Color.nannyAccent)
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

    // MARK: - Diagnostics

    private struct DiagResult: Identifiable {
        let id = UUID()
        let label: String
        let detail: String
        let status: DiagStatus
    }

    private enum DiagStatus {
        case ok, warn, fail, info
        var icon: String {
            switch self {
            case .ok:   return "checkmark.circle.fill"
            case .warn: return "exclamationmark.triangle.fill"
            case .fail: return "xmark.circle.fill"
            case .info: return "info.circle.fill"
            }
        }
        var color: Color {
            switch self {
            case .ok:   return .green
            case .warn: return .orange
            case .fail: return Color(red: 1, green: 0.3, blue: 0.3)
            case .info: return .secondary
            }
        }
    }

    @MainActor
    private func buildDiagResults() -> [DiagResult] {
        var results: [DiagResult] = []

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let osVer   = ProcessInfo.processInfo.operatingSystemVersionString
        results.append(DiagResult(label: "App version",   detail: "v\(version) (\(build))", status: .info))
        results.append(DiagResult(label: "macOS version", detail: osVer,                    status: .info))

        let bundlePath = Bundle.main.bundlePath
        let installDetail: String
        if bundlePath.contains("/opt/homebrew") || bundlePath.contains("/usr/local/Caskroom") {
            installDetail = "Homebrew Cask — update with brew upgrade --cask notificationnanny"
        } else if bundlePath.hasPrefix("/Applications") {
            installDetail = "Direct install (/Applications)"
        } else {
            installDetail = bundlePath
        }
        results.append(DiagResult(label: "Install location", detail: installDetail, status: .info))

        if repositioner.hasAccessibilityPermission {
            results.append(DiagResult(label: "Accessibility", detail: "Granted", status: .ok))
        } else {
            results.append(DiagResult(label: "Accessibility", detail: "Not granted — banner repositioning disabled", status: .fail))
        }

        if repositioner.hasAccessibilityPermission {
            if repositioner.isObserving {
                results.append(DiagResult(label: "Repositioner", detail: "Active and observing", status: .ok))
            } else {
                results.append(DiagResult(label: "Repositioner", detail: "Permission granted but not observing", status: .warn))
            }
        }

        launchAtLogin.refresh()
        results.append(DiagResult(
            label: "Launch at login",
            detail: launchAtLogin.isEnabled ? "Enabled" : "Disabled",
            status: launchAtLogin.isEnabled ? .ok : .info
        ))

        let errors = NannyLogger.shared.entries.filter { $0.level == .error }.suffix(5)
        if errors.isEmpty {
            results.append(DiagResult(label: "Recent errors", detail: "None", status: .ok))
        } else {
            let fmt = DateFormatter(); fmt.dateFormat = "HH:mm:ss"
            for e in errors {
                results.append(DiagResult(label: "Error \(fmt.string(from: e.timestamp))", detail: e.message, status: .warn))
            }
        }
        return results
    }

    private func diagReportText(_ results: [DiagResult]) -> String {
        let lines = results.map { r in
            let badge: String
            switch r.status {
            case .ok:   badge = "[OK]  "
            case .warn: badge = "[WARN]"
            case .fail: badge = "[FAIL]"
            case .info: badge = "[INFO]"
            }
            return "\(badge)  \(r.label): \(r.detail)"
        }
        let header = "NotificationNanny Diagnostics — \(Date())"
        return ([header, String(repeating: "-", count: header.count)] + lines).joined(separator: "\n")
    }
}
