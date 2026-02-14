#!/bin/bash
# Link solo-factory as live plugin in Claude Code cache.
# Run once after `claude plugin install solo@solo` or after version bump.
#
# What it does:
#   1. Reads version from plugin.json
#   2. Replaces cache copy with symlink → solo-factory
#   3. Updates installed_plugins.json version if needed
#   4. Result: edit files → changes are live immediately
#
# Usage:
#   ./scripts/link-plugin.sh          # from solo-factory dir
#   make plugin-link                  # via Makefile

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PLUGIN_JSON="$PLUGIN_DIR/.claude-plugin/plugin.json"
INSTALLED_JSON="$HOME/.claude/plugins/installed_plugins.json"
CACHE_BASE="$HOME/.claude/plugins/cache/solo/solo"

# Read version from plugin.json
VERSION=$(python3 -c "import json; print(json.load(open('$PLUGIN_JSON'))['version'])")
CACHE_DIR="$CACHE_BASE/$VERSION"

echo "solo-factory: $PLUGIN_DIR"
echo "version:      $VERSION"
echo "cache target: $CACHE_DIR"

# 1. Ensure solo → .claude-plugin symlink exists (Claude Code expects solo/plugin.json)
if [[ ! -L "$PLUGIN_DIR/solo" ]]; then
  ln -s .claude-plugin "$PLUGIN_DIR/solo"
  echo "Created: solo → .claude-plugin"
fi

# 2. Remove ALL version dirs in cache (clean slate)
if [[ -d "$CACHE_BASE" ]]; then
  for old in "$CACHE_BASE"/*/; do
    [[ -e "$old" ]] || continue
    rm -rf "$old"
  done
fi

# 3. Create symlink
mkdir -p "$CACHE_BASE"
ln -s "$PLUGIN_DIR" "$CACHE_DIR"
echo "Linked: $CACHE_DIR → $PLUGIN_DIR"

# 4. Update installed_plugins.json version + installPath
if [[ -f "$INSTALLED_JSON" ]]; then
  python3 -c "
import json, sys
path = '$INSTALLED_JSON'
data = json.load(open(path))
key = 'solo@solo'
if key in data.get('plugins', {}):
    for entry in data['plugins'][key]:
        entry['version'] = '$VERSION'
        entry['installPath'] = '$CACHE_DIR'
    json.dump(data, open(path, 'w'), indent=2)
    print(f'Updated installed_plugins.json → {\"$VERSION\"}')
else:
    print('Warning: solo@solo not found in installed_plugins.json')
    print('Run first: claude plugin install solo@solo --scope user')
"
fi

echo ""
echo "Done. Restart Claude Code session to pick up changes."
