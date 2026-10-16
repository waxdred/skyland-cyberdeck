# Changelog

Each `## vX.Y.Z` section is also the text of its GitHub release.

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
- **herdr plugin**: a message when an agent finishes or needs you, nothing for the pane
  you are looking at. Finds `skyland-cyberdeck` and `skyland` on the PATH and follows
  skyland's `[terminal] app`.
- Homebrew: `brew install waxdred/tap/skyland-cyberdeck`.
