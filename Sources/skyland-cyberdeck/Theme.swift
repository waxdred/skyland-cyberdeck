import AppKit

/// Colors of the deck: the built-in "cyberpunk" palette, the current skyland theme
/// ("skyland": ~/.cache/skyland/theme.css, follows light / dark, the theme picker
/// and the wallpaper colors), a skyland theme by name (~/.config/skyland/themes/
/// <name>.css) or any file of `@define-color <key> #rrggbb;` lines. Theme keys:
/// accent -> primary, highlight -> secondary, term3 -> highlight, bg -> ink.
struct Theme {
    var primary: NSColor
    var secondary: NSColor
    var highlight: NSColor
    var ink: NSColor

    static let cyberpunk = Theme(primary: rgb(0xff2a3a), secondary: rgb(0x5ef4f8), highlight: rgb(0xf3e600), ink: rgb(0x0a050d))

    private static let defaults = UserDefaults(suiteName: "com.waxdred.skyland-cyberdeck")!
    private static let home = FileManager.default.homeDirectoryForCurrentUser
    static let themesDir = home.appending(path: ".config/skyland/themes")

    /// Theme name: --theme <name> of this call, else the saved one, else [general]
    /// theme of the config, else cyberpunk.
    static var name: String {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--theme"), args.indices.contains(index + 1) { return args[index + 1] }
        return defaults.string(forKey: "theme") ?? Config.string("general.theme", "cyberpunk")
    }

    static func save(_ name: String) { defaults.set(name, forKey: "theme") }

    /// CSS file of a theme name, nil for cyberpunk or an unknown name.
    static func file(_ name: String) -> URL? {
        let candidates = [name == "skyland" ? home.appending(path: ".cache/skyland/theme.css") : nil,
                          name.hasSuffix(".css") ? URL(fileURLWithPath: (name as NSString).expandingTildeInPath) : nil,
                          themesDir.appending(path: "\(name).css")]
        return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Names to pass to `theme`: built-ins, then the skyland themes.
    static func available() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: themesDir.path)) ?? []
        return ["cyberpunk", "skyland"] + files.filter { $0.hasSuffix(".css") }.map { String($0.dropLast(4)) }.sorted()
    }

    static func load() -> Theme {
        guard let file = file(name), let css = try? String(contentsOf: file, encoding: .utf8) else { return cyberpunk }
        var colors: [String: NSColor] = [:]
        let regex = try! NSRegularExpression(pattern: #"@define-color\s+([A-Za-z0-9_]+)\s+#([0-9A-Fa-f]{6})\s*;"#)
        for match in regex.matches(in: css, range: NSRange(css.startIndex..., in: css)) {
            guard let key = Range(match.range(at: 1), in: css), let hex = Range(match.range(at: 2), in: css),
                  let value = Int(css[hex], radix: 16) else { continue }
            colors[String(css[key])] = rgb(value)
        }
        return Theme(primary: colors["accent"] ?? colors["border_strong"] ?? cyberpunk.primary,
                     secondary: colors["highlight"] ?? colors["fg_soft"] ?? cyberpunk.secondary,
                     highlight: colors["term3"] ?? colors["term11"] ?? cyberpunk.highlight,
                     ink: colors["bg"] ?? cyberpunk.ink)
    }
}

private func rgb(_ hex: Int) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
}
