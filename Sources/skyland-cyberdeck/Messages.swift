import AppKit
import SQLite3

// Messages: the macOS Notification Center history (read only) merged with the
// messages scripts send through `skyland-cyberdeck notify`. Dismissing hides a
// message here only; the Notification Center keeps its own copy.

struct Message: Codable, Equatable {
    var id: String // "nc:<record id>" or "api:<uuid>"
    var app: String // bundle id, or a free name for api messages
    var title: String
    var subtitle: String = ""
    var body: String = ""
    var date: Date
    var source: String // "macos" | "api"

    /// App name for display: the app's own name when `app` is a bundle id.
    var appName: String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: app)
            .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? app
    }

    var appIcon: NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: app).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
}

private struct Store: Codable {
    var messages: [Message] = [] // api messages, newest last
    var dismissed: Set<String> = []
    var clearedBefore: Date = .distantPast // dismiss --all
}

enum Messages {
    static let maxApiMessages = 200
    private static let storeUrl: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "skyland-cyberdeck")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "messages.json")
    }()
    private static let notificationDb = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Group Containers/group.com.apple.usernoted/db2/db")

    private static func load() -> Store {
        (try? Data(contentsOf: storeUrl)).flatMap { try? decoder.decode(Store.self, from: $0) } ?? Store()
    }

    private static func save(_ store: Store) {
        if let data = try? encoder.encode(store) { try? data.write(to: storeUrl, options: .atomic) }
    }

    /// Visible messages (or all of them), newest first.
    static func list(includeDismissed: Bool = false, limit: Int = 100) -> [Message] {
        let store = load()
        let all = (store.messages + notificationCenter(limit: limit)).sorted { $0.date > $1.date }
        let shown = includeDismissed ? all : all.filter { !store.dismissed.contains($0.id) && $0.date > store.clearedBefore }
        return Array(shown.prefix(limit))
    }

    @discardableResult
    static func add(app: String, title: String, subtitle: String, body: String) -> Message {
        var store = load()
        let message = Message(id: "api:\(UUID().uuidString.lowercased())", app: app, title: title, subtitle: subtitle,
                              body: body, date: .now, source: "api")
        store.messages.append(message)
        store.messages = Array(store.messages.suffix(maxApiMessages))
        save(store)
        return message
    }

    static func dismiss(_ id: String) {
        var store = load()
        store.dismissed.insert(id)
        save(store)
    }

    static func dismissAll() {
        var store = load()
        store.clearedBefore = .now
        store.dismissed = store.dismissed.filter { id in store.messages.contains { $0.id == id } } // keep it small
        save(store)
    }

    /// Delivered notifications of the Notification Center database, newest first.
    private static func notificationCenter(limit: Int) -> [Message] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(notificationDb.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_close(db) }
        let sql = "SELECT r.rec_id, a.identifier, r.data, r.delivered_date FROM record r JOIN app a ON a.app_id = r.app_id ORDER BY r.delivered_date DESC LIMIT ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(limit))
        var result: [Message] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let recId = sqlite3_column_int64(statement, 0)
            let app = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            guard !app.hasPrefix("_system_center_"), let blob = sqlite3_column_blob(statement, 2) else { continue }
            let data = Data(bytes: blob, count: Int(sqlite3_column_bytes(statement, 2)))
            guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let request = plist["req"] as? [String: Any] else { continue }
            let date = Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 3))
            result.append(Message(id: "nc:\(recId)", app: app, title: request["titl"] as? String ?? "",
                                  subtitle: request["subt"] as? String ?? "", body: request["body"] as? String ?? "",
                                  date: date, source: "macos"))
        }
        return result
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
