// A screenshot helper with a Screen Recording grant of its own, for lab runs started from
// an editor's terminal, which has none to lend. Built once into build/panel-lab/Shot.app
// by shot.sh and never rebuilt, so the grant, which an ad-hoc signature ties to this exact
// build, stays.
//
//   Shot screencapture <args…>          runs /usr/sbin/screencapture with them
//   Shot window <windowID> <out.png>    the window as ScreenCaptureKit sees it, the way
//                                       WidgetCapture captures Notification Center's
//
// Writes what happened to <out>.txt (or build/panel-lab/shot.txt), as open -W can't
// hand back an exit status.
import AppKit
@preconcurrency import ScreenCaptureKit

let args = Array(CommandLine.arguments.dropFirst())
let report = URL(fileURLWithPath: (args.last.map { $0.hasSuffix(".png") ? $0 : nil } ?? nil).map { $0 + ".txt" }
    ?? FileManager.default.currentDirectoryPath + "/shot.txt")

func finish(_ message: String) -> Never {
    try? (message + "\n").write(to: report, atomically: true, encoding: .utf8)
    exit(message.hasPrefix("ok") ? 0 : 1)
}

switch args.first {
case "screencapture":
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = Array(args.dropFirst())
    do { try p.run() } catch { finish("failed: \(error)") }
    p.waitUntilExit()
    finish(p.terminationStatus == 0 ? "ok" : "failed: screencapture exited \(p.terminationStatus)")
case "window":
    guard args.count == 3, let id = CGWindowID(args[1]) else { finish("usage: Shot window <windowID> <out.png>") }
    let out = URL(fileURLWithPath: args[2])
    Task {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let window = content.windows.first(where: { $0.windowID == id }) else { finish("failed: no window \(id)") }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let scale = CGFloat(filter.pointPixelScale)
            let config = SCStreamConfiguration()
            config.width = Int(window.frame.width * scale)
            config.height = Int(window.frame.height * scale)
            config.showsCursor = false
            config.ignoreShadowsSingleWindow = true
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let rep = NSBitmapImageRep(cgImage: image)
            try rep.representation(using: .png, properties: [:])?.write(to: out)
            finish("ok \(image.width)x\(image.height) frame \(window.frame) onScreen \(window.isOnScreen)")
        } catch {
            finish("failed: \(error)")
        }
    }
    RunLoop.main.run()
default:
    finish("usage: Shot screencapture <args…> | window <windowID> <out.png>")
}
