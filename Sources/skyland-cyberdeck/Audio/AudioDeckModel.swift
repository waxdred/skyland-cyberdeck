import AppKit
import Combine
import CoreAudio

/// [audio] of config.toml: the audio deck.
struct AudioSettings {
    var theme: String
    var scale: Double       // size of the whole deck
    var opacity: Double     // deck background around the cards
    var blur: Double        // blur behind the deck, 0 = none
    var cardOpacity: Double
    var cyberspace: Double  // grid, data streams and scan line behind the signal, 0 = off
    var volumeStep: Float   // ↑ ↓, 0...1

    static func load() -> AudioSettings {
        let theme = Config.string("audio.theme", "")
        return AudioSettings(
            // --theme of this call wins, then [audio] theme, then the HUD's
            theme: CommandLine.arguments.contains("--theme") ? Theme.name : theme.isEmpty ? Config.string("hud.theme", "netrunner") : theme,
            scale: Double(min(2, max(0.5, Config.number("audio.scale", 1)))),
            opacity: Double(min(1, max(0, Config.number("audio.opacity", 0.55)))),
            blur: Double(min(1, max(0, Config.number("audio.blur", 0.35)))),
            cardOpacity: Double(min(1, max(0, Config.number("audio.card-opacity", 0.72)))),
            cyberspace: Double(min(1, max(0, Config.number("audio.cyberspace", 0.6)))),
            volumeStep: Float(min(25, max(1, Config.number("audio.volume-step", 5)))) / 100
        )
    }
}

/// What the audio deck shows and does. Lives as long as the deck (the process ends
/// with it): nothing runs while it is closed. Used on the main thread only (timers on
/// the main run loop, callbacks dispatched to the main queue): it drives the wave view.
final class AudioDeckModel: NSObject, ObservableObject {
    enum Capture { case waiting, live, unavailable }

    let settings = AudioSettings.load()
    @Published var nowPlaying: NowPlaying?
    @Published var artwork: NSImage?
    @Published var adapterAvailable = true
    @Published var capture = Capture.waiting
    @Published var sources: [AudioSource] = []
    /// the source the transport controls (the now playing app)
    @Published var controlled: pid_t?
    @Published var outputs: [AudioDevice] = []
    @Published var output: AudioObjectID?
    @Published var volume: Float?
    @Published var muted: Bool?
    /// bumped when the theme file changes: the deck redraws with the new palette
    @Published var themeVersion = 0
    /// set by the app: forget the dragged position, back in the middle
    var resetPosition: () -> Void = {}

    /// the signal, drawn 30 times a second outside SwiftUI
    let wave = AudiowareWave(frame: .zero)
    private let stream = NowPlayingStream()
    private lazy var bands = AudioBands(bands: 14) { [weak self] levels in self?.target = levels }
    private var target = [Float](repeating: 0, count: 14), shown = [Float](repeating: 0, count: 14)
    private var signals: (low: [Float], mid: [Float])?
    private var capturing = false
    private var artworkData: Data?
    private var timers: [Timer] = []
    private var ticks = 0
    private var themeDate: Date?

    var playing: Bool { nowPlaying?.playing ?? false }

    func start() {
        wave.axisFraction = 0.48 // on the horizon of the cyberspace grid
        wave.setTheme(accent: Tok.accentColor, background: Tok.inkColor)
        bands.onWave = { [weak self] low, mid in
            self?.signals = (low, mid)
            if self?.capture != .live { self?.capture = .live }
        }
        bands.onUnavailable = { [weak self] in self?.capture = .unavailable }
        stream.onChange = { [weak self] info in self?.update(info) }
        stream.start()
        adapterAvailable = stream.available
        readAudio()
        readSources()
        timers = [
            Timer.scheduledTimer(timeInterval: 1.0 / 30, target: self, selector: #selector(tick), userInfo: nil, repeats: true),
            Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(slowTick), userInfo: nil, repeats: true),
        ]
    }

