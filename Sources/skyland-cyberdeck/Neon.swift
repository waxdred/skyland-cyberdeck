import AppKit

/// HUD palette and drawing helpers. Original drawing code; the look (neon, cut
/// corners, glow, flicker) follows the Cyberpunk 2077 UI style. The colors come
/// from the theme (see Theme): `red` is the primary, `cyan` the secondary,
/// `yellow` the highlight and `ink` the dark background tint.
enum Neon {
    static let palette = Theme.load()
    static let red = Config.color("colors.primary") ?? palette.primary
    static let cyan = Config.color("colors.secondary") ?? palette.secondary
    static let yellow = Config.color("colors.highlight") ?? palette.highlight
    static let ink = Config.color("colors.ink") ?? palette.ink

    static let scale = Config.number("general.font-scale", 1)
    static let glow = Config.number("general.glow", 1)
    static let tint = Config.number("general.tint", 1)
    static let scanlines = Config.bool("general.scanlines", true)
    static let footer = Config.bool("general.footer", true)
    static let uppercase = Config.bool("general.uppercase", true)
    private static let titleFont = Config.string("general.font", "")
    private static let monoFont = Config.string("general.mono-font", "")

    static func caps(_ text: String) -> String { uppercase ? text.uppercased() : text }

    /// Display font: [general] font, else the condensed system font.
    static func title(_ size: CGFloat, _ weight: NSFont.Weight = .heavy) -> NSFont {
        custom(titleFont, size * scale, weight) ?? NSFont.systemFont(ofSize: size * scale, weight: weight, width: .condensed)
    }

    /// Label font: [general] mono-font, else the monospaced system font.
    static func mono(_ size: CGFloat, _ weight: NSFont.Weight = .medium) -> NSFont {
        custom(monoFont, size * scale, weight) ?? NSFont.monospacedSystemFont(ofSize: size * scale, weight: weight)
    }

    /// A family in the closest weight (NSFontManager 0-15, 5 = regular, 9 = bold), or a
    /// PostScript name as is.
    private static func custom(_ name: String, _ size: CGFloat, _ weight: NSFont.Weight) -> NSFont? {
        guard !name.isEmpty else { return nil }
        let managerWeight = weight >= .heavy ? 11 : weight >= .bold ? 9 : weight >= .semibold ? 8 : weight >= .medium ? 6 : 5
        return NSFontManager.shared.font(withFamily: name, traits: [], weight: managerWeight, size: size) ?? NSFont(name: name, size: size)
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
    halo.shadowColor = Neon.ink.withAlphaComponent(0.95 * alpha)
    halo.shadowBlurRadius = 5
    halo.shadowOffset = .zero
    halo.set()
    (text as NSString).draw(at: point, withAttributes: [.font: font, .foregroundColor: color.withAlphaComponent(alpha), .kern: kern])
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color.withAlphaComponent(0.9 * alpha)
    shadow.shadowBlurRadius = glow * Neon.glow
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
    shadow.shadowBlurRadius = glow * Neon.glow
    shadow.shadowOffset = .zero
    shadow.set()
    color.withAlphaComponent(alpha).setStroke()
    path.lineWidth = width
    path.stroke()
    NSGraphicsContext.restoreGraphicsState()
}

/// Horizontal scanlines over `rect`.
func scanlines(_ rect: NSRect, color: NSColor, alpha: CGFloat, step: CGFloat = 3) {
    guard Neon.scanlines else { return }
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
