import AppKit

// skyland-cyberdeck: cyberpunk HUD pieces for macOS (made for skyland, works alone).
//   skyland-cyberdeck launcher   toggle the apps launcher
let usage = "usage: skyland-cyberdeck launcher"

guard let command = CommandLine.arguments.dropFirst().first, ["launcher"].contains(command) else {
    FileHandle.standardError.write((usage + "\n").data(using: .utf8)!)
    exit(2)
}

// Toggle: a second call closes the open one
let pidFile = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "skyland-cyberdeck-\(command).pid")
if let old = (try? String(contentsOf: pidFile, encoding: .utf8)).flatMap({ pid_t($0) }), old != getpid(), kill(old, 0) == 0 {
    kill(old, SIGTERM)
    exit(0)
}
try? String(getpid()).write(to: pidFile, atomically: true, encoding: .utf8)

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = LauncherApp()
app.delegate = delegate
app.run()
