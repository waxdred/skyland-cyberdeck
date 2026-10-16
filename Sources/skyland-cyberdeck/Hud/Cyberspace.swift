import AppKit
import QuartzCore
import SwiftUI

// Cyberspace backdrop of the deck: a perspective grid, data streams rising and a slow
// scan line, behind the cards ([hud] cyberspace = strength, 0 = off). Everything is
// Core Animation (emitter, layer animations), run by the render server: the HUD
// does no per-frame work. Reduce Motion: the grid only.

struct Cyberspace: NSViewRepresentable {
    let strength: Double
    let color: NSColor

    func makeNSView(context: Context) -> CyberspaceView { CyberspaceView(strength: strength, color: color) }
    func updateNSView(_ view: CyberspaceView, context: Context) {}
}

final class CyberspaceView: NSView {
    private let strength: Double
    private let color: NSColor
    private let grid = CAShapeLayer()
    private let streams = CAEmitterLayer()
    private let scan = CAGradientLayer()
    private let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    init(strength: Double, color: NSColor) {
        self.strength = strength
        self.color = color
        super.init(frame: .zero)
        layer = CALayer()
        wantsLayer = true
        grid.fillColor = nil
        grid.strokeColor = color.withAlphaComponent(0.16 * strength).cgColor
        grid.lineWidth = 1
        layer?.addSublayer(grid)
        if !still {
            streams.emitterShape = .line
            streams.renderMode = .additive
            streams.emitterCells = [streamCell()]
            layer?.addSublayer(streams)
            scan.colors = [NSColor.clear.cgColor, color.withAlphaComponent(0.16 * strength).cgColor, NSColor.clear.cgColor]
            layer?.addSublayer(scan)
        }
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil } // decoration: clicks go to the cards

    override func layout() {
        super.layout()
        let b = bounds
        guard b.width > 0, b.height > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        grid.frame = b
        grid.path = gridPath(in: b)
        streams.frame = b
        streams.emitterPosition = CGPoint(x: b.midX, y: 0)
        streams.emitterSize = CGSize(width: b.width, height: 1)
        streams.birthRate = 1
        scan.frame = CGRect(x: 0, y: 0, width: b.width, height: 60)
        CATransaction.commit()
        if !still, scan.animation(forKey: "scan") == nil {
            let sweep = CABasicAnimation(keyPath: "position.y")
            sweep.fromValue = b.height + 30
            sweep.toValue = -30
            sweep.duration = 9
            sweep.repeatCount = .infinity
            sweep.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 30, preferred: 24)
            scan.add(sweep, forKey: "scan")
        }
    }

    /// Floor grid in the lower half, lines converging to a horizon point.
    private func gridPath(in b: CGRect) -> CGPath {
        let path = CGMutablePath()
        let horizon = b.height * 0.48
        let vanishing = CGPoint(x: b.midX, y: horizon)
        for i in -12 ... 12 {
            path.move(to: vanishing)
            path.addLine(to: CGPoint(x: b.midX + CGFloat(i) * b.width / 8, y: 0))
        }
        var y = horizon
        var step: CGFloat = 4
        while y > 0 {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: b.width, y: y))
            y -= step
            step *= 1.35 // farther lines closer together
        }
        return path
    }

    /// A thin vertical streak fading at both ends, rising from the bottom.
    private func streamCell() -> CAEmitterCell {
        let size = CGSize(width: 2, height: 26)
        let image = NSImage(size: size, flipped: false) { rect in
            NSGradient(colors: [.clear, .white, .clear])?.draw(in: rect, angle: 90)
            return true
        }
        let cell = CAEmitterCell()
        cell.contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        cell.color = color.withAlphaComponent(0.55 * strength).cgColor
        cell.birthRate = Float(5 * strength)
        cell.lifetime = 14
        cell.velocity = 70
        cell.velocityRange = 40
        cell.emissionLongitude = .pi / 2 // up
        cell.scale = 1
        cell.scaleRange = 0.6
        cell.alphaSpeed = -0.05
        return cell
    }
}
