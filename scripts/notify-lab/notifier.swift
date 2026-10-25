// A minimal app whose only job is to post one notification and quit.
//
// macOS shows one banner per app at a time and swaps the content when the same
// app posts again, so stacking can only be exercised with several apps. build.sh
// wraps this one binary as several bundles with their own names and bundle IDs.
//
//   "Lab Alpha.app/Contents/MacOS/notifier" "Title" "Body"
//   "Lab Alpha.app/Contents/MacOS/notifier" "Title" "Body" --actions
//                                                         with the app's own buttons:
//                                                         Archive, Snooze, and Reply
//                                                         with a text field
//   "Lab Alpha.app/Contents/MacOS/notifier" --clear      removes everything this
//                                                         app has delivered, e.g. a
//                                                         backlog queued while locked
//
// When one of its notifications is clicked or one of its buttons used, macOS
// launches the app with no arguments to hand over the response. It then appends
// it to responses.log next to the lab apps (build/notify-lab) and quits, posting
// nothing; that log is how panel-lab checks an action really reached the app.
//
// The first post from each bundle asks for notification permission.

import AppKit
import UserNotifications

let categoryID = "lab.actions"

final class Delegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var handledResponse = false

    func applicationWillFinishLaunching(_ note: Notification) {
        // Before launching ends, or a response that launched the app is never delivered.
        UNUserNotificationCenter.current().delegate = self
        let reply = UNTextInputNotificationAction(identifier: "reply", title: "Reply", options: [],
                                                  textInputButtonTitle: "Send", textInputPlaceholder: "Message")
        let archive = UNNotificationAction(identifier: "archive", title: "Archive", options: [])
        let snooze = UNNotificationAction(identifier: "snooze", title: "Snooze", options: [])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: categoryID, actions: [reply, archive, snooze], intentIdentifiers: []),
        ])
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.first == "--clear" {
            UNUserNotificationCenter.current().removeAllDeliveredNotifications()
            // The removal is handed to the notification daemon asynchronously.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
            return
        }
        if args.isEmpty {
            // Launched to receive a response; wait for it, and quit either way.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { NSApp.terminate(nil) }
            return
        }
        let title = args[0]
        let body = args.count > 1 && args[1] != "--actions" ? args[1] : "Sent by notify-lab"
        let withActions = args.contains("--actions")
        Task { @MainActor in
            await post(title: title, body: body, withActions: withActions)
            // Stay a moment, in case the response arrives while still running.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if !self.handledResponse { NSApp.terminate(nil) }
            }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        handledResponse = true
        let app = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "?"
        let text = (response as? UNTextInputNotificationResponse)?.userText
        var line = "\(ISO8601DateFormatter().string(from: Date())) \(app) action=\(response.actionIdentifier)"
        line += " title=\(response.notification.request.content.title)"
        if let text { line += " text=\(text)" }
        let log = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("responses.log")
        if let handle = try? FileHandle(forWritingTo: log) {
            handle.seekToEndOfFile()
            handle.write(Data((line + "\n").utf8))
            try? handle.close()
        } else {
            try? Data((line + "\n").utf8).write(to: log)
        }
        completionHandler()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.terminate(nil) }
    }

    private func post(title: String, body: String, withActions: Bool) async {
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
        if withActions { content.categoryIdentifier = categoryID }
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
