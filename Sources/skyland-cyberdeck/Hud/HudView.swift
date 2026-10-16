import AppKit
import CoreAudio
import SwiftUI

/// Design tokens of the HUD, every color of the HUD comes from here. The palette is
/// [hud] theme (netrunner by default, `skyland` follows the skyland theme) with the
/// [colors] overrides; surfaces are the ink tinted with the accent; states are fixed.
enum Tok {
    private static let settings = HudSettings.load()
    private static let theme = Theme.load(named: settings.theme)
    private static let accentNS = Config.color("colors.primary") ?? theme.primary
    private static let inkNS = Config.color("colors.ink") ?? theme.ink
    static let accent = Color(nsColor: accentNS)                                     // active states, frame, values
    static let label = Color(nsColor: Config.color("colors.secondary") ?? theme.secondary) // micro labels
    static let hot = Color(nsColor: Config.color("colors.highlight") ?? theme.highlight)   // upload, alerts
    static let background = Color(nsColor: inkNS)
    static let accentColor = accentNS
    // cards and their tiles: [hud] card-opacity lets the cyberspace backdrop through
    static let surface = Color(nsColor: inkNS.blended(withFraction: 0.07, of: accentNS) ?? inkNS).opacity(settings.cardOpacity)
    static let elevated = Color(nsColor: inkNS.blended(withFraction: 0.13, of: accentNS) ?? inkNS).opacity(min(1, settings.cardOpacity + 0.1))
    static let text = Color(red: 0.87, green: 0.98, blue: 1)
    static let dim = Color(red: 0.46, green: 0.65, blue: 0.72)
    static let off = Color(red: 0.21, green: 0.33, blue: 0.40)
    static let ok = Color(red: 0.27, green: 1, blue: 0.78)
    static let warn = Color(red: 1, green: 0.78, blue: 0.34)
    static let bad = Color(red: 1, green: 0.30, blue: 0.43)

    /// readable text: [general] font, else the system font
    static func sans(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> Font {
        let custom = Config.string("general.font", "")
        return Font(custom.isEmpty ? NSFont.systemFont(ofSize: size * Neon.scale, weight: weight) : Neon.title(size, weight))
    }
    static func mono(_ size: CGFloat, _ weight: NSFont.Weight = .medium) -> Font { Font(Neon.mono(size, weight)) }
}

/// Micro label: uppercase, spaced.
struct Label: View {
    let text: String
    var body: some View { Text(text.uppercased()).font(Tok.mono(10, .semibold)).foregroundStyle(Tok.label).kerning(1.6) }
}

/// A card of the deck.
struct Card<Content: View>: View {
    var title: String?
    var elevated = false
    /// what a click on the card does (title, empty space); its controls keep their own
    var action: (() -> Void)?
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                HStack(spacing: 4) {
                    Text(title.uppercased()).font(Tok.mono(10, .semibold)).foregroundStyle(Tok.accent).kerning(1.6)
                    if action != nil { Image(systemName: "arrow.up.right").font(.system(size: 8, weight: .bold)).foregroundStyle(Tok.accent.opacity(0.6)) }
                }
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 9).fill(elevated ? Tok.elevated : Tok.surface))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Tok.accent.opacity(0.22), lineWidth: 1))
        .hover(9, action: action)
    }
}

/// Hover feedback: the edge lights up, a slight lift, and the pointing
/// hand on what does something when clicked. Reduce Motion: no lift.
struct Hover: ViewModifier {
    var radius: CGFloat
    var action: (() -> Void)?
    @State private var over = false
    private let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    func body(content: Content) -> some View {
        content
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(Tok.accent.opacity(over ? 0.85 : 0), lineWidth: 1.2))
            .scaleEffect(over && !still ? 1.012 : 1)
            .animation(.easeOut(duration: 0.16), value: over)
            .contentShape(RoundedRectangle(cornerRadius: radius))
            .onHover { inside in
                over = inside
                if action != nil { if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
            }
            .onTapGesture { action?() }
    }
}

extension View {
    func hover(_ radius: CGFloat = 9, action: (() -> Void)? = nil) -> some View { modifier(Hover(radius: radius, action: action)) }
}

