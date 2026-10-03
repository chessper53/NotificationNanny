/// Order of a custom pile while overlays leave it.
///
/// An overlay whose banner has gone plays its exit animation where it stands.
/// If the pile closed the gap at once, the overlay below would move into that
/// slot and the two would overlap until the animation ends. So a leaving
/// overlay keeps its slot until then, between the same neighbours it had.
enum PileOrder {
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
}
