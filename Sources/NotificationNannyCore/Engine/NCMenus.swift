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
        let started = ProcessInfo.processInfo.systemUptime
        let timing = ProcessInfo.processInfo.environment["NN_TIMING"] == "1"
        func trace(_ what: String) { // DEBUG-CLICK
            guard timing else { return }
            let ms = Int((ProcessInfo.processInfo.systemUptime - started) * 1000)
            FileHandle.standardError.write(Data("[menu] \(ms) ms \(what), window at \(window.point().map { "(\(Int($0.x)),\(Int($0.y)))" } ?? "?")\n".utf8))
        }
        trace("asked")
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
            trace("menu up at \(menu.point().map { "(\(Int($0.x)),\(Int($0.y)))" } ?? "?")")
            let children = menu.children()
            let read = children.map { child in
                (title: cleanAXString(child.stringAttribute(kAXTitleAttribute as String) ?? ""),
                 height: child.size()?.height ?? 0,
                 isAction: child.identifier?.hasPrefix("menuAction") == true)
            }
            // A ticked item has a mark: a widget's current size.
            let ticked = Set(children.enumerated().compactMap { i, child in
                (child.stringAttribute("AXMenuItemMarkChar") ?? "").isEmpty ? nil : read[i].title
            })
            let items = NCMenuItem.build(from: read).map { item in
                var item = item
                item.checked = item.kind == .action && ticked.contains(item.title)
                return item
            }
            if let press, let hit = Self.item(press, in: children, read: read) {
                AXUIElementPerformAction(hit, kAXPressAction as CFString)
            } else {
                // AXCancel says it worked and leaves the menu open; Escape closes it. Sent
                // to Notification Center itself: posted to the session it went to the app
                // with the keyboard, and a widget's menu, which doesn't take it, stayed up
                // until the panel moved, a third of a second on screen.
                var pid: pid_t = 0
                AXUIElementGetPid(el, &pid)
                for down in [true, false] {
                    guard let key = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: down) else { continue }
                    if pid > 0 { key.postToPid(pid) } else { key.post(tap: .cghidEventTap) }
                }
            }
            done(items)
            for delay in [0.02, 0.06, 0.12, 0.25, 0.5] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { trace("after +\(Int(delay * 1000)) ms, menu \(Self.openMenu(of: el, in: window) == nil ? "gone" : "still up")") }
            }
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
