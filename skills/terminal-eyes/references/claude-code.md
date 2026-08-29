# Claude Code: theme, statusline, rendering

## Rendering

| Setting | Effect |
|---------|--------|
| `/tui fullscreen` | Alt-screen renderer, atomic frames, input box stops jumping. Saves the preference |
| `CLAUDE_CODE_NO_FLICKER=1` | Same renderer via env var. Costs native scrollback and Cmd+F (use Ctrl+O and `/`). Breaks under `tmux -CC` |
| `CLAUDE_CODE_FORCE_SYNC_OUTPUT=1` | Keeps the normal renderer, forces synchronized output. Use when the terminal supports sync but isn't auto-detected — you keep native scrollback |
| `CLAUDE_CODE_SCROLL_SPEED=3` | Scroll step in fullscreen mode |
| `CLAUDE_CODE_DISABLE_MOUSE` | Mouse reporting off |

Prefer `FORCE_SYNC_OUTPUT` over `NO_FLICKER` when the terminal is GPU-accelerated: same
calm, native scrollback intact.

## Themes

`"theme"` in `~/.claude/settings.json` takes a preset — `dark`, `light`, `dark-daltonized`,
`light-daltonized`, `dark-ansi`, `light-ansi` — or `custom:<slug>` pointing at
`~/.claude/themes/<slug>.json`:

```json
{ "name": "Novel", "base": "light", "overrides": { "text": "#3b2322" } }
```

`base` is the preset it starts from; `overrides` maps tokens to `#rrggbb`, `#rgb`,
`rgb(r,g,b)`, `ansi256(n)` or `ansi:<name>`. Unknown tokens and bad values are ignored,
so a typo cannot break rendering.

**`light-ansi` / `dark-ansi` draw from the terminal's own ANSI palette.** If you have
already tuned that palette, an ansi base keeps the two in sync for free and survives a
terminal theme switch. Use an explicit hex theme when you want the same look in terminals
whose palettes differ.

Claude Code watches `~/.claude/themes/` and reloads on file change — no restart. That
makes the active file a switch point: an external script can copy a light or dark variant
over `<slug>.json` and the running session follows. (The `theme` setting itself is read at
startup, so switching by rewriting the file beats rewriting settings.json.)

### Tokens

Documented: `claude`, `text`, `inverseText`, `inactive`, `subtle`, `suggestion`,
`permission`, `remember`, `success`, `error`, `warning`, `merged`, `promptBorder`,
`planMode`, `autoAccept`, `bashBorder`, `ide`, `fastMode`, `effortUltra`, `diffAdded`,
`diffRemoved`, `diffAddedDimmed`, `diffRemovedDimmed`, `diffAddedWord`, `diffRemovedWord`,
`userMessageBackground`, `userMessageBackgroundHover`, `bashMessageBackgroundColor`,
`memoryBackgroundColor`, `selectionBg`, `rate_limit_fill`, `rate_limit_empty`,
`briefLabelYou`, `briefLabelClaude`.

Shimmer pairs (the lighter half of the spinner gradient): `claudeShimmer`,
`warningShimmer`, `permissionShimmer`, `promptBorderShimmer`, `inactiveShimmer`,
`fastModeShimmer`, `autoAcceptShimmer`.

**Not in the docs** (verified present in v2.1.251, they carry a real share of the accents —
`professionalBlue` in particular is what reads as "washed out blue" in inline code on a
light ground):

`professionalBlue`, `chromeYellow`, `skill`, `background`, `composerSidebarBackground`,
`clawd_body`, `clawd_background`, `claudeBlue_FOR_SYSTEM_SPINNER`,
`claudeBlueShimmer_FOR_SYSTEM_SPINNER`.

Leave `background` alone unless you mean it — it paints behind UI blocks and will fight
the terminal's own background.

Subagent colors: `<color>_FOR_SUBAGENTS_ONLY` for red/blue/green/yellow/purple/orange/
pink/cyan. Ultrathink gradient: `rainbow_<color>` and `rainbow_<color>_shimmer`.

To confirm the list against your own build:

```bash
BIN=$(ls -d ~/.local/share/claude/versions/* | tail -1)
LC_ALL=C grep -a -b -o 'diffAddedWord' "$BIN" | head    # offsets
dd if="$BIN" bs=1 skip=<offset-2000> count=6000 2>/dev/null | \
  LC_ALL=C tr -c '[:print:]' '\n' | grep -oE '[a-zA-Z_]{4,32}'
```

Editing tokens interactively is easier: `/theme` → highlight a custom theme → `Ctrl+E`
gives a live preview of every token, including the single-purpose ones omitted here.

## Statusline

The JSON on stdin carries more than most statuslines use:

`session_name` (the chat's own title), `model.display_name`, `model.id`,
`workspace.current_dir`, `effort.level`, `fast_mode`, `thinking.enabled`,
`context_window.remaining_percentage`, `rate_limits.five_hour.used_percentage`,
`rate_limits.seven_day.used_percentage`, `cost.total_cost_usd`, `version`,
`output_style.name`, `prompt_cache.hit_ratio`.

Rules that matter for readability:

- **Never `\033[2m`.** Dim is unreadable on a light background and weak on a dark one.
  Color by importance instead: the two or three fields the eye actually hunts for
  (chat name, branch, model) get a saturated color and bold; the rest stay muted.
- **256-palette, not truecolor.** Apple Terminal has no 24-bit color; `38;5;N` works
  everywhere.
- **Switch the palette with the theme** — read the same state file the theme switcher
  writes. A statusline tuned for a light ground is unreadable on a dark one.
- **One `jq` call, not six.** It runs on every render.
- Color thresholds beat raw numbers: context remaining green/amber/red at 50/20%,
  weekly limit muted until 50%, red past 80%.

`../scripts/statusline.sh` implements all of this.
