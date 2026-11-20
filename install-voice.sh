#!/usr/bin/env bash
# Sets up the "Claude" voice assistant: Python env, models, echo cancellation,
# wake word, and a user service that starts it with the desktop.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}/sudoclaude"
VENV="$DATA/venv"
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }

asroot() { if [[ -t 0 ]]; then sudo "$@"; else pkexec "$@"; fi; }
if ! command -v uv >/dev/null; then
  step "Installing uv"
  asroot pacman -S --needed --noconfirm uv || { echo "needs uv (pacman -S uv)"; exit 1; }
fi

step "Python environment"
[[ -x "$VENV/bin/python" ]] || uv venv --python 3.11 "$VENV"
uv pip install --python "$VENV/bin/python" -q \
  numpy scipy soundfile onnxruntime "openwakeword>=0.6" "onnx-asr[cpu,hub]" \
  kokoro-onnx espeakng-loader claude-agent-sdk huggingface_hub "setuptools<81"
if [[ "${1:-}" != "--no-chatterbox" ]]; then
  step "Chatterbox voice (GPU)"
  uv pip install --python "$VENV/bin/python" -q chatterbox-tts || \
    echo "  chatterbox failed to install; Kokoro will be used"
fi

step "Models"
"$DIR/bin/sudoclaude-voice" setup

step "Echo cancellation"
DROP="$HOME/.config/pipewire/pipewire.conf.d/60-sudoclaude-echo-cancel.conf"
mic="$(pactl -f json list sources | python3 -c '
import json,sys
src=[s for s in json.load(sys.stdin) if s["name"].startswith("alsa_input.")]
usb=[s for s in src if "usb" in s["name"]]
print((usb or src or [{"name":""}])[0]["name"])')"
if [[ -n "$mic" && ! -f "$DROP" ]]; then
  mkdir -p "$(dirname "$DROP")"
  sed "s|capture.props = {|capture.props = {\n                target.object = \"$mic\"|" \
    "$DIR/systemd/sudoclaude-echo-cancel.conf" > "$DROP"
  systemctl --user restart pipewire pipewire-pulse
  sleep 3
  if pactl list short sources | grep -q sudoclaude_mic; then
    echo "  echo-cancelled input on $mic"
  else
    echo "  module did not load; removing it"; rm -f "$DROP"
    systemctl --user restart pipewire pipewire-pulse
  fi
fi

step "Wake word"
if [[ ! -f "$DATA/models/claude.onnx" ]]; then
  uv pip install --python "$VENV/bin/python" -q torch onnx || true
  "$DIR/bin/sudoclaude-voice" train || echo "  training failed; using hey-claude only"
fi

step "Service"
mkdir -p "$HOME/.config/systemd/user"
sed "s|%h/Projects/SudoClaude|$DIR|" "$DIR/systemd/sudoclaude-voice.service" \
  > "$HOME/.config/systemd/user/sudoclaude-voice.service"
systemctl --user daemon-reload
systemctl --user enable --now sudoclaude-voice.service
echo
echo "Say \"Claude\" to try it. Logs: journalctl --user -u sudoclaude-voice -f"
