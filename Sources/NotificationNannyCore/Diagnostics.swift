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

        // Default position the user picked — the "it moved my notifications somewhere" answer.
        if let main = NSScreen.main {
            let p = settings.placement(for: main)
            let displayLabel = settings.targetDisplayID == 0
                ? (settings.followActiveScreen ? "active screen" : "current screen")
                : "display \(settings.targetDisplayID)"
            let offset = (p.xOffset != 0 || p.yOffset != 0) ? " (offset \(Int(p.xOffset)),\(Int(p.yOffset)))" : ""
            r.append(DiagItem(label: "Default position", detail: "\(p.position.label) on \(displayLabel)\(offset)", status: .info))
        }

        // Behavior toggles — these decide whether banners/widgets/the panel get touched, so
        // they're the first thing to check for "it moved my widgets" / "it grabbed the panel".
        let toggles: [(String, Bool)] = [
            ("Protect desktop widgets", settings.protectDesktopWidgets),
            ("Hold while asleep",       settings.holdWhileAsleep),
            ("Avoid Notification Center panel", settings.avoidNCPanel),
            ("Follow active screen",    settings.followActiveScreen),
            ("Pause while screen-sharing", settings.pauseWhileStreaming),
            ("Pause during Focus",      settings.pauseDuringFocus),
        ]
        let onList  = toggles.filter { $0.1 }.map(\.0)
        let offList = toggles.filter { !$0.1 }.map(\.0)
        r.append(DiagItem(
            label: "Behavior",
            detail: "On: \(onList.isEmpty ? "none" : onList.joined(separator: ", "))"
                + "  •  Off: \(offList.isEmpty ? "none" : offList.joined(separator: ", "))",
            status: .info
        ))

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

    /// Developer tool: reads a pasted diagnostics report and applies the settings it describes
    /// to `settings`, so a user's configuration can be reproduced locally. Parses the same
    /// human-readable lines `collect` emits (Behavior toggles, Default position, Auto-dismiss,
    /// Custom banner scale). Returns a list of the changes applied (empty if nothing matched).
    @discardableResult
    static func applyReport(_ text: String, to settings: AppSettings) -> [String] {
        var changes: [String] = []

        // Behavior toggles — match each known label inside the On / Off segments.
        if let detail = value(after: "Behavior:", in: text) {
            let segments = detail.components(separatedBy: "•")
            let onSeg  = segments.first ?? ""
            let offSeg = segments.count > 1 ? segments[1] : ""
            let toggles: [(String, (Bool) -> Void)] = [
                ("Protect desktop widgets",         { settings.protectDesktopWidgets = $0 }),
                ("Hold while asleep",               { settings.holdWhileAsleep = $0 }),
                ("Avoid Notification Center panel", { settings.avoidNCPanel = $0 }),
                ("Follow active screen",            { settings.followActiveScreen = $0 }),
                ("Pause while screen-sharing",      { settings.pauseWhileStreaming = $0 }),
                ("Pause during Focus",              { settings.pauseDuringFocus = $0 }),
            ]
            for (label, apply) in toggles {
                if onSeg.contains(label)  { apply(true);  changes.append("\(label): on") }
                else if offSeg.contains(label) { apply(false); changes.append("\(label): off") }
            }
        }

        // Default position — "Top Right on active screen (offset 0,12)".
        if let detail = value(after: "Default position:", in: text),
           let onRange = detail.range(of: " on ") {
            let posLabel = String(detail[..<onRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            if let pos = NotificationPosition.allCases.first(where: { $0.label == posLabel }) {
                let nums = numbers(in: detail, matching: #"offset (-?\d+),(-?\d+)"#)
                let xOff = nums.count > 0 ? nums[0] : 0
                let yOff = nums.count > 1 ? nums[1] : 0
                let rest = String(detail[onRange.upperBound...])
                if rest.contains("active screen") {
                    settings.followActiveScreen = true; settings.targetDisplayID = 0
                } else if let id = numbers(in: rest, matching: #"display (\d+)"#).first {
                    settings.followActiveScreen = false; settings.targetDisplayID = CGDirectDisplayID(id)
                } else {
                    settings.targetDisplayID = 0
                }
                if let main = NSScreen.main {
                    settings.setPlacement(ScreenPlacement(position: pos, xOffset: xOff, yOffset: yOff), for: main)
                }
                changes.append("Default position: \(posLabel)")
            }
        }

        // Auto-dismiss — "8s custom timeout" or "System default".
        if let detail = value(after: "Auto-dismiss:", in: text) {
            if detail.contains("System default") {
                settings.autoDismissSeconds = 0; changes.append("Auto-dismiss: system default")
            } else if let secs = numbers(in: detail, matching: #"(\d+)s"#).first {
                settings.autoDismissSeconds = secs; changes.append("Auto-dismiss: \(Int(secs))s")
            }
        }

        // Custom banner scale — "Active — scale 150%".
        if let detail = value(after: "Custom banner (global):", in: text) {
            if let pct = numbers(in: detail, matching: #"scale (\d+)%"#).first {
                settings.bannerScale = pct / 100; changes.append("Banner scale: \(Int(pct))%")
            } else if detail.contains("Off") {
                settings.bannerScale = 1.0
            }
        }

        return changes
    }

    /// The text following `label` up to the end of that line, trimmed.
    private static func value(after label: String, in text: String) -> String? {
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if let r = line.range(of: label) {
                return String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    /// All capture-group integers from the first regex match in `text`.
    private static func numbers(in text: String, matching pattern: String) -> [Double] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return [] }
        return (1..<m.numberOfRanges).compactMap { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : Double(ns.substring(with: r))
        }
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
