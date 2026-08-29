# Following the room's light on macOS

## The sensor

Apple Silicon exposes no `AppleLMUController` (that was Intel). The ambient value lives in
the display driver instead:

```bash
ioreg -r -l -w 0 -k AmbientBrightness | grep -o '"AmbientBrightness" = [0-9]*' | head -1
```

~25 ms with `-k`; the naive `ioreg -l -c AppleCLCD2` form dumps the whole tree and costs
~600 ms. Divide by 65536 for lux: `awk -v r=$raw 'BEGIN{printf "%.0f", r/65536}'`.

Rough anchors: dim room with one lamp 10–30 lux, normal room 40–120, bright daylight
interior 300+. Calibrate on the actual machine — the sensor sits near the camera and reads
the room in front of the screen, not the screen itself.

Requires the display driver to be publishing the key; verify before building on it:

```bash
ioreg -r -l -w 0 -k AmbientBrightness | grep -c AmbientBrightness   # 0 = not available
```

If it returns 0 (external-display-only setups, some Macs), fall back to the OS appearance
(`defaults read -g AppleInterfaceStyle`) and let the user drive it manually.

## Making it not annoying

Two properties separate a useful switcher from one the user disables in a day:

1. **Dead zone.** One threshold flips the theme every time a cloud passes. Use two: below
   `LUX_DARK` go dark, above `LUX_LIGHT` go light, in between change nothing. 25/55 is a
   reasonable start.
2. **Manual override.** When the user switches by hand, suppress the automation for a few
   hours — otherwise the next poll undoes their choice and they never trust it again.
   A touched file plus an age check is enough.

Poll every 60 s. The read is cheap, and a slower cadence makes the switch feel broken.

## launchd agent

`../references/configs/com.example.theme-auto.plist` → `~/Library/LaunchAgents/`, then
`launchctl load`. Notes:

- Run the script through `/bin/zsh -lc` so it inherits a login PATH
- `StartInterval 60` plus `RunAtLoad`
- Log to a file — a launchd agent that fails silently is the second-most-common failure
  here (the first is a PATH that doesn't include the script)
- The agent talks to Terminal.app via AppleScript, so the first run raises an Automation
  permission dialog. Tell the user to expect it

## What to switch, and what not to

Switch: the terminal palette (live, via remote control if the terminal has one), the
agent's own theme, the statusline palette.

Do not switch the OS appearance unless explicitly asked. `tell application "System Events"
to tell appearance preferences to set dark mode to true` changes Finder, Safari and every
other app — far beyond "make my terminal readable". Keep it behind an explicit flag.
