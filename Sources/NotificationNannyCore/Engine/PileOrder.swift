/// Leaving overlays keep their slots until their exit animations finish to avoid overlaps.
enum PileOrder {
    /// Order by first appearance; `ids` supplies native order to break ties.
    /// Temporary banners can appear below older Persistent banners in native order.
    static func arrange(_ ids: [String], firstSeen: [String: Double], newestAtBottom: Bool) -> [String] {
        let ranked = ids.enumerated().map { (index: $0.offset, id: $0.element, seen: firstSeen[$0.element] ?? 0) }
        let newestFirst = ranked.sorted { a, b in
            a.seen != b.seen ? a.seen > b.seen : a.index < b.index
        }.map(\.id)
        return newestAtBottom ? newestFirst.reversed() : newestFirst
    }

    /// Restore each leaving overlay after its previous neighbour, or at the top if no neighbour
    /// remains.
    static func merge(current: [String], previous: [String], leaving: Set<String>) -> [String] {
        var result = current
        for (index, id) in previous.enumerated() where leaving.contains(id) && !result.contains(id) {
            let above = previous[..<index].reversed().first { result.contains($0) }
            let at = above.flatMap { result.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
            result.insert(id, at: at)
        }
        return result
    }

    /// Merge within each anchor, preserving leaving slots. Order anchors by `current`, then
    /// `previous`.
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