    private func update(_ info: NowPlaying?) {
        if info != nowPlaying { nowPlaying = info }
        if info?.artwork != artworkData {
            artworkData = info?.artwork
            artwork = artworkData.flatMap { NSImage(data: $0) }
        }
        // capture only while something plays
        if playing, !capturing { bands.start(); capturing = true }
        if !playing, capturing { bands.stop(); capturing = false }
        readSources()
    }

    /// 30 times a second: the wave (levels rise at once, fall slowly) and its progress line.
    @objc private func tick() {
        for i in shown.indices { shown[i] = max(playing ? target[i] : 0, shown[i] * 0.85) }
        wave.advance(levels: shown, playing: playing, wave: playing ? signals : nil)
        if let info = nowPlaying, let duration = info.duration, duration > 0, let elapsed = info.elapsed(at: Date()) {
            wave.progress = CGFloat(elapsed / duration)
        } else {
            wave.progress = 1 // no track: the whole line lit
        }
    }

    /// Once a second: volume and device (changed from elsewhere too), sources every 2 s,
    /// output devices every 5 s, the theme file.
    @objc private func slowTick() {
        ticks += 1
        readAudio()
        if ticks % 2 == 0 { readSources() }
        watchTheme()
    }

    /// Assign only a new value: every assignment re-renders the deck.
    private func set<T: Equatable>(_ key: ReferenceWritableKeyPath<AudioDeckModel, T>, _ value: T) {
        if self[keyPath: key] != value { self[keyPath: key] = value }
    }

    func readAudio() {
        set(\.output, Audio.defaultOutput)
        set(\.volume, output.flatMap(Audio.volume))
        set(\.muted, output.flatMap(Audio.muted))
        if ticks % 5 == 0 { set(\.outputs, Audio.outputDevices()) }
    }

    func readSources() {
        let current = nowPlaying.flatMap { info -> AudioSource? in
            let app = info.pid.flatMap { AudioSources.owner(of: $0, bundleID: info.bundleID) }
                ?? info.bundleID.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first }
            return app.map { AudioSource(id: $0.processIdentifier, name: $0.localizedName ?? info.bundleID ?? "?", bundleID: $0.bundleIdentifier, live: false) }
        }
        let merged = AudioSources.merged(AudioSources.live(), nowPlaying: current)
        set(\.sources, merged)
        set(\.controlled, current == nil ? nil : merged.first?.id)
    }

    /// The theme file changed since the last look: reload the palette.
    private func watchTheme() {
        guard let file = Theme.file(settings.theme),
              let date = try? FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date else { return }
        if let themeDate, date != themeDate {
            Tok.reloadTheme()
            wave.setTheme(accent: Tok.accentColor, background: Tok.inkColor)
            themeVersion += 1
        }
        themeDate = date
    }

    // MARK: commands

    func togglePlay() { MediaRemote.send(.toggle) }
    func next() { MediaRemote.send(.next) }
    func previous() { MediaRemote.send(.previous) }

    /// Seek to a fraction of the track (a click on the signal).
    func seek(to fraction: Double) {
        guard let duration = nowPlaying?.duration, duration > 0 else { return }
        MediaRemote.seek(to: duration * min(1, max(0, fraction)))
    }

    func setVolume(_ value: Float) {
        guard let output, Audio.setVolume(value, of: output) else { return }
        volume = Audio.volume(of: output) // what the device took
    }

    func nudgeVolume(_ steps: Float) {
        guard let volume else { return }
        setVolume(volume + steps * settings.volumeStep)
    }

    func toggleMute() {
        guard let output, let muted, Audio.setMuted(!muted, output) else { return }
        self.muted = Audio.muted(output)
    }

    func select(_ device: AudioObjectID) {
        guard Audio.setDefaultOutput(device) else { return }
        readAudio()
    }

    /// The n-th output device (1-based, the digit keys).
    func select(port number: Int) {
        guard outputs.indices.contains(number - 1) else { return }
        select(outputs[number - 1].id)
    }

    /// Bring a source's app to the front and close the deck.
    func focus(_ source: AudioSource) {
        NSRunningApplication(processIdentifier: source.id)?.activate(options: [.activateAllWindows])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { exit(0) }
    }
}
