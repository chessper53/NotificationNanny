import SwiftUI
import AppKit

/// Health-check status for a single diagnostics row.
enum DiagStatus {
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
    var badge: String {
        switch self {
        case .ok:   return "[OK]  "
        case .warn: return "[WARN]"
        case .fail: return "[FAIL]"
        case .info: return "[INFO]"
        }
    }
}

struct DiagItem: Identifiable {
    let id = UUID()
    let label: String
    let detail: String
    let status: DiagStatus
}

/// Builds the diagnostics health report shown in the Diagnostics tab and attached to bug reports.
@MainActor
enum Diagnostics {
    private static let repoURL = "https://github.com/chessper53/NotificationNanny"

    static func collect(settings: AppSettings,
                        repositioner: NotificationRepositioner,
                        launchAtLogin: LaunchAtLogin) -> [DiagItem] {
        var r: [DiagItem] = []

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let osVer   = ProcessInfo.processInfo.operatingSystemVersionString
        r.append(DiagItem(label: "App version",   detail: "v\(version) (\(build))", status: .info))
        r.append(DiagItem(label: "macOS version", detail: osVer,                    status: .info))

        let bundlePath = Bundle.main.bundlePath
        let installDetail: String
        switch InstallSource.current {
        case .homebrew: installDetail = "Homebrew Cask"
        case .direct:   installDetail = bundlePath.hasPrefix("/Applications") ? "Direct install (/Applications)" : bundlePath
        }
        r.append(DiagItem(label: "Install source", detail: installDetail, status: .info))

        r.append(DiagItem(
            label: "App enabled",
            detail: settings.isEnabled ? "Yes" : "Disabled by user",
            status: settings.isEnabled ? .ok : .warn
        ))

        if settings.isSnoozed, let until = settings.snoozedUntil {
            let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none
            r.append(DiagItem(label: "Snoozed", detail: "Paused until \(f.string(from: until))", status: .warn))
        }

        r.append(DiagItem(
            label: "Accessibility",
            detail: repositioner.hasAccessibilityPermission ? "Granted" : "Not granted — repositioning disabled",
            status: repositioner.hasAccessibilityPermission ? .ok : .fail
        ))

        if repositioner.hasAccessibilityPermission {
            r.append(DiagItem(
                label: "Repositioner",
                detail: repositioner.isObserving ? "Active and observing" : "Permission granted but not observing",
                status: repositioner.isObserving ? .ok : .warn
            ))
        }

        let customBannerActive = settings.shouldUseCustomBanner(for: nil)
        var customReason = ""
        if abs(settings.bannerScale - 1.0) > 0.001 { customReason = "scale \(Int(settings.bannerScale * 100))%" }
        else if settings.hasBannerColor { customReason = "global tint set" }
        else if settings.bannerAnimation != .default { customReason = "animation \(settings.bannerAnimation.label)" }
        r.append(DiagItem(
            label: "Custom banner (global)",
            detail: customBannerActive ? "Active — \(customReason)" : "Off — using system banner",
            status: .info
        ))

        let screens = NSScreen.screens
        let screenNames = screens.enumerated().map { i, s in
            "\(i + 1): \(Int(s.frame.width))x\(Int(s.frame.height))"
        }.joined(separator: ", ")
        r.append(DiagItem(
            label: "Screens",
            detail: "\(screens.count) display\(screens.count == 1 ? "" : "s") — \(screenNames)",
            status: screens.count > 1 ? .info : .ok
        ))

        let dismissDetail = settings.autoDismissSeconds > 0
            ? "\(Int(settings.autoDismissSeconds))s custom timeout"
            : "System default"
        r.append(DiagItem(label: "Auto-dismiss", detail: dismissDetail, status: .info))

        let groupCount = settings.appGroups.count
        let appCount   = settings.appGroups.flatMap(\.appNames).count
        let knownCount = settings.knownAppNames.count
        r.append(DiagItem(
            label: "Exception groups",
            detail: groupCount == 0
                ? "None configured"
                : "\(groupCount) group\(groupCount == 1 ? "" : "s"), \(appCount) app\(appCount == 1 ? "" : "s") assigned, \(knownCount) apps seen",
            status: .info
        ))

        r.append(DiagItem(
            label: "Presets",
            detail: settings.presets.isEmpty ? "None saved" : "\(settings.presets.count) saved",
            status: .info
        ))

        launchAtLogin.refresh()
        r.append(DiagItem(
            label: "Launch at login",
            detail: launchAtLogin.isEnabled ? "Enabled" : "Disabled",
            status: launchAtLogin.isEnabled ? .ok : .info
        ))

        let ncRunning = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first != nil
        r.append(DiagItem(
            label: "Notification Center",
            detail: ncRunning ? "Running" : "Not detected (may be normal)",
            status: ncRunning ? .ok : .warn
        ))

        let allErrors = NannyLogger.shared.entries.filter { $0.level == .error }
        let allWarns  = NannyLogger.shared.entries.filter { $0.level == .warn  }
        if allErrors.isEmpty && allWarns.isEmpty {
            r.append(DiagItem(label: "Session log", detail: "No errors or warnings", status: .ok))
        } else {
            r.append(DiagItem(
                label: "Session log",
                detail: "\(allErrors.count) error\(allErrors.count == 1 ? "" : "s"), \(allWarns.count) warning\(allWarns.count == 1 ? "" : "s") — see logs below",
                status: allErrors.isEmpty ? .warn : .fail
            ))
        }

        return r
    }

    static func reportText(_ items: [DiagItem]) -> String {
        let lines = items.map { "\($0.status.badge)  \($0.label): \($0.detail)" }
        let header = "NotificationNanny Diagnostics — \(Date())"
        return ([header, String(repeating: "-", count: header.count)] + lines).joined(separator: "\n")
    }

    /// Full text (diagnostics + logs) suitable for the clipboard.
    static func fullReport(_ items: [DiagItem]) -> String {
        let logs = NannyLogger.shared.exportText()
        return reportText(items) + "\n\n=== Activity log ===\n" + (logs.isEmpty ? "(empty)" : logs)
    }

    /// A GitHub "new issue" URL with diagnostics + recent logs prefilled in the body. Logs are
    /// capped so the URL stays within limits; the full report is also copied to the clipboard.
    static func bugReportURL(items: [DiagItem]) -> URL? {
        let diag = reportText(items)
        // Keep the inline logs to a recent tail so the URL doesn't blow past server limits.
        let allLogs = NannyLogger.shared.exportText()
        let logCap = 3000
        let logSection: String
        if allLogs.isEmpty {
            logSection = "(no log entries)"
        } else if allLogs.count > logCap {
            logSection = "…(truncated — full log copied to your clipboard, please paste below)\n"
                + String(allLogs.suffix(logCap))
        } else {
            logSection = allLogs
        }

        let body = """
        ## Describe the bug
        <!-- What happened? What did you expect? Steps to reproduce. -->


        ## Diagnostics
        ```
        \(diag)
        ```

        ## Logs
        ```
        \(logSection)
        ```
        """

        var comps = URLComponents(string: "\(repoURL)/issues/new")
        comps?.queryItems = [
            URLQueryItem(name: "title", value: "Bug: "),
            URLQueryItem(name: "labels", value: "bug"),
            URLQueryItem(name: "body", value: body),
        ]
        return comps?.url
    }
}
