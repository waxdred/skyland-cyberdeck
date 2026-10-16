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
    var opacity: Double
    var secondTimezone: TimeZone?
    var theme: String
    var apps: [String]

    static let allWidgets = ["clock", "calendar", "herdr", "sound", "system", "messages", "launch"]
    static let defaultApps = ["Finder", "Ghostty", "Terminal", "Visual Studio Code", "Firefox", "Safari", "Spotify", "Notes", "System Settings"]

    static func load() -> HudSettings {
        let widgets = parseWidgetList(Config.string("hud.widgets", allWidgets.joined(separator: ",")))
        return HudSettings(
            widgets: widgets.isEmpty ? allWidgets : widgets,
            clock24h: Config.bool("hud.clock-24h", true),
            clockSeconds: Config.bool("hud.clock-seconds", false),
            weekStart: min(7, max(0, Config.int("hud.week-start", 0))),
            refreshMs: min(10000, max(250, Config.int("hud.refresh-ms", 1000))),
            opacity: Double(min(1, max(0.3, Config.number("hud.opacity", 0.86)))),
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
    @Published var messages: [Message] = []
    /// quick launch: the configured apps that are installed
    lazy var launchApps: [AppEntry] = {
        let installed = Apps.all()
        return settings.apps.compactMap { name in installed.first { $0.name.caseInsensitiveCompare(name) == .orderedSame } }
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
        memory = SystemReaders.memory()
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
        if every(5) { interface = SystemReaders.primaryInterface(); battery = SystemReaders.battery(); outputs = Audio.outputDevices() }
        if every(30) { storage = SystemReaders.storage() }
        if every(3) { messages = Messages.list(limit: 2); brightness = Brightness.get() }
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

    func readAudio() {
        output = Audio.defaultOutput
        volume = output.flatMap(Audio.volume)
        muted = output.flatMap(Audio.muted)
    }

    func setVolume(_ value: Float) {
        guard let output, Audio.setVolume(value, of: output) else { return }
        volume = Audio.volume(of: output) // what the device took
    }

    func toggleMute() {
        guard let output, let muted, Audio.setMuted(!muted, output) else { return }
        self.muted = Audio.muted(output)
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
