import AppKit
import SwiftUI

// The HUD: `skyland-cyberdeck hud` toggles a translucent column on the right third
// of the screen under the mouse. esc or a click outside closes it, not the focus
// moving away (focus follows the mouse in skyland) (the process
// ends, so nothing is sampled while it is hidden); ← → change the calendar month.

final class HudApp: NSObject, NSApplicationDelegate {
    var panel: KeyPanel!
    let model = HudModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = KeyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .modalPanel
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false // stays when focus follows the mouse elsewhere
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // the deck reports its size from its own layout (no extra layout pass per update):
        // the window follows when it grows / shrinks (herdr agents, messages, lists)
        let scale = model.settings.scale
        let host = NSHostingView(rootView: ScaledDeck(scale: scale) { HudView(model: self.model) } onSize: { [weak self] size in self?.place(size) })
        panel.contentView = host
        model.resetPosition = { [weak self] in
            HudApp.defaults.removeObject(forKey: "hudTopLeft")
            if let self { self.place(self.panel.frame.size) }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
            guard let frame = self?.panel.frame else { return }
            HudApp.defaults.set(NSStringFromPoint(NSPoint(x: frame.minX, y: frame.maxY)), forKey: "hudTopLeft")
        }
        model.start()
        place(host.fittingSize) // once at open: an empty window gets no layout to report from

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            switch event.keyCode {
                case 53: exit(0) // esc
                case 123: self?.model.monthOffset -= 1; return nil // left
                case 124: self?.model.monthOffset += 1; return nil // right
                default: return event
            }
            return nil
        }
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in exit(0) }
        panel.alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { $0.duration = reduceMotion ? 0 : 0.18; panel.animator().alphaValue = 1 }
    }

    private lazy var screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]

    static let defaults = UserDefaults(suiteName: "com.waxdred.skyland-cyberdeck")!

    /// Where it was dragged last (its top-left corner stays put when it grows), else on
    /// the right of the screen it opened on, vertically centered.
    private func place(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let area = screen.visibleFrame
        let height = min(size.height, area.height - 16)
        var frame = NSRect(x: area.maxX - size.width - 16, y: area.midY - height / 2, width: size.width, height: height)
        if let saved = HudApp.defaults.string(forKey: "hudTopLeft").map(NSPointFromString),
           NSScreen.screens.contains(where: { $0.frame.insetBy(dx: -1, dy: -1).contains(saved) }) {
            frame.origin = NSPoint(x: saved.x, y: saved.y - height)
            // kept on screen: a bigger deck (scale, more rows) than when it was dragged there
            let visible = NSScreen.screens.first { $0.frame.insetBy(dx: -1, dy: -1).contains(saved) }?.visibleFrame ?? area
            frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        }
        if frame != panel.frame { panel.setFrame(frame, display: true) }
    }

    // Not closed when it loses focus: skyland's focus follows the mouse, so leaving
    // the deck would close it. A click anywhere outside does (global monitors only
    // see other apps' events).
}

private struct DeckSize: PreferenceKey {
    static let defaultValue = CGSize.zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

/// The deck at [hud] scale: laid out at its natural size, drawn scaled, and the
/// window sized to the scaled result.
struct ScaledDeck<Deck: View>: View {
    let scale: Double
    @ViewBuilder let deck: () -> Deck
    let onSize: (CGSize) -> Void
    @State private var natural = CGSize.zero
    var body: some View {
        deck()
            .environment(\.colorScheme, .dark)
            .fixedSize()
            .background(GeometryReader { Color.clear.preference(key: DeckSize.self, value: $0.size) })
            .onPreferenceChange(DeckSize.self) { size in
                natural = size
                onSize(CGSize(width: size.width * scale, height: size.height * scale))
            }
            .scaleEffect(scale, anchor: .topLeading)
            // unknown size yet: natural size, so the first layout happens and reports it
            .frame(width: natural == .zero ? nil : natural.width * scale, height: natural == .zero ? nil : natural.height * scale, alignment: .topLeading)
    }
}
