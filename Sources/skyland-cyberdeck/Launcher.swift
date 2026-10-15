import AppKit
import QuartzCore

// Apps launcher: a tilted neon deck over a dimmed screen. A curved column of app
// rows around the selected one, type to search, arrows / scroll to move, return
// or click to launch, esc to close. The selection flickers when it changes.

final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class LauncherView: NSView {
    static let visible = 9
    let rowHeight: CGFloat = 50, rowWidth: CGFloat = 430, curve: CGFloat = 46

    var apps: [AppEntry] = []
    var shown: [AppEntry] = []
    var query = "" { didSet { refilter() } }
    var selected = 0 { didSet { if selected != oldValue { flicker() } } }
    private var flickerAlpha: CGFloat = 1
    private var flickerTimer: Timer?
    private var cursorOn = true
    private var icons: [String: (plain: NSImage, dim: NSImage)] = [:]

    override var isFlipped: Bool { true }

    func refilter() {
        shown = Apps.search(apps, query)
        selected = 0
        needsDisplay = true
    }

    func move(_ delta: Int) {
        guard !shown.isEmpty else { return }
        selected = (selected + delta + shown.count) % shown.count
        needsDisplay = true
    }

    func blink() { cursorOn.toggle(); needsDisplay = true }

    private func flicker() {
        flickerTimer?.invalidate()
        var steps = 6
        flickerTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            steps -= 1
            self.flickerAlpha = steps <= 0 ? 1 : (Double.random(in: 0 ... 1) < 0.5 ? 0.35 : 1)
            if steps <= 0 { timer.invalidate() }
            self.needsDisplay = true
        }
    }

    private func icon(_ app: AppEntry) -> (plain: NSImage, dim: NSImage) {
        if let cached = icons[app.id] { return cached }
        let plain = NSWorkspace.shared.icon(forFile: app.url.path)
        let pair = (plain, tinted(plain, Neon.cyan, amount: 0.55))
        icons[app.id] = pair
        return pair
    }

    /// Row frame for an offset from the selected row (deck coordinates).
    func rowRect(_ offset: Int, in deck: NSRect) -> NSRect {
        let d = CGFloat(offset)
        let x = deck.minX + curve * (d * d) / 8 // the column bends away from the selection
        let y = deck.midY - rowHeight / 2 + d * rowHeight
        let scale = 1 - abs(d) * 0.035
        return NSRect(x: x, y: y + (1 - scale) * rowHeight / 2, width: rowWidth * scale, height: (rowHeight - 10) * scale)
    }

    var deck: NSRect { NSRect(x: bounds.width * 0.12, y: bounds.midY - 60, width: rowWidth + 200, height: 120) }

    override func draw(_ dirtyRect: NSRect) {
        // eye implant overlay: the screen stays visible behind a light tint,
        // scanlines and a red vignette on the left
        Neon.ink.withAlphaComponent(0.22).setFill()
        bounds.fill()
        scanlines(bounds, color: .black, alpha: 0.14)
        NSGradient(starting: Neon.red.withAlphaComponent(0.14), ending: .clear)!
            .draw(in: NSRect(x: 0, y: 0, width: bounds.width * 0.55, height: bounds.height), angle: 0)

        let deck = self.deck
        let left = deck.minX
        // HUD tilt: the deck rises slightly to the right
        let tilt = NSAffineTransform()
        tilt.translateX(by: left, yBy: deck.midY)
        tilt.transformStruct.m12 = -0.06
        tilt.translateX(by: -left, yBy: -deck.midY)
        NSGraphicsContext.saveGraphicsState()
        tilt.concat()
        // header
        neonText("APPS", at: NSPoint(x: left, y: deck.minY - 372), font: Neon.title(76), color: Neon.red, glow: 16, kern: 4)
        neonText("// NETRUNNER DECK — ONLINE", at: NSPoint(x: left + 4, y: deck.minY - 282), font: Neon.mono(13, .semibold), color: Neon.cyan, glow: 6, alpha: 0.9)
        Neon.red.withAlphaComponent(0.6).setFill()
        NSRect(x: left, y: deck.minY - 256, width: rowWidth, height: 1.5).fill()
        // search line
        let prompt = "> " + (query.isEmpty ? "" : query.uppercased()) + (cursorOn ? "_" : " ")
        neonText(prompt, at: NSPoint(x: left, y: deck.minY - 242), font: Neon.mono(20, .bold), color: Neon.yellow, glow: 8)
        if query.isEmpty {
            neonText("TYPE TO SEARCH", at: NSPoint(x: left + 48, y: deck.minY - 238), font: Neon.mono(14), color: Neon.yellow, glow: 0, alpha: 0.7)
        }
        neonText("\(shown.count) / \(apps.count)", at: NSPoint(x: left + rowWidth - 70, y: deck.minY - 238), font: Neon.mono(12), color: Neon.cyan, glow: 0, alpha: 0.9)

        // rows, far ones first so the selection is on top
        let half = Self.visible / 2
        let offsets = (-half ... half).sorted { abs($0) > abs($1) }
        for offset in offsets {
            guard let index = rowIndex(offset) else { continue }
            drawRow(shown[index], index: index, offset: offset, rect: rowRect(offset, in: deck))
        }
        if shown.isEmpty {
            neonText("// NO MATCH", at: NSPoint(x: left, y: deck.midY - 12), font: Neon.mono(18, .bold), color: Neon.red, glow: 8)
        }

        NSGraphicsContext.restoreGraphicsState()
        // footer
        let footer = "TYPE  search      ↑ ↓ / SCROLL  move      ↩ / CLICK  launch      ESC  close"
        neonText(footer, at: NSPoint(x: left, y: bounds.maxY - 60), font: Neon.mono(11, .semibold), color: Neon.cyan, glow: 0, alpha: 0.9)
    }

    /// Index of the row `offset` away from the selection: the list wraps like a wheel
    /// once it fills the column, else rows past the ends are empty.
    func rowIndex(_ offset: Int) -> Int? {
        guard !shown.isEmpty else { return nil }
        if shown.count >= Self.visible { return ((selected + offset) % shown.count + shown.count) % shown.count }
        return shown.indices.contains(selected + offset) ? selected + offset : nil
    }

    private func drawRow(_ app: AppEntry, index: Int, offset: Int, rect: NSRect) {
        let focus = offset == 0
        let fade = max(0.5, 1 - CGFloat(abs(offset)) * 0.12) * (focus ? flickerAlpha : 1)
        let path = chamfered(rect, cut: 10)
        if focus {
            Neon.ink.withAlphaComponent(0.5 * fade).setFill()
            path.fill()
            Neon.red.withAlphaComponent(0.20 * fade).setFill()
            path.fill()
            neonStroke(path, color: Neon.red, width: 1.6, glow: 12, alpha: fade)
            // corner ticks
            Neon.yellow.withAlphaComponent(fade).setFill()
            NSRect(x: rect.maxX - 26, y: rect.minY - 4, width: 22, height: 2).fill()
            NSRect(x: rect.minX - 6, y: rect.maxY - 12, width: 2, height: 12).fill()
        } else {
            Neon.ink.withAlphaComponent(0.6 * fade).setFill() // keeps the label readable over any window
            path.fill()
            Neon.cyan.withAlphaComponent(0.05 * fade).setFill()
            path.fill()
            Neon.cyan.withAlphaComponent(0.35 * fade).setStroke()
            path.lineWidth = 1
            path.stroke()
        }
        let iconSize = rect.height - 10
        let images = icon(app)
        (focus ? images.plain : images.dim).draw(in: NSRect(x: rect.minX + 12, y: rect.minY + 5, width: iconSize, height: iconSize),
                                                 from: .zero, operation: .sourceOver, fraction: fade, respectFlipped: true, hints: nil)
        let font = Neon.title(focus ? 21 : 17, focus ? .bold : .semibold)
        let textY = rect.midY - font.capHeight / 2 - (font.ascender - font.capHeight)
        neonText(app.name.uppercased(), at: NSPoint(x: rect.minX + iconSize + 24, y: textY), font: font,
                 color: focus ? NSColor.white : Neon.cyan, glow: focus ? 10 : 3, alpha: min(1, fade + 0.2), kern: 1.5)
        let tag = String(format: "0x%02X", index)
        neonText(tag, at: NSPoint(x: rect.maxX - 52, y: rect.midY - 7), font: Neon.mono(11), color: focus ? Neon.red : Neon.cyan, glow: 0, alpha: 0.7 * fade)
    }

    // MARK: mouse

    override func scrollWheel(with event: NSEvent) {
        scrollAccumulator += event.scrollingDeltaY
        let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 24 : 1
        while abs(scrollAccumulator) >= threshold {
            move(scrollAccumulator > 0 ? -1 : 1)
            scrollAccumulator -= scrollAccumulator > 0 ? threshold : -threshold
        }
    }
    private var scrollAccumulator: CGFloat = 0

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let half = Self.visible / 2
        // undo the tilt: m12 shears y by x around (deck.minX, deck.midY)
        let deck = self.deck
        let flat = NSPoint(x: point.x, y: point.y + 0.06 * (point.x - deck.minX))
        for offset in -half ... half where rowIndex(offset) != nil {
            if rowRect(offset, in: deck).insetBy(dx: -4, dy: -4).contains(flat) {
                if offset == 0 { Apps.launch(shown[selected]) } else { move(offset) }
                return
            }
        }
        exit(0) // click outside the deck
    }
}

final class LauncherApp: NSObject, NSApplicationDelegate {
    var panel: KeyPanel!
    let view = LauncherView()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
        panel = KeyPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .modalPanel
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        view.frame = NSRect(origin: .zero, size: screen.frame.size)
        panel.contentView = view
        view.apps = Apps.all()
        view.refilter()

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.key(event) == true ? nil : event
        }
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.view.blink() }
        // slide in from the left with a fade
        panel.alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }
    }

    func applicationDidResignActive(_ notification: Notification) { exit(0) }

    private func key(_ event: NSEvent) -> Bool {
        switch event.keyCode {
            case 53: exit(0) // esc
            case 36, 76: if view.shown.indices.contains(view.selected) { Apps.launch(view.shown[view.selected]) } // return
            case 125: view.move(1) // down
            case 126: view.move(-1) // up
            case 51: if !view.query.isEmpty { view.query.removeLast() } // delete
            default:
                guard let chars = event.characters, !event.modifierFlags.contains(.command),
                      chars.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == " " || $0 == "-" || $0 == "." })
                else { return false }
                view.query += chars
        }
        return true
    }
}
