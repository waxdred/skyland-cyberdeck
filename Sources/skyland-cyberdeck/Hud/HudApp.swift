import AppKit
import Combine
import SwiftUI

// The HUD: `skyland-cyberdeck hud` toggles a translucent column on the right third
// of the screen under the mouse. esc or a click outside closes it (the process
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
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let host = NSHostingView(rootView: HudView(model: model).environment(\.colorScheme, .dark))
        panel.contentView = host
        model.start()
        place()
        // the deck grows / shrinks with its content (herdr agents, messages)
        sizeWatch = model.objectWillChange.sink { [weak self] _ in DispatchQueue.main.async { self?.place() } }

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            switch event.keyCode {
                case 53: exit(0) // esc
                case 123: self?.model.monthOffset -= 1; return nil // left
                case 124: self?.model.monthOffset += 1; return nil // right
                default: return event
            }
            return nil
        }
        panel.alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { $0.duration = reduceMotion ? 0 : 0.18; panel.animator().alphaValue = 1 }
    }

    private var sizeWatch: Any?

    /// Content size, on the right of the screen under the mouse, vertically centered.
    private func place() {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
        let area = screen.visibleFrame
        let size = panel.contentView?.fittingSize ?? .zero
        let height = min(size.height, area.height - 16)
        let frame = NSRect(x: area.maxX - size.width - 16, y: area.midY - height / 2, width: size.width, height: height)
        if frame != panel.frame { panel.setFrame(frame, display: true) }
    }

    func applicationDidResignActive(_ notification: Notification) { exit(0) }
}
