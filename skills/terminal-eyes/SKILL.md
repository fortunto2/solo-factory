---
name: solo-terminal-eyes
description: Set up a terminal for hours of reading agent output without eye strain — kill flicker and blinking, pick a polarity that fits the room, fix the ANSI palette so accents stay readable, and swap watching-the-stream for a bell. Use when the user says "глаза устают от терминала", "eye strain", "терминал режет глаза", "мерцает", "flicker", "настрой терминал/палитру", "светлая тема в терминале", "statusline не видно", "акценты бледные", or after switching to a light background. Do NOT use for editor/IDE themes or for website color systems (use /dataviz for chart palettes).
license: MIT
metadata:
  author: fortunto2
  version: "1.0.0"
  openclaw:
    emoji: "👓"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
argument-hint: "[terminal name, e.g. kitty | ghostty | iterm2 | apple-terminal]"
---

# Terminal Eyes

Reading an agent stream is not the job a terminal was tuned for. You stopped writing
and became a reviewer: hours of reading text that moves while you read it. Three
different things tire the eyes, and they need three different fixes. Do them in this
order — the first is most of the win and takes minutes.

## 0. Read the room before changing anything

Ask, or check: how bright is the room, and does the user read more than they type?
That decides polarity (step 2). Everything in step 1 applies regardless.

Never migrate a config blind. Read the existing one first — it usually holds keybindings,
launchers and layout the user cares about. Keep them; change only what this skill names.
Back it up: `cp kitty.conf kitty.conf.bak-$(date +%s)`.

## 1. Kill the motion

Moving text breaks the saccadic rhythm: the eye re-hunts a fixation point on every
frame instead of holding one. Everything here is about frames, not colors.

| What | Why | Where |
|------|-----|-------|
| Cursor blink off | A blinking block in peripheral vision never stops pulling attention | `cursor_blink_interval 0` (kitty), "Blink cursor" off (Apple Terminal), `cursor-style-blink false` (Ghostty) |
| Blinking text off | ANSI blink attribute, worse than the cursor | `BlinkText: false` (Apple Terminal), most others ignore blink by default |
| Visual bell off | A full-window flash is the single loudest thing a terminal can do | `visual_bell_duration 0`, `enable_audio_bell no` |
| Slower repaint | Halves redraw frequency: a stream arrives in chunks instead of shimmering | kitty `repaint_delay 20` (default 10; try 16–30) |
| Synchronized output | Frames update atomically, no half-drawn UI | On by default in kitty/Ghostty/WezTerm. Claude Code: `CLAUDE_CODE_FORCE_SYNC_OUTPUT=1` if the terminal supports it but isn't detected |
| Fullscreen renderer | Alt-screen buffer, the input box stops jumping while streaming | Claude Code: `/tui fullscreen`, or `CLAUDE_CODE_NO_FLICKER=1`. Costs native scrollback and Cmd+F — use Ctrl+O and `/` instead. Incompatible with `tmux -CC` |
| No transparency, no blur | Text over a moving background is the worst case of all | `background_opacity 1.0` |

GPU-accelerated terminals (kitty, Ghostty, WezTerm, Alacritty) redraw dense TUIs with
far less flicker than Apple Terminal. If the user is willing to switch, that alone
removes a class of the problem.

## 2. Polarity and palette

**Positive polarity wins in a lit room.** Dark text on light background reads better
(Buchner & Baumgartner 2007; Piepenbrock et al. 2014 explains why: a smaller pupil means
more depth of field and less defocus — the same mechanism as squinting). In a dark room
the advantage inverts: match the screen to the ambient light, not to taste. If the user
reads far more than they types, a light background is worth a 3–4 day trial — first
impression of a polarity switch is always "too bright" and it passes in two days.

**Never pure black or pure white.** `#000`/`#fff` is 21:1; halation around glyphs is
worst there and it's brutal with astigmatism. Aim 7–12:1.

- Light: warm off-white ground (`#dfdbc3`, `#fdf6e3`), dark brown/grey text (`#3b2322`)
- Dark: `#1a1b26`, `#282c34`, `#1a1610`; text `#c0caf5`, `#d4c4a5`

**The trap nobody fixes: the ANSI palette.** Ported light themes usually keep the accent
colors from their dark ancestor, and those were chosen against a dark ground. On a cream
background a canonical Novel yellow `#d06b00` or cyan `#0087cc` lands near 2–3:1 — the
user reads it as "accents look washed out" without knowing why. Two rules:

1. Re-derive all 16 colors against the actual background: normal colors ≥4.5:1,
   bright ≥3.5:1 (they carry bold text). `scripts/contrast.py` checks a palette and
   prints what fails.
2. On a light theme make `color7`/`color15` **dark**, not light. Solarized Light keeps
   them light and every TUI that paints "white" text disappears. The cost is that
   background fills using color7 go dark — rare, and worth it.

