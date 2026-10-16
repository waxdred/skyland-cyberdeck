import AppKit
import Combine
import CoreAudio

/// [hud] of config.toml.
struct HudSettings {
    var widgets: [String]
    var clock24h: Bool
    var clockSeconds: Bool
    var weekStart: Int // 1 = Sunday ... 7 = Saturday, 0 = the locale's
    var refreshMs: Int
    var opacity: Double // deck background around the cards
    var blur: Double    // strength of the blur behind the deck, 0 = none
    var cardOpacity: Double
    var cyberspace: Double // backdrop effect strength, 0 = off
    var scale: Double      // size of the whole deck
    var secondTimezone: TimeZone?
    var theme: String
    var apps: [String]

    static let allWidgets = ["clock", "calendar", "connections", "sound", "system", "herdr", "messages", "launch"]
    static let defaultApps = ["Finder", "Ghostty", "Terminal", "Visual Studio Code", "Firefox", "Safari", "Spotify", "Notes", "System Settings"]

    static func load() -> HudSettings {
        let widgets = parseWidgetList(Config.string("hud.widgets", allWidgets.joined(separator: ",")))
        return HudSettings(
            widgets: widgets.isEmpty ? allWidgets : widgets,
            clock24h: Config.bool("hud.clock-24h", true),
            clockSeconds: Config.bool("hud.clock-seconds", false),
            weekStart: min(7, max(0, Config.int("hud.week-start", 0))),
            refreshMs: min(10000, max(250, Config.int("hud.refresh-ms", 2000))),
            opacity: Double(min(1, max(0, Config.number("hud.opacity", 0.45)))),
            blur: Double(min(1, max(0, Config.number("hud.blur", 0.35)))),
            cardOpacity: Double(min(1, max(0, Config.number("hud.card-opacity", 0.72)))),
            cyberspace: Double(min(1, max(0, Config.number("hud.cyberspace", 0.6)))),
            scale: Double(min(2, max(0.5, Config.number("hud.scale", 1)))),
            secondTimezone: TimeZone(identifier: Config.string("hud.second-timezone", "")),
            // --theme of this call wins, then [hud] theme; netrunner is the HUD's own palette
            theme: CommandLine.arguments.contains("--theme") ? Theme.name : Config.string("hud.theme", "netrunner"),
            apps: Config.values["hud.apps"].map { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } } ?? defaultApps
        )
    }
}

/// "clock, system,  herdr" -> known widget names in that order, no duplicates.
func parseWidgetList(_ text: String) -> [String] {
    var seen = Set<String>()
    return text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        .filter { HudSettings.allWidgets.contains($0) && seen.insert($0).inserted }
}

/// The days of `month`'s grid, whole weeks starting on `firstWeekday` (1 = Sunday):
/// nil for the cells before the 1st and after the last day.
func monthGrid(_ month: Date, firstWeekday: Int, calendar base: Calendar = .current) -> [Date?] {
    var calendar = base
    calendar.firstWeekday = firstWeekday
    guard let interval = calendar.dateInterval(of: .month, for: month),
          let days = calendar.range(of: .day, in: .month, for: month) else { return [] }
    let lead = (calendar.component(.weekday, from: interval.start) - firstWeekday + 7) % 7
    var cells: [Date?] = Array(repeating: nil, count: lead)
    cells += days.map { calendar.date(byAdding: .day, value: $0 - 1, to: interval.start) }
    cells += Array(repeating: nil, count: (7 - cells.count % 7) % 7)
    return cells
}

/// Everything the HUD shows. Sampled only while the HUD is open (the process lives
/// as long as the panel), off the main thread for herdr.
final class HudModel: ObservableObject {
    let settings = HudSettings.load()
    var firstWeekday: Int { settings.weekStart == 0 ? Calendar.current.firstWeekday : settings.weekStart }

    @Published var monthOffset = 0
    /// bumped when the theme file changes: the deck redraws with the new palette
    @Published var themeVersion = 0
    private var themeDate: Date?
    /// set by the app: forget the dragged position, back on the right
    var resetPosition: () -> Void = {}

    @Published var cpu: Double?
    @Published var cpuHistory = History(capacity: 60)
    @Published var memory: (used: UInt64, total: UInt64)?
    @Published var download: Double?
    @Published var upload: Double?
    @Published var netHistory = History(capacity: 60)
    @Published var interface: String?
    @Published var storage: (available: Int64, total: Int64)?
    @Published var battery: SystemReaders.Battery?
    @Published var herdr: HerdrState?
    @Published var outputs: [AudioDevice] = []
    @Published var output: AudioObjectID?
    @Published var volume: Float?
    @Published var muted: Bool?
    @Published var brightness: Float?
    @Published var wifi: Tile?
    @Published var bluetooth: Tile?
    @Published var knownNetworks: [String] = []
    @Published var devices: [BluetoothDevice] = []
    @Published var busy: String? // network / device being joined
    @Published var airdrop: Tile?
    @Published var messages: [Message] = []
    /// quick launch: the configured apps that are installed
    lazy var launchApps: [AppEntry] = {
        let installed = Apps.all()
        return settings.apps.compactMap { name in
            installed.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
                // elsewhere (Finder in CoreServices...): ask LaunchServices by name
                ?? NSWorkspace.shared.fullPath(forApplication: name).map { AppEntry(name: name, url: URL(fileURLWithPath: $0)) }
        }
    }()

