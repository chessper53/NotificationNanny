// A minimal app whose only job is to post one notification and quit.
//
// macOS shows one banner per app at a time and swaps the content when the same
// app posts again, so stacking can only be exercised with several apps. build.sh
// wraps this one binary as several bundles with their own names and bundle IDs.
//
//   "Lab Alpha.app/Contents/MacOS/notifier" "Title" "Body"
//
// The first post from each bundle asks for notification permission.

import AppKit
import UserNotifications

final class Delegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ note: Notification) {
        let args = Array(CommandLine.arguments.dropFirst())
        let title = args.first ?? "Lab notification"
        let body = args.dropFirst().first ?? "Sent by notify-lab"
        Task { @MainActor in
            await post(title: title, body: body)
            NSApp.terminate(nil)
        }
    }

    private func post(title: String, body: String) async {
        let center = UNUserNotificationCenter.current()
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            status = await center.notificationSettings().authorizationStatus
        }
        guard status == .authorized || status == .provisional else {
            FileHandle.standardError.write(Data("not authorized (status \(status.rawValue)); allow it in System Settings > Notifications\n".utf8))
            exit(2)
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        do {
            try await center.add(request)
        } catch {
            FileHandle.standardError.write(Data("post failed: \(error)\n".utf8))
            exit(3)
        }
    }
}

let app = NSApplication.shared
let delegate = Delegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
