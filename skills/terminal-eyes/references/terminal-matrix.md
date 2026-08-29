# Same seven settings, six terminals

Every terminal calls these something different. This is the mapping — find the row, apply
the column for whatever the user actually runs.

| Goal | kitty | Ghostty | WezTerm | Alacritty | iTerm2 | Apple Terminal |
|------|-------|---------|---------|-----------|--------|----------------|
| No cursor blink | `cursor_blink_interval 0` | `cursor-style-blink = false` | `cursor_blink_rate = 0` | `cursor.blink_interval` / style | Prefs → Profiles → Text | "Blink cursor" off |
| No blinking text | (ignored) | (ignored) | (ignored) | (ignored) | Prefs → Profiles → Text | **"Allow blinking text" off** |
| No visual bell | `visual_bell_duration 0` | `bell-features = system` | `visual_bell` off | `bell.animation none` | Prefs → Profiles → Terminal | "Visual bell" off |
| Bell as badge | `bell_on_tab`, `window_alert_on_bell` | `bell-features = attention` | tab bell indicator | — | badge + bounce | `BellBadge`, `BellBounce` |
| Line height | `modify_font cell_height 130%` | `adjust-cell-height = 30%` | `line_height = 1.3` | (no) | vertical spacing | `FontHeightSpacing 1.2` |
| Padding | `window_padding_width 12` | `window-padding-x/y` | `window_padding` | `window.padding` | Prefs → Appearance | (no) |
| Option as Meta | `macos_option_as_alt yes` | `macos-option-as-alt = true` | `send_composed_key_when_left_alt_is_pressed` | `option_as_alt` | Left/Right Option → Esc+ | "Use Option as Meta Key" |

Notes worth knowing:

- **`repaint_delay` is kitty-only** and it is the most underrated knob for streaming text.
  Default 10 ms; 16–30 makes an agent stream arrive in chunks instead of shimmering.
- **iTerm2 has "Minimum contrast"** — a slider that lifts any unreadable ANSI color to a
  floor automatically. On a light background it fixes the washed-out yellow/cyan problem
  in one move, without hand-editing sixteen colors.
- **Apple Terminal has no truecolor and no GPU acceleration.** Both matter for dense TUIs.
  It is the one terminal where `38;2;r;g;b` silently degrades, so statuslines and themes
  aimed at it must use the 256-palette.
- **Ghostty and kitty forward desktop notifications** (OSC 99 / OSC 777) to the OS with no
  setup. iTerm2 needs "Send escape sequence-generated alerts" enabled under Notification
  Center Alerts.

## Apple Terminal profiles are archived plists

There is no text config. A profile is a plist where each color is an embedded
`NSKeyedArchiver` blob:

```
$objects: ["$null",
           {"NSRGB": b"0.87 0.86 0.76\x00", "NSColorSpace": 2, "$class": UID(2)},
           {"$classname": "NSColor", "$classes": ["NSColor", "NSObject"]}]
```

`../scripts/gen_apple_terminal_profile.py` builds a full `.terminal` file (16 ANSI colors,
font, spacing, bell and scrollback) from a hex palette.

**Import with `open profile.terminal`, never by writing the plist directly.** Terminal.app
holds its settings in memory and rewrites them on quit, so a `defaults write` while it is
running is silently lost. After import:

```applescript
tell application "Terminal"
  set default settings to settings set "<name>"
  set startup settings to settings set "<name>"
  repeat with w in windows
    try
      set current settings of w to settings set "<name>"
    end try
  end repeat
end tell
```

Keys the generator sets that are easy to miss: `useOptionAsMetaKey` (without it Option-key
shortcuts in TUIs are dead), `UseBrightBold: false`, `ShouldLimitScrollback: 0` with
`ScrollbackLines`, and `BellBadge`/`BellBounce` with `Bell: false` — a silent bell that
still marks the tab.

## Live palette switching

kitty is the only one of these with a clean remote-control path:

```bash
kitty @ --to unix:/tmp/kitty-<pid> set-colors --all --configured theme.conf
```

Needs `allow_remote_control yes` and `listen_on unix:/tmp/kitty-{kitty_pid}` — and note
that `listen_on` only takes effect on restart. For the others, write the config file and
apply on the next window (Apple Terminal being the exception: AppleScript can re-skin live
windows, as above).
