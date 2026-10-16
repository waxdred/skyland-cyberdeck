import AppKit
import CoreAudio
import SwiftUI

/// Design tokens of the HUD, every color of the HUD comes from here. The palette is
/// [hud] theme (netrunner by default, `skyland` follows the skyland theme) with the
/// [colors] overrides; surfaces are the ink tinted with the accent; states are fixed.
enum Tok {
    private static let theme = Theme.load(named: HudSettings.load().theme)
    private static let accentNS = Config.color("colors.primary") ?? theme.primary
    private static let inkNS = Config.color("colors.ink") ?? theme.ink
    static let accent = Color(nsColor: accentNS)                                     // active states, frame, values
    static let label = Color(nsColor: Config.color("colors.secondary") ?? theme.secondary) // micro labels
    static let hot = Color(nsColor: Config.color("colors.highlight") ?? theme.highlight)   // upload, alerts
    static let background = Color(nsColor: inkNS)
    static let surface = Color(nsColor: inkNS.blended(withFraction: 0.07, of: accentNS) ?? inkNS)
    static let elevated = Color(nsColor: inkNS.blended(withFraction: 0.13, of: accentNS) ?? inkNS)
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
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title { Text(title.uppercased()).font(Tok.mono(10, .semibold)).foregroundStyle(Tok.accent).kerning(1.6) }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 9).fill(elevated ? Tok.elevated : Tok.surface))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Tok.accent.opacity(0.22), lineWidth: 1))
    }
}

