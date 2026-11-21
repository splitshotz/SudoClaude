"""Is a game running? One answer shared by the overlay, the MCP server and the
voice assistant, so they all get out of the way at the same moment.

A game counts when any of these is true:
- Steam launched it (`reaper SteamLaunch AppId=N`)
- a process named in config "game_apps" (or the built-in list) is running
- a Windows .exe is running under Wine/Proton
- a Hyprland window says contentType "game", or is truly fullscreen and isn't
  a browser, video player or terminal

Standard library only, and cached for a second, so calling it on every overlay
message costs nothing.
"""
import json
import os
import re
import socket
import time

CONFIG = os.path.expanduser("~/.config/sudoclaude/config.json")
DEFAULT_APPS = {"longshot", "gamescope", "gamescope-wl", "retroarch", "dolphin-emu",
                "Ryujinx", "yuzu", "citron", "eden", "pcsx2-qt", "rpcs3", "ppsspp",
                "cemu", "xemu", "duckstation-qt", "minecraft-launcher"}
# Fullscreen windows of these classes are not games (fullscreen video, slides...).
NOT_GAMES = re.compile(r"(?i)firefox|zen|chrom|brave|vivaldi|edge|librewolf|mpv|vlc|celluloid|"
                       r"haruna|totem|showtime|clapper|kitty|alacritty|foot|wezterm|ghostty|"
                       r"konsole|terminal|claude|obsidian|code|libreoffice|evince|okular|"
                       r"imv|loupe|eog|swayimg")
_cache = (0.0, None)
_cfg = (None, {})


def _config():
    global _cfg
    try:
        mtime = os.stat(CONFIG).st_mtime
    except OSError:
        return {}
    if mtime != _cfg[0]:
        try:
            with open(CONFIG) as f:
                _cfg = (mtime, json.load(f))
        except (OSError, ValueError):
            _cfg = (mtime, {})
    return _cfg[1]


def enabled():
    return _config().get("hide_in_games", True)


def _from_processes(apps):
    me = os.getpid()
    for entry in os.scandir("/proc"):
        if not entry.name.isdigit() or int(entry.name) == me:
            continue
        try:
            with open(f"/proc/{entry.name}/cmdline", "rb") as f:
                argv = f.read().split(b"\0")
        except OSError:
            continue
        if not argv or not argv[0]:
            continue
        exe = argv[0].decode(errors="replace").replace("\\", "/")
        base = os.path.basename(exe)
        if b"SteamLaunch" in argv:
            for a in argv:
                m = re.match(rb"AppId=(\d+)$", a)
                if m and m.group(1) != b"0":
                    return f"Steam game {m.group(1).decode()}"
        if base in apps:
            return base
        # Wine/Proton processes show their Windows path; skip Wine's own helpers.
        if base.lower().endswith(".exe") and base.lower() not in (
                "wineserver.exe", "services.exe", "winedevice.exe", "plugplay.exe",
                "explorer.exe", "rpcss.exe", "svchost.exe", "conhost.exe", "start.exe",
                "steam.exe", "steamwebhelper.exe", "tabtip.exe", "rundll32.exe"):
            return base
    return None


def _hypr_clients():
    run = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if not sig:
        try:
            dirs = [os.path.join(run, "hypr", d) for d in os.listdir(os.path.join(run, "hypr"))]
            dirs = [d for d in dirs if os.path.exists(os.path.join(d, ".socket.sock"))]
            sig = os.path.basename(max(dirs, key=os.path.getmtime)) if dirs else None
        except OSError:
            sig = None
    if not sig:
        return []
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(1)
    try:
        s.connect(os.path.join(run, "hypr", sig, ".socket.sock"))
        s.sendall(b"j/clients")
        buf = b""
        while True:
            d = s.recv(65536)
            if not d:
                break
            buf += d
        return json.loads(buf or b"[]")
    except (OSError, ValueError):
        return []
    finally:
        s.close()


def _from_windows():
    for c in _hypr_clients():
        if not c.get("mapped", True):
            continue
        cls = c.get("class") or c.get("initialClass") or ""
        if c.get("contentType") == "game":
            return cls or "a game"
        if c.get("fullscreen") == 2 and cls and not NOT_GAMES.search(cls):
            return cls
    return None


def running(force=False):
    """Name of the running game, or None. Always None when hide_in_games is off."""
    global _cache
    if not enabled():
        return None
    now = time.monotonic()
    if not force and now - _cache[0] < 1.0:
        return _cache[1]
    cfg = _config()
    apps = DEFAULT_APPS | set(cfg.get("game_apps") or [])
    try:
        name = _from_processes(apps) or _from_windows()
    except Exception:
        name = None
    _cache = (now, name)
    return name


if __name__ == "__main__":
    print(running(force=True) or "no game")
