import AppKit
import CoreAudio
import SwiftUI

// The audio deck: the live signal floating on the cyberspace grid (its horizon is the
// track's progress, a click seeks), now playing with the transport, the output (volume,
// ports) and the apps on the audio bus. Same deck as the HUD: cut frame, cards, Tok.

struct AudioDeckView: View {
    @ObservedObject var model: AudioDeckModel
    @State private var shown = false
    private let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Group {
                SignalCard(model: model) // recolors itself on a new theme (the wave is one view for the deck's life)
                Group {
                    HStack(alignment: .top, spacing: 12) {
                        NowPlayingCard(model: model)
                        OutputCard(model: model).frame(width: 330)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    SourcesCard(model: model)
                }
                .id(model.themeVersion) // a new theme rebuilds the cards with the new palette
            }
            .opacity(shown ? 1 : 0).offset(y: shown || still ? 0 : 16)
            Text("SPACE play / pause     ← → previous / next     ↑ ↓ volume     M mute     1-9 port     click the signal to seek     ESC jack out")
                .font(Tok.mono(9)).foregroundStyle(Tok.off)
        }
        .padding(24)
        .frame(width: 900)
        .background(DragHandle(reset: model.resetPosition)) // the deck moves when dragged between the cards
        .background(CutFrame().fill(Tok.background.opacity(model.settings.opacity)))
        .background(CutFrame().fill(.ultraThinMaterial).opacity(model.settings.blur))
        .overlay(CutFrame().stroke(Tok.accent.opacity(0.55), lineWidth: 1.2).shadow(color: Tok.accent.opacity(0.6), radius: 5))
        .overlay(CutFrame(cut: 17).stroke(Tok.accent.opacity(0.14), lineWidth: 1).padding(6))
        .overlay(DeckFrame().stroke(Tok.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            .shadow(color: Tok.accent, radius: 7).shadow(color: Tok.accent.opacity(0.45), radius: 12))
        .padding(32) // room for the glow to fade out before the window edge
        .onAppear { withAnimation(.easeOut(duration: still ? 0 : 0.35).delay(0.05)) { shown = true } }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.path").foregroundStyle(Tok.accent)
            Text("SKYLAND CYBERDECK // AUDIO CONSTRUCT").font(Tok.mono(11, .semibold)).foregroundStyle(Tok.accent).kerning(2)
            Spacer()
            let state = status
            Text(state.text).font(Tok.mono(10, .bold)).foregroundStyle(state.color)
            if let output = model.output, let name = Audio.name(of: output) {
                let number = (model.outputs.firstIndex { $0.id == output } ?? 0) + 1
                Label(text: String(format: "Port %02d · %@", number, name))
            }
        }
    }

    /// Jacked in (playing), paused, flatline (nothing), or no adapter: in words, not color only.
    private var status: (text: String, color: Color) {
        if !model.adapterAvailable { return ("✕ NO ADAPTER", Tok.bad) }
        guard let info = model.nowPlaying else { return ("○ FLATLINE", Tok.off) }
        return info.playing ? ("● JACKED IN", Tok.ok) : ("◐ PAUSED", Tok.warn)
    }
}

/// The construct: the wave on the horizon of the cyberspace grid, its line the progress.
struct SignalCard: View {
    @ObservedObject var model: AudioDeckModel