/// The deck outline: all four corners cut.
struct CutFrame: Shape {
    var cut: CGFloat = 22
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.minX + cut, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX - cut, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY + cut))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - cut))
            p.addLine(to: CGPoint(x: r.maxX - cut, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX + cut, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY - cut))
            p.addLine(to: CGPoint(x: r.minX, y: r.minY + cut))
            p.closeSubpath()
        }
    }
}

/// The glowing corner pieces of the deck: arm, the cut, arm.
struct DeckFrame: Shape {
    var cut: CGFloat = 22
    var arm: CGFloat = 46
    func path(in r: CGRect) -> Path {
        Path { p in
            for (corner, dx, dy) in [(CGPoint(x: r.minX, y: r.minY), 1.0, 1.0), (CGPoint(x: r.maxX, y: r.minY), -1.0, 1.0),
                                     (CGPoint(x: r.minX, y: r.maxY), 1.0, -1.0), (CGPoint(x: r.maxX, y: r.maxY), -1.0, -1.0)] {
                p.move(to: CGPoint(x: corner.x + dx * (cut + arm), y: corner.y))
                p.addLine(to: CGPoint(x: corner.x + dx * cut, y: corner.y))
                p.addLine(to: CGPoint(x: corner.x, y: corner.y + dy * cut))
                p.addLine(to: CGPoint(x: corner.x, y: corner.y + dy * (cut + arm)))
            }
        }
    }
}

struct Meter: View {
    let value: Double // 0...1
    var color: Color = Tok.accent
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Tok.off.opacity(0.45))
                Capsule().fill(color).frame(width: max(4, geo.size.width * min(1, max(0, value))))
                    .shadow(color: color.opacity(0.6), radius: 4)
            }
        }
        .frame(height: 5)
    }
}

struct Spark: View {
    let values: [Double]
    var color: Color = Tok.accent
    var body: some View {
        GeometryReader { geo in
            let top = max(values.max() ?? 1, 0.000001)
            Path { p in
                for (i, v) in values.enumerated() {
                    let point = CGPoint(x: geo.size.width * CGFloat(i) / CGFloat(max(1, values.count - 1)),
                                        y: geo.size.height * (1 - CGFloat(v / top)))
                    if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
                }
            }
            .stroke(color, lineWidth: 1.3)
            .shadow(color: color.opacity(0.7), radius: 3)
        }
    }
}

struct Ring: View {
    let value: Double?
    let center: String
    var size: CGFloat = 56
    var body: some View {
        ZStack {
            Circle().stroke(Tok.off.opacity(0.5), lineWidth: 3)
            Circle().trim(from: 0, to: value ?? 0).stroke(Tok.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90)).shadow(color: Tok.accent.opacity(0.7), radius: 4)
            Text(center).font(Tok.mono(12, .semibold)).foregroundStyle(Tok.text)
        }
        .frame(width: size, height: size)
    }
}

