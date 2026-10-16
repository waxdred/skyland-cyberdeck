# Changelog

Each `## vX.Y.Z` section is also the text of its GitHub release.

## Unreleased

- **HUD** (`skyland-cyberdeck hud`): clock, calendar, herdr agents, brightness and
  volume, CPU / RAM / network / disk / battery, last messages, quick launch. Real data
  only, sampled only while it is open. `[hud]` settings, `netrunner` palette.

## v0.1.0

First release.

- **Apps launcher**: a tilted neon deck with a curved, wrapping column of apps, type to
  search (fuzzy), apps you launch often first, eye implant overlay on the screen under
  the mouse.
- **Messages panel**: the macOS Notification Center history merged with the messages
  your scripts send; open, dismiss, dismiss all.
- **Scripting API**: `notify` (glitching popup top right), `list --json`, `dismiss`.
- **Themes**: `cyberpunk` (default), `skyland` (follows the current skyland theme), any
  skyland / 43PR theme by name or path.
- **Settings** (`skyland-cyberdeck config init`, `~/.config/skyland-cyberdeck/config.toml`):
  fonts, text size, titles, colors over the theme, launcher rows and shape, glow, tint,
  scanlines, toast duration.
- **herdr plugin**: a message when an agent finishes or needs you, nothing for the pane
  you are looking at. Finds `skyland-cyberdeck` and `skyland` on the PATH and follows
  skyland's `[terminal] app`.
- Homebrew: `brew install waxdred/tap/skyland-cyberdeck`.