    var body: some View {
        ZStack {
            if model.settings.cyberspace > 0 { Cyberspace(strength: model.settings.cyberspace, color: Tok.accentColor) }
            WaveView(wave: model.wave)
            SeekArea(help: model.nowPlaying?.duration == nil ? nil : "Click to seek") { model.seek(to: $0) }
            Brackets().stroke(Tok.accent.opacity(0.55), lineWidth: 1).allowsHitTesting(false)
            VStack {
                HStack {
                    Text("CYBERSPACE // SIGNAL").font(Tok.mono(9, .semibold)).foregroundStyle(Tok.accent).kerning(1.4)
                    Spacer()
                    let state = signal
                    Text(state.text).font(Tok.mono(9, .semibold)).foregroundStyle(state.color).kerning(1.4)
                }
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack {
                        let info = model.nowPlaying
                        let elapsed = info?.elapsed(at: context.date)
                        Text(elapsed.map(timecode) ?? "--:--").foregroundStyle(Tok.accent)
                        Spacer()
                        if let duration = info?.duration, let elapsed {
                            Text("-\(timecode(duration - elapsed)) / \(timecode(duration))").foregroundStyle(Tok.dim)
                        }
                    }
                    .font(Tok.mono(11, .medium))
                }
            }
            .padding(.horizontal, 22).padding(.vertical, 16)
            .allowsHitTesting(false)
        }
        .frame(height: 250)
        .background(RoundedRectangle(cornerRadius: 9).fill(Tok.surface))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Tok.accent.opacity(0.22), lineWidth: 1))
    }

    /// What the signal is made of, or why there is none.
    private var signal: (text: String, color: Color) {
        switch model.capture {
            case .unavailable: return ("NO CAPTURE · SCREEN RECORDING PERMISSION", Tok.warn)
            case .live where model.playing: return ("48 KHZ · 14 BANDS", Tok.label)
            default: return (model.nowPlaying == nil ? "FLATLINE" : model.playing ? "TRACING…" : "HOLD", Tok.off)
        }
    }
}

/// minutes:seconds
func timecode(_ seconds: Double) -> String {
    let total = seconds.isFinite ? max(0, Int(seconds.rounded(.down))) : 0
    return String(format: "%02d:%02d", total / 60, total % 60)
}

/// The wave view of the model, drawn outside SwiftUI (30 fps).
struct WaveView: NSViewRepresentable {
    let wave: AudiowareWave
    func makeNSView(context: Context) -> AudiowareWave { wave }
    func updateNSView(_ view: AudiowareWave, context: Context) {}
}

/// A click on the signal: where, as a fraction of its width.
struct SeekArea: NSViewRepresentable {
    let help: String?
    let seek: (Double) -> Void

    final class Area: NSView {
        var seek: (Double) -> Void = { _ in }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {
            seek(Double(convert(event.locationInWindow, from: nil).x / max(1, bounds.width)))
        }
    }

    func makeNSView(context: Context) -> Area { Area() }
    func updateNSView(_ view: Area, context: Context) {
        view.seek = seek
        view.toolTip = help
    }
}

struct NowPlayingCard: View {
    @ObservedObject var model: AudioDeckModel

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 16) {
                Hologram(image: model.artwork, icon: sourceIcon)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("NOW PLAYING").font(Tok.mono(10, .semibold)).foregroundStyle(Tok.accent).kerning(1.6)
                        if let name = model.sources.first(where: { $0.id == model.controlled })?.name {
                            Text("// " + name.uppercased()).font(Tok.mono(10, .semibold)).foregroundStyle(Tok.dim).kerning(1.6)
                        }
                    }
                    if let info = model.nowPlaying {
                        Text(info.title.uppercased()).font(Font(Neon.title(28, .heavy))).foregroundStyle(Tok.accent)
                            .shadow(color: Tok.accent.opacity(0.55), radius: 10).lineLimit(1)
                        Text(info.artist).font(Tok.sans(14)).foregroundStyle(Tok.text).lineLimit(1)
                        Text(info.album).font(Tok.sans(12)).foregroundStyle(Tok.dim).lineLimit(1)
                    } else {
                        Text(model.adapterAvailable ? "NOTHING PLAYING" : "ADAPTER MISSING").font(Font(Neon.title(28, .heavy))).foregroundStyle(Tok.off)
                        Text(model.adapterAvailable ? "Start a track in any app." : "libMediaRemoteAdapter.dylib is not next to skyland-cyberdeck.")
                            .font(Tok.sans(12)).foregroundStyle(Tok.dim)
                    }
                    Spacer(minLength: 12)
                    HStack(spacing: 10) {
                        DeckButton(symbol: "backward.fill", help: "Previous (←)") { model.previous() }
                        DeckButton(symbol: model.playing ? "pause.fill" : "play.fill", primary: true, help: "Play / pause (space)") { model.togglePlay() }
                        DeckButton(symbol: "forward.fill", help: "Next (→)") { model.next() }
                        Spacer()
                        if let track = model.nowPlaying?.track, let tracks = model.nowPlaying?.tracks, tracks > 0 {
                            Label(text: String(format: "Track %02d / %02d", track, tracks))
                        }
                    }
                    .disabled(model.nowPlaying == nil)
                    .opacity(model.nowPlaying == nil ? 0.4 : 1)
                }
            }
        }
    }

    private var sourceIcon: NSImage? { model.controlled.flatMap { NSRunningApplication(processIdentifier: $0)?.icon } }
}

