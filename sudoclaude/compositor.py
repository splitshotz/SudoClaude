import glob
import json
import os
import socket
import struct


def _runtime():
    return os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"


class Hyprland:
    name = "hyprland"

    def __init__(self):
        self.sock_path = self._find()

    @staticmethod
    def _find():
        sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
        cands = []
        if sig:
            cands += [os.path.join(_runtime(), "hypr", sig, ".socket.sock"),
                      os.path.join("/tmp/hypr", sig, ".socket.sock")]
        found = glob.glob(os.path.join(_runtime(), "hypr", "*", ".socket.sock")) + \
            glob.glob("/tmp/hypr/*/.socket.sock")
        cands += sorted(found, key=lambda p: os.path.getmtime(p), reverse=True)
        for c in cands:
            if os.path.exists(c):
                try:
                    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                    s.settimeout(1)
                    s.connect(c)
                    s.close()
                    return c
                except OSError:
                    continue
        raise RuntimeError("Hyprland socket not found")

    def _req(self, cmd):
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(3)
        try:
            s.connect(self.sock_path)
        except OSError:
            self.sock_path = self._find()
            s.connect(self.sock_path)
        s.sendall(cmd.encode())
        chunks = []
        while True:
            d = s.recv(65536)
            if not d:
                break
            chunks.append(d)
        s.close()
        return b"".join(chunks).decode(errors="replace")

    def j(self, what):
        return json.loads(self._req("j/" + what))

    def windows(self, clients=None, active=None):
        active = self.j("activewindow") if active is None else active
        active = active or {}
        out = []
        for c in (self.j("clients") if clients is None else clients):
            if not c.get("mapped", True):
                continue
            ws = c.get("workspace") or {}
            out.append({
                "id": c["address"], "app": c.get("class") or c.get("initialClass"),
                "initial_app": c.get("initialClass"),
                "title": c.get("title", ""), "x": c["at"][0], "y": c["at"][1],
                "width": c["size"][0], "height": c["size"][1],
                "workspace": ws.get("name"), "workspace_id": ws.get("id"),
                "monitor": c.get("monitor"), "floating": c.get("floating"),
                "fullscreen": c.get("fullscreen"), "pinned": c.get("pinned", False),
                "pid": c.get("pid"), "hidden": c.get("hidden", False),
                "xwayland": c.get("xwayland", False),
                "focus_order": c.get("focusHistoryID", 99),
                "focused": c["address"] == active.get("address"),
            })
        return out

    def visible_windows(self):
        """Windows currently on screen, ordered bottom -> top."""
        mons = self.j("monitors")
        vis = set()
        for m in mons:
            vis.add((m.get("activeWorkspace") or {}).get("id"))
            sp = (m.get("specialWorkspace") or {}).get("id")
            if sp:
                vis.add(sp)
        wins = [w for w in self.windows() if not w["hidden"] and
                (w["workspace_id"] in vis or w["pinned"])]

        def z(w):
            special = 1 if (w["workspace_id"] or 0) < 0 else 0
            fs = 1 if w["fullscreen"] else 0
            return (special, fs, 1 if w["floating"] else 0, -w["focus_order"])
        return sorted(wins, key=z)

    def window_at(self, x, y):
        for w in reversed(self.visible_windows()):
            if w["x"] <= x < w["x"] + w["width"] and w["y"] <= y < w["y"] + w["height"]:
                return w
        return None

    def focused_app(self):
        a = self.j("activewindow") or {}
        return a.get("class") or a.get("initialClass") or None

    MODS = [(64, "SUPER"), (4, "CTRL"), (8, "ALT"), (1, "SHIFT"), (128, "MOD5"),
            (32, "MOD3"), (16, "MOD2"), (2, "CAPS")]

    def mods_str(self, mask):
        return "+".join(n for b, n in self.MODS if mask & b)

    def keybinds(self, query=None):
        out = []
        for b in self.j("binds"):
            if "sudoclaude.abort" in (b.get("arg") or ""):
                continue
            mods = self.mods_str(b.get("modmask", 0))
            key = b.get("key") or (f"code:{b.get('keycode')}" if b.get("keycode") else "")
            combo = (mods + "+" if mods else "") + key
            d = {"keys": combo, "dispatcher": b.get("dispatcher"), "arg": b.get("arg", ""),
                 "description": b.get("description", "")}
            if b.get("submap"):
                d["submap"] = b["submap"]
            if b.get("mouse"):
                d["mouse"] = True
            if query:
                q = query.lower()
                if q not in " ".join(str(v) for v in d.values()).lower():
                    continue
            out.append(d)
        return out

    def desktop_state(self):
        mons = self.j("monitors")
        wss = self.j("workspaces")
        active = self.j("activewindow") or {}
        wins = self.windows(active=active)
        layers = {}
        try:
            for mon, data in self.j("layers").items():
                names = []
                for lvl, items in (data.get("levels") or {}).items():
                    for it in items:
                        ns = it.get("namespace")
                        if ns and ns not in names and ns != "claude-computer-use":
                            names.append(ns)
                layers[mon] = names
        except Exception:
            pass
        state = {"monitors": [], "workspaces": [], "focused_window": None}
        for m in mons:
            state["monitors"].append({
                "name": m["name"], "focused": m.get("focused"),
                "size": [m["width"], m["height"]], "scale": m.get("scale"),
                "position": [m["x"], m["y"]], "refresh": round(m.get("refreshRate", 0)),
                "active_workspace": (m.get("activeWorkspace") or {}).get("name"),
                "special_workspace": (m.get("specialWorkspace") or {}).get("name") or None,
                "layers": layers.get(m["name"], [])})
        for w in sorted(wss, key=lambda w: (w["id"] < 0, w["id"])):
            ws_wins = [f'{x["app"]}: {x["title"][:50]}' +
                       (" [focused]" if x["focused"] else "") +
                       (" [floating]" if x["floating"] else "") +
                       (" [fullscreen]" if x["fullscreen"] else "")
                       for x in wins if x["workspace_id"] == w["id"]]
            state["workspaces"].append({"id": w["id"], "name": w["name"],
                                        "monitor": w.get("monitor"), "windows": ws_wins})
        if active.get("address"):
            state["focused_window"] = {"id": active["address"], "app": active.get("class"),
                                       "title": active.get("title"),
                                       "workspace": (active.get("workspace") or {}).get("name")}
        return state

    def send_shortcut(self, mods, key, window_id):
        return self.dispatch("sendshortcut", f"{mods}, {key}, address:{window_id}")

    def active_window(self):
        w = self.j("activewindow") or {}
        return w.get("address")

    def monitors(self):
        res = []
        for m in self.j("monitors"):
            res.append({"name": m["name"], "focused": m.get("focused", False),
                        "workspace": (m.get("activeWorkspace") or {}).get("name"),
                        "id": m.get("id")})
        return res

    def focused_output(self):
        for m in self.j("monitors"):
            if m.get("focused"):
                return m["name"]
        return None

    def cursor(self):
        c = self.j("cursorpos")
        return c["x"], c["y"]

    def dispatch(self, *args):
        r = self._req("dispatch " + " ".join(str(a) for a in args)).strip()
        if r != "ok":
            raise RuntimeError(f"hyprctl dispatch failed: {r}")
        return r

    def focus_window(self, wid):
        return self.dispatch("focuswindow", f"address:{wid}")

    def launch(self, cmd):
        return self.dispatch("exec", cmd)

    def raw(self, cmd):
        return self._req(cmd)


