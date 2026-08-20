#!/usr/bin/env bash
#
# Pull Apple's own agent skills out of the installed Xcode toolchain.
#
# Xcode ships them as ordinary Agent-Skills folders (`SKILL.md` + references),
# so once exported they work in any agent — Claude Code, Cursor, Codex — not
# only in Xcode's assistant. Expected set from Xcode 27: swiftui-specialist,
# swiftui-whats-new, uikit-app-modernization, test-modernizer,
# audit-xcode-security-settings, c-bounds-safety, device-interaction.
#
# Re-run after every Xcode update: the skills track the SDK, and a stale
# "what's new" skill is worse than none. There is no version stamp to compare,
# so the script prints what changed and leaves the decision to you.
#
#   ./scripts/sync-apple-skills.sh              # into ~/.agents/skills
#   ./scripts/sync-apple-skills.sh --dry-run    # what would land, no writes
#   ./scripts/sync-apple-skills.sh --into DIR
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

xcode="$(xcode-select -p 2>/dev/null || true)"
[ -n "$xcode" ] || { say "no Xcode selected — xcode-select -p is empty"; exit 1; }
version="$(xcodebuild -version 2>/dev/null | head -1 || echo 'unknown')"
say "$version at $xcode"

# `xcrun agent` exists from Xcode 26; the skills themselves arrive with 27.
if ! agent_bin="$(xcrun --find agent 2>/dev/null)"; then
    say "this toolchain has no \`agent\` tool — Xcode 26 or newer is needed"
    exit 1
fi

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
