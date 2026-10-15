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

<p align="center"><img src="docs/messages.jpg" alt="Messages panel: neon contact cards over the screen" width="520"></p>

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

<p align="center"><img src="docs/toast.jpg" alt="notify popups, top right" width="420"></p>

- `notify` stores a message, shows a glitching popup top right (stacked, click
  closes it) unless `--quiet`, and prints the message id. `-a` is a bundle id
  (its icon and name are used, e.g. `com.mitchellh.ghostty`) or any name.
- `list --json` prints `[{id, app, title, subtitle, body, date (ISO 8601), source}]`,
  newest first; `source` is `macos` or `api`. `--all` includes dismissed ones.
- `dismiss` hides one message by id, or all of them.

API messages live in `~/Library/Application Support/skyland-cyberdeck/messages.json`
(last 200).
`SKYLAND_CYBERDECK_STORE=<file>` uses another store and leaves the Notification
Center out (demos, tests).

```sh
# long command done, from fish / zsh
make build; skyland-cyberdeck notify -t "make build" -b "exit $status" -a com.mitchellh.ghostty

# unread count for a bar item
skyland-cyberdeck list --json | jq length
```

## Themes

```sh
skyland-cyberdeck theme                 # current theme
skyland-cyberdeck theme list            # cyberpunk, skyland, then the skyland themes
skyland-cyberdeck theme skyland         # follow the current skyland theme
skyland-cyberdeck theme 43pr-dracula    # a skyland theme by name, or a path to a .css file
skyland-cyberdeck launcher --theme 43pr-nord   # this call only
```

- `cyberpunk` (default): neon red, cyan and yellow
- `skyland`: `~/.cache/skyland/theme.css`, so it follows light / dark, the theme
  picker and the colors generated from the wallpaper
- any file of `@define-color <key> #rrggbb;` lines (the 43PR / skyland theme format),
  by name from `~/.config/skyland/themes` or by path: `accent` is the primary color,
  `highlight` the secondary, `term3` the highlight and `bg` the background tint

## Integrations

### herdr: agent finished / needs you

[`integrations/herdr`](integrations/herdr) is a [herdr](https://herdr.dev) plugin: on
`pane.agent_status_changed`, an agent that is `done` gives "claude finished", one that
is `blocked` or `waiting` gives "claude needs you", with the herdr workspace label
and the pane title. Nothing pops up for the pane you are looking at (focused pane
with Ghostty in front, asked to skyland's CLI when it is there).

```sh
herdr plugin link ~/code/hyperland/skyland-cyberdeck/integrations/herdr
```

### Mail

Any mail checker can call `notify`, e.g. a sketchybar mail item, once per new mail:

```sh
skyland-cyberdeck notify -a com.apple.mail -t "$subject" -s "$sender" -b "$preview"
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

## License

MIT