class Sway:
    name = "sway"
    MAGIC = b"i3-ipc"

    def __init__(self):
        self.sock_path = os.environ.get("SWAYSOCK") or \
            next(iter(glob.glob(os.path.join(_runtime(), "sway-ipc.*.sock"))), None)
        if not self.sock_path:
            raise RuntimeError("sway socket not found")

    def _req(self, typ, payload=""):
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(3)
        s.connect(self.sock_path)
        b = payload.encode()
        s.sendall(self.MAGIC + struct.pack("=II", len(b), typ) + b)
        hdr = b""
        while len(hdr) < 14:
            hdr += s.recv(14 - len(hdr))
        n, _ = struct.unpack("=II", hdr[6:])
        body = b""
        while len(body) < n:
            body += s.recv(n - len(body))
        s.close()
        return json.loads(body)

    def _walk(self, node, ws=None, out=None):
        out = [] if out is None else out
        if node.get("type") == "workspace":
            ws = node.get("name")
        if node.get("type") in ("con", "floating_con") and node.get("pid"):
            r = node["rect"]
            out.append({"id": str(node["id"]), "app": node.get("app_id") or
                        (node.get("window_properties") or {}).get("class"),
                        "title": node.get("name", ""), "x": r["x"], "y": r["y"],
                        "width": r["width"], "height": r["height"], "workspace": ws,
                        "floating": node.get("type") == "floating_con",
                        "focused": node.get("focused", False), "pid": node.get("pid"),
                        "visible": node.get("visible", True), "initial_app": None})
        for ch in node.get("nodes", []) + node.get("floating_nodes", []):
            self._walk(ch, ws, out)
        return out

    def windows(self):
        return self._walk(self._req(4))

    def active_window(self):
        for w in self.windows():
            if w["focused"]:
                return w["id"]

    def visible_windows(self):
        return [w for w in self._walk(self._req(4)) if w.get("visible", True)]

    def window_at(self, x, y):
        for w in reversed(self.visible_windows()):
            if w["x"] <= x < w["x"] + w["width"] and w["y"] <= y < w["y"] + w["height"]:
                return w
        return None

    def focused_app(self):
        for w in self.windows():
            if w["focused"]:
                return w["app"]

    def keybinds(self, query=None):
        return []

    def desktop_state(self):
        return {"outputs": self.monitors(), "windows": self.windows()}

    def monitors(self):
        return [{"name": o["name"], "focused": o.get("focused", False),
                 "workspace": o.get("current_workspace")} for o in self._req(3)]

    def focused_output(self):
        for o in self._req(3):
            if o.get("focused"):
                return o["name"]

    def cursor(self):
        return None

    def dispatch(self, *args):
        r = self._req(0, " ".join(str(a) for a in args))
        if not all(x.get("success") for x in r):
            raise RuntimeError(f"sway command failed: {r}")
        return "ok"

    def focus_window(self, wid):
        return self.dispatch(f"[con_id={wid}]", "focus")

    def launch(self, cmd):
        return self.dispatch("exec", cmd)

    def raw(self, cmd):
        return json.dumps(self._req(0, cmd))


def detect():
    for cls in (Hyprland, Sway):
        try:
            return cls()
        except Exception:
            continue
    return None
