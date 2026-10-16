import AppKit

// Messages panel: a see-through column of contact cards on the right of the
// screen under the mouse, newest first, refreshed while open. ↑ ↓ / scroll to
// move, return or click opens the app, x dismisses, shift-x dismisses all, esc
// closes. Toast: the popup a `notify` call shows top right for a few seconds.

private let timeFormat: DateFormatter = {
    let format = DateFormatter()
    format.dateFormat = "HH:mm"
    return format
}()

private func stamp(_ date: Date) -> String {
    Calendar.current.isDateInToday(date) ? timeFormat.string(from: date) : DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .none)
}

/// One message card (flipped coordinates), shared by the panel and the toast.
func drawCard(_ message: Message, in rect: NSRect, focus: Bool, alpha: CGFloat) {
    let path = chamfered(rect, cut: 12)
    Neon.ink.withAlphaComponent(0.38 * alpha).setFill()
    path.fill()
    if focus {
        Neon.red.withAlphaComponent(0.18 * alpha).setFill()
        path.fill()
        neonStroke(path, color: Neon.red, width: 1.5, glow: 12, alpha: alpha)
    } else {
        Neon.cyan.withAlphaComponent(0.35 * alpha).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
    // accent bar: red for api messages, cyan for macOS ones
    (message.source == "api" ? Neon.red : Neon.cyan).withAlphaComponent(alpha).setFill()
    NSRect(x: rect.minX + 6, y: rect.minY + 14, width: 2, height: rect.height - 28).fill()

    let icon = rect.minX + 18
    if let image = message.appIcon {
        image.draw(in: NSRect(x: icon, y: rect.minY + 12 * Neon.scale, width: 30 * Neon.scale, height: 30 * Neon.scale), from: .zero, operation: .sourceOver,
                   fraction: alpha, respectFlipped: true, hints: nil)
    } else {
        neonText("◆", at: NSPoint(x: icon + 6, y: rect.minY + 14), font: Neon.title(20), color: Neon.red, glow: 6, alpha: alpha)
    }
    let text = icon + 42 * Neon.scale, width = rect.maxX - text - 14
    neonText(Neon.caps(message.appName), at: NSPoint(x: text, y: rect.minY + 10 * Neon.scale), font: Neon.mono(11, .bold), color: Neon.cyan, glow: 2, alpha: alpha, kern: 1)
    neonText(stamp(message.date), at: NSPoint(x: rect.maxX - 54 * Neon.scale, y: rect.minY + 10 * Neon.scale), font: Neon.mono(11), color: Neon.yellow, glow: 0, alpha: 0.9 * alpha)
    let title = [message.title, message.subtitle].filter { !$0.isEmpty }.joined(separator: " — ")
    clipped(title, NSRect(x: text, y: rect.minY + 26 * Neon.scale, width: width, height: 20 * Neon.scale), Neon.title(17, .bold), .white, alpha, lines: 1)
    clipped(message.body, NSRect(x: text, y: rect.minY + 48 * Neon.scale, width: width, height: rect.height - 56 * Neon.scale), Neon.mono(12), Neon.cyan, alpha * 0.95, lines: 2)
}

private func clipped(_ text: String, _ rect: NSRect, _ font: NSFont, _ color: NSColor, _ alpha: CGFloat, lines: Int) {
    let style = NSMutableParagraphStyle()
    style.lineBreakMode = .byTruncatingTail
    let halo = NSShadow()
    halo.shadowColor = Neon.ink.withAlphaComponent(0.9 * alpha)
    halo.shadowBlurRadius = 4
    halo.shadowOffset = .zero
    let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color.withAlphaComponent(alpha),
                                                                   .paragraphStyle: style, .shadow: halo])
    let height = min(rect.height, font.boundingRectForFont.height * CGFloat(lines))
    attributed.draw(with: NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: height),
                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
}

final class MessagesView: NSView {
    let cardHeight = Config.number("messages.card-height", 92), width = Config.number("messages.width", 470)
    var messages: [Message] = [] { didSet { selected = min(selected, max(0, messages.count - 1)); needsDisplay = true } }
    var selected = 0 { didSet { needsDisplay = true } }
    private var top = 0 // first visible card

    override var isFlipped: Bool { true }

    var column: NSRect { NSRect(x: bounds.maxX - width - 60, y: 70, width: width, height: bounds.height - 140) }
    var visibleCount: Int { max(1, Int((column.height - 110 * Neon.scale) / (cardHeight + 10))) }

    func reload() { messages = Messages.list() }

    func move(_ delta: Int) {
        guard !messages.isEmpty else { return }
        selected = max(0, min(messages.count - 1, selected + delta))
    }

