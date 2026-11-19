"""Cider (Apple Music) control.

Cider has a local REST API on port 10767. Playing something by name needs it,
because the only search is Apple Music's catalogue, proxied through
/api/v1/amapi/run-v3. Plain transport (pause, skip) falls back to MPRIS via
playerctl, so it still works with the API off or the token wrong.

The token comes from Cider's Settings > Connectivity > Manage External
Application Access and lives in ~/.config/sudoclaude/config.json under
"cider". If it isn't there yet, it's picked up from Relay's config once.
"""

import json
import os
import shutil
import subprocess
import time
import urllib.error
import urllib.request
from urllib.parse import quote

CONFIG = os.path.expanduser("~/.config/sudoclaude/config.json")
RELAY_CONFIG = os.path.expanduser("~/.config/relay/config.toml")
PLAYBACK = "/api/v1/playback"
HEADERS = ("apptoken", "apitoken")


class MusicError(Exception):
    pass


def _settings():
    try:
        with open(CONFIG) as f:
            cfg = json.load(f)
    except (OSError, ValueError):
        cfg = {}
    cider = cfg.get("cider") or {}
    if not cider.get("token") and os.path.exists(RELAY_CONFIG):
        try:
            import tomllib
            with open(RELAY_CONFIG, "rb") as f:
                music = tomllib.load(f).get("music") or {}
            if music.get("cider_token"):
                cider = {"token": music["cider_token"],
                         "url": music.get("cider_url", "http://localhost:10767")}
                cfg["cider"] = cider
                os.makedirs(os.path.dirname(CONFIG), exist_ok=True)
                tmp = CONFIG + ".tmp"
                with open(tmp, "w") as f:
                    json.dump(cfg, f, indent=2)
                os.chmod(tmp, 0o600)
                os.replace(tmp, CONFIG)
        except Exception:
            pass
    return cider


class Cider:
    def __init__(self):
        s = _settings()
        self.url = (s.get("url") or "http://localhost:10767").rstrip("/")
        self.token = s.get("token") or ""
        self.launch_cmd = s.get("command") or "cider"
        self.header = None

    def call(self, method, path, body=None, timeout=6.0):
        names = [self.header] if self.header else list(HEADERS)
        err = "no attempt"
        for name in names:
            headers = {}
            data = None
            if body is not None:
                data = json.dumps(body).encode()
                headers["Content-Type"] = "application/json"
            if self.token:
                headers[name] = self.token
            req = urllib.request.Request(self.url + path, data=data, method=method,
                                         headers=headers)
            try:
                with urllib.request.urlopen(req, timeout=timeout) as r:
                    raw = r.read()
            except urllib.error.HTTPError as e:
                if e.code in (401, 403):
                    err = "Cider rejected the API token"
                    continue
                raise MusicError(f"Cider returned {e.code} for {path}")
            except Exception as e:
                raise MusicError("Cider isn't reachable") from e
            self.header = name
            if not raw:
                return None
            try:
                return json.loads(raw)
            except ValueError:
                return None
        raise MusicError(err + ". Check Settings > Connectivity in Cider and the token in "
                         "~/.config/sudoclaude/config.json (cider.token).")

    def up(self):
        try:
            self.call("GET", f"{PLAYBACK}/is-playing", timeout=1.0)
            return True
        except MusicError:
            return False

    def ensure(self, launch=None, timeout=25.0):
        if self.up():
            return True
        if not launch:
            return False
        launch(self.launch_cmd)
        end = time.time() + timeout
        while time.time() < end:
            time.sleep(0.6)
            if self.up():
                time.sleep(0.8)
                return True
        raise MusicError("Cider didn't finish starting. Its API may be switched off in "
                         "Settings > Connectivity.")

    def search(self, term, kind="songs", limit=5):
        path = f"/v1/catalog/us/search?term={quote(term, safe='')}&types={kind}&limit={limit}"
        data = self.call("POST", "/api/v1/amapi/run-v3", {"path": path}, timeout=12.0)
        res = (((data or {}).get("data") or {}).get("results") or {}).get(kind) or {}
        return res.get("data") or []

    def now(self):
        return ((self.call("GET", f"{PLAYBACK}/now-playing") or {}).get("info")) or {}


