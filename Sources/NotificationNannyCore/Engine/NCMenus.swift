import AppKit
@preconcurrency import ApplicationServices

/// Notification Center's own menu of a notification (its ⋯, a right click) or of the
/// panel's Clear Notifications ✕, used from the custom Notification Center and from
/// custom banners.
///
/// Notification Center builds the menu, so it is asked for it: the real one is opened on
/// the parked notification, read, and closed again at once, and an item chosen in ours is
/// pressed in it, opened again. It opens at the parked notification's place pulled onto
/// the screen, never where it was asked for, which is why ours is drawn instead; used at
/// once, no frame of it was filmed (measured on 27.0, scripts/panel-lab `parked-menu`).
@MainActor
enum NCMenus {
    /// The row's menu answers on its texts, not on the row (measured on 27.0).
    static func target(of row: AXUIElement) -> AXUIElement {
        row.children().first { $0.identifier == "title" }
            ?? row.children().first { $0.stringAttribute(kAXRoleAttribute as String) == (kAXStaticTextRole as String) }
            ?? row
    }

    /// Opens Notification Center's menu on `el`, in `window`, reads it, and closes it:
    /// with Escape, or by pressing `press` in it. Nil if no menu came.
    static func read(of el: AXUIElement, in window: AXUIElement, press: NCMenuItem? = nil, logger: NannyLogger,
                     _ done: @escaping ([NCMenuItem]?) -> Void) {
        // Only a menu that wasn't there before is the one asked for: Escape goes to
        // whatever has the keyboard, and without the menu up that is the user's app.
        let before = Self.openMenu(of: el, in: window)
        // The call waits for the menu to close again; with a short timeout it returns while
        // the menu is up.
        AXUIElementSetMessagingTimeout(el, 0.05)
        AXUIElementPerformAction(el, kAXShowMenuAction as CFString)
        AXUIElementSetMessagingTimeout(el, 0)
        let deadline = ProcessInfo.processInfo.systemUptime + 0.6
        func poll() {
            guard let menu = Self.openMenu(of: el, in: window), before.map({ !CFEqual($0, menu) }) ?? true else {
                if ProcessInfo.processInfo.systemUptime < deadline {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.004) { poll() }
                } else {
                    logger.log("Notification Center showed no menu", level: .warn, tag: "Menu")
                    done(nil)
                }
                return
            }
            let children = menu.children()
            let read = children.map { child in
                (title: cleanAXString(child.stringAttribute(kAXTitleAttribute as String) ?? ""),
                 height: child.size()?.height ?? 0,
                 isAction: child.identifier?.hasPrefix("menuAction") == true)
            }
            let items = NCMenuItem.build(from: read)
            if let press, let hit = Self.item(press, in: children, read: read) {
                AXUIElementPerformAction(hit, kAXPressAction as CFString)
            } else {
                // AXCancel says it worked and leaves the menu open; Escape closes it. Only
                // sent with the menu up, which has the keyboard then.
                for down in [true, false] {
                    CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: down)?.post(tap: .cghidEventTap)
                }
            }
            done(items)
        }
        poll()
    }

    static func item(_ wanted: NCMenuItem, in children: [AXUIElement],
                             read: [(title: String, height: CGFloat, isAction: Bool)]) -> AXUIElement? {
        var seen = 0
        for (i, r) in read.enumerated() where r.isAction && r.title == wanted.title {
            if seen == wanted.occurrence { return children[i] }
            seen += 1
        }
        return nil
    }

    /// A menu Notification Center has open for `el`: a row's sits in the panel's window,
    /// beside the panel; a menu button's under the button (measured on 27.0).
    static func openMenu(of el: AXUIElement, in window: AXUIElement) -> AXUIElement? {
        if let own = el.children().first(where: { $0.stringAttribute(kAXRoleAttribute as String) == (kAXMenuRole as String) }) {
            return own
        }
        for child in window.children() {
            if child.stringAttribute(kAXRoleAttribute as String) == (kAXMenuRole as String) { return child }
            for grandchild in child.children()
            where grandchild.stringAttribute(kAXRoleAttribute as String) == (kAXMenuRole as String) {
                return grandchild
            }
        }
        return nil
    }
}
