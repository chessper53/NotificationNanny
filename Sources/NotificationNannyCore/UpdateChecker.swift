import Foundation

enum UpdateChecker {
    private struct Release: Decodable {
        let tagName: String
        enum CodingKeys: String, CodingKey { case tagName = "tag_name" }
    }

    /// Returns the latest version string if it is newer than the running app, otherwise nil.
    static func fetchNewerVersion() async -> String? {
        guard let url = URL(string: "https://api.github.com/repos/chessper53/NotificationNanny/releases/latest"),
              let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        else { return nil }
        do {
            var req = URLRequest(url: url)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, _) = try await URLSession.shared.data(for: req)
            let release = try JSONDecoder().decode(Release.self, from: data)
            let latest = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
            return isNewer(latest, than: current) ? latest : nil
        } catch {
            return nil
        }
    }

    private static func isNewer(_ latest: String, than current: String) -> Bool {
        let parse: (String) -> [Int] = { $0.split(separator: ".").compactMap { Int($0) } }
        let l = parse(latest), c = parse(current)
        for i in 0..<max(l.count, c.count) {
            let lv = i < l.count ? l[i] : 0
            let cv = i < c.count ? c[i] : 0
            if lv > cv { return true }
            if lv < cv { return false }
        }
        return false
    }
}
