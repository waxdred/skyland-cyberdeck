import AppKit

/// Cyberpunk HUD palette and drawing helpers. Original drawing code; the look
/// (neon red / cyan, cut corners, glow, flicker) follows the in-game UI style.
enum Neon {
    static let red = NSColor(srgbRed: 1.0, green: 0.16, blue: 0.23, alpha: 1) // #ff2a3a
    static let cyan = NSColor(srgbRed: 0.37, green: 0.96, blue: 0.97, alpha: 1) // #5ef4f8
    static let yellow = NSColor(srgbRed: 0.95, green: 0.90, blue: 0.0, alpha: 1) // #f3e600
    static let ink = NSColor(srgbRed: 0.04, green: 0.02, blue: 0.05, alpha: 1)

    /// Condensed display font, falls back to the system font.
    static func title(_ size: CGFloat, _ weight: NSFont.Weight = .heavy) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: weight, width: .condensed)
    }

    static func mono(_ size: CGFloat, _ weight: NSFont.Weight = .medium) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }
}

/// Rectangle with the top-left and bottom-right corners cut (flipped coordinates).
func chamfered(_ rect: NSRect, cut: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: rect.minX + cut, y: rect.minY))
    path.line(to: NSPoint(x: rect.maxX, y: rect.minY))
    path.line(to: NSPoint(x: rect.maxX, y: rect.maxY - cut))
    path.line(to: NSPoint(x: rect.maxX - cut, y: rect.maxY))
    path.line(to: NSPoint(x: rect.minX, y: rect.maxY))
    path.line(to: NSPoint(x: rect.minX, y: rect.minY + cut))
    path.close()
    return path
}

/// Draw `text` with a neon glow (a colored shadow) over a dark halo, so it reads
/// over any window behind the see-through overlay.
func neonText(_ text: String, at point: NSPoint, font: NSFont, color: NSColor, glow: CGFloat = 8, alpha: CGFloat = 1, kern: CGFloat = 0) {
    NSGraphicsContext.saveGraphicsState()
    let halo = NSShadow()
    halo.shadowColor = NSColor.black.withAlphaComponent(0.95 * alpha)
    halo.shadowBlurRadius = 5
    halo.shadowOffset = .zero
    halo.set()
    (text as NSString).draw(at: point, withAttributes: [.font: font, .foregroundColor: color.withAlphaComponent(alpha), .kern: kern])
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color.withAlphaComponent(0.9 * alpha)
    shadow.shadowBlurRadius = glow
    shadow.shadowOffset = .zero
    shadow.set()
    (text as NSString).draw(at: point, withAttributes: [.font: font, .foregroundColor: color.withAlphaComponent(alpha), .kern: kern])
    NSGraphicsContext.restoreGraphicsState()
}

/// Stroke `path` with a glow.
func neonStroke(_ path: NSBezierPath, color: NSColor, width: CGFloat, glow: CGFloat = 10, alpha: CGFloat = 1) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color.withAlphaComponent(alpha)
    shadow.shadowBlurRadius = glow
    shadow.shadowOffset = .zero
    shadow.set()
    color.withAlphaComponent(alpha).setStroke()
    path.lineWidth = width
    path.stroke()
    NSGraphicsContext.restoreGraphicsState()
}

/// Horizontal scanlines over `rect`.
func scanlines(_ rect: NSRect, color: NSColor, alpha: CGFloat, step: CGFloat = 3) {
    color.withAlphaComponent(alpha).setFill()
    var y = rect.minY
    while y < rect.maxY {
        NSRect(x: rect.minX, y: y, width: rect.width, height: 1).fill()
        y += step
    }
}

/// `image` washed with `color` (sourceAtop keeps the icon shape).
func tinted(_ image: NSImage, _ color: NSColor, amount: CGFloat) -> NSImage {
    NSImage(size: image.size, flipped: false) { rect in
        image.draw(in: rect)
        color.withAlphaComponent(amount).setFill()
        rect.fill(using: .sourceAtop)
        return true
    }
}
