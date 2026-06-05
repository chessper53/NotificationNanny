import AppKit
import Combine
import SwiftUI

@MainActor
package protocol NotificationSettingsProviding: AnyObject {
    var isEnabled: Bool { get }
    var pauseWhileStreaming: Bool { get }
    var avoidNCPanel: Bool { get }
    var holdWhileAsleep: Bool { get }
    var targetDisplayID: CGDirectDisplayID { get }
    var autoDismissSeconds: Double { get }
    /// 1.0 = native size. Applied via private CGSSetWindowTransform.
    var bannerScale: Double { get }
    var bannerColor: Color { get }
    func effectiveBannerColor(for appName: String?) -> Color
    func effectiveBannerColor(forGroupID groupID: UUID?) -> Color
    /// Fires (on the main actor) whenever any setting changes.
    var settingsDidChange: AnyPublisher<Void, Never> { get }
    func placement(for appName: String?, screen: NSScreen) -> ScreenPlacement
    func placement(forGroupID groupID: UUID?, screen: NSScreen) -> ScreenPlacement
    /// Returns the group-level screen override, or 0 if none.
    func targetDisplay(for appName: String?) -> CGDirectDisplayID
    func targetDisplay(forGroupID groupID: UUID?) -> CGDirectDisplayID
    func recordAppName(_ name: String)
    /// Returns the group's bannerScale if set, otherwise the global bannerScale.
    func effectiveBannerScale(for appName: String?) -> Double
    func effectiveBannerScale(forGroupID groupID: UUID?) -> Double
    func effectiveBannerMode(for appName: String?) -> BannerMode?
    func effectiveBannerMode(forGroupID groupID: UUID?) -> BannerMode?
    /// True when a custom overlay should be used for the given context.
    func shouldUseCustomBanner(for appName: String?) -> Bool
    func shouldUseCustomBanner(forGroupID groupID: UUID?) -> Bool
    var bannerAnimation: BannerAnimation { get }
}
