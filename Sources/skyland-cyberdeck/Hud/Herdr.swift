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
    /// herdr's server socket: no `herdr` process is started (security tools such as
    /// XFENCE ask before every program run from ~/.local/bin).
    static let socketPath = ProcessInfo.processInfo.environment["HERDR_SOCKET_PATH"]
        ?? "\(NSHomeDirectory())/.config/herdr/herdr.sock"

    /// One `pane.list` request, off the main thread, at most 2 s.
    static func read(completion: @escaping (HerdrState) -> Void) {
        DispatchQueue.global(qos: .utility).async { completion(request()) }
    }

    private static func request() -> HerdrState {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return .error("socket") }
        defer { close(fd) }
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        guard socketPath.utf8.count < MemoryLayout.size(ofValue: address.sun_path) else { return .error("socket path too long") }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: socketPath.utf8)
            buffer[socketPath.utf8.count] = 0
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { return .unavailable } // no herdr server
        let line = #"{"id":"cyberdeck:hud","method":"pane.list","params":{}}"# + "\n"
        guard line.withCString({ write(fd, $0, strlen($0)) }) > 0 else { return .error("write") }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65536)
        while !data.contains(UInt8(ascii: "\n")) {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count <= 0 { break }
            data.append(contentsOf: buffer[0 ..< count])
        }
        return parseHerdrPanes(data).map { .connected($0, Date()) } ?? .error("unexpected reply")
    }
}
