@preconcurrency import ApplicationServices
import Foundation

/// Forwards app actions to native notifications and mirrors native reply fields.
/// AX actions reach the notifying app even while the native host is parked.
@MainActor
final class NotificationActions {
    /// Actions offered before opening a reply; the newly offered action sends it.
    private var offeredBefore: [String: [String]] = [:]

    /// The app's own actions on the notification, in Notification Center's order.
    static func appActions(of el: AXUIElement) -> [String] {
        appActions(of: el, builtIn: NCActionNames.builtIn)
    }

    /// Accepts native built in names explicitly for reads off the main thread.
    nonisolated static func appActions(of el: AXUIElement, builtIn: Set<String>) -> [String] {
        var ref: CFArray?
        guard AXUIElementCopyActionNames(el, &ref) == .success, let actions = ref as? [String] else { return [] }
        return actions.filter { $0.hasPrefix("Name:") }.map(customActionName)
            .filter { !builtIn.contains($0) }
    }

    /// Hide Details is offered only while the native action buttons are expanded.
    static func isExpanded(_ el: AXUIElement) -> Bool {
        isExpanded(el, hideDetails: NCActionNames.hideDetails)
    }

    nonisolated static func isExpanded(_ el: AXUIElement, hideDetails: Set<String>) -> Bool {
        var ref: CFArray?
        guard AXUIElementCopyActionNames(el, &ref) == .success, let actions = ref as? [String] else { return false }
        return actions.contains { hideDetails.contains(customActionName($0)) }
    }

    /// The reply field Notification Center shows in the notification, if one is open.
    nonisolated static func replyField(in el: AXUIElement, depth: Int = 0) -> AXUIElement? {
        guard depth < 6 else { return nil }
        if let role = el.stringAttribute(kAXRoleAttribute as String),
           role == (kAXTextAreaRole as String) || role == (kAXTextFieldRole as String) { return el }
        for child in el.children() {
            if let found = replyField(in: child, depth: depth + 1) { return found }
        }
        return nil
    }

    func toggleDetails(of el: AXUIElement) {
        let names = Self.isExpanded(el) ? NCActionNames.hideDetails : NCActionNames.showDetails
        el.performCustomAction(namedAnyOf: names)
    }

    /// Perform an app action, focus any reply field, and report whether it opened to `then`.
    func perform(_ name: String, id: String, on el: AXUIElement, then: @escaping (_ opensReply: Bool) -> Void) {
        offeredBefore[id] = Self.appActions(of: el)
        el.performCustomAction(namedAnyOf: [name])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard let field = Self.replyField(in: el) else { then(false); return }
            AXUIElementSetAttributeValue(field, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            then(true)
        }
    }

    /// Finds the new action offered after a reply opens; falls back to the last app action if
    /// unknown.
    func sendAction(id: String, on el: AXUIElement) -> String? {
        let now = Self.appActions(of: el)
        if let before = offeredBefore[id], let new = now.first(where: { !before.contains($0) }) { return new }
        return now.last
    }

    func send(id: String, on el: AXUIElement) {
        guard let name = sendAction(id: id, on: el) else { return }
        el.performCustomAction(namedAnyOf: [name])
        offeredBefore[id] = nil
    }

    func forget(_ id: String) { offeredBefore[id] = nil }
}
