import Foundation

/// One notification in the open Notification Center panel, read through Accessibility.
struct NCPanelRow: Equatable, Identifiable {
    /// The row's `AXIdentifier`. It stays the same while the notification exists, from
    /// banner to panel row and across the panel closing and opening again (measured on
    /// 27.0 with scripts/panel-lab).
    let id: String
    let appName: String
    let title: String
    let subtitle: String
    let body: String
    /// A collapsed stack: one row standing for several notifications from one app,
    /// showing the newest. Pressing it expands the stack in place.
    let isStack: Bool
    /// The app's own buttons (Reply, Archive…); see NotificationActions.
    var actions: [String] = []
    /// What is typed in its open reply field, nil while no reply is open.
    var reply: String? = nil
    /// The reply field's placeholder, as the app set it.
    var replyPlaceholder: String = ""
    /// Its details are shown in Notification Center: the app's buttons under the text.
    var expanded = false
    /// Its height in Notification Center, which grows with details and a reply: ours is
    /// drawn the same.
    var height: CGFloat = 58
    /// The time Notification Center draws on it ("17:46", "2 days ago"): the row's one
    /// text without an identifier. Alerts still up have none (measured on 27.0,
    /// scripts/panel-lab `real-times`).
    var time: String? = nil
}

/// One item of a menu Notification Center shows, read from it: a row's (⋯, right click)
/// or the footer's Clear Notifications.
struct NCMenuItem: Equatable, Identifiable {
    enum Kind: Equatable { case action, header, separator }
    let kind: Kind
    let title: String
    /// Which of the menu's items with this title it is, to find it again.
    let occurrence: Int
    var id: String { "\(kind)-\(title)-\(occurrence)" }

    /// The menu's items from its AX children, as (title, height) in order. Separators are
    /// short untitled items; untitled full height items are containers and are left out;
    /// a titled item that isn't a `menuAction:` is a section heading (measured on 27.0:
    /// "Lab Bravo Notifications" over Mute for 1 Hour…).
    static func build(from children: [(title: String, height: CGFloat, isAction: Bool)]) -> [NCMenuItem] {
        var items: [NCMenuItem] = []
        var seen: [String: Int] = [:]
        for child in children {
            if child.title.isEmpty {
                guard child.height > 0, child.height < 16, !items.isEmpty, items.last?.kind != .separator else { continue }
                items.append(NCMenuItem(kind: .separator, title: "", occurrence: 0))
                continue
            }
            let n = seen[child.title, default: 0]
            seen[child.title] = n + 1
            items.append(NCMenuItem(kind: child.isAction ? .action : .header, title: child.title, occurrence: n))
        }
        while items.last?.kind == .separator { items.removeLast() }
        return items
    }
}

/// A child of the panel's `AXNotificationListItems` list, reduced to what decides the
/// layout. The list is flat: section headings, group headers and rows are siblings.
enum NCListEntry: Equatable {
    case heading(String)
    case button
    case row(NCPanelRow)
}

/// The panel's notifications in Notification Center's own order and grouping.
///
/// Measured on 27.0, the list reads, top to bottom:
///
///     alerts still up            rows, no heading
///     "Notification Center"      a heading, then its Clear All button
///     history                    rows
///
/// An expanded stack is a heading with the app's name, its Show Less and Clear
/// buttons, then one row per notification. A collapsed stack is a single row.
struct NCPanelSnapshot: Equatable {
    struct Group: Equatable, Identifiable {
        let id: String
        let appName: String
        /// Expanded in Notification Center, so it has a header with Show Less and Clear.
        let expanded: Bool
        var rows: [NCPanelRow]
    }

    struct Section: Equatable, Identifiable {
        let id: Int
        /// Nil for the alerts at the top of the list, which have no heading.
        let title: String?
        var groups: [Group]
    }

    var sections: [Section]

    static let empty = NCPanelSnapshot(sections: [])

    var rowCount: Int { sections.reduce(0) { $0 + $1.groups.reduce(0) { $0 + $1.rows.count } } }
    var isEmpty: Bool { rowCount == 0 }

    /// Whether the heading at `i` heads an expanded stack rather than a section: the row
    /// after it, before any other heading, belongs to an app of that name.
    static func headingOpensGroup(at i: Int, in entries: [NCListEntry]) -> Bool {
        guard case .heading(let text) = entries[i] else { return false }
        for entry in entries[(i + 1)...] {
            switch entry {
            case .button: continue
            case .row(let row): return row.appName == text && !row.isStack
            case .heading: return false
            }
        }
        return false
    }

    /// Builds the layout from the list's children in order. A heading starts an expanded
    /// group when the row after it belongs to an app of that name, and a new section
    /// otherwise; buttons only ever follow headings and carry no layout of their own.
    static func build(from entries: [NCListEntry]) -> NCPanelSnapshot {
        var sections: [Section] = [Section(id: 0, title: nil, groups: [])]
        var openGroup: (appName: String, index: Int)?

        for (i, entry) in entries.enumerated() {
            switch entry {
            case .button:
                continue
            case .heading(let text):
                let s = sections.count - 1
                if headingOpensGroup(at: i, in: entries) {
                    sections[s].groups.append(Group(id: "group:\(s):\(text)", appName: text, expanded: true, rows: []))
                    openGroup = (text, sections[s].groups.count - 1)
                } else {
                    sections.append(Section(id: sections.count, title: text, groups: []))
                    openGroup = nil
                }
            case .row(let row):
                let s = sections.count - 1
                if let open = openGroup, open.appName == row.appName, !row.isStack {
                    sections[s].groups[open.index].rows.append(row)
                } else {
                    openGroup = nil
                    sections[s].groups.append(Group(id: row.id, appName: row.appName, expanded: false, rows: [row]))
                }
            }
        }
        // An expanded group can be caught with its rows not in the tree yet.
        for s in sections.indices { sections[s].groups.removeAll { $0.rows.isEmpty } }
        return NCPanelSnapshot(sections: sections.filter { !$0.groups.isEmpty })
    }
}