struct HudView: View {
    @ObservedObject var model: HudModel
    private func shows(_ widget: String) -> Bool { model.settings.widgets.contains(widget) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "cpu").foregroundStyle(Tok.accent)
                Text("SKYLAND CYBERDECK").font(Tok.mono(11, .semibold)).foregroundStyle(Tok.accent).kerning(2)
                Spacer()
                Text("● ONLINE").font(Tok.mono(10, .bold)).foregroundStyle(Tok.ok)
                Label(text: "Profile \(model.settings.theme)")
            }
            Group {
                row(left: shows("clock") ? AnyView(ClockCard(model: model)) : nil,
                    right: shows("calendar") ? AnyView(CalendarCard(model: model)) : nil)
                row(left: shows("connections") ? AnyView(ConnectionsCard(model: model)) : nil,
                    right: shows("sound") ? AnyView(SoundCard(model: model)) : nil)
                if shows("system") { SystemCard(model: model) }
                row(left: shows("herdr") ? AnyView(HerdrCard(model: model)) : nil,
                    right: shows("messages") ? AnyView(MessagesCard(model: model)) : nil, rightWidth: 360)
                if shows("launch") && !model.launchApps.isEmpty { LaunchCard(apps: model.launchApps) }
            }
            .opacity(shown ? 1 : 0).offset(x: shown || still ? 0 : 24)
            Text("ESC close     ← → month     click a card to open it     a click outside closes").font(Tok.mono(9)).foregroundStyle(Tok.off)
        }
        .padding(24)
        .frame(width: 780)
        .background(DragHandle(reset: model.resetPosition)) // the deck moves when dragged between the cards
        .background(model.settings.cyberspace > 0 ? Cyberspace(strength: model.settings.cyberspace, color: Tok.accentColor).clipShape(CutFrame()) : nil)
        .background(CutFrame().fill(Tok.background.opacity(model.settings.opacity)))
        .background(CutFrame().fill(.ultraThinMaterial).opacity(model.settings.blur)) // [hud] blur: partly blurred behind
        .overlay(CutFrame().stroke(Tok.accent.opacity(0.55), lineWidth: 1.2).shadow(color: Tok.accent.opacity(0.6), radius: 5))
        .overlay(CutFrame(cut: 17).stroke(Tok.accent.opacity(0.14), lineWidth: 1).padding(6))
        .overlay(DeckFrame().stroke(Tok.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            .shadow(color: Tok.accent, radius: 7).shadow(color: Tok.accent.opacity(0.45), radius: 12))
        .padding(32) // room for the glow to fade out before the window edge (no visible rectangle)
        .onAppear { withAnimation(.easeOut(duration: still ? 0 : 0.35).delay(0.05)) { shown = true } }
    }

    @State private var shown = false
    private let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    /// two cards side by side, the right one at the calendar width
    @ViewBuilder private func row(left: AnyView?, right: AnyView?, rightWidth: CGFloat = 310) -> some View {
        if left != nil || right != nil {
            HStack(alignment: .top, spacing: 12) {
                if let left { left }
                if let right { right.frame(width: left == nil ? nil : rightWidth) }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ClockCard: View {
    @ObservedObject var model: HudModel
    var settings: HudSettings { model.settings }
    var body: some View {
        Card(action: { model.open(app: "com.apple.clock") }) {
            // on each minute (or second) boundary, nothing in between
            TimelineView(.periodic(from: Calendar.current.dateInterval(of: .minute, for: .now)?.start ?? .now, by: settings.clockSeconds ? 1 : 60)) { context in
                VStack(alignment: .leading, spacing: 10) {
                    Text(time(context.date, .current))
                        .font(Font(NSFont.monospacedDigitSystemFont(ofSize: 92 * Neon.scale, weight: .thin)))
                        .foregroundStyle(Tok.accent).shadow(color: Tok.accent.opacity(0.55), radius: 10)
                    Text(context.date.formatted(.dateTime.weekday(.wide).day().month(.wide).year()).uppercased())
                        .font(Tok.mono(16, .medium)).foregroundStyle(Tok.text).kerning(3)
                    Rectangle().fill(Tok.accent.opacity(0.35)).frame(height: 1)
                    if let zone = settings.secondTimezone {
                        HStack {
                            Label(text: zone.identifier.split(separator: "/").last.map(String.init) ?? zone.identifier)
                            Spacer()
                            Text(time(context.date, zone)).font(Tok.mono(13, .semibold)).foregroundStyle(Tok.text)
                        }
                    } else {
                        Label(text: TimeZone.current.identifier.replacingOccurrences(of: "_", with: " "))
                    }
                }
            }
        }
    }

    private func time(_ date: Date, _ zone: TimeZone) -> String {
        let format = DateFormatter()
        format.timeZone = zone
        format.dateFormat = (settings.clock24h ? "HH:mm" : "h:mm") + (settings.clockSeconds ? ":ss" : "") + (settings.clock24h ? "" : " a")
        return format.string(from: date)
    }
}

struct CalendarCard: View {
    @ObservedObject var model: HudModel
    var body: some View {
        let calendar = Calendar.current
        let month = calendar.date(byAdding: .month, value: model.monthOffset, to: .now) ?? .now
        let cells = monthGrid(month, firstWeekday: model.firstWeekday)
        let shift = model.firstWeekday - 1
        let symbols = Array(calendar.shortStandaloneWeekdaySymbols[shift...] + calendar.shortStandaloneWeekdaySymbols[..<shift])
        return Card(action: { model.open(app: "com.apple.iCal") }) {
            HStack {
                Text(month.formatted(.dateTime.month(.abbreviated).year()).uppercased())
                    .font(Tok.mono(15, .semibold)).foregroundStyle(Tok.accent).kerning(1.5)
                    .help("Open Calendar")
                Spacer()
                Button { model.monthOffset -= 1 } label: { Image(systemName: "chevron.left") }.buttonStyle(.plain).help("Previous month")
                Button { model.monthOffset += 1 } label: { Image(systemName: "chevron.right") }.buttonStyle(.plain).help("Next month")
            }
            .foregroundStyle(Tok.accent)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 6) {
                ForEach(Array(symbols.enumerated()), id: \.offset) {
                    Text($0.element.uppercased().prefix(3)).font(Tok.mono(9, .semibold)).foregroundStyle(Tok.dim)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    let today = day.map(calendar.isDateInToday) ?? false
                    Text(day.map { "\(calendar.component(.day, from: $0))" } ?? "")
                        .font(Tok.mono(12, today ? .bold : .regular))
                        .foregroundStyle(today ? Tok.background : Tok.text)
                        .frame(width: 30, height: 22)
                        .background(today ? RoundedRectangle(cornerRadius: 5).fill(Tok.accent).shadow(color: Tok.accent, radius: 5) : nil)
                        .hover(5) { model.open(app: "com.apple.iCal") }
                        .accessibilityLabel(day.map { $0.formatted(date: .complete, time: .omitted) + (today ? ", today" : "") } ?? "")
                }
            }
        }
    }
}

struct HerdrCard: View {
    @ObservedObject var model: HudModel
    var body: some View {
        Card(title: "Herdr // Agents", action: { model.openTerminal() }) {
            switch model.herdr {
                case nil:
                    Text("CONNECTING").font(Tok.mono(11)).foregroundStyle(Tok.dim)
                case .unavailable:
                    Text("○ UNAVAILABLE  herdr is not running").font(Tok.mono(11)).foregroundStyle(Tok.off)
                case let .error(message):
                    Text("✕ ERROR  \(message)").font(Tok.mono(11)).foregroundStyle(Tok.bad)
                case let .connected(summary, date):
                    HStack(spacing: 8) {
                        tile("SESSIONS", summary.total, Tok.text)
                        tile("RUNNING", summary.running, summary.running > 0 ? Tok.accent : Tok.text)
                        tile("NEEDS YOU", summary.blocked, summary.blocked > 0 ? Tok.warn : Tok.text)
                        tile("IDLE", summary.idle, Tok.dim)
                    }
                    ForEach(Array(summary.agents.filter { $0.status != "idle" }.prefix(3).enumerated()), id: \.offset) { _, agent in
                        HStack(spacing: 6) {
                            Text("›").foregroundStyle(Tok.accent)
                            Text(agent.agent).font(Tok.mono(11, .semibold)).foregroundStyle(Tok.text)
                            Text(agent.title).font(Tok.sans(11)).foregroundStyle(Tok.dim).lineLimit(1)
                            Spacer()
                            Text(agent.status.uppercased()).font(Tok.mono(9, .bold))
                                .foregroundStyle(agent.status == "working" ? Tok.accent : agent.status == "done" ? Tok.ok : Tok.warn)
                        }
                    }
                    Text("● CONNECTED   UPDATED \(date.formatted(date: .omitted, time: .standard))")
                        .font(Tok.mono(9, .semibold)).foregroundStyle(Tok.ok)
            }
        }
    }

    private func tile(_ label: String, _ value: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(format: "%02d", value)).font(Tok.mono(20, .semibold)).foregroundStyle(color)
            Text(label).font(Tok.mono(8, .semibold)).foregroundStyle(Tok.dim)
        }
        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 7).fill(Tok.elevated))
    }
}

