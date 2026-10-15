# skyland-cyberdeck

Cyberpunk HUD pieces for macOS: neon red / cyan, cut corners, glow, scanlines and
flicker. Made for [skyland](https://github.com/waxdred/skyland) (a Hyprland-like
tiling window manager for macOS), works on its own with any window manager.

<p align="center"><img src="docs/launcher.jpg" alt="Apps launcher: tilted neon deck with a curved column of apps" width="520"></p>

## Apps launcher

```sh
skyland-cyberdeck launcher   # toggle
```

- a curved column of apps around the selection, wrapping like a wheel
- type to search (prefix, word start, substring, then fuzzy), apps you launch often come first
- `↑` `↓` or scroll to move, `return` or click to launch, `esc` or a click outside to close
- an eye implant overlay: opens on the screen under the mouse, which stays visible behind a light tint and scanlines

Apps come from `/Applications` (and one folder down), `/System/Applications`,
their `Utilities`, `/System/Library/CoreServices/Applications` and `~/Applications`.

## Messages

A column of contact cards on the right of the screen: the macOS Notification
Center history (Ghostty, Mail, Outlook, any app allowed to notify) merged with the
messages your scripts send. `↑` `↓` / scroll to move, `return` or click opens the
app, `x` dismisses, `shift-x` dismisses all, `esc` closes. New messages show up
while it is open.

```sh
skyland-cyberdeck messages   # toggle the panel
```

The first time, macOS asks to let it read data from other apps: the Notification
Center database (`~/Library/Group Containers/group.com.apple.usernoted/db2/db`),
read only. Dismissing hides a message in the deck, not in the Notification Center.

### Scripting API

```sh
skyland-cyberdeck notify -t TITLE [-b BODY] [-s SUBTITLE] [-a APP] [--seconds N] [--quiet]
skyland-cyberdeck list [--json] [--limit N] [--all]
skyland-cyberdeck dismiss <id> | --all
```

- `notify` stores a message, shows a glitching popup top right (stacked, click
  closes it) unless `--quiet`, and prints the message id. `-a` is a bundle id
  (its icon and name are used, e.g. `com.mitchellh.ghostty`) or any name.
- `list --json` prints `[{id, app, title, subtitle, body, date (ISO 8601), source}]`,
  newest first; `source` is `macos` or `api`. `--all` includes dismissed ones.
- `dismiss` hides one message by id, or all of them.

API messages live in `~/Library/Application Support/skyland-cyberdeck/messages.json`
(last 200).

```sh
# long command done, from fish / zsh
make build; skyland-cyberdeck notify -t "make build" -b "exit $status" -a com.mitchellh.ghostty

# unread count for a bar item
skyland-cyberdeck list --json | jq length
```

## Build

```sh
swift build -c release   # .build/release/skyland-cyberdeck, macOS 13+
```

With skyland, bind it in `~/.config/aerospace/aerospace.toml`:

```toml
[mode.main.binding]
alt-d = 'exec-and-forget ~/code/hyperland/skyland-cyberdeck/.build/release/skyland-cyberdeck launcher'
alt-shift-m = 'exec-and-forget ~/code/hyperland/skyland-cyberdeck/.build/release/skyland-cyberdeck messages'
alt-shift-x = 'exec-and-forget ~/code/hyperland/skyland-cyberdeck/.build/release/skyland-cyberdeck dismiss --all'
```

## Credits

The look is inspired by [CyberArch-Shell](https://github.com/ARCANGEL0/CyberArch-Shell)
and the Cyberpunk 2077 UI. No code or asset of either is used: the drawing is
original and no game icon, font or sound is included.

## License

MIT