/// Glowing corner brackets around the whole deck.
struct DeckFrame: Shape {
    var arm: CGFloat = 34
    func path(in r: CGRect) -> Path {
        Path { p in
            for (corner, dx, dy) in [(CGPoint(x: r.minX, y: r.minY), 1.0, 1.0), (CGPoint(x: r.maxX, y: r.minY), -1.0, 1.0),
                                     (CGPoint(x: r.minX, y: r.maxY), 1.0, -1.0), (CGPoint(x: r.maxX, y: r.maxY), -1.0, -1.0)] {
                p.move(to: CGPoint(x: corner.x + dx * arm, y: corner.y))
                p.addLine(to: corner)
                p.addLine(to: CGPoint(x: corner.x, y: corner.y + dy * arm))
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
    var body: some View {
        ZStack {
            Circle().stroke(Tok.off.opacity(0.5), lineWidth: 3)
            Circle().trim(from: 0, to: value ?? 0).stroke(Tok.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90)).shadow(color: Tok.accent.opacity(0.7), radius: 4)
            Text(center).font(Tok.mono(15, .semibold)).foregroundStyle(Tok.text)
        }
        .frame(width: 56, height: 56)
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
            row(left: shows("clock") ? AnyView(ClockCard(settings: model.settings)) : nil,
                right: shows("calendar") ? AnyView(CalendarCard(model: model)) : nil)
            row(left: shows("herdr") ? AnyView(HerdrCard(state: model.herdr)) : nil,
                right: shows("sound") ? AnyView(SoundCard(model: model)) : nil)
            if shows("system") { SystemCard(model: model) }
            if shows("messages") { MessagesCard(messages: model.messages) }
            if shows("launch") && !model.launchApps.isEmpty { LaunchCard(apps: model.launchApps) }
            Text("ESC close     ← → month     a click outside closes").font(Tok.mono(9)).foregroundStyle(Tok.off)
        }
        .padding(20)
        .frame(width: 760)
        .background(RoundedRectangle(cornerRadius: 16).fill(Tok.background.opacity(model.settings.opacity)))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16)) // blur what is behind
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Tok.accent.opacity(0.3), lineWidth: 1))
        .overlay(DeckFrame().stroke(Tok.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round)).shadow(color: Tok.accent, radius: 6))
        .padding(8)
    }

    /// two cards side by side, the right one at the calendar width
    @ViewBuilder private func row(left: AnyView?, right: AnyView?) -> some View {
        if left != nil || right != nil {
            HStack(alignment: .top, spacing: 12) {
                if let left { left }
                if let right { right.frame(width: 310) }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ClockCard: View {
    let settings: HudSettings
    var body: some View {
        Card {
            TimelineView(.periodic(from: .now, by: 1)) { context in
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
        return Card {
            HStack {
                Text(month.formatted(.dateTime.month(.abbreviated).year()).uppercased())
                    .font(Tok.mono(15, .semibold)).foregroundStyle(Tok.accent).kerning(1.5)
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
                        .accessibilityLabel(day.map { $0.formatted(date: .complete, time: .omitted) + (today ? ", today" : "") } ?? "")
                }
            }
        }
    }
}

struct HerdrCard: View {
    let state: HerdrState?
    var body: some View {
        Card(title: "Herdr // Agents") {
            switch state {
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
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text("● CONNECTED   UPDATED \(max(0, Int(context.date.timeIntervalSince(date))))s AGO")
                            .font(Tok.mono(9, .semibold)).foregroundStyle(Tok.ok)
                    }
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
        Card(title: "Display & Sound") {
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
        Card(title: "System") {
            HStack(alignment: .top, spacing: 12) {
                HStack(spacing: 10) {
                    Ring(value: model.cpu, center: model.cpu.map { "\(Int(($0 * 100).rounded()))" } ?? "--")
                    VStack(alignment: .leading, spacing: 2) {
                        Label(text: "CPU")
                        Text(model.cpu.map { "\(Int(($0 * 100).rounded()))%" } ?? "…").font(Tok.mono(16, .semibold)).foregroundStyle(Tok.text)
                        Spark(values: model.cpuHistory.values).frame(height: 22)
                    }
                }
                .frame(maxWidth: .infinity)
                HStack(spacing: 10) {
                    let share = model.memory.map { Double($0.used) / Double($0.total) }
                    Ring(value: share, center: share.map { "\(Int(($0 * 100).rounded()))" } ?? "--")
                    VStack(alignment: .leading, spacing: 2) {
                        Label(text: "RAM")
                        Text(model.memory.map { formatBytes(Double($0.used), binary: true) } ?? "…").font(Tok.mono(16, .semibold)).foregroundStyle(Tok.text)
                        Text(model.memory.map { "OF \(formatBytes(Double($0.total), binary: true))" } ?? "").font(Tok.mono(9)).foregroundStyle(Tok.dim)
                    }
                }
                .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 4) {
                    Label(text: "Network \(model.interface ?? "offline")")
                    HStack(spacing: 10) {
                        Text("↓ \(model.download.map { formatBytes($0, perSecond: true) } ?? "…")").foregroundStyle(Tok.accent)
                        Text("↑ \(model.upload.map { formatBytes($0, perSecond: true) } ?? "…")").foregroundStyle(Tok.hot)
                    }
                    .font(Tok.mono(11, .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                    Spark(values: model.netHistory.values, color: Tok.hot).frame(height: 22)
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 7).fill(Tok.elevated))
                VStack(alignment: .leading, spacing: 6) {
                    if let storage = model.storage {
                        let used = Double(storage.total - storage.available)
                        Label(text: "Storage")
                        Text("\(formatBytes(used)) / \(formatBytes(Double(storage.total)))").font(Tok.mono(11, .semibold)).foregroundStyle(Tok.text)
                        Meter(value: used / Double(storage.total), color: used / Double(storage.total) > 0.9 ? Tok.warn : Tok.accent)
                    }
                    if let battery = model.battery {
                        let low = battery.percent < 15 && !battery.onAC
                        Label(text: battery.charging ? "Battery charging" : battery.onAC ? "Battery on AC" : "Battery")
                        Text("\(battery.percent)%" + (battery.minutesLeft.map { "  \($0 / 60)h\(String(format: "%02d", $0 % 60))" } ?? ""))
                            .font(Tok.mono(11, .semibold)).foregroundStyle(low ? Tok.bad : Tok.text)
                        Meter(value: Double(battery.percent) / 100, color: low ? Tok.bad : Tok.ok)
                    }
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 7).fill(Tok.elevated))
            }
        }
    }
}

struct MessagesCard: View {
    let messages: [Message]
    var body: some View {
        Card(title: "Messages") {
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
                    Button { Apps.launch(app) } label: {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 34, height: 34)
                            .padding(5).background(RoundedRectangle(cornerRadius: 8).fill(Tok.elevated))
                    }
                    .buttonStyle(.plain).help(app.name).accessibilityLabel("Launch \(app.name)")
                }
                Spacer()
            }
        }
    }
}
