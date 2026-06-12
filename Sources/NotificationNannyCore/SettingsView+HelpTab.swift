import SwiftUI
import AppKit

struct HelpTabView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var repositioner: NotificationRepositioner
    @EnvironmentObject var launchAtLogin: LaunchAtLogin
    @ObservedObject private var logger = NannyLogger.shared

    @State private var diagResults: [DiagResult]? = nil
    @State private var diagCopied = false
    @State private var logsExpanded = false

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

            // MARK: - Diagnostics
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

            // MARK: - Logs
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { logsExpanded.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 14)
                        Text("Activity Logs").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        Spacer()
                        if !logger.entries.isEmpty {
                            let errorCount = logger.entries.filter { $0.level == .error }.count
                            let warnCount  = logger.entries.filter { $0.level == .warn  }.count
                            HStack(spacing: 4) {
                                if errorCount > 0 {
                                    logBadge("\(errorCount)", color: Color(red: 1, green: 0.3, blue: 0.3))
                                }
                                if warnCount > 0 {
                                    logBadge("\(warnCount)", color: .orange)
                                }
                                Text("\(logger.entries.count) entries")
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                        } else {
                            Text("Empty").font(.caption2).foregroundStyle(.tertiary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(logsExpanded ? 90 : 0))
                            .animation(.easeInOut(duration: 0.2), value: logsExpanded)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if logsExpanded {
                    Divider().padding(.horizontal, 12)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("\(logger.entries.count) entries")
                                .font(.footnote.weight(.semibold)).foregroundStyle(Color(white: 0.45))
                            Spacer()
                            Button("Clear") { logger.clear() }
                                .buttonStyle(.borderless).font(.caption).foregroundStyle(Color.nannyAccent)
                                .disabled(logger.entries.isEmpty)
                            Button("Save…") { logger.saveToFile() }
                                .buttonStyle(.borderless).font(.caption).foregroundStyle(Color.nannyAccent)
                                .disabled(logger.entries.isEmpty)
                        }

                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 1) {
                                if logger.entries.isEmpty {
                                    Text("No entries yet. Trigger a notification to start logging.")
                                        .font(.caption2).foregroundStyle(.tertiary).padding(10)
                                } else {
                                    ForEach(logger.entries.reversed()) { entry in
                                        LogEntryRow(entry: entry)
                                    }
                                }
                            }
                            .padding(6)
                        }
                        .frame(height: 200)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                }
            }
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Log helpers

    @ViewBuilder
    private func logBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(color, in: Capsule())
    }

    // MARK: - Help links

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
        var r: [DiagResult] = []

        // App info
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let osVer   = ProcessInfo.processInfo.operatingSystemVersionString
        r.append(DiagResult(label: "App version",   detail: "v\(version) (\(build))", status: .info))
        r.append(DiagResult(label: "macOS version", detail: osVer,                    status: .info))

        let bundlePath = Bundle.main.bundlePath
        let installDetail: String
        switch InstallSource.current {
        case .homebrew: installDetail = "Homebrew Cask"
        case .direct:   installDetail = bundlePath.hasPrefix("/Applications") ? "Direct install (/Applications)" : bundlePath
        }
        r.append(DiagResult(label: "Install source", detail: installDetail, status: .info))

        // Core status
        r.append(DiagResult(
            label: "App enabled",
            detail: settings.isEnabled ? "Yes" : "Disabled by user",
            status: settings.isEnabled ? .ok : .warn
        ))

        r.append(DiagResult(
            label: "Accessibility",
            detail: repositioner.hasAccessibilityPermission ? "Granted" : "Not granted — repositioning disabled",
            status: repositioner.hasAccessibilityPermission ? .ok : .fail
        ))

        if repositioner.hasAccessibilityPermission {
            r.append(DiagResult(
                label: "Repositioner",
                detail: repositioner.isObserving ? "Active and observing" : "Permission granted but not observing",
                status: repositioner.isObserving ? .ok : .warn
            ))
        }

        // Custom banner
        let customBannerActive = settings.shouldUseCustomBanner(for: nil)
        var customReason = ""
        if abs(settings.bannerScale - 1.0) > 0.001 { customReason = "scale \(Int(settings.bannerScale * 100))%" }
        else if settings.hasBannerColor { customReason = "global tint set" }
        r.append(DiagResult(
            label: "Custom banner (global)",
            detail: customBannerActive ? "Active — \(customReason)" : "Off — using system banner",
            status: customBannerActive ? .info : .info
        ))

        // Screens
        let screens = NSScreen.screens
        let screenNames = screens.enumerated().map { i, s in
            "\(i + 1): \(Int(s.frame.width))x\(Int(s.frame.height))"
        }.joined(separator: ", ")
        r.append(DiagResult(
            label: "Screens",
            detail: "\(screens.count) display\(screens.count == 1 ? "" : "s") — \(screenNames)",
            status: screens.count > 1 ? .info : .ok
        ))

        // Settings summary
        let dismissDetail = settings.autoDismissSeconds > 0
            ? "\(Int(settings.autoDismissSeconds))s custom timeout"
            : "System default"
        r.append(DiagResult(label: "Auto-dismiss", detail: dismissDetail, status: .info))

        let groupCount = settings.appGroups.count
        let appCount   = settings.appGroups.flatMap(\.appNames).count
        let knownCount = settings.knownAppNames.count
        r.append(DiagResult(
            label: "Exception groups",
            detail: groupCount == 0
                ? "None configured"
                : "\(groupCount) group\(groupCount == 1 ? "" : "s"), \(appCount) app\(appCount == 1 ? "" : "s") assigned, \(knownCount) apps seen",
            status: .info
        ))

        r.append(DiagResult(
            label: "Presets",
            detail: settings.presets.isEmpty ? "None saved" : "\(settings.presets.count) saved",
            status: .info
        ))

        launchAtLogin.refresh()
        r.append(DiagResult(
            label: "Launch at login",
            detail: launchAtLogin.isEnabled ? "Enabled" : "Disabled",
            status: launchAtLogin.isEnabled ? .ok : .info
        ))

        // Notification Center process
        let ncRunning = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first != nil
        r.append(DiagResult(
            label: "Notification Center",
            detail: ncRunning ? "Running" : "Not detected (may be normal)",
            status: ncRunning ? .ok : .warn
        ))

        // Log health
        let allErrors = logger.entries.filter { $0.level == .error }
        let allWarns  = logger.entries.filter { $0.level == .warn  }
        if allErrors.isEmpty && allWarns.isEmpty {
            r.append(DiagResult(label: "Session log", detail: "No errors or warnings", status: .ok))
        } else {
            r.append(DiagResult(
                label: "Session log",
                detail: "\(allErrors.count) error\(allErrors.count == 1 ? "" : "s"), \(allWarns.count) warning\(allWarns.count == 1 ? "" : "s") — open Logs for details",
                status: allErrors.isEmpty ? .warn : .fail
            ))
        }

        return r
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
