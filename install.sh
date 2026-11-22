#!/usr/bin/env bash
# Installs SudoClaude. Run it on its own and it asks about the optional parts;
# the settings app runs it with flags instead:
#   --yes              don't ask anything (optional parts default to off)
#   --ocr / --no-ocr   tesseract for reading text in apps without accessibility
#   --voice            set up the voice assistant too (install-voice.sh)
#   --browser          set up the Chromium extension
#   --phone            install adb and scrcpy for controlling an Android phone
#   --keybind TALK STOP  combos for the voice keybinds (default SUPER+Space SUPER+SHIFT+Escape)
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$DIR/bin/sudoclaude"
chmod +x "$BIN" "$DIR"/bin/* "$DIR"/*.sh

YES=0; OCR=""; VOICE=""; BROWSER=""; PHONE=""; TALK="SUPER+Space"; STOP="SUPER+SHIFT+Escape"
while (($#)); do
  case "$1" in
    --yes) YES=1 ;;
    --ocr) OCR=1 ;; --no-ocr) OCR=0 ;;
    --voice) VOICE=1 ;; --no-voice) VOICE=0 ;;
    --browser) BROWSER=1 ;; --no-browser) BROWSER=0 ;;
    --phone) PHONE=1 ;; --no-phone) PHONE=0 ;;
    --keybind) TALK="$2"; STOP="$3"; shift 2 ;;
  esac
  shift
done
ask() {  # ask "question" default(y/n) -> 0 for yes
  if ((YES)); then [[ "$2" == y ]]; return; fi
  local a; read -rp "$1 [$([[ $2 == y ]] && echo Y/n || echo y/N)] " a
  [[ "${a:-$2}" =~ ^[Yy] ]]
}
# Root for pacman: sudo in a terminal, the desktop's password prompt otherwise.
asroot() { if [[ -t 0 ]]; then sudo "$@"; else pkexec "$@"; fi; }

if command -v pacman >/dev/null; then
  need=(python python-pillow python-gobject at-spi2-core grim wl-clipboard zenity libnotify)
  missing=()
  for p in "${need[@]}"; do pacman -Qq "$p" >/dev/null 2>&1 || missing+=("$p"); done
  if ((${#missing[@]})); then
    echo "Installing: ${missing[*]}"
    asroot pacman -S --needed --noconfirm "${missing[@]}"
  fi

  opt=()
  pacman -Qq tesseract >/dev/null 2>&1 || opt+=(tesseract tesseract-data-eng)
  if ((${#opt[@]})); then
    if [[ "$OCR" == 1 ]] || { [[ -z "$OCR" ]] && ask "Install tesseract for find_text (OCR)?" y; }; then
      asroot pacman -S --needed --noconfirm "${opt[@]}"
    fi
  fi
else
  # Not Arch: check for the pieces instead of installing them.
  gaps=()
  python3 -c "import PIL" 2>/dev/null || gaps+=("Pillow for python3")
  python3 -c "import gi; gi.require_version('Atspi', '2.0')" 2>/dev/null || gaps+=("PyGObject with AT-SPI")
  for c in grim wl-copy notify-send; do command -v "$c" >/dev/null || gaps+=("$c"); done
  if ((${#gaps[@]})); then
    echo "No pacman here, so install these with your package manager and run this again:"
    printf '  %s\n' "${gaps[@]}"
    exit 1
  fi
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

if command -v pacman >/dev/null; then
  phone=()
  command -v adb >/dev/null || [[ -x "$HOME/Android/Sdk/platform-tools/adb" ]] || phone+=(android-tools)
  command -v scrcpy >/dev/null || phone+=(scrcpy)
  if ((${#phone[@]})) && { [[ "$PHONE" == 1 ]] || { [[ -z "$PHONE" ]] && ask "Install ${phone[*]} so Claude can use your Android phone?" n; }; }; then
    asroot pacman -S --needed --noconfirm "${phone[@]}"
  fi
fi

if command -v chromium >/dev/null || command -v google-chrome-stable >/dev/null; then
  if [[ "$BROWSER" == 1 ]] || { [[ -z "$BROWSER" ]] && ask "Set up the Chromium extension (lets Claude work inside browser tabs)?" n; }; then
    "$DIR/bin/sudoclaude-browser-setup" || \
      echo "Browser extension setup failed; run bin/sudoclaude-browser-setup later."
  fi
fi

if [[ "$VOICE" == 1 ]] || { [[ -z "$VOICE" ]] && ask "Set up the \"Claude\" voice assistant too (downloads ~2 GB of models)?" n; }; then
  "$DIR/install-voice.sh" || echo "Voice setup failed; run ./install-voice.sh later."
  "$DIR/bin/sudoclaude-keybind" "$TALK" "$STOP" || echo "Skipped the keybind; see the README."
fi

echo
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"desktop","arguments":{"action":"doctor"}}}' \
  | timeout 20 "$BIN" 2>/dev/null | tail -1 \
  | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["result"]["content"][0]["text"])'
echo
echo "Done. Quit Claude from the tray icon and open it again."