/// The artwork as a hologram: tinted, scanlines; the app's icon or a waveform without one.
struct Hologram: View {
    let image: NSImage?
    let icon: NSImage?

    var body: some View {
        ZStack {
            Tok.elevated
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill).saturation(0.8)
            } else if let icon {
                Image(nsImage: icon).resizable().padding(30).opacity(0.75)
            } else {
                Image(systemName: "waveform").font(.system(size: 44, weight: .light)).foregroundStyle(Tok.accent.opacity(0.6))
            }
            LinearGradient(colors: [Tok.accent.opacity(0.18), .clear, Tok.accent.opacity(0.10)], startPoint: .top, endPoint: .bottom)
                .blendMode(.screen)
            Scanlines().fill(Tok.background.opacity(0.35))
        }
        .frame(width: 132, height: 132)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Tok.accent.opacity(0.5), lineWidth: 1))
        .shadow(color: Tok.accent.opacity(0.25), radius: 9)
    }
}

/// Horizontal lines every 3 points.
struct Scanlines: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            var y = r.minY
            while y < r.maxY {
                p.addRect(CGRect(x: r.minX, y: y, width: r.width, height: 1))
                y += 3
            }
        }
    }
}

/// Corner brackets of the construct.
struct Brackets: Shape {
    var arm: CGFloat = 14
    var inset: CGFloat = 10
    func path(in r: CGRect) -> Path {
        let b = r.insetBy(dx: inset, dy: inset)
        return Path { p in
            let corners: [(CGPoint, CGFloat, CGFloat)] = [(CGPoint(x: b.minX, y: b.minY), 1, 1), (CGPoint(x: b.maxX, y: b.minY), -1, 1),
                                                          (CGPoint(x: b.minX, y: b.maxY), 1, -1), (CGPoint(x: b.maxX, y: b.maxY), -1, -1)]
            for (corner, dx, dy) in corners {
                p.move(to: CGPoint(x: corner.x + dx * arm, y: corner.y))
                p.addLine(to: corner)
                p.addLine(to: CGPoint(x: corner.x, y: corner.y + dy * arm))
            }
        }
    }
}

/// Top-left and bottom-right corners cut.
struct CutCorners: Shape {
    var cut: CGFloat = 8
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.minX + cut, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - cut))
            p.addLine(to: CGPoint(x: r.maxX - cut, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.minY + cut))
            p.closeSubpath()
        }
    }
}

/// A transport / mute button: cut corners, the primary one filled and glowing.
struct DeckButton: View {
    let symbol: String
    var primary = false
    var small = false
    var help = ""
    let action: () -> Void
    @State private var over = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: primary ? 17 : small ? 12 : 13, weight: .bold))
                .foregroundStyle(primary ? Tok.background : Tok.accent)
                .frame(width: primary ? 64 : small ? 38 : 46, height: small ? 28 : 34)
                .background(CutCorners(cut: small ? 6 : 8).fill(primary ? Tok.accent : Tok.accent.opacity(over ? 0.28 : 0.12)))
                .shadow(color: primary ? Tok.accent.opacity(over ? 0.95 : 0.7) : .clear, radius: primary ? 8 : 0)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { over = $0 }
        .help(help)
    }
}

struct OutputCard: View {
    @ObservedObject var model: AudioDeckModel

