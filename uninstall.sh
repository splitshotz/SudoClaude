#!/usr/bin/env bash
# Removes SudoClaude from Claude, stops the voice assistant and takes out the
# keybinds and browser flags it added. Your settings in ~/.config/sudoclaude
# and the models in ~/.local/share/sudoclaude stay unless you pass --purge.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PURGE=0; [[ "${1:-}" == --purge ]] && PURGE=1

command -v claude >/dev/null && claude mcp remove -s user sudoclaude >/dev/null 2>&1 \
  && echo "Removed from Claude Code"

CFG="${XDG_CONFIG_HOME:-$HOME/.config}/Claude/claude_desktop_config.json"
if [[ -f "$CFG" ]]; then
  python3 - "$CFG" <<'PY'
import json, sys
p = sys.argv[1]
try:
    d = json.load(open(p))
except Exception:
    sys.exit()
if d.get("mcpServers", {}).pop("sudoclaude", None) is not None:
    json.dump(d, open(p, "w"), indent=2)
    print("Removed from the Claude desktop app")
PY
fi

if systemctl --user list-unit-files sudoclaude-voice.service >/dev/null 2>&1; then
  systemctl --user disable --now sudoclaude-voice.service 2>/dev/null
  rm -f "$HOME/.config/systemd/user/sudoclaude-voice.service"
  systemctl --user daemon-reload
  echo "Voice assistant stopped"
fi

H="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
for f in "$H"/custom/keybinds.lua "$H"/custom/keybinds.conf "$H"/hyprland.lua "$H"/hyprland.conf; do
  [[ -f "$f" ]] && grep -q "sudoclaude" "$f" || continue
  cp "$f" "$f.bak-sudoclaude-removed"
  python3 - "$f" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p).read()
# The blocks SudoClaude adds start with a "SudoClaude" comment and run to the
# next blank line.
s = re.sub(r"\n*(?:--|#) SudoClaude[^\n]*\n(?:[^\n]+\n)*", "\n\n", s).replace("\n\n\n", "\n\n")
open(p, "w").write(s)
PY
  echo "Removed keybinds from $f"
done

FLAGS="$HOME/.config/chromium-flags.conf"
[[ -f "$FLAGS" ]] && sed -i '/sudoclaude/d' "$FLAGS" && echo "Removed the Chromium extension flags"

pkill -f "[o]verlay/overlay.qml" 2>/dev/null

if ((PURGE)); then
  rm -rf "$HOME/.config/sudoclaude" "$HOME/.local/share/sudoclaude" "$HOME/.local/state/sudoclaude"
  echo "Deleted settings, models and state"
fi
echo "SudoClaude is uninstalled. The source folder ($DIR) is still there; delete it if you like."