struct SoundCard: View {
    @ObservedObject var model: HudModel
    var body: some View {
        Card(title: "Display & Sound", action: { model.open(settings: "sound") }) {
            if let brightness = model.brightness {
                slider("sun.max", "Brightness", brightness, help: "Built-in display brightness", set: { model.setBrightness($0) })
            }
            if let volume = model.volume {
                slider(model.muted == true ? "speaker.slash" : "speaker.wave.2", model.muted == true ? "Muted" : "Volume", volume,
                       help: "Output volume, click the icon to mute", set: { model.setVolume($0) }, icon: { model.toggleMute() })
            } else {
                Text(model.output == nil ? "NO OUTPUT DEVICE" : "NO VOLUME CONTROL ON THIS DEVICE").font(Tok.mono(10)).foregroundStyle(Tok.off)
            }
            if model.output != nil {
                Menu {
                    ForEach(model.outputs) { device in
                        Button(device.name + (device.id == model.output ? "  ✓" : "")) { model.select(device.id) }
                    }
                } label: {
                    Text(model.output.flatMap(Audio.name) ?? "?").font(Tok.sans(11)).foregroundStyle(Tok.dim)
                }
                .menuStyle(.borderlessButton).fixedSize().help("Output device")
            }
        }
    }

    private func slider(_ symbol: String, _ title: String, _ value: Float, help: String, set: @escaping (Float) -> Void, icon: (() -> Void)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button { icon?() } label: { Image(systemName: symbol).frame(width: 18) }.buttonStyle(.plain).foregroundStyle(Tok.text).disabled(icon == nil)
                Text(title).font(Tok.sans(13)).foregroundStyle(Tok.text)
                Spacer()
                Text("\(Int((value * 100).rounded()))%").font(Tok.mono(11)).foregroundStyle(Tok.dim)
            }
            Slider(value: Binding(get: { Double(value) }, set: { set(Float($0)) }), in: 0 ... 1).tint(Tok.accent).help(help)
        }
    }
}

