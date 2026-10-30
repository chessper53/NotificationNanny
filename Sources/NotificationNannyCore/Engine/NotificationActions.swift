@preconcurrency import ApplicationServices
import Foundation

/// An app's own buttons on a notification, such as Reply, Archive or Snooze, used from
/// the custom banner and the custom Notification Center.
///
/// Notification Center lists them as custom actions of the notification's element,
/// next to its own (Close, Show Details…), and performing one reaches the app exactly as
/// a click on the button does. A reply is Notification Center's own text field: the
/// app's reply action shows it, together with a send action that replaces the reply
/// one, and real keystrokes land in it once it has the focus, even with the real banner
/// or panel off screen. All measured on 27.0 with scripts/panel-lab (`act`, `type`,
/// `panel-reply`) against a Lab app that logs what reaches it.
@MainActor
final class NotificationActions {
    /// The app's actions a notification offered before one of them was used, by
    /// notification ID; the send action of a reply is the one that is new after.
    private var offeredBefore: [String: [String]] = [:]

    /// The app's own actions on the notification, in Notification Center's order.
    static func appActions(of el: AXUIElement) -> [String] {
        var ref: CFArray?
        guard AXUIElementCopyActionNames(el, &ref) == .success, let actions = ref as? [String] else { return [] }
        return actions.filter { $0.hasPrefix("Name:") }.map(customActionName)
            .filter { !NCActionNames.builtIn.contains($0) }
    }

    /// Expanded to show its buttons ("Show Details" was used): it now offers Hide Details.
    static func isExpanded(_ el: AXUIElement) -> Bool {
        var ref: CFArray?
        guard AXUIElementCopyActionNames(el, &ref) == .success, let actions = ref as? [String] else { return false }
        return actions.contains { NCActionNames.hideDetails.contains(customActionName($0)) }
    }

    /// The reply field Notification Center shows in the notification, if one is open.
    static func replyField(in el: AXUIElement, depth: Int = 0) -> AXUIElement? {
        guard depth < 6 else { return nil }
        if let role = el.stringAttribute(kAXRoleAttribute as String),
           role == (kAXTextAreaRole as String) || role == (kAXTextFieldRole as String) { return el }
        for child in el.children() {
            if let found = replyField(in: child, depth: depth + 1) { return found }
        }
        return nil
    }

    /// Shows or hides the notification's buttons, as its chevron does.
    func toggleDetails(of el: AXUIElement) {
        let names = Self.isExpanded(el) ? NCActionNames.hideDetails : NCActionNames.showDetails
        el.performCustomAction(namedAnyOf: names)
    }

    /// Uses one of the app's actions. If it opens a reply field, the field gets the focus,
    /// so typing goes there; `then` runs once that is known.
    func perform(_ name: String, id: String, on el: AXUIElement, then: @escaping (_ opensReply: Bool) -> Void) {
        offeredBefore[id] = Self.appActions(of: el)
        el.performCustomAction(namedAnyOf: [name])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard let field = Self.replyField(in: el) else { then(false); return }
            AXUIElementSetAttributeValue(field, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            then(true)
        }
    }

    /// The action that sends the reply: the one offered now that wasn't before the reply
    /// opened. Unknown, for a reply opened before this ran, it is the last of the app's.
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
