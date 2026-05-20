import Foundation
import Testing
@testable import NotificationNannyCore

@Suite("NotificationPosition")
struct NotificationPositionTests {

    @Test func stacksUpward_onlyBottomRow() {
        let shouldStack: Set<NotificationPosition> = [.bottomLeft, .bottomCenter, .bottomRight]
        for position in NotificationPosition.allCases {
            #expect(position.stacksUpward == shouldStack.contains(position),
                    "\(position).stacksUpward is wrong")
        }
    }

    @Test func allCases_count() {
        #expect(NotificationPosition.allCases.count == 9)
    }

    @Test func labels_nonEmpty() {
        for position in NotificationPosition.allCases {
            #expect(!position.label.isEmpty, "\(position) has an empty label")
        }
    }

    @Test func rawValues_matchCaseNames() {
        #expect(NotificationPosition.topLeft.rawValue == "topLeft")
        #expect(NotificationPosition.bottomRight.rawValue == "bottomRight")
        #expect(NotificationPosition.middleCenter.rawValue == "middleCenter")
    }

    @Test func codable_roundTrip() throws {
        for position in NotificationPosition.allCases {
            let data = try JSONEncoder().encode(position)
            let decoded = try JSONDecoder().decode(NotificationPosition.self, from: data)
            #expect(decoded == position)
        }
    }
}
