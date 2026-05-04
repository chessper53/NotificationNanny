import AppKit
import ApplicationServices
import Combine

/// Watches `com.apple.notificationcenterui` for new windows and repositions them
/// to the user-selected location via the Accessibility API.
///
/// Apple does not expose a public API for moving notification banners. This is the
/// least-bad approach that does not require private SPI: subscribe to AX window
/// notifications on the NotificationCenter process and `kAXPositionAttribute`
/// each window as it appears.
@MainActor
final class NotificationRepositioner: ObservableObject {
    @Published private(set) var hasAccessibilityPermission: Bool = false
    @Published private(set) var isObserving: Bool = false

    private var settings: AppSettings?
    private var cancellables = Set<AnyCancellable>()

    private var observer: AXObserver?
    private var ncApp: AXUIElement?
    private var ncPid: pid_t = 0
    private var permissionPollTimer: Timer?

    init() {
        refreshAccessibilityStatus()
        // If the user grants permission via System Settings (without clicking
        // the in-app button), poll until we notice and start observing.
        startPermissionPollIfNeeded()
        // The NotificationCenterUI process can be relaunched; re-bind when it does.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == "com.apple.notificationcenterui" else { return }
            Task { @MainActor [weak self] in
                self?.startObserving()
            }
        }
    }

    func bind(to settings: AppSettings) {
        guard self.settings == nil else { return }
        self.settings = settings

        // Re-apply on every settings change. Throttle so dragging a slider doesn't
        // hammer the AX API at full screen-refresh rate.
        settings.objectWillChange
            .throttle(for: .milliseconds(16), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                self?.repositionVisibleWindows()
            }
            .store(in: &cancellables)

        startObserving()
    }

    // MARK: - Accessibility permission

    func refreshAccessibilityStatus() {
        hasAccessibilityPermission = AXIsProcessTrusted()
    }

    func requestAccessibilityPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        refreshAccessibilityStatus()
        startPermissionPollIfNeeded()
    }

    private func startPermissionPollIfNeeded() {
        guard permissionPollTimer == nil, !hasAccessibilityPermission else { return }
        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.refreshAccessibilityStatus()
                if self.hasAccessibilityPermission {
                    timer.invalidate()
                    self.permissionPollTimer = nil
                    self.startObserving()
                }
            }
        }
    }

    // MARK: - Observation

    func startObserving() {
        guard hasAccessibilityPermission else {
            startPermissionPollIfNeeded()
            return
        }

        teardownObserver()

        guard let runningApp = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.notificationcenterui")
            .first else {
            return
        }
        let pid = runningApp.processIdentifier
        let app = AXUIElementCreateApplication(pid)

        var newObserver: AXObserver?
        let createResult = AXObserverCreate(pid, axNotificationCallback, &newObserver)
        guard createResult == .success, let newObserver else { return }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let notes: [String] = [
            kAXWindowCreatedNotification as String,
            kAXFocusedWindowChangedNotification as String,
            kAXWindowMovedNotification as String,
        ]
        for name in notes {
            AXObserverAddNotification(newObserver, app, name as CFString, selfPtr)
        }

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(newObserver),
            .defaultMode
        )

        self.observer = newObserver
        self.ncApp = app
        self.ncPid = pid
        self.isObserving = true

        repositionVisibleWindows()
    }

    private func teardownObserver() {
        if let observer {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .defaultMode
            )
        }
        observer = nil
        ncApp = nil
        ncPid = 0
        isObserving = false
    }

    // MARK: - Repositioning

    fileprivate func handleAXEvent(element: AXUIElement, notification: String) {
        // The event element may be the app or the window; try repositioning both.
        repositionWindow(element)
        repositionVisibleWindows()
    }

    private func repositionVisibleWindows() {
        guard let ncApp else { return }
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(ncApp, kAXWindowsAttribute as CFString, &value)
        guard result == .success, let windows = value as? [AXUIElement] else { return }
        for window in windows {
            repositionWindow(window)
        }
    }

    private func repositionWindow(_ window: AXUIElement) {
        guard let settings, settings.isEnabled else { return }

        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let sizeValue = sizeRef, CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return }
        var size = CGSize.zero
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        guard size.width > 0, size.height > 0 else { return }

        // Figure out which screen the notification currently lives on so we
        // reposition relative to the right display in a multi-monitor setup.
        var currentAxPoint = CGPoint.zero
        var posRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
           let posValue = posRef, CFGetTypeID(posValue) == AXValueGetTypeID() {
            AXValueGetValue(posValue as! AXValue, .cgPoint, &currentAxPoint)
        }
        guard let screen = screenContainingAxPoint(currentAxPoint) ?? NSScreen.main else { return }
        let placement = settings.placement(for: screen)

        var newOrigin = placement.position.axOrigin(
            forWindowSize: size,
            screen: screen,
            xOffset: CGFloat(placement.xOffset),
            yOffset: CGFloat(placement.yOffset)
        )

        guard let positionValue = AXValueCreate(.cgPoint, &newOrigin) else { return }
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
    }

    /// Convert an AX point (top-left of primary screen) to NSScreen coords
    /// (bottom-left of primary screen) and find the screen that contains it.
    private func screenContainingAxPoint(_ axPoint: CGPoint) -> NSScreen? {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let nsPoint = CGPoint(x: axPoint.x, y: primaryHeight - axPoint.y)
        return NSScreen.screens.first { $0.frame.contains(nsPoint) }
    }
}

// MARK: - C-style AX callback

private func axNotificationCallback(observer: AXObserver,
                                    element: AXUIElement,
                                    notification: CFString,
                                    refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let nanny = Unmanaged<NotificationRepositioner>.fromOpaque(refcon).takeUnretainedValue()
    let name = notification as String
    Task { @MainActor in
        nanny.handleAXEvent(element: element, notification: name)
    }
}
