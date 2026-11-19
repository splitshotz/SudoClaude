#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$DIR/bin/sudoclaude"
chmod +x "$BIN"

need=(python python-pillow python-gobject at-spi2-core grim wl-clipboard zenity libnotify)
missing=()
for p in "${need[@]}"; do pacman -Qq "$p" >/dev/null 2>&1 || missing+=("$p"); done
if ((${#missing[@]})); then
  echo "Installing: ${missing[*]}"
  sudo pacman -S --needed --noconfirm "${missing[@]}"
fi

opt=()
pacman -Qq tesseract >/dev/null 2>&1 || opt+=(tesseract tesseract-data-eng)
if ((${#opt[@]})); then
  read -rp "Install tesseract for find_text (OCR)? [Y/n] " a
  [[ "${a:-y}" =~ ^[Yy] ]] && sudo pacman -S --needed --noconfirm "${opt[@]}"
fi
command -v qs >/dev/null || command -v quickshell >/dev/null || \
  echo "Note: quickshell not found, so the on-screen overlay will be disabled."

CFG="${XDG_CONFIG_HOME:-$HOME/.config}/Claude/claude_desktop_config.json"
mkdir -p "$(dirname "$CFG")"
[[ -f "$CFG" ]] && cp "$CFG" "$CFG.bak.$(date +%s)"
python3 - "$CFG" "$BIN" <<'EOF'
import json, os, sys
cfg, binp = sys.argv[1], sys.argv[2]
data = {}
if os.path.exists(cfg) and os.path.getsize(cfg):
    with open(cfg) as f:
        data = json.load(f)
servers = data.setdefault("mcpServers", {})
servers.pop("linux-computer-use", None)
servers["sudoclaude"] = {"command": binp, "args": []}
with open(cfg, "w") as f:
    json.dump(data, f, indent=2)
print("Added to", cfg)
EOF

if command -v claude >/dev/null; then
  claude mcp remove -s user sudoclaude >/dev/null 2>&1 || true
  claude mcp add -s user sudoclaude -- "$BIN" && echo "Added to Claude Code"
fi

"$DIR/bin/sudoclaude-browser-setup" || echo "Browser extension setup failed; run bin/sudoclaude-browser-setup later."

echo
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"desktop","arguments":{"action":"doctor"}}}' \
  | timeout 20 "$BIN" 2>/dev/null | tail -1 \
  | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["result"]["content"][0]["text"])'
echo
echo "Done. Quit Claude from the tray icon and open it again."