struct SystemCard: View {
    @ObservedObject var model: HudModel
    var body: some View {
        Card(title: "System", action: { model.open(app: "com.apple.ActivityMonitor") }) {
            HStack(alignment: .center, spacing: 14) {
                let share = model.memory.map { Double($0.used) / Double($0.total) }
                gauge("CPU", value: model.cpu, text: model.cpu.map { "\(Int(($0 * 100).rounded()))%" }, history: model.cpuHistory.values)
                gauge("RAM", value: share, text: model.memory.map { formatBytes(Double($0.used), binary: true) }, history: nil)
                VStack(alignment: .leading, spacing: 3) {
                    Label(text: model.interface ?? "offline")
                    Text("↓ \(model.download.map { formatBytes($0, perSecond: true) } ?? "…")").foregroundStyle(Tok.accent)
                    Text("↑ \(model.upload.map { formatBytes($0, perSecond: true) } ?? "…")").foregroundStyle(Tok.hot)
                }
                .font(Tok.mono(10, .semibold)).lineLimit(1).frame(minWidth: 90, alignment: .leading)
                Spark(values: model.netHistory.values, color: Tok.hot).frame(height: 26)
                if let storage = model.storage {
                    let used = Double(storage.total - storage.available) / Double(storage.total)
                    bar("DISK", "\(Int((used * 100).rounded()))%", used, used > 0.9 ? Tok.warn : Tok.accent)
                }
                if let battery = model.battery {
                    let low = battery.percent < 15 && !battery.onAC
                    bar(battery.charging ? "BAT ⚡" : "BAT", "\(battery.percent)%", Double(battery.percent) / 100, low ? Tok.bad : Tok.ok)
                }
            }
        }
    }

    private func gauge(_ label: String, value: Double?, text: String?, history: [Double]?) -> some View {
        HStack(spacing: 8) {
            Ring(value: value, center: value.map { "\(Int(($0 * 100).rounded()))" } ?? "--", size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Label(text: label)
                Text(text ?? "…").font(Tok.mono(12, .semibold)).foregroundStyle(Tok.text).lineLimit(1)
                if let history { Spark(values: history).frame(width: 54, height: 12) }
            }
        }
    }

