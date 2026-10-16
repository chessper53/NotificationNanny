/// Order of a custom pile while overlays leave it.
///
/// An overlay whose banner has gone plays its exit animation where it stands.
/// If the pile closed the gap at once, the overlay below would move into that
/// slot and the two would overlap until the animation ends. So a leaving
/// overlay keeps its slot until then, between the same neighbours it had.
enum PileOrder {
    /// Live banners in pile order by when each first appeared: newest first, or
    /// with `newestAtBottom` oldest first. macOS's own order breaks ties (several
    /// first seen in one sweep, e.g. a pile that was already up) and is otherwise
    /// not used: it puts a Temporary banner below Persistent ones even when it
    /// is newer.
    ///
    /// - Parameter ids: banners in macOS's order, newest first.
    static func arrange(_ ids: [String], firstSeen: [String: Double], newestAtBottom: Bool) -> [String] {
        let ranked = ids.enumerated().map { (index: $0.offset, id: $0.element, seen: firstSeen[$0.element] ?? 0) }
        let newestFirst = ranked.sorted { a, b in
            a.seen != b.seen ? a.seen > b.seen : a.index < b.index
        }.map(\.id)
        return newestAtBottom ? newestFirst.reversed() : newestFirst
    }

    /// `current` in the order macOS gives now, with each id of `leaving` put
    /// back right after the overlay that was above it in `previous`, or at the
    /// top when nothing above it is still there.
    static func merge(current: [String], previous: [String], leaving: Set<String>) -> [String] {
        var result = current
        for (index, id) in previous.enumerated() where leaving.contains(id) && !result.contains(id) {
            let above = previous[..<index].reversed().first { result.contains($0) }
            let at = above.flatMap { result.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
            result.insert(id, at: at)
        }
        return result
    }

    /// One pile per anchor, each ordered as `merge` orders a whole pile. Banners
    /// from apps placed in different spots then each pile up where their app
    /// goes, and a leaving overlay holds its slot in its own pile. Piles come in
    /// the order their anchors first appear in `current`, then in `previous`.
    static func split<Anchor: Equatable>(current: [String], previous: [String], leaving: Set<String>,
                                         anchor: (String) -> Anchor) -> [(anchor: Anchor, ids: [String])] {
        var anchors: [Anchor] = []
        for id in current + previous.filter(leaving.contains) {
            let a = anchor(id)
            if !anchors.contains(a) { anchors.append(a) }
        }
        return anchors.map { a in
            (a, merge(current: current.filter { anchor($0) == a },
                      previous: previous.filter { anchor($0) == a }, leaving: leaving))
        }
    }
}