    private var ticks: CPUTicks?
    private var bytes: (received: UInt64, sent: UInt64, date: Date)?
    private var timer: Timer?
    private var ticksCount = 0

    func start() {
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: Double(settings.refreshMs) / 1000, repeats: true) { [weak self] _ in self?.sample() }
    }

    private func sample() {
        ticksCount += 1
        let seconds = Double(settings.refreshMs) / 1000
        if let now = SystemReaders.cpuTicks() {
            if let ticks, let usage = cpuUsage(from: ticks, to: now) { cpu = usage; cpuHistory.append(usage) }
            ticks = now
        }
        let memory = SystemReaders.memory()
        if memory?.used != self.memory?.used || memory?.total != self.memory?.total { self.memory = memory }
        if let now = SystemReaders.networkBytes() {
            let date = Date()
            if let bytes {
                let elapsed = date.timeIntervalSince(bytes.date)
                download = rate(from: bytes.received, to: now.received, seconds: elapsed)
                upload = rate(from: bytes.sent, to: now.sent, seconds: elapsed)
                netHistory.append((download ?? 0) + (upload ?? 0))
            }
            bytes = (now.received, now.sent, date)
        }
        // slower readers: every ~5 s (interface, battery, audio devices), ~30 s (disk), ~3 s (herdr)
        let every = { (period: Double) in self.ticksCount == 1 || self.ticksCount % max(1, Int(period / seconds)) == 0 }
        if every(5) {
            set(\.interface, SystemReaders.primaryInterface()); set(\.battery, SystemReaders.battery()); set(\.outputs, Audio.outputDevices())
            if settings.widgets.contains("connections") { readConnections() }
        }
        watchTheme()
        if every(30) { let storage = SystemReaders.storage(); if storage?.available != self.storage?.available { self.storage = storage } }
        if every(3) { set(\.messages, Messages.list(limit: 2)); set(\.brightness, Brightness.get()) }
        if every(3), settings.widgets.contains("herdr") {
            HerdrReader.read { state in
                DispatchQueue.main.async {
                    // a failed read less than 10 s after a good one keeps the good one
                    if case .connected = state {} else if case let .connected(_, date)? = self.herdr, Date().timeIntervalSince(date) < 10 { return }
                    self.herdr = state
                }
            }
        }
        readAudio()
    }

    /// The theme file (skyland's theme.css, a theme by name or path) changed since the
    /// last look: reload the palette. A file date per refresh, nothing more.
    private func watchTheme() {
        guard let file = Theme.file(settings.theme),
              let date = try? FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date else { return }
        if let themeDate, date != themeDate {
            Tok.reloadTheme()
            themeVersion += 1
        }
        themeDate = date
    }

    /// Assign only a new value: every assignment re-renders the deck.
    private func set<T: Equatable>(_ key: ReferenceWritableKeyPath<HudModel, T>, _ value: T) {
        if self[keyPath: key] != value { self[keyPath: key] = value }
    }

    func readAudio() {
        set(\.output, Audio.defaultOutput)
        set(\.volume, output.flatMap(Audio.volume))
        set(\.muted, output.flatMap(Audio.muted))
    }

    func setVolume(_ value: Float) {
        guard let output, Audio.setVolume(value, of: output) else { return }
        volume = Audio.volume(of: output) // what the device took
    }

    func toggleMute() {
        guard let output, let muted, Audio.setMuted(!muted, output) else { return }
        self.muted = Audio.muted(output)
    }

    func readConnections() {
        set(\.wifi, Connectivity.wifi())
        set(\.bluetooth, Connectivity.bluetooth())
        set(\.airdrop, Connectivity.airdrop())
    }

    func toggleWifi() {
        guard let wifi, wifi.state != .unavailable else { return }
        Connectivity.setWifi(wifi.state == .off)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.readConnections() } // what the system did
    }

    func loadKnownNetworks() {
        DispatchQueue.global(qos: .userInitiated).async {
            let networks = Connectivity.knownNetworks()
            DispatchQueue.main.async { self.knownNetworks = networks }
        }
    }

    func join(_ network: String) {
        busy = network
        DispatchQueue.global(qos: .userInitiated).async {
            _ = Connectivity.join(network)
            DispatchQueue.main.async { self.busy = nil; self.readConnections() } // the tile shows what happened
        }
    }

    func loadDevices() { devices = Connectivity.pairedDevices() }

    func toggle(_ device: BluetoothDevice) {
        busy = device.id
        DispatchQueue.global(qos: .userInitiated).async {
            Connectivity.toggle(device)
            DispatchQueue.main.async { self.busy = nil; self.loadDevices(); self.readConnections() }
        }
    }

    /// Open something (an app, a settings pane, the messages panel) and close the deck.
    func open(app bundleId: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in exit(0) }
    }

    func open(settings pane: String) {
        Connectivity.openSettings(pane)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { exit(0) }
    }

    /// herdr lives in the terminal: Ghostty when installed, else Terminal.
    func openTerminal() {
        open(app: NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.mitchellh.ghostty") != nil ? "com.mitchellh.ghostty" : "com.apple.Terminal")
    }

    func openMessagesPanel() {
        let me = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        try? Process.run(me, arguments: ["messages"])
        exit(0)
    }

    func setBrightness(_ value: Float) {
        guard Brightness.set(value) else { return }
        brightness = Brightness.get()
    }

    func select(_ device: AudioObjectID) {
        guard Audio.setDefaultOutput(device) else { return }
        readAudio()
    }
}
