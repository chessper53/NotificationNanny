/// Keep clock presses in order even if a tap transition loses a mouse release. A subsequent
/// press proves the previous physical click ended; finish that pair rather than blocking input.
struct ClockClickQueue<Event, Destination> {
    struct Click {
        var down: Event
        var up: Event?
        var destination: Destination
    }

    private(set) var pending: [Click] = []
    var first: Click? { pending.first }
    var count: Int { pending.count }

    mutating func press(_ event: Event, on destination: Destination, missingRelease: (Event) -> Event) {
        if let index = pending.lastIndex(where: { $0.up == nil }) {
            pending[index].up = missingRelease(pending[index].down)
        }
        pending.append(Click(down: event, destination: destination))
    }

    @discardableResult
    mutating func release(_ event: Event) -> Bool {
        guard let index = pending.lastIndex(where: { $0.up == nil }) else { return false }
        pending[index].up = event
        return true
    }

    mutating func removeFirst() { pending.removeFirst() }
    mutating func removeAll() { pending.removeAll() }

    /// Two complete toggles on the same clock leave the desired state unchanged. Use only
    /// while waiting for a native transition, before either click has been forwarded.
    @discardableResult
    mutating func cancelPairedToggles(sameDestination: (Destination, Destination) -> Bool) -> Int {
        var removed = 0
        while pending.count >= 2, pending[0].up != nil, pending[1].up != nil,
              sameDestination(pending[0].destination, pending[1].destination) {
            pending.removeFirst(2)
            removed += 2
        }
        return removed
    }
}
