import AppKit
import Combine
import SwiftUI

@MainActor
package protocol NotificationSettingsProviding: AnyObject {
    var isEnabled: Bool { get }
    var isActive: Bool { get }
    var pauseWhileStreaming: Bool { get }
    var avoidNCPanel: Bool { get }
    var protectDesktopWidgets: Bool { get }
    var followActiveScreen: Bool { get }
    var pauseDuringFocus: Bool { get }
    var holdWhileAsleep: Bool { get }
    var targetDisplayID: CGDirectDisplayID { get }
    func resolvedTargetScreen() -> NSScreen?
    func resolvedTargetScreen(for appName: String?) -> NSScreen?
    func resolvedTargetScreen(forGroupID groupID: UUID?) -> NSScreen?
    var autoDismissSeconds: Double { get }
    var bannerScale: Double { get }
    var bannerColor: Color { get }
    func effectiveBannerColor(for appName: String?) -> Color
    func effectiveBannerColor(forGroupID groupID: UUID?) -> Color
    var effectiveBannerTextColor: Color? { get }
    var settingsDidChange: AnyPublisher<Void, Never> { get }
    func placement(for appName: String?, screen: NSScreen) -> ScreenPlacement
    func placement(forGroupID groupID: UUID?, screen: NSScreen) -> ScreenPlacement
    func targetDisplay(for appName: String?) -> CGDirectDisplayID
    func targetDisplay(forGroupID groupID: UUID?) -> CGDirectDisplayID
    func recordAppName(_ name: String)
    func effectiveBannerScale(for appName: String?) -> Double
    func effectiveBannerScale(forGroupID groupID: UUID?) -> Double
    func effectiveBannerMode(for appName: String?) -> BannerMode?
    func effectiveBannerMode(forGroupID groupID: UUID?) -> BannerMode?
    func shouldUseCustomBanner(for appName: String?) -> Bool
    func shouldUseCustomBanner(forGroupID groupID: UUID?) -> Bool
    var bannerAnimation: BannerAnimation { get }
    func effectiveBannerAnimation(for appName: String?) -> BannerAnimation
    func effectiveBannerAnimation(forGroupID groupID: UUID?) -> BannerAnimation
}
