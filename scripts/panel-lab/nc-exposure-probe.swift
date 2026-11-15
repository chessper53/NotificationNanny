// Frame-rate-independent flash detector: samples the window server every ~2 ms and reports
// moments when a Notification Center window lies in the visible screen area without a
// NotificationNanny window (opening cover or custom panel) in front of it.
// Windows already on screen at start (desktop widgets) are ignored.
// Usage: nc-exposure-probe SECONDS [log-path]
import AppKit

let seconds = Double(CommandLine.arguments.dropFirst().first ?? "30") ?? 30
let logPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : nil
let screen = NSScreen.screens.first!.frame
// The native panel draws in the rightmost column; its full-screen host is mostly transparent.
let visible = CGRect(x: screen.width - 480, y: 25, width: 480, height: screen.height - 25)
let nanny = NSRunningApplication.runningApplications(withBundleIdentifier: "com.notificationnanny.app").first?.processIdentifier

struct Win { let id: Int; let pid: pid_t; let owner: String; let frame: CGRect; let alpha: Double; let layer: Int }
func windows() -> [Win] {
    let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
    return list.compactMap { w in
        guard let b = w[kCGWindowBounds as String] as? NSDictionary,
              let f = CGRect(dictionaryRepresentation: b as CFDictionary) else { return nil }
        return Win(id: w[kCGWindowNumber as String] as? Int ?? 0, pid: w[kCGWindowOwnerPID as String] as? pid_t ?? 0,
                   owner: w[kCGWindowOwnerName as String] as? String ?? "", frame: f,
                   alpha: w[kCGWindowAlpha as String] as? Double ?? 1, layer: w[kCGWindowLayer as String] as? Int ?? 0)
    }
}
let baseline = Set(windows().filter { $0.owner == "Notification Center" }.map(\.id))
var out = ""
func log(_ s: String) { print(s); out += s + "\n"; fflush(stdout) }
let start = ProcessInfo.processInfo.systemUptime
var exposed = false, exposedSince = 0.0, exposures = 0, samples = 0, worst = 0.0
var lastState = ""
while ProcessInfo.processInfo.systemUptime - start < seconds {
    let now = ProcessInfo.processInfo.systemUptime, t = now - start
    let list = windows() // front to back
    samples += 1
    var uncovered: CGRect?
    var state = ""
    for (i, w) in list.enumerated() where w.owner == "Notification Center" && !baseline.contains(w.id) && w.alpha > 0.01 {
        let part = w.frame.intersection(visible)
        guard part.width > 40, part.height > 40 else { continue }
        // Is any NotificationNanny window in front of it covering the visible part?
        // The cover starts below the menu bar, a few points lower than the native host.
        let covered = list[..<i].contains {
            let shared = $0.frame.intersection(part)
            return $0.pid == nanny && $0.alpha > 0.99 && shared.width * shared.height >= part.width * part.height * 0.97
        }
        state += String(format: "nc#%d %.0f,%.0f %.0fx%.0f a%.2f L%d %@; ", w.id, w.frame.minX, w.frame.minY,
                        w.frame.width, w.frame.height, w.alpha, w.layer, covered ? "covered" : "UNCOVERED")
        if !covered { uncovered = part }
    }
    for w in list where w.pid == nanny && w.alpha > 0.01 && w.frame.intersects(visible) && w.frame.width > 200 {
        state += String(format: "nn %.0fx%.0f L%d; ", w.frame.width, w.frame.height, w.layer)
    }
    if state != lastState { log(String(format: "%8.3f [%.3f] %@", t, now, state.isEmpty ? "(none visible)" : state)); lastState = state }
    if uncovered != nil, !exposed { exposed = true; exposedSince = t; exposures += 1 }
    if uncovered == nil, exposed {
        exposed = false; worst = max(worst, t - exposedSince)
        log(String(format: "%8.3f exposure ended after %.1f ms", t, (t - exposedSince) * 1000))
    }
    usleep(2000)
}
log("samples=\(samples) exposures=\(exposures) longest=\(String(format: "%.1f", worst * 1000)) ms")
if let logPath { try? out.write(toFile: logPath, atomically: true, encoding: .utf8) }
exit(exposures == 0 ? 0 : 1)
