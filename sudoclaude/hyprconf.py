import glob
import os
import re

MOD_ALIASES = {"CONTROL": "CTRL", "CTL": "CTRL", "WIN": "SUPER", "LOGO": "SUPER",
               "MOD4": "SUPER", "MOD1": "ALT", "META": "SUPER"}


def norm_mods(s):
    toks = [t for t in re.split(r"[\s_+]+", (s or "").upper()) if t]
    return frozenset(MOD_ALIASES.get(t, t) for t in toks)


def _expand(path, base, vars_):
    for k, v in sorted(vars_.items(), key=lambda kv: -len(kv[0])):
        path = path.replace("$" + k, v)
    path = os.path.expanduser(path.strip())
    if not os.path.isabs(path):
        path = os.path.join(base, path)
    return sorted(glob.glob(path))


def parse(root=None):
    root = root or os.path.join(os.environ.get("XDG_CONFIG_HOME") or
                                os.path.expanduser("~/.config"), "hypr", "hyprland.conf")
    vars_, out, seen = {}, {}, set()
    mtimes = {}

    def walk(path):
        real = os.path.realpath(path)
        if real in seen or not os.path.isfile(real):
            return
        seen.add(real)
        try:
            mtimes[real] = os.path.getmtime(real)
            lines = open(real, encoding="utf-8", errors="replace").read().splitlines()
        except OSError:
            return
        section = ""
        base = os.path.dirname(real)
        for raw in lines:
            line = raw.strip()
            m = re.match(r"^#+!\s*(.*?)\s*#*$", line)
            if m:
                title = re.sub(r"[#=\-\s]+$", "", m.group(1)).strip(" #=-")
                if title:
                    section = title
                continue
            if not line or line.startswith("#"):
                continue
            m = re.match(r"^\$(\w+)\s*=\s*(.*?)\s*(#.*)?$", line)
            if m:
                vars_[m.group(1)] = m.group(2)
                continue
            m = re.match(r"^source\s*=\s*(.+?)\s*(#.*)?$", line)
            if m:
                for p in _expand(m.group(1), base, vars_):
                    walk(p)
                continue
            m = re.match(r"^(bind[a-z]*)\s*=\s*(.*)$", line)
            if not m:
                continue
            flags, rest = m.group(1)[4:], m.group(2)
            comment = ""
            if "#" in rest:
                # comments start at ' #' (a bare # can be part of a key/arg)
                idx = rest.find(" #")
                if idx >= 0:
                    rest, comment = rest[:idx], rest[idx + 2:].strip()
            for k, v in sorted(vars_.items(), key=lambda kv: -len(kv[0])):
                rest = rest.replace("$" + k, v)
            parts = [p.strip() for p in rest.split(",")]
            if len(parts) < 2:
                continue
            mods, key = norm_mods(parts[0]), parts[1].lower()
            hidden = "[hidden]" in comment.lower()
            desc = re.sub(r"\[hidden\]", "", comment, flags=re.I).strip(" -:")
            if not desc and "d" in flags and len(parts) >= 3:
                desc = parts[2]
            out[(mods, key)] = {"description": desc, "section": section,
                                "hidden": hidden, "file": real}
    walk(root)
    return out, mtimes


class KeybindLabels:
    def __init__(self):
        self.data, self.mtimes = {}, {}
        self.loaded = 0

    def get(self):
        stale = not self.loaded or any(
            (os.path.getmtime(p) if os.path.exists(p) else 0) != t
            for p, t in self.mtimes.items())
        if stale:
            try:
                self.data, self.mtimes = parse()
            except Exception:
                self.data, self.mtimes = {}, {}
            self.loaded = 1
        return self.data

    def label(self, mods_str, key):
        return self.get().get((norm_mods(mods_str.replace("+", " ")), (key or "").lower()))
