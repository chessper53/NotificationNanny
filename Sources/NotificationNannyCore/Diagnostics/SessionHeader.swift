import AppKit

/// Session context for bug reports. Record group and preset counts to keep user names private.
enum SessionHeader {
    @MainActor
    static func lines(settings: AppSettings) -> [String] {
        let screens = NSScreen.screens.map { s in
            "\(s.localizedName) \(Int(s.frame.width))×\(Int(s.frame.height)) @\(Int(s.backingScaleFactor))x"
        }
        return [
            "macOS \(ProcessInfo.processInfo.operatingSystemVersionString), \(model()), "
                + "\(screens.count) screen\(screens.count == 1 ? "" : "s"): \(screens.joined(separator: ", "))",
            "Settings: " + summary(settings),
        ]
    }

    @MainActor
    static func summary(_ s: AppSettings) -> String {
        var parts: [String] = [s.isEnabled ? "on" : "off"]
        if s.isSnoozed { parts.append("snoozed") }
        parts.append(s.autoDismissSeconds > 0 ? "dismiss after \(Int(s.autoDismissSeconds))s" : "no auto-dismiss")
        if s.bannerScale != 1 { parts.append("scale \(Int(s.bannerScale * 100))%") }
        if s.bannerTint != nil { parts.append("banner colour") }
        if s.bannerTextTint != nil { parts.append("text colour") }
        if s.bannerAnimation != .default { parts.append("animation \(s.bannerAnimation.rawValue)") }
        parts.append("\(s.appGroups.count) group\(s.appGroups.count == 1 ? "" : "s") "
                     + "(\(s.appGroups.reduce(0) { $0 + $1.appNames.count }) apps)")
        if !s.soundGroups.isEmpty { parts.append("\(s.soundGroups.count) sound groups") }
        if !s.presets.isEmpty { parts.append("\(s.presets.count) presets") }
        let flags: [(Bool, String)] = [
            (s.redactBannerContent, "redact"), (s.newestBannerAtBottom, "newest at bottom"),
            (s.followActiveScreen, "follow screen"), (s.pauseDuringFocus, "pause in Focus"),
            (s.pauseWhileStreaming, "pause while sharing"), (s.holdWhileAsleep, "hold while asleep"),
            (!s.avoidNCPanel, "NC may move"), (s.customNotificationCenter, "custom NC"),
            (s.customNotificationCenter && s.customNotificationCenterWidgets, "NC widgets"),
            (!s.protectDesktopWidgets, "desktop widgets unprotected"),
        ]
        parts += flags.filter(\.0).map(\.1)
        return parts.joined(separator: ", ")
    }

    private static func model() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "unknown Mac" }
        var bytes = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &bytes, &size, nil, 0)
        return String(cString: bytes)
    }
}

extension NannyLogger {
    package func logSessionHeader(settings: AppSettings) {
        for line in SessionHeader.lines(settings: settings) { log(line, tag: "App") }
    }
}
