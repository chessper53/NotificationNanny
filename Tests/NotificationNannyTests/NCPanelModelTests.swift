import Testing
@testable import NotificationNannyCore

/// The panel's list is flat; these are the shapes measured on 27.0 with
/// scripts/panel-lab (`run.sh list`).
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

    /// The section heading names no app, so it never opens a group, even when it is
    /// followed by a row.
    @Test func sectionHeading_followedByRow_isASection() {
        let snap = NCPanelSnapshot.build(from: [
            .heading("Notification Center"), .button, row("m", "Mail"),
        ])
        #expect(snap.sections.map(\.title) == ["Notification Center"])
        #expect(snap.sections[0].groups.map(\.expanded) == [false])
    }

    /// An expanded group ends where another app's row starts.
    @Test func expandedGroup_endsAtAnotherApp() {
        let snap = NCPanelSnapshot.build(from: [
            .heading("Mail"), .button, .button, row("m1", "Mail"), row("m2", "Mail"),
            row("x", "Messages"),
        ])
        #expect(snap.sections[0].groups.map(\.id) == ["group:0:Mail", "x"])
    }

    /// Caught mid-update: a header whose rows aren't in the tree yet is dropped,
    /// and a section left with nothing in it too.
    @Test func headerWithoutRows_isDropped() {
        let snap = NCPanelSnapshot.build(from: [.heading("Notification Center"), .button])
        #expect(snap.isEmpty)
        #expect(snap.sections.isEmpty)
    }

    @Test func emptyList_isEmpty() {
        #expect(NCPanelSnapshot.build(from: []) == .empty)
    }
}
