import AppKit

/// User settings: ~/.config/skyland-cyberdeck/config.toml (or $SKYLAND_CYBERDECK_CONFIG).
/// A small TOML subset: `[section]`, `key = value` with a quoted string, a number or
/// true / false, `#` comments. Every key is optional; `skyland-cyberdeck config init`
/// writes the file below with the defaults.
enum Config {
    static let example = """
        # skyland-cyberdeck settings. Every key is optional: delete a line to get the default.

        [general]
        theme = "cyberpunk"      # used until `skyland-cyberdeck theme <name>` saves another one
        font = ""                # titles and app names: a font family or PostScript name ("" = system condensed)
        mono-font = ""           # labels, search, footers ("" = system monospaced)
        font-scale = 1.0         # every text size
        uppercase = true         # app names, message apps and the search in capitals
        scanlines = true
        glow = 1.0               # neon glow strength, 0 = none
        tint = 1.0               # screen tint and vignette strength, 0 = none
        footer = true            # key hints at the bottom

        [colors]                 # override the theme, "#rrggbb"
        # primary = "#ff2a3a"    # frames, selection
        # secondary = "#5ef4f8"  # labels, rows
        # highlight = "#f3e600"  # search line, time
        # ink = "#0a050d"        # dark tint behind the text

        [launcher]
        title = "APPS LAUNCHER"
        subtitle = "// CYBERDECK — RUNNING"
        placeholder = "TYPE TO SEARCH"
        rows = 9                 # visible rows (odd)
        row-width = 430
        row-height = 50
        curve = 46               # how much the column bends, 0 = straight
        tilt = 0.06              # the deck rises to the right, 0 = flat

        [messages]
        title = "MESSAGES"
        subtitle = "// {count} IN BUFFER"
        width = 470
        card-height = 92

        [toast]
        seconds = 4.5
        width = 400

        [hud]
        widgets = "clock, calendar, connections, sound, system, herdr, messages, launch" # shown
        theme = "netrunner"      # the HUD's palette: netrunner, cyberpunk, skyland, any theme
        clock-24h = true
        clock-seconds = false
        second-timezone = ""     # e.g. "America/New_York"
        week-start = 0           # 0 = locale, 1 = Sunday, 2 = Monday
        refresh-ms = 2000
        opacity = 0.45           # deck background around the cards, 0 = clear
        blur = 0.35              # blur behind the deck, 0 = none, 1 = full
        card-opacity = 0.72      # card backgrounds, lower lets the backdrop through
        cyberspace = 0.6         # grid, data streams and scan line behind the cards, 0 = off
        scale = 1.0              # size of the whole deck, 0.5 to 2
        apps = "Finder, Ghostty, Visual Studio Code, Safari, Spotify" # quick launch, by app name
        """

    static let file: URL = {
        if let path = ProcessInfo.processInfo.environment["SKYLAND_CYBERDECK_CONFIG"] {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/skyland-cyberdeck/config.toml")
    }()

    static let values: [String: String] = (try? String(contentsOf: file, encoding: .utf8)).map(parse) ?? [:]

    /// "section.key" -> raw value (quotes removed).
    static func parse(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        var section = ""
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = stripComment(String(raw)).trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") && line.hasSuffix("]") {
                section = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            } else if let eq = line.firstIndex(of: "=") {
                let key = line[..<eq].trimmingCharacters(in: .whitespaces)
                var value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                if value.count >= 2, let quote = value.first, quote == "\"" || quote == "'", value.last == quote {
                    value = String(value.dropFirst().dropLast())
                }
                result[section.isEmpty ? key : "\(section).\(key)"] = value
            }
        }
        return result
    }

    /// The line up to a `#` that is not inside quotes.
    private static func stripComment(_ line: String) -> String {
        var quote: Character?
        for (index, char) in zip(line.indices, line) {
            if let open = quote { if char == open { quote = nil } } else if char == "\"" || char == "'" { quote = char } else if char == "#" { return String(line[..<index]) }
        }
        return line
    }

    static func string(_ key: String, _ fallback: String) -> String { values[key] ?? fallback }
    static func number(_ key: String, _ fallback: CGFloat) -> CGFloat { values[key].flatMap(Double.init).map { CGFloat($0) } ?? fallback }
    static func int(_ key: String, _ fallback: Int) -> Int { values[key].flatMap(Int.init) ?? fallback }
    static func bool(_ key: String, _ fallback: Bool) -> Bool { values[key].map { $0 == "true" } ?? fallback }

    static func color(_ key: String) -> NSColor? {
        guard let value = values[key], value.hasPrefix("#"), value.count == 7, let hex = Int(value.dropFirst(), radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }

    /// `config init`: write the example, never over an existing file.
    static func initFile() {
        guard !FileManager.default.fileExists(atPath: file.path) else { fail("skyland-cyberdeck: \(file.path) already exists") }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        do { try (example + "\n").write(to: file, atomically: true, encoding: .utf8) } catch { fail("skyland-cyberdeck: \(error.localizedDescription)") }
        print(file.path)
    }
}
