// Toggles Notification Center with the Fn+N shortcut, a route that bypasses the clock.
// Arguments: cycles, open seconds, closed seconds.
import AppKit

let args = CommandLine.arguments.dropFirst().map { Double($0) ?? 0 }
let cycles = Int(args.first ?? 5), openTime = args.count > 1 ? args[1] : 1, closedTime = args.count > 2 ? args[2] : 1
func press() {
    let n: CGKeyCode = 45
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: nil, virtualKey: n, keyDown: down)
        e?.flags = .maskSecondaryFn
        e?.post(tap: .cghidEventTap)
        usleep(30_000)
    }
}
let start = ProcessInfo.processInfo.systemUptime
for cycle in 1...max(cycles, 1) {
    print(String(format: "%.3f open %d", ProcessInfo.processInfo.systemUptime - start, cycle)); press()
    usleep(useconds_t(openTime * 1e6))
    print(String(format: "%.3f close %d", ProcessInfo.processInfo.systemUptime - start, cycle)); press()
    usleep(useconds_t(closedTime * 1e6))
}
