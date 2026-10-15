# skyland-cyberdeck

Cyberpunk HUD pieces for macOS: neon red / cyan, cut corners, glow, scanlines and
flicker. Made for [skyland](https://github.com/waxdred/skyland) (a Hyprland-like
tiling window manager for macOS), works on its own with any window manager.

<p align="center"><img src="docs/launcher.png" alt="Apps launcher: tilted neon deck with a curved column of apps" width="520"></p>

## Apps launcher

```sh
skyland-cyberdeck launcher   # toggle
```

- a curved column of apps around the selection, wrapping like a wheel
- type to search (prefix, word start, substring, then fuzzy), apps you launch often come first
- `↑` `↓` or scroll to move, `return` or click to launch, `esc` or a click outside to close
- opens on the screen under the mouse, over a blurred and dimmed screen

Apps come from `/Applications` (and one folder down), `/System/Applications`,
their `Utilities`, `/System/Library/CoreServices/Applications` and `~/Applications`.

## Build

```sh
swift build -c release   # .build/release/skyland-cyberdeck, macOS 13+
```

With skyland, bind it in `~/.config/aerospace/aerospace.toml`:

```toml
[mode.main.binding]
alt-d = 'exec-and-forget ~/code/hyperland/skyland-cyberdeck/.build/release/skyland-cyberdeck launcher'
```

## Credits

The look is inspired by [CyberArch-Shell](https://github.com/ARCANGEL0/CyberArch-Shell)
and the Cyberpunk 2077 UI. No code or asset of either is used: the drawing is
original and no game icon, font or sound is included.

## License

MIT
