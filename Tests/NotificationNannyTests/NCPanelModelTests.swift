import Testing
@testable import NotificationNannyCore

/// Fixtures match the flat AX list observed on macOS 27.
@Suite("Notification Center panel model")
struct NCPanelModelTests {

    private func row(_ id: String, _ app: String, stack: Bool = false) -> NCListEntry {
        .row(NCPanelRow(id: id, appName: app, title: "t\(id)", subtitle: "", body: "", isStack: stack))
    }

    @Test func alertsThenHistory_makeTwoSections() {
        let snap = NCPanelSnapshot.build(from: [
            row("a1", "Lab Charlie", stack: true),
            row("a2", "Lab Bravo", stack: true),
            .heading("Notification Center"), .button,
            row("h1", "Mail", stack: true),
            row("h2", "Messages"),
        ])
        #expect(snap.sections.map(\.title) == [nil, "Notification Center"])
        #expect(snap.sections[0].groups.map(\.id) == ["a1", "a2"])
        #expect(snap.sections[1].groups.map(\.appName) == ["Mail", "Messages"])
        #expect(snap.rowCount == 4)
    }

    @Test func expandedStack_isOneGroupWithItsRows() {
        let snap = NCPanelSnapshot.build(from: [
            .heading("Lab Charlie"), .button, .button,
            row("c3", "Lab Charlie"), row("c2", "Lab Charlie"), row("c1", "Lab Charlie"),
            row("b", "Lab Bravo", stack: true),
        ])
        #expect(snap.sections.count == 1)
        let groups = snap.sections[0].groups
        #expect(groups.count == 2)
        #expect(groups[0].expanded)
        #expect(groups[0].rows.map(\.id) == ["c3", "c2", "c1"])
        #expect(!groups[1].expanded)
        #expect(groups[1].rows.first?.isStack == true)
    }

    @Test func sectionHeading_followedByRow_isASection() {
        let snap = NCPanelSnapshot.build(from: [
            .heading("Notification Center"), .button, row("m", "Mail"),
        ])
        #expect(snap.sections.map(\.title) == ["Notification Center"])
        #expect(snap.sections[0].groups.map(\.expanded) == [false])
    }

    @Test func expandedGroup_endsAtAnotherApp() {
        let snap = NCPanelSnapshot.build(from: [
            .heading("Mail"), .button, .button, row("m1", "Mail"), row("m2", "Mail"),
            row("x", "Messages"),
        ])
        #expect(snap.sections[0].groups.map(\.id) == ["group:0:Mail", "x"])
    }

    /// AX can report a header before its rows arrive.
    @Test func headerWithoutRows_isDropped() {
        let snap = NCPanelSnapshot.build(from: [.heading("Notification Center"), .button])
        #expect(snap.isEmpty)
        #expect(snap.sections.isEmpty)
    }

    @Test func emptyList_isEmpty() {
        #expect(NCPanelSnapshot.build(from: []) == .empty)
    }

    /// Native AX menu fixture: containers, 11 point separators, and a heading.
    @Test func rowMenu_keepsItemsSeparatorsAndHeading() {
        let items = NCMenuItem.build(from: [
            ("", 24, false), ("Reply", 24, true), ("Archive", 24, true), ("Snooze", 24, true),
            ("", 11, false), ("", 24, false), ("Lab Bravo Notifications", 24, false),
            ("Mute for 1 Hour", 24, true), ("Mute for Today", 24, true), ("Turn Off", 24, true),
            ("", 11, false), ("", 24, false), ("Dismiss", 24, true),
            ("", 11, false), ("Notification Settings…", 24, true), ("", 0, false),
        ])
        #expect(items.map(\.kind) == [.action, .action, .action, .separator, .header, .action, .action, .action,
                                      .separator, .action, .separator, .action])
        #expect(items[4].title == "Lab Bravo Notifications")
        #expect(items.last?.title == "Notification Settings…")
    }

    @Test func menu_sameTitleTwice_isToldApart() {
        let items = NCMenuItem.build(from: [("Clear", 24, true), ("", 11, false), ("Clear", 24, true)])
        #expect(items.filter { $0.kind == .action }.map(\.occurrence) == [0, 1])
        #expect(Set(items.map(\.id)).count == items.count)
    }

    @Test func menu_noLeadingOrDoubledSeparators() {
        let items = NCMenuItem.build(from: [("", 11, false), ("A", 24, true), ("", 11, false), ("", 11, false),
                                            ("B", 24, true), ("", 11, false)])
        #expect(items.map(\.kind) == [.action, .separator, .action])
    }
}

@Suite("Menu ticks")
struct NCMenuTickTests {
    private func menu(ticked: String) -> [NCMenuItem] {
        var items = NCMenuItem.build(from: [
            ("Edit “Featured”…", 24, true), ("", 11, false), ("Size", 24, false),
            ("Small", 24, true), ("Medium", 24, true), ("Large", 24, true), ("", 11, false),
            ("Remove Widget", 24, true),
        ])
        for i in items.indices where items[i].title == ticked { items[i].checked = true }
        return items
    }

    @Test func tickMovesWithinItsGroup() {
        let items = menu(ticked: "Medium")
        let large = items.first { $0.title == "Large" }!
        let next = NCMenuItem.choosing(large, in: items)
        #expect(next.filter(\.checked).map(\.title) == ["Large"])
    }

    @Test func itemOutsideATickedGroup_changesNothing() {
        let items = menu(ticked: "Medium")
        let edit = items.first { $0.title == "Edit “Featured”…" }!
        #expect(NCMenuItem.choosing(edit, in: items) == items)
    }
}
