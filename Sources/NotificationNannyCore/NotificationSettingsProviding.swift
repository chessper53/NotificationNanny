import AppKit
import Combine

@MainActor
package protocol NotificationSettingsProviding: AnyObject {
    var isEnabled: Bool { get }
    var targetDisplayID: CGDirectDisplayID { get }
    var autoDismissSeconds: Double { get }
    /// Fires (on the main actor) whenever any setting changes.
    var settingsDidChange: AnyPublisher<Void, Never> { get }
    func placement(for appName: String?, screen: NSScreen) -> ScreenPlacement
    func recordAppName(_ name: String)
}
