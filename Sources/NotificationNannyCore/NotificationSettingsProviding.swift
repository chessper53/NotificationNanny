import AppKit
import Combine

@MainActor
package protocol NotificationSettingsProviding: AnyObject {
    var isEnabled: Bool { get }
    var pauseWhileStreaming: Bool { get }
    var targetDisplayID: CGDirectDisplayID { get }
    var autoDismissSeconds: Double { get }
    /// Fires (on the main actor) whenever any setting changes.
    var settingsDidChange: AnyPublisher<Void, Never> { get }
    func placement(for appName: String?, screen: NSScreen) -> ScreenPlacement
    func placement(forGroupID groupID: UUID?, screen: NSScreen) -> ScreenPlacement
    /// Returns the group-level screen override, or 0 if none.
    func targetDisplay(for appName: String?) -> CGDirectDisplayID
    func targetDisplay(forGroupID groupID: UUID?) -> CGDirectDisplayID
    func recordAppName(_ name: String)
}