def describe(info):
    name = info.get("name") or info.get("title")
    artist = info.get("artistName") or info.get("artist")
    if not name:
        return "Nothing is playing."
    return f"{name} by {artist}" if artist else name


def _mpris_player():
    if not shutil.which("playerctl"):
        return None
    out = subprocess.run(["playerctl", "-l"], capture_output=True, text=True).stdout.split()
    for p in out:
        if "cider" in p.lower():
            return p
    # Cider shows up as chromium.instanceNNN; its Identity property says Cider.
    for p in out:
        r = subprocess.run(["busctl", "--user", "get-property", f"org.mpris.MediaPlayer2.{p}",
                            "/org/mpris/MediaPlayer2", "org.mpris.MediaPlayer2", "Identity"],
                           capture_output=True, text=True)
        if "cider" in r.stdout.lower():
            return p
    return None


def _mpris(*args):
    p = _mpris_player()
    if not p:
        raise MusicError("Cider isn't running")
    r = subprocess.run(["playerctl", "--player", p, *args], capture_output=True, text=True)
    if r.returncode:
        raise MusicError((r.stderr or r.stdout).strip() or "playerctl failed")
    return r.stdout.strip()


TRANSPORT = {"pause": ("pause", "pause", "Paused."), "resume": ("play", "play", "Playing."),
             "next": ("next", "next", "Skipped."), "previous": ("previous", "previous", "Went back.")}


def run(action, query=None, kind="songs", percent=None, seconds=None, launch=None, delta=None):
    """One music action. Returns a short sentence; raises MusicError."""
    c = Cider()
    if action in TRANSPORT:
        rest, mp, done = TRANSPORT[action]
        if action == "resume" and not c.up() and launch:
            c.ensure(launch)
        try:
            if c.up():
                c.call("POST", f"{PLAYBACK}/{rest}")
                return done
        except MusicError:
            pass
        _mpris(mp)
        return done
    if action == "play":
        c.ensure(launch)
        if not query:
            c.call("POST", f"{PLAYBACK}/play")
            return "Playing."
        hits = c.search(query, kind or "songs")
        if not hits:
            raise MusicError(f"Nothing on Apple Music for '{query}'.")
        best = hits[0]
        c.call("POST", f"{PLAYBACK}/play-item", {"type": best.get("type") or kind,
                                                  "id": str(best.get("id"))})
        return "Playing " + describe(best.get("attributes") or {}) + "."
    if action == "now_playing":
        try:
            if c.up():
                return describe(c.now())
        except MusicError:
            pass
        try:
            return _mpris("metadata", "--format", "{{title}} by {{artist}}") or "Nothing is playing."
        except MusicError:
            return "Nothing is playing."
    if not c.up():
        raise MusicError("Cider isn't running.")
    if action == "volume":
        if delta is not None:
            v = float((c.call("GET", f"{PLAYBACK}/volume") or {}).get("volume", 0))
            percent = round(v * 100) + int(delta)
        if percent is None:
            v = float((c.call("GET", f"{PLAYBACK}/volume") or {}).get("volume", 0))
            return f"Volume is {round(v * 100)}%."
        p = max(0, min(100, int(percent)))
        c.call("POST", f"{PLAYBACK}/volume", {"volume": p / 100})
        return f"Volume {p}%."
    if action == "seek":
        c.call("POST", f"{PLAYBACK}/seek", {"position": max(0, int(seconds or 0))})
        return "Done."
    if action in ("shuffle", "repeat"):
        c.call("POST", f"{PLAYBACK}/toggle-{action}")
        mode = (c.call("GET", f"{PLAYBACK}/{action}-mode") or {}).get("value", 0)
        if action == "shuffle":
            return "Shuffle on." if mode else "Shuffle off."
        return ["Repeat off.", "Repeating this song.", "Repeating all."][int(mode) % 3]
    if action == "queue":
        q = c.call("GET", f"{PLAYBACK}/queue") or []
        names = [describe(i.get("attributes") or i) for i in q[:8]] if isinstance(q, list) else []
        return "; ".join(names) or "The queue is empty."
    raise MusicError(f"unknown music action {action!r}")