    func cardRect(_ position: Int) -> NSRect {
        NSRect(x: column.minX + CGFloat(position) * 4, y: column.minY + 96 * Neon.scale + CGFloat(position) * (cardHeight + 10), width: width, height: cardHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        Neon.ink.withAlphaComponent(0.08 * Neon.tint).setFill()
        bounds.fill()
        scanlines(bounds, color: .black, alpha: 0.08)
        NSGradient(starting: .clear, ending: Neon.red.withAlphaComponent(0.14 * Neon.tint))!
            .draw(in: NSRect(x: bounds.width * 0.5, y: 0, width: bounds.width * 0.5, height: bounds.height), angle: 0)

        let column = self.column
        neonText(Config.string("messages.title", "MESSAGES"), at: NSPoint(x: column.minX, y: column.minY), font: Neon.title(56), color: Neon.red, glow: 14, kern: 3)
        neonText(Config.string("messages.subtitle", "// {count} IN BUFFER").replacingOccurrences(of: "{count}", with: "\(messages.count)"), at: NSPoint(x: column.minX + 4, y: column.minY + 66 * Neon.scale), font: Neon.mono(12, .semibold), color: Neon.cyan, glow: 4)
        Neon.red.withAlphaComponent(0.6).setFill()
        NSRect(x: column.minX, y: column.minY + 86 * Neon.scale, width: width, height: 1.5).fill()

        if selected < top { top = selected }
        if selected >= top + visibleCount { top = selected - visibleCount + 1 }
        for position in 0 ..< visibleCount {
            let index = top + position
            guard messages.indices.contains(index) else { break }
            drawCard(messages[index], in: cardRect(position), focus: index == selected, alpha: 1)
        }
        if messages.isEmpty {
            neonText("// NO MESSAGES", at: NSPoint(x: column.minX, y: column.minY + 110 * Neon.scale), font: Neon.mono(16, .bold), color: Neon.cyan, glow: 6)
        }
        let footer = "↑ ↓  move    ↩  open app    X  dismiss    ⇧X  dismiss all    ESC  close"
        if Neon.footer { neonText(footer, at: NSPoint(x: column.minX, y: column.maxY + 20), font: Neon.mono(11, .semibold), color: Neon.cyan, glow: 0, alpha: 0.9) }
    }

    func open(_ message: Message) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: message.app) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in exit(0) }
        } else {
            exit(0)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        scroll += event.scrollingDeltaY
        let step: CGFloat = event.hasPreciseScrollingDeltas ? 30 : 1
        while abs(scroll) >= step {
            move(scroll > 0 ? -1 : 1)
            scroll -= scroll > 0 ? step : -step
        }
    }
    private var scroll: CGFloat = 0

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        for position in 0 ..< visibleCount where messages.indices.contains(top + position) && cardRect(position).contains(point) {
            if top + position == selected { open(messages[selected]) } else { selected = top + position }
            return
        }
        exit(0)
    }
}

final class MessagesApp: NSObject, NSApplicationDelegate {
    var panel: KeyPanel!
    let view = MessagesView()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
        panel = KeyPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .modalPanel
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        view.frame = NSRect(origin: .zero, size: screen.frame.size)
        panel.contentView = view
        view.reload()
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.view.reload() } // new ones while open

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.key(event) == true ? nil : event
        }
        panel.alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.18; panel.animator().alphaValue = 1 }
    }

    func applicationDidResignActive(_ notification: Notification) { exit(0) }

    private func key(_ event: NSEvent) -> Bool {
        switch event.keyCode {
            case 53: exit(0) // esc
            case 36, 76: if view.messages.indices.contains(view.selected) { view.open(view.messages[view.selected]) }
            case 125: view.move(1)
            case 126: view.move(-1)
            case 7, 51: // x, delete
                if event.modifierFlags.contains(.shift) {
                    Messages.dismissAll()
                } else if view.messages.indices.contains(view.selected) {
                    Messages.dismiss(view.messages[view.selected].id)
                }
                view.reload()
            default: return false
        }
        return true
    }
}

/// Popup for a `notify` call: top right of the screen under the mouse, stacked
/// under the toasts already shown, glitches in, fades out after `seconds`.
final class ToastApp: NSObject, NSApplicationDelegate {
    let message: Message
    let seconds: Double
    var panel: NSPanel!
    private var flicker = 0

    init(_ message: Message, seconds: Double) {
        self.message = message
        self.seconds = seconds
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let size = NSSize(width: Config.number("toast.width", 400), height: Config.number("messages.card-height", 92) + 4)
        let slot = ToastSlots.claim()
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
        let frame = NSRect(x: screen.visibleFrame.maxX - size.width - 16,
                           y: screen.visibleFrame.maxY - 16 - CGFloat(slot + 1) * (size.height + 10), width: size.width, height: size.height)
        panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        let view = ToastView(frame: NSRect(origin: .zero, size: size))
        view.message = message
        view.onClick = { exit(0) }
        panel.contentView = view
        panel.orderFrontRegardless()
        // glitch in: a few random flashes, then steady
        Timer.scheduledTimer(withTimeInterval: 0.045, repeats: true) { [weak self] timer in
            guard let self else { return }
            self.flicker += 1
            self.panel.alphaValue = self.flicker > 7 ? 1 : (Bool.random() ? 1 : 0.25)
            if self.flicker > 7 { timer.invalidate() }
        }
        Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.35; self.panel.animator().alphaValue = 0 }) { exit(0) }
        }
    }
}

final class ToastView: NSView {
    var message: Message!
    var onClick: () -> Void = {}
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) { drawCard(message, in: bounds.insetBy(dx: 4, dy: 4), focus: true, alpha: 1) }
    override func mouseDown(with event: NSEvent) { onClick() }
}

/// Slots of the toasts on screen: one pid file per slot, a dead pid frees it.
enum ToastSlots {
    static let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "skyland-cyberdeck-toasts")

    static func claim() -> Int {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for slot in 0 ..< 6 {
            let file = dir.appending(path: "\(slot)")
            if let pid = (try? String(contentsOf: file, encoding: .utf8)).flatMap({ pid_t($0) }), kill(pid, 0) == 0 { continue }
            try? String(getpid()).write(to: file, atomically: true, encoding: .utf8)
            return slot
        }
        return 0
    }
}
