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
        let root = HudView(model: model).environment(\.colorScheme, .dark).fixedSize()
            .background(GeometryReader { Color.clear.preference(key: DeckSize.self, value: $0.size) })
            .onPreferenceChange(DeckSize.self) { [weak self] size in self?.place(size) }
        let host = NSHostingView(rootView: root)
        panel.contentView = host
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

    /// Deck size, on the right of the screen it opened on, vertically centered.
    private func place(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let area = screen.visibleFrame
        let height = min(size.height, area.height - 16)
        let frame = NSRect(x: area.maxX - size.width - 16, y: area.midY - height / 2, width: size.width, height: height)
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
