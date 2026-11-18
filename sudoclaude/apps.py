import configparser
import difflib
import glob
import os
import re
import shlex
import shutil


def _dirs():
    home = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    data = (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":")
    ds = [home] + data + ["/var/lib/flatpak/exports/share",
                          os.path.expanduser("~/.local/share/flatpak/exports/share"),
                          "/var/lib/snapd/desktop"]
    seen, out = set(), []
    for d in ds:
        p = os.path.join(d, "applications")
        if p not in seen and os.path.isdir(p):
            seen.add(p)
            out.append(p)
    return out


class App:
    __slots__ = ("id", "name", "generic", "exec", "wmclass", "keywords", "categories",
                 "path", "terminal")

    def as_dict(self):
        return {"id": self.id, "name": self.name, "class": self.wmclass or self.id,
                **({"generic": self.generic} if self.generic else {})}

    @property
    def app_key(self):
        """Best guess at the window class this app will use."""
        return (self.wmclass or self.id).lower()


_cache = {"t": 0, "apps": []}


def list_apps(refresh=False):
    import time
    if not refresh and _cache["apps"] and time.time() - _cache["t"] < 60:
        return _cache["apps"]
    apps = {}
    for d in _dirs():
        for path in glob.glob(os.path.join(d, "**", "*.desktop"), recursive=True):
            aid = os.path.relpath(path, d)[:-8].replace("/", "-")
            if aid in apps:
                continue  # earlier dirs (user) take precedence
            cp = configparser.RawConfigParser(strict=False, interpolation=None)
            try:
                cp.read(path, encoding="utf-8")
                e = cp["Desktop Entry"]
            except Exception:
                continue
            if e.get("Type", "Application") != "Application":
                continue
            if e.get("NoDisplay", "false").lower() == "true" or \
                    e.get("Hidden", "false").lower() == "true":
                apps[aid] = None
                continue
            a = App()
            a.id, a.path = aid, path
            a.name = e.get("Name", aid)
            a.generic = e.get("GenericName", "")
            a.exec = e.get("Exec", "")
            a.wmclass = e.get("StartupWMClass", "")
            a.keywords = e.get("Keywords", "")
            a.categories = e.get("Categories", "")
            a.terminal = e.get("Terminal", "false").lower() == "true"
            if a.exec:
                apps[aid] = a
    out = sorted((a for a in apps.values() if a), key=lambda a: a.name.lower())
    _cache.update(t=__import__("time").time(), apps=out)
    return out


def find_app(query):
    q = query.strip().lower()
    apps = list_apps()
    if not apps:
        return None
    for key in (lambda a: a.name.lower(), lambda a: a.id.lower(),
                lambda a: (a.wmclass or "").lower(), lambda a: a.id.lower().split(".")[-1]):
        for a in apps:
            if key(a) == q:
                return a
    for a in apps:
        if a.name.lower().startswith(q):
            return a
    for a in apps:
        hay = " ".join([a.name, a.id, a.wmclass or "", a.generic, a.keywords]).lower()
        if q in hay:
            return a
    names = {a.name.lower(): a for a in apps}
    m = difflib.get_close_matches(q, list(names), n=1, cutoff=0.6)
    return names[m[0]] if m else None


def launch_command(app):
    if shutil.which("gtk-launch"):
        return f"gtk-launch {shlex.quote(app.id)}"
    cmd = re.sub(r"%[fFuUdDnNickvm]", "", app.exec).replace("%%", "%").strip()
    if app.terminal:
        term = next((t for t in ("kitty", "foot", "alacritty", "wezterm", "konsole")
                     if shutil.which(t)), None)
        if term:
            cmd = f"{term} -e {cmd}"
    return cmd


def window_matches(app, win):
    keys = {app.app_key, app.id.lower(), app.id.lower().split(".")[-1],
            app.name.lower()}
    wc = (win.get("app") or "").lower()
    ic = (win.get("initial_app") or "").lower()
    return wc in keys or ic in keys or any(k and (k == wc.split(".")[-1]) for k in keys)
