import AppKit

struct AppEntry {
    let name: String
    let url: URL
    var id: String { url.path }
}

/// Installed apps, ranked by how often they were launched from the deck.
enum Apps {
    private static let defaults = UserDefaults(suiteName: "com.waxdred.skyland-cyberdeck")!

    static func all() -> [AppEntry] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let roots = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
                     "/System/Library/CoreServices/Applications", "\(home)/Applications"]
        var seen = Set<String>()
        var result: [AppEntry] = []
        func add(_ url: URL) {
            let name = url.deletingPathExtension().lastPathComponent
            guard seen.insert(name.lowercased()).inserted else { return }
            result.append(AppEntry(name: name, url: url))
        }
        for root in roots {
            let rootUrl = URL(fileURLWithPath: root)
            for item in (try? FileManager.default.contentsOfDirectory(at: rootUrl, includingPropertiesForKeys: nil)) ?? [] {
                if item.pathExtension == "app" {
                    add(item)
                } else if (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true, root != "/Applications/Utilities" {
                    // one level down: "/Applications/Adobe X/Foo.app", "/Applications/HP/..."
                    for sub in (try? FileManager.default.contentsOfDirectory(at: item, includingPropertiesForKeys: nil)) ?? []
                        where sub.pathExtension == "app" { add(sub) }
                }
            }
        }
        return result
    }

    static func launches(_ app: AppEntry) -> Int { (defaults.dictionary(forKey: "launches") as? [String: Int])?[app.id] ?? 0 }

    static func launch(_ app: AppEntry) {
        var counts = (defaults.dictionary(forKey: "launches") as? [String: Int]) ?? [:]
        counts[app.id, default: 0] += 1
        defaults.set(counts, forKey: "launches")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: app.url, configuration: configuration) { _, _ in exit(0) }
    }

    /// Apps matching `query` (fuzzy), best first; all apps by launches when empty.
    static func search(_ apps: [AppEntry], _ query: String) -> [AppEntry] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        if q.isEmpty {
            return apps.sorted { (launches($0), $1.name.lowercased()) > (launches($1), $0.name.lowercased()) }
        }
        return apps.compactMap { app -> (AppEntry, Int)? in score(app.name.lowercased(), q).map { (app, $0 * 100 + min(99, launches(app))) } }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.name < $1.0.name }
            .map(\.0)
    }

    /// prefix > word start > substring > subsequence; nil when it does not match.
    static func score(_ name: String, _ query: String) -> Int? {
        if name.hasPrefix(query) { return 4 }
        if name.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "." }).contains(where: { $0.hasPrefix(query) }) { return 3 }
        if name.contains(query) { return 2 }
        var rest = Substring(name)
        for char in query {
            guard let index = rest.firstIndex(of: char) else { return nil }
            rest = rest[rest.index(after: index)...]
        }
        return 1
    }
}
