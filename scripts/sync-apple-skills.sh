#!/usr/bin/env bash
#
# Pull Apple's own agent skills out of the installed Xcode toolchain.
#
# Xcode ships them as ordinary Agent-Skills folders (`SKILL.md` + references),
# so once exported they work in any agent — Claude Code, Cursor, Codex — not
# only in Xcode's assistant. Measured on Xcode 27.0 beta 2, ten of them:
# adopt-c-bounds-safety, app-intents-specialist, app-intents-whats-new-27,
# audit-xcode-security-settings, building-document-based-swiftui-applications,
# device-interaction, modernize-tests, swiftui-specialist, swiftui-whats-new-27,
# uikit-app-modernization.
#
# Re-run after every Xcode update: the skills track the SDK, and a stale
# "what's new" skill is worse than none. There is no version stamp to compare,
# so the script prints what changed and leaves the decision to you.
#
# It exports from whichever installed Xcode actually *has* skills, not from
# whichever one `xcode-select` happens to point at. Those are usually
# different: the skills arrive with Xcode 27, and most people keep 26 selected
# because it is the release toolchain they build against. Measured 29 Aug
# 2026 — Xcode 26.6 exports nothing at all, and the script used to answer
# "this Xcode ships no agent skills yet" and stop, which reads as "not
# available yet" rather than "look in the other one".
#
#   ./scripts/sync-apple-skills.sh              # into ~/.agents/skills
#   ./scripts/sync-apple-skills.sh --dry-run    # what would land, no writes
#   ./scripts/sync-apple-skills.sh --into DIR
#   DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer ./scripts/…   # force one
set -euo pipefail

DEST="${HOME}/.agents/skills"
DRY=0
while [ $# -gt 0 ]; do
    case "$1" in
        --into) DEST="$2"; shift 2 ;;
        --dry-run) DRY=1; shift ;;
        -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

say() { printf '  %s\n' "$1"; }

# Which toolchain: an explicit DEVELOPER_DIR wins, then the selected one,
# then any other Xcode on the machine. `agent skills export` is the probe —
# a toolchain with no skills answers with none, and there is no cheaper
# question to ask it.
has_skills() {
    local dev="$1" bin
    bin="$(DEVELOPER_DIR="$dev" xcrun --find agent 2>/dev/null)" || return 1
    local probe; probe="$(mktemp -d)"
    DEVELOPER_DIR="$dev" "$bin" skills export --output-dir "$probe" --replace-existing >/dev/null 2>&1 || { rm -rf "$probe"; return 1; }
    local n; n=$(find "$probe" -name SKILL.md -maxdepth 2 2>/dev/null | wc -l | tr -d ' ')
    rm -rf "$probe"
    [ "$n" -gt 0 ]
}

candidates=()
[ -n "${DEVELOPER_DIR:-}" ] && candidates+=("$DEVELOPER_DIR")
selected="$(xcode-select -p 2>/dev/null || true)"
[ -n "$selected" ] && candidates+=("$selected")
for app in /Applications/Xcode*.app; do
    [ -d "$app/Contents/Developer" ] && candidates+=("$app/Contents/Developer")
done

xcode=""
for dev in "${candidates[@]}"; do
    case " ${seen:-} " in *" $dev "*) continue ;; esac
    seen="${seen:-} $dev"
    if has_skills "$dev"; then xcode="$dev"; break; fi
done

if [ -z "$xcode" ]; then
    say "no Xcode on this machine ships agent skills."
    say "They arrive with Xcode 27; 26.x exports nothing. Checked:"
    for dev in ${seen:-}; do say "  $dev"; done
    exit 1
fi

export DEVELOPER_DIR="$xcode"
version="$(xcodebuild -version 2>/dev/null | head -1)"
say "${version:-Xcode} at $xcode"
[ "$xcode" = "$selected" ] || say "(not the selected toolchain — that one ships no skills)"
agent_bin="$(xcrun --find agent)"

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT

# The exporter writes into the CWD by default, which is never what you want.
if ! out="$("$agent_bin" skills export --output-dir "$staging" --replace-existing 2>&1)"; then
    say "export failed:"
    printf '     %s\n' "$out"
    say "If it names the toolchain: Xcode → Settings → Locations → Command Line"
    say "Tools, and pick the Xcode you actually want to export from."
    exit 1
fi

found=$(find "$staging" -name SKILL.md -maxdepth 2 2>/dev/null | wc -l | tr -d ' ')
if [ "$found" -eq 0 ]; then
    say "nothing exported — this Xcode ships no agent skills yet."
    say "Measured on Xcode 26.6: \"No skills available to export\". They arrive"
    say "with Xcode 27; re-run this after the update."
    exit 0
fi

say "$found skill(s) exported"
for dir in "$staging"/*/; do
    [ -f "${dir}SKILL.md" ] || continue
    name="$(basename "$dir")"
    if [ -d "$DEST/$name" ]; then
        if diff -rq "$dir" "$DEST/$name" >/dev/null 2>&1; then
            say "  = $name (unchanged)"
            continue
        fi
        say "  ~ $name (updated)"
    else
        say "  + $name (new)"
    fi
    [ "$DRY" -eq 1 ] && continue
    rm -rf "${DEST:?}/$name"
    mkdir -p "$DEST"
    cp -R "$dir" "$DEST/$name"
done

[ "$DRY" -eq 1 ] && say "dry run — nothing written to $DEST"
exit 0
