import Foundation

/// One notification in the open Notification Center panel, read through Accessibility.
struct NCPanelRow: Equatable, Identifiable {
    /// Stable notification identifier across banners, panel rows, and panel reopenings on macOS 27.
    let id: String
    let appName: String
    let title: String
    let subtitle: String
    let body: String
    /// One row represents several notifications from an app; pressing it expands the stack.
    let isStack: Bool
    /// The notifying app's actions; see NotificationActions.
    var actions: [String] = []
    /// What is typed in its open reply field, nil while no reply is open.
    var reply: String? = nil
    var replyPlaceholder: String = ""
    /// Its details are shown in Notification Center: the app's buttons under the text.
    var expanded = false
    /// Match the native height, including expanded details and replies.
    var height: CGFloat = 58
    /// The native time is the row's unlabelled text; active alerts have none on macOS 27.
    var time: String? = nil
}

/// An item read from a native row or footer menu.
struct NCMenuItem: Equatable, Identifiable {
    enum Kind: Equatable { case action, header, separator }
    let kind: Kind
    let title: String
    /// Which of the menu's items with this title it is, to find it again.
    let occurrence: Int
    var checked = false
    var id: String { "\(kind)-\(title)-\(occurrence)" }

    /// Moves a checkmark within the chosen separator group; groups without a checkmark stay
    /// unchanged.
    static func choosing(_ chosen: NCMenuItem, in items: [NCMenuItem]) -> [NCMenuItem] {
        guard let at = items.firstIndex(where: { $0.id == chosen.id }) else { return items }
        var start = at, end = at
        while start > 0, items[start - 1].kind != .separator { start -= 1 }
        while end < items.count - 1, items[end + 1].kind != .separator { end += 1 }
        guard items[start...end].contains(where: \.checked) else { return items }
        var next = items
        for i in start...end { next[i].checked = i == at }
        return next
    }

    /// Builds menu items from AX children; short untitled items separate groups, titled nonactions
    /// are headings.
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

/// Flat list entries: section headings, group headers, and rows are siblings.
enum NCListEntry: Equatable {
    case heading(String)
    case button
    case row(NCPanelRow)
}

/// Native list order: active alerts, the Notification Center heading and Clear All, then history.
/// Expanded stacks have a header and rows; collapsed stacks have one row.
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

    /// A heading opens an expanded group when the next row belongs to an app with that name.
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

    /// Builds groups and sections from headings and following rows; header buttons have no separate
    /// layout.
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
