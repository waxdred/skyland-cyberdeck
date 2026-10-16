import AppKit
import SwiftUI

// The audio deck: `skyland-cyberdeck audio` toggles it in the middle of the screen
// under the mouse. esc or a click outside closes it (the process ends: no capture, no
// now playing stream while it is closed). space play / pause, ← → previous / next,
// ↑ ↓ volume, m mute, 1-9 output port.

final class AudioDeckApp: NSObject, NSApplicationDelegate {
    var panel: KeyPanel!
    let model = AudioDeckModel()

    static let positionKey = "audioTopLeft"

    func applicationDidFinishLaunching(_ notification: Notification) {
        Tok.use(theme: model.settings.theme, cardOpacity: model.settings.cardOpacity) // [audio], before a card reads it
        panel = KeyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .modalPanel
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false // stays when focus follows the mouse elsewhere
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let scale = model.settings.scale
        let host = NSHostingView(rootView: ScaledDeck(scale: scale) { AudioDeckView(model: self.model) } onSize: { [weak self] size in self?.place(size) })
        panel.contentView = host
        model.resetPosition = { [weak self] in
            HudApp.defaults.removeObject(forKey: AudioDeckApp.positionKey)
            if let self { self.place(self.panel.frame.size) }
        }
        // remembered when the user moves it, not when the deck places itself
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: nil) { [weak self] _ in
            guard let self, !self.placing else { return }
            HudApp.defaults.set(NSStringFromPoint(NSPoint(x: self.panel.frame.minX, y: self.panel.frame.maxY)), forKey: AudioDeckApp.positionKey)
        }
        model.start()
        let natural = host.fittingSize
        place(CGSize(width: natural.width * scale, height: natural.height * scale))

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            (self?.key(event) ?? false) ? nil : event
        }
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in exit(0) }
        panel.alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { $0.duration = reduceMotion ? 0 : 0.18; panel.animator().alphaValue = 1 }
    }

    /// The deck's keys; false: not one of them (the event goes on).
    private func key(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        if event.isARepeat, event.keyCode != 125, event.keyCode != 126 { return true } // held: only the volume repeats
        switch event.keyCode {
            case 53: exit(0) // esc
            case 49: model.togglePlay() // space
            case 123: model.previous() // left
            case 124: model.next() // right
            case 126: model.nudgeVolume(1) // up
            case 125: model.nudgeVolume(-1) // down
            default:
                let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
                if key == "m" {
                    model.toggleMute()
                } else if let digit = Int(key), (1 ... 9).contains(digit) {
                    model.select(port: digit)
                } else {
                    return false
                }
        }
        return true
    }

    private lazy var screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
    private var placing = false

    /// Where it was dragged last (its top-left corner stays put), else in the middle of
    /// the screen it opened on.
    private func place(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let area = screen.visibleFrame
        let height = min(size.height, area.height - 16)
        var frame = NSRect(x: max(area.minX, area.midX - size.width / 2), y: area.midY - height / 2, width: size.width, height: height)
        if let saved = HudApp.defaults.string(forKey: AudioDeckApp.positionKey).map(NSPointFromString),
           let visible = NSScreen.screens.first(where: { $0.frame.insetBy(dx: -1, dy: -1).contains(saved) })?.visibleFrame {
            frame.origin = NSPoint(x: saved.x, y: saved.y - height)
            // kept on screen: a bigger deck (scale) than when it was dragged there
            frame.origin.x = max(visible.minX, min(frame.minX, visible.maxX - frame.width))
            frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        }
        if frame != panel.frame {
            placing = true
            panel.setFrame(frame, display: true)
            placing = false
        }
    }
}