    private func bar(_ label: String, _ text: String, _ value: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Label(text: label); Spacer(); Text(text).font(Tok.mono(10, .semibold)).foregroundStyle(Tok.text) }
            Meter(value: value, color: color)
        }
        .frame(width: 70)
    }
}

struct MessagesCard: View {
    @ObservedObject var model: HudModel
    var messages: [Message] { model.messages }
    var body: some View {
        Card(title: "Messages", action: { model.openMessagesPanel() }) {
            if messages.isEmpty {
                Text("NO MESSAGES").font(Tok.mono(11)).foregroundStyle(Tok.off)
            }
            ForEach(messages, id: \.id) { message in
                HStack(spacing: 10) {
                    if let icon = message.appIcon {
                        Image(nsImage: icon).resizable().frame(width: 26, height: 26)
                    } else {
                        Image(systemName: "checkmark.square.fill").font(.system(size: 22)).foregroundStyle(Tok.ok)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(message.title.uppercased()).font(Tok.mono(12, .semibold)).foregroundStyle(Tok.text).lineLimit(1)
                        Text([message.subtitle, message.body].filter { !$0.isEmpty }.joined(separator: " — "))
                            .font(Tok.sans(11)).foregroundStyle(Tok.dim).lineLimit(1)
                    }
                    Spacer()
                    Text(message.date, style: .relative).font(Tok.mono(9)).foregroundStyle(Tok.dim)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 7).fill(Tok.elevated))
                .hover(7) { model.open(app: message.app) }
            }
        }
    }
}

struct LaunchCard: View {
    let apps: [AppEntry]
    var body: some View {
        Card(title: "Quick Launch") {
            HStack(spacing: 12) {
                ForEach(apps, id: \.id) { app in
                    LaunchIcon(app: app)
                }
                Spacer()
            }
        }
    }
}

struct LaunchIcon: View {
    let app: AppEntry
    @State private var over = false
    private let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 34, height: 34)
                .padding(5)
                .background(RoundedRectangle(cornerRadius: 8).fill(over ? Tok.accent.opacity(0.18) : Tok.elevated))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Tok.accent.opacity(over ? 0.9 : 0.15), lineWidth: 1))
                .scaleEffect(over && !still ? 1.12 : 1)
                .offset(y: over && !still ? -3 : 0)
            Text(app.name.uppercased()).font(Tok.mono(8, .semibold)).foregroundStyle(over ? Tok.accent : .clear).lineLimit(1).frame(width: 64)
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: over)
        .contentShape(Rectangle())
        .onHover { inside in over = inside; if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
        .onTapGesture { Apps.launch(app) }
        .help(app.name).accessibilityLabel("Launch \(app.name)").accessibilityAddTraits(.isButton)
    }
}

struct ConnectionsCard: View {
    @ObservedObject var model: HudModel
    @State private var open: String? // "wifi" or "bluetooth": its list is shown
    var body: some View {
        Card(title: "Connections") {
            HStack(spacing: 8) {
                TileView(symbol: "wifi", title: "Wi-Fi", tile: model.wifi, selected: open == "wifi", toggle: { model.toggleWifi() }) {
                    open = open == "wifi" ? nil : "wifi"
                    if open == "wifi" { model.loadKnownNetworks() }
                }
                TileView(symbol: "dot.radiowaves.left.and.right", title: "Bluetooth", tile: model.bluetooth, selected: open == "bluetooth") {
                    open = open == "bluetooth" ? nil : "bluetooth"
                    if open == "bluetooth" { model.loadDevices() }
                }
                TileView(symbol: "airplayaudio", title: "AirDrop", tile: model.airdrop, selected: false) { model.open(settings: "airdrop") }
            }
            if open == "wifi" {
                ListRows(title: "Known networks", rows: model.knownNetworks.map { ($0, $0, false) }, busy: model.busy,
                         empty: "NO KNOWN NETWORK", settings: { model.open(settings: "wifi") }) { model.join($0) }
            } else if open == "bluetooth" {
                ListRows(title: "Paired devices", rows: model.devices.map { ($0.id, $0.name, $0.connected) }, busy: model.busy,
                         empty: "NO PAIRED DEVICE", settings: { model.open(settings: "bluetooth") }) { id in
                    if let device = model.devices.first(where: { $0.id == id }) { model.toggle(device) }
                }
            }
        }
        .animation(.easeOut(duration: 0.18), value: open)
    }
}