    var body: some View {
        Card(title: "Signal // Output") {
            if let volume = model.volume {
                let muted = model.muted == true
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text("\(Int((volume * 100).rounded()))")
                        .font(Font(NSFont.monospacedDigitSystemFont(ofSize: 54 * Neon.scale, weight: .thin)))
                        .foregroundStyle(muted ? Tok.off : Tok.accent).shadow(color: Tok.accent.opacity(muted ? 0 : 0.5), radius: 10)
                    Text(muted ? "MUTED" : "%").font(Tok.mono(13, .semibold)).foregroundStyle(muted ? Tok.warn : Tok.dim)
                    Spacer()
                    DeckButton(symbol: muted ? "speaker.slash.fill" : "speaker.wave.2.fill", small: true, help: "Mute (M)") { model.toggleMute() }
                }
                Slider(value: Binding(get: { Double(volume) }, set: { model.setVolume(Float($0)) }), in: 0 ... 1)
                    .tint(Tok.accent).help("Output volume (↑ ↓)")
            } else {
                Text(model.output == nil ? "NO OUTPUT DEVICE" : "NO VOLUME CONTROL ON THIS DEVICE").font(Tok.mono(10)).foregroundStyle(Tok.off)
            }
            Label(text: "Ports")
            ForEach(Array(model.outputs.enumerated()), id: \.element.id) { index, device in
                PortRow(number: index + 1, name: device.name, active: device.id == model.output) { model.select(device.id) }
            }
        }
    }
}

/// An output device: its number (the digit key), name, state in words.
struct PortRow: View {
    let number: Int
    let name: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(String(format: "%02d", number)).font(Tok.mono(11, .semibold)).foregroundStyle(active ? Tok.accent : Tok.dim)
            Text(name).font(Tok.sans(12)).foregroundStyle(Tok.text).lineLimit(1)
            Spacer()
            Text(active ? "◆ ACTIVE" : "JACK IN").font(Tok.mono(8, .bold)).foregroundStyle(Tok.accent.opacity(active ? 1 : 0.75))
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 7).fill(active ? Tok.accent.opacity(0.14) : Tok.elevated))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Tok.accent.opacity(active ? 0.8 : 0), lineWidth: 1))
        .hover(7) { if !active { action() } }
        .help(active ? "\(name): the output now" : "Send the sound to \(name) (\(number))")
    }
}

struct SourcesCard: View {
    @ObservedObject var model: AudioDeckModel

    var body: some View {
        Card(title: "Sources // Processes on the bus") {
            if model.sources.isEmpty {
                Text(sourcesListed ? "NO PROCESS ON THE BUS" : "SOURCES NEED MACOS 14.4").font(Tok.mono(11)).foregroundStyle(Tok.off)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), alignment: .leading, spacing: 10) {
                    ForEach(model.sources) { source in
                        SourceTile(source: source, controlled: source.id == model.controlled) { model.focus(source) }
                    }
                }
            }
        }
    }

    private var sourcesListed: Bool {
        if #available(macOS 14.4, *) { return true }
        return false
    }
}

/// An app on the bus: icon, name, controlled / live / paused in words.
struct SourceTile: View {
    let source: AudioSource
    let controlled: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSRunningApplication(processIdentifier: source.id)?.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage())
                .resizable().frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(source.name).font(Tok.sans(12, .semibold)).foregroundStyle(Tok.text).lineLimit(1)
                Text(controlled ? "◆ CONTROLLED" : source.live ? "LIVE" : "PAUSED").font(Tok.mono(8, .bold))
                    .foregroundStyle(controlled ? Tok.accent : source.live ? Tok.ok : Tok.off)
            }
            Spacer(minLength: 0)
            if source.live { Circle().fill(Tok.ok).frame(width: 6, height: 6).shadow(color: Tok.ok, radius: 4) }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 7).fill(controlled ? Tok.accent.opacity(0.14) : Tok.elevated))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Tok.accent.opacity(controlled ? 0.8 : 0), lineWidth: 1))
        .opacity(source.live || controlled ? 1 : 0.6)
        .hover(7, action: action)
        .help("Bring \(source.name) to the front")
    }
}
