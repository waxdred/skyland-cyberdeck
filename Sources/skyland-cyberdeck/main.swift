import AppKit

// skyland-cyberdeck: cyberpunk HUD pieces for macOS (made for skyland, works alone).
let usage = """
    usage: skyland-cyberdeck <command>
      launcher                      toggle the apps launcher
      messages                      toggle the messages panel
      hud                           toggle the HUD: clock, calendar, system, herdr agents, audio
      notify -t TITLE [-b BODY] [-s SUBTITLE] [-a APP] [--seconds N] [--quiet]
                                    add a message (APP: bundle id or any name), show a popup
                                    unless --quiet; prints its id
      list [--json] [--limit N] [--all]
                                    messages, newest first (--all: dismissed ones too)
      dismiss <id> | --all          hide a message, or all of them
      theme [name] | theme list     colors: cyberpunk (default), skyland (the current skyland
                                    theme), a skyland theme name (43pr-dracula...) or a .css file;
                                    no name: print the current one
      config [init]                 print the config file path; init writes it with the defaults
                                    (fonts, sizes, titles, colors: ~/.config/skyland-cyberdeck)
    any command: --theme <name>     use that theme for this call only
    """

func fail(_ text: String) -> Never {
    FileHandle.standardError.write((text + "\n").data(using: .utf8)!)
    exit(2)
}

/// `--flag value` / `-f value` of the arguments after the command.
func option(_ names: String..., in args: [String]) -> String? {
    guard let index = args.firstIndex(where: names.contains), args.indices.contains(index + 1) else { return nil }
    return args[index + 1]
}

/// Toggle: a second call closes the open one.
func toggle(_ name: String) {
    let pidFile = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "skyland-cyberdeck-\(name).pid")
    if let old = (try? String(contentsOf: pidFile, encoding: .utf8)).flatMap({ pid_t($0) }), old != getpid(), kill(old, 0) == 0 {
        kill(old, SIGTERM)
        exit(0)
    }
    try? String(getpid()).write(to: pidFile, atomically: true, encoding: .utf8)
}

func run(_ delegate: NSApplicationDelegate) -> Never {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.delegate = delegate
    app.run()
    exit(0)
}

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
    case "launcher":
        toggle("launcher")
        run(LauncherApp())
    case "messages":
        toggle("messages")
        run(MessagesApp())
    case "hud":
        toggle("hud")
        run(HudApp())
    case "notify":
        guard let title = option("-t", "--title", in: args) else { fail(usage) }
        let message = Messages.add(app: option("-a", "--app", in: args) ?? "skyland", title: title,
                                   subtitle: option("-s", "--subtitle", in: args) ?? "", body: option("-b", "--body", in: args) ?? "")
        print(message.id)
        if args.contains("--quiet") { exit(0) }
        run(ToastApp(message, seconds: option("--seconds", in: args).flatMap(Double.init) ?? Double(Config.number("toast.seconds", 4.5))))
    case "list":
        let messages = Messages.list(includeDismissed: args.contains("--all"), limit: option("--limit", in: args).flatMap(Int.init) ?? 50)
        if args.contains("--json") {
            print(String(data: try! Messages.encoder.encode(messages), encoding: .utf8)!)
        } else {
            let time = DateFormatter()
            time.dateFormat = "yyyy-MM-dd HH:mm"
            for message in messages {
                print("\(time.string(from: message.date))  \(message.appName)  \(message.title)\(message.body.isEmpty ? "" : " — \(message.body)")  [\(message.id)]")
            }
        }
    case "dismiss":
        if args.contains("--all") { Messages.dismissAll() } else if args.count > 1 { Messages.dismiss(args[1]) } else { fail(usage) }
    case "theme":
        if args.count < 2 {
            print(Theme.name)
        } else if args[1] == "list" {
            Theme.available().forEach { print($0) }
        } else if Theme.builtIn[args[1]] != nil || Theme.file(args[1]) != nil {
            Theme.save(args[1])
        } else {
            fail("skyland-cyberdeck: unknown theme '\(args[1])' (skyland-cyberdeck theme list)")
        }
    case "config":
        if args.count > 1 && args[1] == "init" { Config.initFile() } else { print(Config.file.path) }
    case "-h", "--help", "help":
        print(usage)
    default:
        fail(usage)
}