Turn off "use bright colors for bold" (`UseBrightBold: false`). Bright variants on a
light ground burn contrast for no gain; bold should come from the font weight.

Font: 14–15pt, line height 1.2–1.3 (`modify_font cell_height 130%` in kitty,
`FontHeightSpacing` in Apple Terminal). Courier at 12pt is the worst common default —
thin strokes, low x-height, the eye reconstructs the glyphs and that is hidden work.
JetBrains Mono, Berkeley Mono, SF Mono are all better. On macOS light themes add
`macos_thicken_font 0.3` if strokes look anemic.

Padding: `window_padding_width 12`. Text hard against the frame reads worse.

Ready-made palettes: `references/configs/kitty-theme-light.conf`, `kitty-theme-dark.conf`.
Both are contrast-checked against their own background.

## 3. Stop watching the stream

This is a habit fix, and it outperforms every setting above. Launch, switch away, get
called back.

- **Tabs, not splits.** Four live panes are four independent sources of motion in one
  visual field, and the brain processes all of them. One active tab plus indicators on
  the rest carries the same information. In kitty: `enabled_layouts stack,splits` and
  `map ctrl+shift+z toggle_layout stack` keeps splits available but collapsed.
- **Bell as a tab badge, never a flash**: `bell_on_tab "🔔 "`, `tab_activity_symbol "•"`,
  `window_alert_on_bell yes`, audio off.
- **Command-finish notification**: kitty `notify_on_cmd_finish unfocused 15.0` (needs
  shell integration). It only fires when the whole command exits, so for an agent that
  runs for hours, use the agent's own notification instead.
- **Claude Code**: `"preferredNotifChannel": "terminal_bell"` turns each pause into a tab
  badge. Desktop notifications work natively in Ghostty, Kitty and iTerm2; a Notification
  hook can play a sound anywhere.

**Inside tmux none of this reaches the outer terminal until you add:**

```tmux
set -g allow-passthrough on          # notifications + progress bar escape tmux
set -s extended-keys on              # Shift+Enter distinguishable from Enter
set -as terminal-features 'xterm*:extkeys'
set -ga terminal-features ',xterm-kitty:RGB'   # else truecolor degrades to 256
```

## 4. Claude Code itself

A light terminal with Claude Code still in its dark theme is the worst of both: dark diff
backgrounds over a cream ground. Set `"theme": "light"` — and if the built-in preset
fights the terminal palette, build a custom theme. Full token list (including the ones
missing from the docs: `professionalBlue`, `chromeYellow`, `skill`, `background`,
`inverseText`, `composerSidebarBackground`), plus the statusline rules, are in
`references/claude-code.md`. Ready themes: `references/configs/claude-theme-{light,dark}.json`.

Statusline: if it is painted with `\033[2m` (dim), it is invisible on a light ground.
Rewrite it with explicit 256-palette colors — Apple Terminal has no truecolor, so
`38;2;r;g;b` is not portable. `scripts/statusline.sh` is a working example that colors
by importance and switches palette with the theme.

## 5. Optional: follow the room, not the clock

On a Mac the ambient light sensor is readable from userspace, so the theme can follow
actual light instead of sunset time. Sensor path, thresholds, hysteresis and the launchd
agent: `references/ambient-light-macos.md`. `scripts/theme` is a working switcher for
kitty + Apple Terminal + Claude Code with a manual override window.

Two rules that keep it from being annoying: a dead zone between thresholds (otherwise a
cloud passing the window flips the theme), and a manual override that suppresses the
automation for a few hours (otherwise it argues with the user immediately).

Do not touch the OS appearance unless asked — it changes Finder, Safari and every other
app, which is not what "make my terminal readable" meant.

## 6. Verify, don't assume

- kitty: `kitty +runpy 'from kitty.config import load_config; bad=[]; load_config("<path>", accumulate_bad_lines=bad); print(bad)'` — silently ignored bad lines are the usual failure
- Apple Terminal: `plutil -lint profile.terminal`, then import with `open` (writing the
  plist directly races the running app, which rewrites its settings on quit)
- Palette: `python3 scripts/contrast.py --bg '#dfdbc3' --palette <file>`
- Then look at a screenshot. Contrast math does not catch "the accent is the wrong hue".

## What not to do

- Transparency or blur "because it looks nice" — it is the single worst setting for reading
- Pure `#000`/`#fff` on either side
- Bright ANSI colors for bold text on a light background
- Four live panes in one window
- A theme chosen at 5pm and judged at 5:05pm — polarity switches need days, not minutes

If the strain does not lift after all of this, it is an optometrist question, not a config
one. Uncorrected astigmatism and presbyopia produce exactly this picture, and they surface
when the work shifts from writing to reading.
