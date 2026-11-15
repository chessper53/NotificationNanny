// Listen-only log of every mouse event (never modifies or blocks input), with absolute uptime.
// Usage: mouse-log SECONDS
import AppKit

let seconds = Double(CommandLine.arguments.dropFirst().first ?? "60") ?? 60
let names: [CGEventType: String] = [
    .leftMouseDown: "L-down", .leftMouseUp: "L-up", .rightMouseDown: "R-down", .rightMouseUp: "R-up",
    .otherMouseDown: "O-down", .otherMouseUp: "O-up", .mouseMoved: "move", .leftMouseDragged: "L-drag",
    .rightMouseDragged: "R-drag", .scrollWheel: "scroll",
]
var mask: CGEventMask = 0
for type in names.keys { mask |= 1 << type.rawValue }
mask |= 1 << 29 // gestures (trackpad swipes)
let callback: CGEventTapCallBack = { _, type, event, _ in
    let now = ProcessInfo.processInfo.systemUptime
    let p = event.location
    let name = names[type] ?? "type\(type.rawValue)"
    let evTime = Double(event.timestamp) / 1e9
    print(String(format: "%.4f %@ x=%.0f y=%.0f clicks=%lld flags=0x%llx srcpid=%lld tag=%llx lag=%.1fms",
                 now, name, p.x, p.y, event.getIntegerValueField(.mouseEventClickState), event.flags.rawValue,
                 event.getIntegerValueField(.eventSourceUnixProcessID), event.getIntegerValueField(.eventSourceUserData),
                 (now - evTime) * 1000))
    fflush(stdout)
    return Unmanaged.passUnretained(event)
}
guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                                  eventsOfInterest: mask, callback: callback, userInfo: nil)
else { fputs("Event tap refused (needs Input Monitoring/Accessibility).\n", stderr); exit(1) }
CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
RunLoop.main.run(until: Date().addingTimeInterval(seconds))
