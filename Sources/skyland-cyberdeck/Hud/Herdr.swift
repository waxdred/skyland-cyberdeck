import Foundation

// herdr agent monitor: `herdr pane list` (JSON) gives every pane with its agent and
// agent_status (working, idle, done, blocked). Sessions = panes running an agent.

struct HerdrAgent: Equatable {
    var agent: String
    var status: String
    var title: String
}

struct HerdrSummary: Equatable {
    var agents: [HerdrAgent]
    var total: Int { agents.count }
    var running: Int { agents.filter { $0.status == "working" }.count }
    var idle: Int { agents.filter { $0.status == "idle" }.count }
    var done: Int { agents.filter { $0.status == "done" }.count }
    /// waiting for you: a permission or a question
    var blocked: Int { agents.filter { $0.status == "blocked" || $0.status == "waiting" }.count }
}

enum HerdrState: Equatable {
    case connected(HerdrSummary, Date)
    case unavailable // herdr not installed or not running
    case error(String)
}

/// Panes running an agent, from the `herdr pane list` JSON; nil when it is not that JSON.
func parseHerdrPanes(_ data: Data) -> HerdrSummary? {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let result = root["result"] as? [String: Any], let panes = result["panes"] as? [[String: Any]] else { return nil }
    let agents = panes.compactMap { pane -> HerdrAgent? in
        guard let agent = pane["agent"] as? String, !agent.isEmpty else { return nil }
        let title = (pane["terminal_title_stripped"] as? String) ?? (pane["cwd"] as? String).map { ($0 as NSString).lastPathComponent } ?? ""
        return HerdrAgent(agent: agent, status: pane["agent_status"] as? String ?? "unknown", title: title)
    }
    return HerdrSummary(agents: agents)
}

enum HerdrReader {
    /// herdr from the PATH, plus the usual install places (apps get a short PATH).
    static let executable: String? = {
        let path = (ProcessInfo.processInfo.environment["PATH"] ?? "") + ":\(NSHomeDirectory())/.local/bin:/opt/homebrew/bin:/usr/local/bin"
        return path.split(separator: ":").map { "\($0)/herdr" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }()

    /// Runs off the main thread; at most 3 s.
    static func read(completion: @escaping (HerdrState) -> Void) {
        guard let executable else { return completion(.unavailable) }
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = ["pane", "list"]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { return completion(.error(error.localizedDescription)) }
            let timer = DispatchWorkItem { process.terminate() }
            DispatchQueue.global().asyncAfter(deadline: .now() + 3, execute: timer)
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            timer.cancel()
            if process.terminationStatus != 0 { return completion(.unavailable) } // no server running
            completion(parseHerdrPanes(data).map { .connected($0, Date()) } ?? .error("unexpected output"))
        }
    }
}