/// Networks or devices: click one to join / connect (or disconnect a connected one).
struct ListRows: View {
    let title: String
    let rows: [(id: String, name: String, connected: Bool)]
    let busy: String?
    let empty: String
    let settings: () -> Void
    let pick: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(text: title)
            if rows.isEmpty { Text(empty).font(Tok.mono(10)).foregroundStyle(Tok.off) }
            ForEach(rows.prefix(6), id: \.id) { row in
                HStack {
                    Image(systemName: row.connected ? "checkmark.circle.fill" : "circle").foregroundStyle(row.connected ? Tok.ok : Tok.dim)
                    Text(row.name).font(Tok.sans(12)).foregroundStyle(Tok.text).lineLimit(1)
                    Spacer()
                    Text(busy == row.id ? "CONNECTING…" : row.connected ? "DISCONNECT" : "CONNECT").font(Tok.mono(8, .bold))
                        .foregroundStyle(busy == row.id ? Tok.warn : Tok.accent)
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6).fill(Tok.elevated))
                .hover(6) { if busy == nil { pick(row.id) } }
            }
            Text("SETTINGS…").font(Tok.mono(9, .bold)).foregroundStyle(Tok.dim).padding(.vertical, 3).hover(4, action: settings)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

/// One connection: icon, name, what the system says, the state in words (not color only).
struct TileView: View {
    let symbol: String
    let title: String
    let tile: Tile?
    let selected: Bool
    var toggle: (() -> Void)?
    let action: () -> Void
    var body: some View {
        let state = tile?.state
        let color = state == .on ? Tok.accent : state == .off ? Tok.dim : Tok.off
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(state == .on ? Tok.background : color)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 6).fill(state == .on ? Tok.accent : Tok.off.opacity(0.3)))
                    .shadow(color: state == .on ? Tok.accent.opacity(0.6) : .clear, radius: 5)
                Spacer()
                if let toggle, state != .unavailable {
                    Button(action: toggle) {
                        Capsule().fill(state == .on ? Tok.accent : Tok.off).frame(width: 26, height: 14)
                            .overlay(Circle().fill(Tok.text).frame(width: 10).offset(x: state == .on ? 6 : -6))
                            .animation(.easeOut(duration: 0.15), value: state)
                    }
                    .buttonStyle(.plain).help(state == .on ? "Turn \(title) off" : "Turn \(title) on")
                }
            }
            Text(title).font(Tok.sans(12, .semibold)).foregroundStyle(Tok.text)
            Text(tile?.detail ?? "…").font(Tok.mono(9)).foregroundStyle(color).lineLimit(1).truncationMode(.tail)
            Text(state == .on ? "ON" : state == .off ? "OFF" : state == nil ? "READING" : "UNAVAILABLE")
                .font(Tok.mono(8, .bold)).foregroundStyle(color.opacity(0.8))
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Tok.accent.opacity(0.16) : Tok.elevated))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Tok.accent.opacity(selected ? 0.8 : 0), lineWidth: 1))
        .hover(8, action: action)
    }
}

/// Drag the deck by its background (header, gaps between cards); double-click puts it
/// back on the right. Native window drag, like the media widget.
struct DragHandle: NSViewRepresentable {
    let reset: () -> Void
    func makeNSView(context: Context) -> NSView { Handle(reset: reset) }
    func updateNSView(_ view: NSView, context: Context) {}

    final class Handle: NSView {
        let reset: () -> Void
        init(reset: @escaping () -> Void) { self.reset = reset; super.init(frame: .zero) }
        required init?(coder: NSCoder) { nil }
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 { reset() } else { window?.performDrag(with: event) }
        }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    }
}
