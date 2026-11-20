#!/bin/sh
# Launcher inside the Flatpak: the PySide6 wheels live in /app/pyside.
export PYTHONPATH="/app/share/sudoclaude-settings:/app/pyside${PYTHONPATH:+:$PYTHONPATH}"
exec python3 -m sudoclaude_app "$@"
