import base64
import io
import json
import math
import os
import shutil
import struct
import subprocess
import sys
import threading
import time
import traceback

from . import a11y, apps, compositor
from .capture import Capturer
from .hyprconf import KeybindLabels
from .overlay import Overlay
from .policy import Policy
from .wayland import (BUTTONS, MODIFIER_CODES, NAMED_KEYS, US_CHARS, Connection,
                      VirtualKeyboard, VirtualPointer, WaylandError)

VERSION = "2.0.0"
MAX_EDGE = int(os.environ.get("SUDOCLAUDE_MAX_EDGE", "1568"))
MAX_PIXELS = int(os.environ.get("SUDOCLAUDE_MAX_PIXELS", "1150000"))
JPEG_Q = int(os.environ.get("SUDOCLAUDE_JPEG_QUALITY", "80"))
DEFAULT_SETTLE_MS = 150
HIDE_FRAME_S = 0.045

try:
    from PIL import Image, ImageDraw
    HAVE_PIL = True
except ImportError:
    HAVE_PIL = False


def log(*a):
    print("[sudoclaude]", *a, file=sys.stderr, flush=True)


def jpeg_size(data):
    i = 2
    while i < len(data) - 9:
        if data[i] != 0xFF:
            i += 1
            continue
        if data[i + 1] in (0xC0, 0xC1, 0xC2):
            h, w = struct.unpack(">HH", data[i + 5:i + 9])
            return w, h
        (seg,) = struct.unpack(">H", data[i + 2:i + 4])
        i += 2 + seg
    raise ValueError("bad jpeg")


class Space:
    def __init__(self, kind, x, y, w, h, img_w, img_h, output=None, window=None):
        self.kind, self.x, self.y, self.w, self.h = kind, x, y, w, h
        self.img_w, self.img_h, self.output, self.window = img_w, img_h, output, window

    def to_logical(self, px, py):
        return (self.x + px * self.w / self.img_w, self.y + py * self.h / self.img_h)

    def from_logical(self, lx, ly):
        return (round((lx - self.x) * self.img_w / self.w),
                round((ly - self.y) * self.img_h / self.h))

    def contains_logical(self, lx, ly):
        return self.x <= lx < self.x + self.w and self.y <= ly < self.y + self.h


def norm_key(k):
    k = k.strip()
    if len(k) == 1:
        return k.lower()
    k = k.lower()
    for suf in ("_l", "_r"):
        if k.endswith(suf) and k[:-2] in ("control", "ctrl", "shift", "alt", "super", "meta"):
            k = ("r" if suf == "_r" else "") + k[:-2]
    k = k.replace("_", "").replace("-", "")
    aliases = {"control": "ctrl", "rcontrol": "rctrl", "next": "pagedown",
               "prior": "pageup", "kpenter": "kp_enter", "arrowup": "up",
               "arrowdown": "down", "arrowleft": "left", "arrowright": "right",
               "audiomute": "mute", "audiolowervolume": "volumedown",
               "audioraisevolume": "volumeup", "audioplay": "playpause",
               "audionext": "nexttrack", "audioprev": "prevtrack", "windows": "super",
               "option": "alt", "spacebar": "space"}
    return aliases.get(k, k)


XKB_NAMES = {"enter": "Return", "return": "Return", "esc": "Escape", "escape": "Escape",
             "backspace": "BackSpace", "tab": "Tab", "delete": "Delete", "del": "Delete",
             "up": "Up", "down": "Down", "left": "Left", "right": "Right",
             "home": "Home", "end": "End", "pageup": "Prior", "pgup": "Prior",
             "pagedown": "Next", "pgdn": "Next", "space": "space", "insert": "Insert",
             "print": "Print", "menu": "Menu"}
MOD_HYPR = {29: "CTRL", 97: "CTRL", 42: "SHIFT", 54: "SHIFT", 56: "ALT", 100: "ALT",
            125: "SUPER", 126: "SUPER"}
MOD_MASK = {29: 4, 97: 4, 42: 1, 54: 1, 56: 8, 100: 8, 125: 64, 126: 64}


class Desktop:
    def __init__(self):
        self.conn = self.ptr = self.kbd = self.cap = None
        self.comp = compositor.detect()
        self.policy = Policy(self.comp)
        self.overlay = Overlay(on_stop=self.policy.abort_now, comp=self.comp)
        self.policy.on_activate.append(self._on_activate)
        self.policy.on_deactivate.append(self._on_deactivate)
        self.labels = KeybindLabels()
        self.tree = None
        self.tree_window = None
        self.a11y_enabled = False
        self.shot_space = None
        self.zoom_space = None
        self.default_monitor = None
        self.grim = shutil.which("grim")
        self.tesseract = shutil.which("tesseract")
        self.wl_copy = shutil.which("wl-copy")
        self.wl_paste = shutil.which("wl-paste")
        self._idle_flag = False
        threading.Thread(target=self._idle_watch, daemon=True).start()

    # ---- wayland -----------------------------------------------------------
    def wl(self):
        if self.conn is None:
            self.conn = Connection()
            self.ptr = VirtualPointer(self.conn)
            self.kbd = VirtualKeyboard(self.conn)
            try:
                self.cap = Capturer(self.conn) if HAVE_PIL else None
            except Exception as e:
                log("capture unavailable:", e)
                self.cap = None
            self.conn.roundtrip()
        else:
            self.conn.flush_events()
        return self.conn

    def reset(self):
        try:
            if self.conn:
                self.conn.sock.close()
        except Exception:
            pass
        self.conn = self.ptr = self.kbd = self.cap = None

    def sync(self):
        self.conn.roundtrip()

    # ---- overlay / activity --------------------------------------------------
    def _on_activate(self):
        self.overlay.send(active=True, stopped=False, idle=False, status="Working",
                          detail="Esc" if self.policy.cfg.get("esc_to_stop") else "")

    def _on_deactivate(self, stopped):
        self.overlay.send(active=False, stopped=stopped, action="",
                          status="Stopped" if stopped else "Done")

    def _idle_watch(self):
        while True:
            time.sleep(0.5)
            try:
                if self.policy.active:
                    idle = time.time() - self.policy.last_action > 3.0
                    if idle != self._idle_flag:
                        self._idle_flag = idle
                        self.overlay.send(idle=idle, **({"status": "Thinking", "action": ""}
                                                        if idle else {}))
            except Exception:
                pass

    def begin(self, status, action="", lx=None, ly=None, click=False):
        self.policy.touch()
        self._idle_flag = False
        msg = {"status": status, "action": action, "idle": False}
        if lx is not None:
            msg.update(x=lx, y=ly, screen=self._output_at(lx, ly))
            if click:
                msg["click"] = True
        if self.policy.cfg.get("overlay", True):
            self.overlay.send(**msg)

    def _output_at(self, lx, ly):
        for o in self.outputs():
            if o.x <= lx < o.x + o.width and o.y <= ly < o.y + o.height:
                return o.name
        return ""

    # ---- geometry ------------------------------------------------------------
    def outputs(self):
        return self.wl().output_list()

    def output(self, name=None):
        outs = self.outputs()
        name = name or self.default_monitor
        if not name and self.comp:
            try:
                name = self.comp.focused_output()
            except Exception:
                name = None
        for o in outs:
            if o.name == name:
                return o
        if name:
            raise ValueError(f"unknown monitor {name!r}; have {[o.name for o in outs]}")
        return outs[0]

    @staticmethod
    def scale_for(w, h, phys_scale):
        s = min(MAX_EDGE / max(w, h), math.sqrt(MAX_PIXELS / (w * h)))
        return min(s, float(phys_scale or 1))

    def default_space(self):
        if self.shot_space:
            return self.shot_space
        o = self.output()
        s = self.scale_for(o.width, o.height, o.scale)
        return Space("screenshot", o.x, o.y, o.width, o.height,
                     round(o.width * s), round(o.height * s), o.name)

    def to_logical(self, x, y, space=None):
        if space == "logical":
            return float(x), float(y)
        if space == "zoom":
            if not self.zoom_space:
                raise ValueError("no zoom image taken yet")
            return self.zoom_space.to_logical(x, y)
        sp = self.default_space()
        if sp.kind == "window" and self.comp:
            vis = {w["id"] for w in self.comp.visible_windows()}
            if sp.window not in vis:
                raise ValueError("the window in the last screenshot is not on screen; "
                                 "focus_window it first, or use a11y_action")
            w = next((w for w in self.comp.windows() if w["id"] == sp.window), None)
            if w:
                sp.x, sp.y = w["x"], w["y"]
        return sp.to_logical(x, y)

    # ---- capture --------------------------------------------------------------
    def _grab_output(self, o, cursor):
        if self.cap and self.cap.wlr:
            return self.cap.output(o.wl_id, cursor)
        if not self.grim:
            raise RuntimeError("no screen capture available (install grim or python-pillow)")
        r = subprocess.run([self.grim, "-o", o.name, "-t", "png", "-l", "0"] +
                           (["-c"] if cursor else []) + ["-"], capture_output=True, timeout=10)
        if r.returncode != 0:
            raise RuntimeError("grim failed: " + r.stderr.decode(errors="replace").strip())
        return Image.open(io.BytesIO(r.stdout)).convert("RGB")

    def _hidden_overlay(self):
        class Ctx:
            def __enter__(s):
                if self.overlay.capture_hide():
                    time.sleep(HIDE_FRAME_S)

            def __exit__(s, *a):
                self.overlay.capture_show()
        return Ctx()

    def _encode(self, img, quality=None):
        buf = io.BytesIO()
        img.save(buf, "JPEG", quality=quality or JPEG_Q, optimize=False)
        return buf.getvalue()

    def screenshot(self, monitor=None, cursor=True, max_edge=None, window=None):
        self.wl()
        if window is not None:
            return self.window_shot(window, max_edge)
        if not HAVE_PIL:
            return self._screenshot_grim(monitor, cursor, max_edge)
        outs = self.outputs()
        if monitor == "all":
            x, y, w, h = self.conn.layout_box()
            sel = outs
            name = "all"
            pscale = max(o.scale for o in outs)
        else:
            o = self.output(monitor)
            x, y, w, h, sel, name, pscale = o.x, o.y, o.width, o.height, [o], o.name, o.scale
        s = (min(int(max_edge) / max(w, h), float(pscale)) if max_edge
             else self.scale_for(w, h, pscale))
        iw, ih = max(1, round(w * s)), max(1, round(h * s))
        with self._hidden_overlay():
            raws = [(o, self._grab_output(o, cursor)) for o in sel]
        if len(raws) == 1:
            img = raws[0][1].resize((iw, ih), Image.BILINEAR if s < 0.6 else Image.LANCZOS)
        else:
            img = Image.new("RGB", (iw, ih))
            for o, im in raws:
                ox, oy = round((o.x - x) * s), round((o.y - y) * s)
                img.paste(im.resize((max(1, round(o.width * s)), max(1, round(o.height * s))),
                                    Image.BILINEAR), (ox, oy))
        sp = Space("screenshot", x, y, w, h, iw, ih, name)
        masked = self._mask(img, sp)
        self.shot_space = sp
        return self._encode(img), sp, masked

    def _screenshot_grim(self, monitor, cursor, max_edge):
        o = self.output(None if monitor == "all" else monitor)
        s = (min(int(max_edge) / max(o.width, o.height), float(o.scale)) if max_edge
             else self.scale_for(o.width, o.height, o.scale))
        with self._hidden_overlay():
            r = subprocess.run([self.grim, "-o", o.name, "-s", f"{s:.6f}", "-t", "jpeg",
                                "-q", str(JPEG_Q)] + (["-c"] if cursor else []) + ["-"],
                               capture_output=True, timeout=10)
        if r.returncode != 0:
            raise RuntimeError("grim failed: " + r.stderr.decode(errors="replace").strip())
        iw, ih = jpeg_size(r.stdout)
        self.shot_space = Space("screenshot", o.x, o.y, o.width, o.height, iw, ih, o.name)
        return r.stdout, self.shot_space, ["(masking unavailable without python-pillow)"]

    def _mask(self, img, sp):
        pol = self.policy
        if not self.comp or not pol.cfg.get("mask_unapproved", True):
            return []
        try:
            wins = self.comp.visible_windows()
        except Exception:
            return []
        orig = None
        masked = []
        draw = ImageDraw.Draw(img)
        for w in wins:
            app = w["app"] or "?"
            blocked = pol.hard_blocked(app)
            if not blocked and (pol.cfg.get("approvals") == "off" or pol.is_approved(app)):
                if orig is not None:
                    box = self._img_box(w, sp)
                    if box:
                        img.paste(orig.crop(box), box[:2])
                continue
            box = self._img_box(w, sp)
            if not box:
                continue
            if orig is None:
                orig = img.copy()
            draw.rounded_rectangle(box, radius=6, fill=(22, 21, 24))
            label = f"{app}" + (" (hidden)" if blocked else " (not approved)")
            cx, cy = (box[0] + box[2]) // 2, (box[1] + box[3]) // 2
            draw.text((cx, cy), label, fill=(150, 145, 140), anchor="mm")
            if not blocked:
                masked.append(app)
        return sorted(set(masked))

    @staticmethod
    def _img_box(w, sp):
        x0, y0 = sp.from_logical(w["x"], w["y"])
        x1, y1 = sp.from_logical(w["x"] + w["width"], w["y"] + w["height"])
        x0, y0 = max(0, x0), max(0, y0)
        x1, y1 = min(sp.img_w, x1), min(sp.img_h, y1)
        if x1 <= x0 or y1 <= y0:
            return None
        return (x0, y0, x1, y1)

    def window_shot(self, query, max_edge=None):
        if not (self.cap and self.cap.can_window):
            raise RuntimeError("window capture needs Hyprland and python-pillow")
        w = self.find_window(**query) if isinstance(query, dict) else self.find_window(id=query)
        self.policy.require(w["app"], "view", w["title"])
        img = self.cap.window(w["id"])
        pw, ph = img.size
        edge = int(max_edge or MAX_EDGE)
        s = min(1.0, edge / max(pw, ph), math.sqrt(MAX_PIXELS / (pw * ph)))
        if s < 1:
            img = img.resize((max(1, round(pw * s)), max(1, round(ph * s))), Image.LANCZOS)
        sp = Space("window", w["x"], w["y"], w["width"], w["height"], img.size[0],
                   img.size[1], None, w["id"])
        self.shot_space = sp
        vis = {v["id"] for v in self.comp.visible_windows()}
        return self._encode(img), sp, {"window": w, "on_screen": w["id"] in vis}

    def zoom(self, x, y, w, h, space=None, max_edge=None):
        if not HAVE_PIL:
            raise RuntimeError("zoom needs python-pillow")
        lx0, ly0 = self.to_logical(x, y, space)
        lx1, ly1 = self.to_logical(x + w, y + h, space)
        o = None
        for cand in self.outputs():
            if cand.x <= (lx0 + lx1) / 2 < cand.x + cand.width and \
                    cand.y <= (ly0 + ly1) / 2 < cand.y + cand.height:
                o = cand
        o = o or self.output()
        with self._hidden_overlay():
            full = self._grab_output(o, False)
        fx, fy = full.size[0] / o.width, full.size[1] / o.height
        box = (max(0, round((lx0 - o.x) * fx)), max(0, round((ly0 - o.y) * fy)),
               min(full.size[0], round((lx1 - o.x) * fx)), min(full.size[1], round((ly1 - o.y) * fy)))
        crop = full.crop(box)
        edge = int(max_edge or MAX_EDGE)
        cw, ch = crop.size
        s = min(edge / max(cw, ch), 2.0)
        if abs(s - 1) > 0.01:
            crop = crop.resize((max(1, round(cw * s)), max(1, round(ch * s))), Image.LANCZOS)
        lx0, ly0 = o.x + box[0] / fx, o.y + box[1] / fy
        lw, lh = (box[2] - box[0]) / fx, (box[3] - box[1]) / fy
        self.zoom_space = Space("zoom", lx0, ly0, lw, lh, crop.size[0], crop.size[1], o.name)
        return self._encode(crop, 90), self.zoom_space

    # ---- targets / permissions -------------------------------------------------
    def app_at(self, lx, ly):
        if not self.comp:
            return None
        w = self.comp.window_at(lx, ly)
        return (w["app"] or "?") if w else "__shell__"

    def focused_app(self):
        if not self.comp:
            return None
        return self.comp.focused_app() or "__shell__"

    def _is_wm_bind(self, mods, code):
        if not self.comp or self.comp.name != "hyprland":
            return False
        mask = 0
        for m in mods:
            mask |= MOD_MASK.get(m, 0)
        names = {k for k, v in NAMED_KEYS.items() if v == code}
        names |= {XKB_NAMES.get(n, n).lower() for n in names}
        try:
            for b in self.comp.j("binds"):
                if b.get("modmask", 0) == mask and (b.get("key") or "").lower() in names:
                    return True
        except Exception:
            pass
        return False

    # ---- pointer ----------------------------------------------------------------
    def _mods(self, modifiers):
        codes = []
        for m in modifiers or []:
            c = NAMED_KEYS.get(norm_key(m))
            if c is None or c not in MODIFIER_CODES:
                raise ValueError(f"not a modifier: {m}")
            codes.append(c)
        return codes

    def move(self, x, y, space=None):
        self.wl()
        lx, ly = self.to_logical(x, y, space)
        self.begin("Moving", "", lx, ly)
        self.ptr.move_to(lx, ly)
        self.sync()
        return lx, ly

    def click(self, x=None, y=None, button="left", count=1, modifiers=None, space=None,
              hold_ms=0):
        self.wl()
        if button not in BUTTONS:
            raise ValueError(f"button must be one of {list(BUTTONS)}")
        if x is not None and y is not None:
            lx, ly = self.to_logical(x, y, space)
        else:
            lx, ly = self.cursor() or (None, None)
        if lx is not None:
            self.policy.require(self.app_at(lx, ly), "click")
        verb = {1: "Click", 2: "Double-click", 3: "Triple-click"}.get(int(count), "Click")
        if button != "left":
            verb = f"{button.capitalize()} click"
        self.begin("Clicking", verb, lx, ly, click=True)
        if x is not None and y is not None:
            self.ptr.move_to(lx, ly)
            self.sync()
            time.sleep(0.015)
        mods = self._mods(modifiers)
        for m in mods:
            self.kbd.key(m, True)
        try:
            for i in range(int(count)):
                self.ptr.button(button, True)
                if hold_ms:
                    self.sync()
                    time.sleep(hold_ms / 1000)
                self.ptr.button(button, False)
                self.sync()
                if i < count - 1:
                    time.sleep(0.04)
        finally:
            for m in reversed(mods):
                self.kbd.key(m, False)
            self.sync()

    def button(self, button, pressed, x=None, y=None, space=None):
        self.wl()
        if x is not None and y is not None:
            lx, ly = self.to_logical(x, y, space)
        else:
            lx, ly = self.cursor() or (0, 0)
        self.policy.require(self.app_at(lx, ly), "type")
        self.begin("Dragging", "Hold" if pressed else "Release", lx, ly)
        if x is not None and y is not None:
            self.ptr.move_to(lx, ly)
        self.ptr.button(button, pressed)
        self.sync()

    def drag(self, x1, y1, x2, y2, button="left", duration_ms=300, space=None,
             modifiers=None):
        self.wl()
        a = self.to_logical(x1, y1, space)
        b = self.to_logical(x2, y2, space)
        self.policy.require(self.app_at(*a), "type")
        self.begin("Dragging", "Drag", a[0], a[1])
        mods = self._mods(modifiers)
        self.ptr.move_to(*a)
        self.sync()
        time.sleep(0.03)
        for m in mods:
            self.kbd.key(m, True)
        self.ptr.button(button, True)
        self.sync()
        steps = max(8, int(duration_ms / 12))
        try:
            time.sleep(0.03)
            for i in range(1, steps + 1):
                t = i / steps
                t = t * t * (3 - 2 * t)
                px, py = a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t
                self.ptr.move_to(px, py)
                self.sync()
                if i % 4 == 0 or i == steps:
                    self.overlay.send(x=px, y=py)
                time.sleep(duration_ms / 1000 / steps)
            time.sleep(0.03)
        finally:
            self.ptr.button(button, False)
            for m in reversed(mods):
                self.kbd.key(m, False)
            self.sync()

    def scroll(self, x=None, y=None, dy=0, dx=0, space=None, modifiers=None):
        self.wl()
        if x is not None and y is not None:
            lx, ly = self.to_logical(x, y, space)
        else:
            lx, ly = self.cursor() or (None, None)
        if lx is not None:
            self.policy.require(self.app_at(lx, ly), "click")
        self.begin("Scrolling", "Scroll", lx, ly)
        if x is not None and y is not None:
            self.ptr.move_to(lx, ly)
            self.sync()
            time.sleep(0.015)
        mods = self._mods(modifiers)
        for m in mods:
            self.kbd.key(m, True)
        try:
            n = max(abs(int(dy)), abs(int(dx)))
            for i in range(n):
                self.ptr.scroll((1 if dy > 0 else -1) if i < abs(int(dy)) else 0,
                                (1 if dx > 0 else -1) if i < abs(int(dx)) else 0)
                self.sync()
                time.sleep(0.008)
        finally:
            for m in reversed(mods):
                self.kbd.key(m, False)
            self.sync()

    def cursor(self):
        if self.comp:
            try:
                p = self.comp.cursor()
                if p:
                    return p
            except Exception:
                pass
        if self.ptr and self.ptr.x is not None:
            return (self.ptr.x, self.ptr.y)
        return None

    # ---- keyboard -----------------------------------------------------------------
    def parse_combo(self, combo):
        parts = combo.split("+")
        toks = []
        for i, p in enumerate(parts):
            if p == "" and (i == len(parts) - 1 or parts[i + 1] == ""):
                if not toks or toks[-1] != "+":
                    toks.append("+")
            elif p != "":
                toks.append(p)
        if not toks:
            raise ValueError(f"empty key combo: {combo!r}")
        mods, key = toks[:-1], toks[-1]
        mod_codes = self._mods(mods)
        nk = norm_key(key)
        if nk in NAMED_KEYS:
            code = NAMED_KEYS[nk]
        elif len(key) == 1 and key in US_CHARS:
            code, shift = US_CHARS[key]
            if shift and 42 not in mod_codes:
                mod_codes.append(42)
        else:
            raise ValueError(f"unknown key {key!r} in {combo!r}")
        return mod_codes, code, key

    def key(self, keys, repeat=1, delay_ms=30, window=None):
        self.wl()
        seq = keys if isinstance(keys, list) else keys.split()
        parsed = [self.parse_combo(k) for k in seq]
        if window:
            return self._key_background(parsed, window, repeat)
        for mods, code, _ in parsed:
            target = "__shell__" if self._is_wm_bind(mods, code) else self.focused_app()
            self.policy.require(target, "type")
        self.begin("Pressing keys", keys if isinstance(keys, str) else " ".join(keys))
        for _ in range(int(repeat)):
            for mods, code, _k in parsed:
                if code == 1:
                    self.policy.mark_own_esc()
                self.kbd.tap(code, mods)
                self.sync()
                self.policy.check_abort()
                if delay_ms:
                    time.sleep(delay_ms / 1000)

    def _key_background(self, parsed, window, repeat):
        if not self.comp or self.comp.name != "hyprland":
            raise RuntimeError("background keys need Hyprland")
        w = self.find_window(**window) if isinstance(window, dict) else self.find_window(id=window)
        self.policy.require(w["app"], "type", w["title"])
        self.begin("Pressing keys", f"→ {w['app']}")
        for _ in range(int(repeat)):
            for mods, code, raw in parsed:
                mod_s = " ".join(dict.fromkeys(MOD_HYPR[m] for m in mods))
                name = next((n for n, c in NAMED_KEYS.items() if c == code), raw)
                key = XKB_NAMES.get(name, name)
                if len(key) == 1:
                    key = key.lower()
                elif key.startswith("f") and key[1:].isdigit():
                    key = key.upper()
                self.comp.send_shortcut(mod_s, key, w["id"])
                time.sleep(0.02)
        return w

    def hold_key(self, keys, duration_ms):
        self.wl()
        mods, code, _ = self.parse_combo(keys)
        target = "__shell__" if self._is_wm_bind(mods, code) else self.focused_app()
        self.policy.require(target, "type")
        self.begin("Holding keys", keys)
        for m in mods:
            self.kbd.key(m, True)
        self.kbd.key(code, True)
        self.sync()
        try:
            end = time.time() + duration_ms / 1000
            while time.time() < end:
                time.sleep(min(0.1, max(0, end - time.time())))
                self.policy.check_abort()
        finally:
            self.kbd.key(code, False)
            for m in reversed(mods):
                self.kbd.key(m, False)
            self.sync()

    def type(self, text, delay_ms=2, method="auto", paste_keys="ctrl+v"):
        self.wl()
        self.policy.require(self.focused_app(), "type")
        self.begin("Typing", "Typing…")
        if method == "auto":
            method = "paste" if (len(text) > 300 and self.wl_copy) else "keys"
        if method == "paste":
            if not self.wl_copy:
                raise RuntimeError("wl-clipboard not installed; use method=keys")
            old = None
            if self.wl_paste:
                r = subprocess.run([self.wl_paste, "-n", "-t", "text/plain"],
                                   capture_output=True, timeout=3)
                old = r.stdout if r.returncode == 0 else None
            subprocess.Popen([self.wl_copy], stdin=subprocess.PIPE).communicate(
                text.encode(), timeout=5)
            time.sleep(0.08)
            mods, code, _ = self.parse_combo(paste_keys)
            self.kbd.tap(code, mods)
            self.sync()
            if old is not None:
                time.sleep(0.25)
                subprocess.Popen([self.wl_copy], stdin=subprocess.PIPE).communicate(
                    old, timeout=5)
            return "pasted"
        for i in range(0, len(text), 48):
            self.kbd.type_text(text[i:i + 48], delay=delay_ms / 1000)
            self.sync()
            self.policy.check_abort()
        return "typed"

    # ---- windows / apps --------------------------------------------------------------
    def need_comp(self):
        if not self.comp:
            self.comp = compositor.detect()
            self.policy.comp = self.comp
        if not self.comp:
            raise RuntimeError("no supported compositor IPC (Hyprland/sway) found")
        return self.comp

    def find_window(self, id=None, app=None, title=None):
        wins = self.need_comp().windows()
        if id:
            for w in wins:
                if w["id"] == id:
                    return w
            raise ValueError(f"no window with id {id}")
        cands = wins
        if app:
            a = app.lower()
            cands = [w for w in cands if a in (w["app"] or "").lower()
                     or a in (w.get("initial_app") or "").lower()]
        if title:
            t = title.lower()
            cands = [w for w in cands if t in (w["title"] or "").lower()]
        if (app or title) and cands:
            return sorted(cands, key=lambda w: w.get("focus_order", 99))[0]
        if not (app or title):
            for w in wins:
                if w.get("focused"):
                    return w
        raise ValueError("no matching window")

    def open_application(self, name, new_window=False, wait_ms=10000):
        c = self.need_comp()
        app = apps.find_app(name)
        if not app:
            close = [a.name for a in apps.list_apps()
                     if name.lower()[:3] in a.name.lower()][:8]
            raise ValueError(f"no installed app matches {name!r}" +
                             (f"; similar: {', '.join(close)}" if close else ""))
        self.policy.require(app.app_key, "view", f"open {app.name}")
        before = c.windows()
        existing = [w for w in before if apps.window_matches(app, w)]
        self.begin("Opening", app.name)
        if existing and not new_window:
            w = sorted(existing, key=lambda w: w.get("focus_order", 99))[0]
            c.focus_window(w["id"])
            self.policy.alias(app.app_key, w["app"])
            return {"opened": False, "focused": True, "window": w, "app": app.as_dict()}
        ids = {w["id"] for w in before}
        c.launch(apps.launch_command(app))
        deadline = time.time() + wait_ms / 1000
        while time.time() < deadline:
            time.sleep(0.12)
            new = [w for w in c.windows() if w["id"] not in ids]
            match = [w for w in new if apps.window_matches(app, w)] or new
            if match:
                w = match[0]
                time.sleep(0.25)
                try:
                    c.focus_window(w["id"])
                except Exception:
                    pass
                self.policy.alias(app.app_key, w["app"])
                return {"opened": True, "window": w, "app": app.as_dict()}
        return {"opened": True, "window": None, "app": app.as_dict(),
                "note": "launched, but no window appeared yet; take a screenshot"}

    # ---- accessibility ----------------------------------------------------------------
    def a11y_tree(self, window=None, query=None, interactive_only=True, max_nodes=400):
        if not a11y.available():
            raise RuntimeError("AT-SPI not available (install python-gobject and at-spi2-core)")
        if not self.a11y_enabled:
            a11y.enable_toolkits()
            self.a11y_enabled = True
        w = self.find_window(**(window or {}))
        self.policy.require(w["app"], "view", w["title"])
        self.tree = self.tree or a11y.Tree()
        app = self.tree.app_for(w.get("pid"), w.get("app"))
        if app is None:
            raise RuntimeError(
                f"{w['app']} exposes no accessibility tree. Electron/Chromium apps may need "
                f"a restart after accessibility is enabled (already done now), or use "
                f"screenshots instead.")
        frame = self.tree.frame_for(app, w.get("title"))
        sp = self.shot_space
        if sp and sp.kind == "screenshot" and sp.contains_logical(
                w["x"] + w["width"] / 2, w["y"] + w["height"] / 2):
            to_screen, space = sp.from_logical, f"screenshot ({sp.output})"
        else:
            def to_screen(lx, ly):
                return round(lx), round(ly)
            space = "logical (use space='logical')"
        lines = self.tree.snapshot(frame, w, to_screen, interactive_only, max_nodes, query)
        self.tree_window = w
        head = f'{w["app"]}: "{w["title"][:70]}"  coords={space}'
        return head + "\n" + ("\n".join(lines) if lines else "(no matching elements)")

    def a11y_action(self, ref, action="click", text=None, value=None):
        if not self.tree or not self.tree_window:
            raise ValueError("call accessibility_tree first")
        w = self.tree_window
        kind = "type" if action in ("set_text", "set_value") else (
            "view" if action == "get_text" else "click")
        self.policy.require(w["app"], kind, w["title"])
        node, box = self.tree.get(ref)
        if box:
            self.begin({"set_text": "Typing", "get_text": "Reading"}.get(action, "Clicking"),
                       action.replace("_", " ").capitalize(),
                       box[0] + box[2] / 2, box[1] + box[3] / 2, click=action == "click")
        else:
            self.begin("Working", action)
        res = self.tree.act(ref, action, text, value)
        if not res.get("ok") and res.get("fallback") and action in ("click", "press",
                                                                     "set_text", "focus"):
            bx, by, bw, bh = res["fallback"]
            self.click(bx + bw / 2, by + bh / 2, space="logical")
            if action == "set_text":
                self.key("ctrl+a")
                self.type(text or "")
            res = {"ok": True, "did": f"{action} via pointer fallback"}
        return res


# =============================================================================
D = None
COORD = {"x": {"type": "number"}, "y": {"type": "number"},
         "space": {"type": "string", "enum": ["screenshot", "zoom", "logical"],
                   "description": "Default 'screenshot': pixel coords of the latest "
                                  "screenshot image (monitor or window)."}}
SHOT = {"screenshot": {"type": "boolean",
                       "description": "Return a fresh screenshot after the action."},
        "settle_ms": {"type": "integer", "description": "Wait before that screenshot (150)."}}
WIN = {"type": "object", "description": "Target window: {id} or {app} and/or {title} "
                                         "(case-insensitive substrings).",
       "properties": {"id": {"type": "string"}, "app": {"type": "string"},
                      "title": {"type": "string"}}}
MODS = {"type": "array", "items": {"type": "string"}}


def obj(props, required=()):
    return {"type": "object", "properties": props, "required": list(required)}


TOOLS = [
    {"name": "screenshot",
     "description": "See the screen. Default: focused monitor, downscaled for vision, with "
                    "unapproved apps blacked out (request_access to reveal them). Pass "
                    "window to capture a single window, even on another workspace or "
                    "covered. Later coordinates default to this image's pixels.",
     "inputSchema": obj({"monitor": {"type": "string", "description": "Name or 'all'."},
                         "window": WIN, "max_edge": {"type": "integer"},
                         "cursor": {"type": "boolean"}})},
    {"name": "zoom",
     "description": "Full-resolution view of a region (x, y, width, height in screenshot "
                    "coords) to read small text. Then space='zoom' targets coords in it.",
     "inputSchema": obj({"x": {"type": "number"}, "y": {"type": "number"},
                         "width": {"type": "number"}, "height": {"type": "number"},
                         "space": {"type": "string", "enum": ["screenshot", "logical"]}},
                        ["x", "y", "width", "height"])},
    {"name": "click",
     "description": "Click at (x, y), or at the current position if omitted. count 2/3 = "
                    "double/triple. modifiers e.g. ['ctrl'].",
     "inputSchema": obj({**COORD, "button": {"type": "string", "enum": list(BUTTONS)},
                         "count": {"type": "integer"}, "modifiers": MODS,
                         "hold_ms": {"type": "integer"}, **SHOT})},
    {"name": "move", "description": "Move the mouse to (x, y) (hover).",
     "inputSchema": obj({**COORD, **SHOT}, ["x", "y"])},
    {"name": "drag", "description": "Press at (x1, y1), glide to (x2, y2), release.",
     "inputSchema": obj({"x1": {"type": "number"}, "y1": {"type": "number"},
                         "x2": {"type": "number"}, "y2": {"type": "number"},
                         "button": {"type": "string", "enum": list(BUTTONS)},
                         "duration_ms": {"type": "integer"}, "modifiers": MODS,
                         "space": COORD["space"], **SHOT}, ["x1", "y1", "x2", "y2"])},
    {"name": "mouse_button", "description": "Press or release a mouse button (manual drags).",
     "inputSchema": obj({"button": {"type": "string", "enum": list(BUTTONS)},
                         "action": {"type": "string", "enum": ["down", "up"]}, **COORD},
                        ["action"])},
    {"name": "scroll",
     "description": "Scroll wheel clicks at (x, y) or the current position. dy>0 down, "
                    "dx>0 right.",
     "inputSchema": obj({**COORD, "dy": {"type": "integer"}, "dx": {"type": "integer"},
                         "modifiers": MODS, **SHOT})},
    {"name": "type",
     "description": "Type text into the focused window (any unicode). 'auto' pastes long "
                    "text; for terminals use paste_keys='ctrl+shift+v'.",
     "inputSchema": obj({"text": {"type": "string"},
                         "method": {"type": "string", "enum": ["auto", "keys", "paste"]},
                         "delay_ms": {"type": "integer"}, "paste_keys": {"type": "string"},
                         **SHOT}, ["text"])},
    {"name": "key",
     "description": "Press key combos, space separated: 'ctrl+l', 'super+2', 'alt+tab', "
                    "'Down Down Return'. Names: ctrl shift alt super enter esc tab "
                    "backspace delete arrows home end pageup pagedown f1-f24 space print "
                    "volumeup volumedown mute playpause, or a character. With window, the "
                    "keys go to that window in the background without focusing it.",
     "inputSchema": obj({"keys": {"type": "string"}, "repeat": {"type": "integer"},
                         "delay_ms": {"type": "integer"}, "window": WIN, **SHOT},
                        ["keys"])},
    {"name": "hold_key", "description": "Hold a key or combo for duration_ms.",
     "inputSchema": obj({"keys": {"type": "string"}, "duration_ms": {"type": "integer"},
                         **SHOT}, ["keys", "duration_ms"])},
    {"name": "wait", "description": "Wait ms milliseconds.",
     "inputSchema": obj({"ms": {"type": "integer"}, **SHOT}, ["ms"])},
    {"name": "batch",
     "description": "Run a sequence of actions in one call, then return one screenshot. "
                    "Items: {\"action\": name, ...args}. Actions: click move drag "
                    "mouse_button scroll type key hold_key wait focus_window workspace "
                    "open_application a11y_action launch hypr. Stops at the first error.",
     "inputSchema": obj({"actions": {"type": "array", "items": {"type": "object"}},
                         "screenshot": {"type": "boolean"}, "settle_ms": {"type": "integer"},
                         "monitor": {"type": "string"}}, ["actions"])},
    {"name": "open_application",
     "description": "Open an installed app by name (e.g. 'zen', 'Discord', 'Files', "
                    "'Unity Hub'), or focus it if already running. Waits for its window.",
     "inputSchema": obj({"name": {"type": "string"}, "new_window": {"type": "boolean"},
                         "wait_ms": {"type": "integer"}, **SHOT}, ["name"])},
    {"name": "list_apps", "description": "Installed applications (filter with query).",
     "inputSchema": obj({"query": {"type": "string"}})},
    {"name": "request_access",
     "description": "Ask the user to approve apps before using them (one dialog). Use app "
                    "names or window classes; 'clipboard' for clipboard, 'shell' for "
                    "desktop shell/bar/launcher, 'commands' for launch/exec.",
     "inputSchema": obj({"apps": {"type": "array", "items": {"type": "string"}},
                         "reason": {"type": "string"}}, ["apps"])},
    {"name": "access_status",
     "description": "Approved, denied and tiered apps; revoke an approval with revoke.",
     "inputSchema": obj({"revoke": {"type": "string"}})},
    {"name": "list_windows",
     "description": "All windows: id, app, title, workspace, monitor, geometry, focus.",
     "inputSchema": obj({"workspace": {"type": "string"}})},
    {"name": "focus_window",
     "description": "Focus a window (switching workspace) by id, or app/title substring.",
     "inputSchema": obj({"id": {"type": "string"}, "app": {"type": "string"},
                         "title": {"type": "string"}, **SHOT})},
    {"name": "desktop_state",
     "description": "Hyprland overview: monitors, active and special workspaces, every "
                    "workspace's windows, focused window, shell layers (bar, panels).",
     "inputSchema": obj({})},
    {"name": "workspace",
     "description": "Switch workspace (action=switch target='3' / 'e+1' / 'name:x'), move "
                    "the focused window (move / move_silent), or toggle a special "
                    "workspace (toggle_special, target = name or empty).",
     "inputSchema": obj({"action": {"type": "string", "enum": [
         "switch", "move", "move_silent", "toggle_special"]}, "target": {"type": "string"},
         **SHOT}, ["action"])},
    {"name": "keybinds",
     "description": "The user's live Hyprland keybinds with their cheatsheet descriptions "
                    "and sections. Use these shortcuts instead of guessing.",
     "inputSchema": obj({"query": {"type": "string"},
                         "include_hidden": {"type": "boolean"}})},
    {"name": "switch_display",
     "description": "Make a monitor the default for screenshots and coordinates.",
     "inputSchema": obj({"monitor": {"type": "string"}}, ["monitor"])},
    {"name": "monitors", "description": "Monitor layout, scale and focus.",
     "inputSchema": obj({})},
    {"name": "accessibility_tree",
     "description": "Semantic UI tree of a window (default focused): buttons, fields, "
                    "menus, links, tabs with names, values, states and click points. Refs "
                    "like e12 work with a11y_action. Use query to search.",
     "inputSchema": obj({"window": WIN, "query": {"type": "string"},
                         "interactive_only": {"type": "boolean"},
                         "max_nodes": {"type": "integer"}})},
    {"name": "a11y_action",
     "description": "Act on an element from accessibility_tree without moving the mouse: "
                    "click (press/activate), focus, set_text, get_text, set_value, select, "
                    "toggle, expand, scroll_into_view. Falls back to a real click.",
     "inputSchema": obj({"ref": {"type": "string"},
                         "action": {"type": "string"}, "text": {"type": "string"},
                         "value": {"type": "number"}, **SHOT}, ["ref"])},
    {"name": "find_text",
     "description": "OCR a monitor and return where text matching query appears.",
     "inputSchema": obj({"query": {"type": "string"}, "monitor": {"type": "string"}},
                        ["query"])},
    {"name": "cursor_position", "description": "Mouse position.", "inputSchema": obj({})},
    {"name": "launch",
     "description": "Run a command detached via the compositor (needs 'commands' access).",
     "inputSchema": obj({"command": {"type": "string"}, "wait_ms": {"type": "integer"},
                         **SHOT}, ["command"])},
    {"name": "hypr",
     "description": "Raw Hyprland IPC: dispatch (e.g. 'fullscreen 0', 'togglefloating', "
                    "'killactive') or query (e.g. 'j/workspaces').",
     "inputSchema": obj({"dispatch": {"type": "string"}, "query": {"type": "string"},
                         **SHOT})},
    {"name": "clipboard", "description": "Get or set the clipboard (needs approval).",
     "inputSchema": obj({"action": {"type": "string", "enum": ["get", "set"]},
                         "text": {"type": "string"}}, ["action"])},
    {"name": "doctor", "description": "Diagnostics and timings.", "inputSchema": obj({})},
]

INSTRUCTIONS = """Controls the user's Linux desktop (Hyprland).
Loop: look, act, verify. Coordinates default to the pixels of the latest screenshot.
Fast paths first: open_application to open/focus apps, keybinds + key for the user's own
shortcuts, accessibility_tree + a11y_action for precise clicks and form filling without
the mouse, batch for multi-step sequences (one round trip), screenshot=true on actions.
Blacked-out windows are unapproved apps: call request_access. Browsers are view-only and
terminals/IDEs click-only by default; use the browser or shell tools for those.
If a call says the user pressed Stop/Esc, stop and ask them. Never enter passwords,
approve payments or security prompts without the user's explicit go-ahead."""

ACTIONS = {"click", "move", "drag", "mouse_button", "scroll", "type", "key", "hold_key",
           "wait", "focus_window", "launch", "hypr", "workspace", "open_application",
           "a11y_action"}


def img_block(data):
    return {"type": "image", "data": base64.b64encode(data).decode(), "mimeType": "image/jpeg"}


def txt(s):
    return {"type": "text", "text": s if isinstance(s, str) else json.dumps(s)}


def shot_block(monitor=None, settle_ms=None):
    time.sleep((DEFAULT_SETTLE_MS if settle_ms is None else settle_ms) / 1000)
    data, sp, masked = D.screenshot(monitor)
    return [img_block(data), txt(shot_meta(sp, masked))]


def shot_meta(sp, masked=None):
    meta = {"monitor": sp.output, "image": [sp.img_w, sp.img_h]}
    pos = D.cursor()
    if pos and sp.contains_logical(*pos):
        meta["cursor"] = list(sp.from_logical(*pos))
    if D.comp and D.comp.name == "hyprland":
        try:
            a = D.comp.j("activewindow") or {}
            if a:
                meta["focused"] = f'{a.get("class")}: {a.get("title", "")[:80]}'
                meta["workspace"] = (a.get("workspace") or {}).get("name")
        except Exception:
            pass
    if masked:
        meta["hidden_unapproved"] = masked
    return meta


def run_action(name, a):
    sp = a.get("space")
    if name == "click":
        D.click(a.get("x"), a.get("y"), a.get("button", "left"), a.get("count", 1),
                a.get("modifiers"), sp, a.get("hold_ms", 0))
        return "clicked" + (f" {a['x']},{a['y']}" if a.get("x") is not None else "")
    if name == "move":
        D.move(a["x"], a["y"], sp)
        return f"moved {a['x']},{a['y']}"
    if name == "drag":
        D.drag(a["x1"], a["y1"], a["x2"], a["y2"], a.get("button", "left"),
               a.get("duration_ms", 300), sp, a.get("modifiers"))
        return "dragged"
    if name == "mouse_button":
        D.button(a.get("button", "left"), a["action"] == "down", a.get("x"), a.get("y"), sp)
        return f"{a.get('button', 'left')} {a['action']}"
    if name == "scroll":
        D.scroll(a.get("x"), a.get("y"), a.get("dy", 0), a.get("dx", 0), sp, a.get("modifiers"))
        return f"scrolled {a.get('dy', 0)},{a.get('dx', 0)}"
    if name == "type":
        how = D.type(a["text"], a.get("delay_ms", 2), a.get("method", "auto"),
                     a.get("paste_keys", "ctrl+v"))
        return f"{how} {len(a['text'])} chars"
    if name == "key":
        w = D.key(a["keys"], a.get("repeat", 1), a.get("delay_ms", 30), a.get("window"))
        return f"pressed {a['keys']}" + (f" in {w['app']}" if w else "")
    if name == "hold_key":
        D.hold_key(a["keys"], a["duration_ms"])
        return f"held {a['keys']}"
    if name == "wait":
        end = time.time() + a["ms"] / 1000
        while time.time() < end:
            time.sleep(min(0.1, max(0, end - time.time())))
            D.policy.check_abort()
        return f"waited {a['ms']}ms"
    if name == "focus_window":
        w = D.find_window(a.get("id"), a.get("app"), a.get("title"))
        D.need_comp().focus_window(w["id"])
        return f"focused {w['app']}: {w['title'][:60]}"
    if name == "workspace":
        c = D.need_comp()
        act, tgt = a["action"], str(a.get("target", "")).strip()
        disp = {"switch": "workspace", "move": "movetoworkspace",
                "move_silent": "movetoworkspacesilent",
                "toggle_special": "togglespecialworkspace"}[act]
        if not tgt and act != "toggle_special":
            raise ValueError("target required")
        D.begin("Switching workspace" if act == "switch" else "Moving window", tgt)
        c.dispatch(disp, tgt) if tgt else c.dispatch(disp)
        return f"{act} {tgt}".strip()
    if name == "open_application":
        r = D.open_application(a["name"], a.get("new_window", False), a.get("wait_ms", 10000))
        w = r.get("window")
        return json.dumps({"opened": r["opened"], "app": r["app"]["name"],
                           "window": {k: w[k] for k in ("id", "app", "title", "workspace")}
                           if w else None, **({"note": r["note"]} if "note" in r else {})})
    if name == "a11y_action":
        return json.dumps(D.a11y_action(a["ref"], a.get("action", "click"), a.get("text"),
                                        a.get("value")))
    if name == "launch":
        D.policy.require("__launch__", "view", a["command"])
        D.begin("Launching", a["command"].split()[0])
        D.need_comp().launch(a["command"])
        if a.get("wait_ms"):
            time.sleep(a["wait_ms"] / 1000)
        return f"launched {a['command']}"
    if name == "hypr":
        c = D.need_comp()
        if a.get("dispatch"):
            d = a["dispatch"].strip()
            D.policy.require("__launch__" if d.split()[0] in ("exec", "execr") else
                             "__shell__", "view", d)
            D.begin("Window manager", d.split()[0])
            return c.dispatch(d)
        if a.get("query"):
            return c.raw(a["query"])
        raise ValueError("give dispatch or query")
    raise ValueError(f"unknown action {name}")


def call_tool(name, a):
    if name == "screenshot":
        if a.get("window"):
            data, sp, info = D.screenshot(window=a["window"], max_edge=a.get("max_edge"))
            w = info["window"]
            meta = {"window": f'{w["app"]}: {w["title"][:80]}', "image": [sp.img_w, sp.img_h],
                    "on_screen": info["on_screen"]}
            if not info["on_screen"]:
                meta["note"] = ("window is not visible; focus_window before clicking, or use "
                                "accessibility_tree/a11y_action/key(window=) in the background")
            return [img_block(data), txt(meta)]
        data, sp, masked = D.screenshot(a.get("monitor"), a.get("cursor", True),
                                        a.get("max_edge"))
        if D.policy.active:
            D.overlay.send(status="Looking", action="")
        return [img_block(data), txt(shot_meta(sp, masked))]
    if name == "zoom":
        data, zs = D.zoom(a["x"], a["y"], a["width"], a["height"], a.get("space"))
        return [img_block(data), txt({"zoom_image": [zs.img_w, zs.img_h],
                                      "hint": "space='zoom' acts on coords in this image"})]
    if name in ACTIONS:
        out = [txt(run_action(name, a))]
        if a.get("screenshot"):
            out += shot_block(None, a.get("settle_ms"))
        return out
    if name == "batch":
        lines = []
        for i, act in enumerate(a["actions"]):
            act = dict(act)
            an = act.pop("action", None)
            if an not in ACTIONS:
                raise ValueError(f"step {i}: invalid action {an!r}")
            try:
                lines.append(f"{i}: {run_action(an, act)}")
            except InterruptedError:
                raise
            except Exception as e:
                lines.append(f"{i}: FAILED {e}")
                break
        out = [txt("\n".join(lines))]
        if a.get("screenshot", True):
            out += shot_block(a.get("monitor"), a.get("settle_ms"))
        return out
    if name == "list_apps":
        q = (a.get("query") or "").lower()
        lst = [x.as_dict() for x in apps.list_apps()
               if not q or q in (x.name + " " + x.id + " " + x.generic).lower()]
        return [txt(json.dumps(lst[:150]))]
    if name == "request_access":
        keys, names = [], {}
        special = {"clipboard": "__clipboard__", "shell": "__shell__",
                   "desktop": "__shell__", "commands": "__launch__", "launch": "__launch__"}
        for n in a["apps"]:
            if n.lower() in special:
                k = special[n.lower()]
            else:
                app = apps.find_app(n)
                k = app.app_key if app else n.lower()
            keys.append(k)
            names[k] = n
        res = D.policy.prompt(keys, a.get("reason"))
        status = {names.get(k, k): {"approved": D.policy.is_approved(k),
                                    "tier": D.policy.tier(k)} for k in keys}
        if any(v for v in res.values()):
            D.policy.touch_soft()
        return [txt(json.dumps(status))]
    if name == "access_status":
        if a.get("revoke"):
            D.policy.forget(a["revoke"])
        return [txt(json.dumps(D.policy.status(), indent=0))]
    if name == "list_windows":
        wins = D.need_comp().windows()
        if a.get("workspace"):
            wins = [w for w in wins if str(w.get("workspace")) == str(a["workspace"])]
        return [txt(json.dumps(wins))]
    if name == "desktop_state":
        return [txt(json.dumps(D.need_comp().desktop_state(), indent=0))]
    if name == "keybinds":
        c = D.need_comp()
        labels = D.labels
        out = []
        for b in c.keybinds(a.get("query")):
            mods, _, key = b["keys"].rpartition("+")
            lab = labels.label(mods, key) or {}
            if lab.get("hidden") and not a.get("include_hidden"):
                continue
            if lab.get("description") and not b.get("description"):
                b["description"] = lab["description"]
            if lab.get("section"):
                b["section"] = lab["section"]
            out.append({k: v for k, v in b.items() if v not in ("", None)})
        return [txt(json.dumps(out))]
    if name == "switch_display":
        o = D.output(a["monitor"])
        D.default_monitor = o.name
        D.shot_space = None
        data, sp, masked = D.screenshot(o.name)
        return [img_block(data), txt(shot_meta(sp, masked))]
    if name == "monitors":
        outs = [o.as_dict() for o in D.outputs()]
        if D.comp:
            try:
                extra = {m["name"]: m for m in D.comp.monitors()}
                for o in outs:
                    o.update({k: v for k, v in extra.get(o["name"], {}).items()
                              if k in ("focused", "workspace")})
            except Exception:
                pass
        return [txt(json.dumps(outs))]
    if name == "accessibility_tree":
        return [txt(D.a11y_tree(a.get("window"), a.get("query"),
                                a.get("interactive_only", True), a.get("max_nodes", 400)))]
    if name == "find_text":
        return [txt(json.dumps(find_text(a["query"], a.get("monitor"))))]
    if name == "cursor_position":
        pos = D.cursor()
        if not pos:
            return [txt("unknown")]
        return [txt({"logical": [round(pos[0]), round(pos[1])],
                     "screenshot": list(D.default_space().from_logical(*pos))})]
    if name == "clipboard":
        D.policy.require("__clipboard__", "view", "clipboard " + a["action"])
        if a["action"] == "get":
            if not D.wl_paste:
                raise RuntimeError("wl-clipboard not installed")
            r = subprocess.run([D.wl_paste, "-n"], capture_output=True, timeout=3)
            return [txt(r.stdout.decode(errors="replace"))]
        if not D.wl_copy:
            raise RuntimeError("wl-clipboard not installed")
        subprocess.Popen([D.wl_copy], stdin=subprocess.PIPE).communicate(
            (a.get("text") or "").encode(), timeout=5)
        return [txt("clipboard set")]
    if name == "doctor":
        return [txt(json.dumps(doctor(), indent=1))]
    raise ValueError(f"unknown tool {name}")


def find_text(query, monitor=None, max_results=10):
    if not D.tesseract:
        raise RuntimeError("tesseract not installed")
    if not HAVE_PIL:
        raise RuntimeError("find_text needs python-pillow")
    from PIL import ImageOps
    D.wl()
    o = D.output(monitor)
    with D._hidden_overlay():
        im = D._grab_output(o, False)
    iw, ih = im.size
    g = im.convert("L")
    if sum(g.resize((64, 64)).getdata()) / 4096 < 110:
        g = ImageOps.invert(g)
    up = 2 if iw < 2500 else 1
    if up > 1:
        g = g.resize((iw * up, ih * up))
    buf = io.BytesIO()
    g.save(buf, "PNG", compress_level=0)
    r = subprocess.run([D.tesseract, "stdin", "stdout", "--psm", "11", "tsv"],
                       input=buf.getvalue(), capture_output=True, timeout=30)
    if r.returncode != 0:
        raise RuntimeError("tesseract failed: " + r.stderr.decode(errors="replace")[-300:])
    lines = {}
    for row in r.stdout.decode(errors="replace").splitlines()[1:]:
        f = row.split("\t")
        if len(f) < 12 or not f[11].strip():
            continue
        lines.setdefault((f[2], f[3], f[4]), []).append(
            (f[11], int(f[6]) / up, int(f[7]) / up, int(f[8]) / up, int(f[9]) / up,
             float(f[10])))
    fx, fy = o.width / iw, o.height / ih
    q = query.lower().strip()
    sp = D.shot_space if (D.shot_space and D.shot_space.output == o.name) else None
    hits = []
    for words in lines.values():
        best = None
        for i in range(len(words)):
            text = ""
            for j in range(i, len(words)):
                text = (text + " " + words[j][0]).strip()
                if q in text.lower():
                    if best is None or (j - i) <= (best[1] - best[0]):
                        best = (i, j, text)
                    break
        if not best:
            continue
        i, j, text = best
        ws = words[i:j + 1]
        x0, y0 = min(w[1] for w in ws), min(w[2] for w in ws)
        x1, y1 = max(w[1] + w[3] for w in ws), max(w[2] + w[4] for w in ws)
        lx, ly = o.x + (x0 + x1) / 2 * fx, o.y + (y0 + y1) / 2 * fy
        hit = {"text": text, "logical": [round(lx), round(ly)],
               "conf": round(min(w[5] for w in ws))}
        if sp:
            hit["screenshot"] = list(sp.from_logical(lx, ly))
        hits.append(hit)
    hits.sort(key=lambda h: -h["conf"])
    return {"monitor": o.name, "matches": hits[:max_results]}


def doctor():
    info = {"version": VERSION, "python": sys.version.split()[0], "pillow": HAVE_PIL,
            "compositor": D.comp.name if D.comp else None,
            "overlay": {"quickshell": D.overlay.bin, "error": D.overlay.error},
            "accessibility": a11y.available(),
            "tools": {t: shutil.which(t) for t in ("grim", "tesseract", "wl-copy", "zenity",
                                                    "notify-send", "gtk-launch")},
            "config": __import__("sudoclaude.policy", fromlist=["x"]).CONFIG_PATH}
    try:
        t0 = time.perf_counter()
        c = D.wl()
        info["protocols"] = {p: c.has(p) for p in (
            "zwlr_virtual_pointer_manager_v1", "zwp_virtual_keyboard_manager_v1",
            "zwlr_screencopy_manager_v1", "hyprland_toplevel_export_manager_v1")}
        info["outputs"] = [o.as_dict() for o in c.output_list()]
        t1 = time.perf_counter()
        c.roundtrip()
        info["roundtrip_ms"] = round((time.perf_counter() - t1) * 1000, 3)
        info["connect_ms"] = round((t1 - t0) * 1000, 2)
        t0 = time.perf_counter()
        _, sp, _ = D.screenshot()
        info["screenshot_ms"] = round((time.perf_counter() - t0) * 1000, 1)
        info["screenshot_size"] = [sp.img_w, sp.img_h]
    except Exception as e:
        info["error"] = str(e)
    return info


def handle(msg):
    mid = msg.get("id")
    method = msg.get("method")
    if method == "initialize":
        pv = (msg.get("params") or {}).get("protocolVersion") or "2025-06-18"
        return {"jsonrpc": "2.0", "id": mid, "result": {
            "protocolVersion": pv, "capabilities": {"tools": {"listChanged": False}},
            "serverInfo": {"name": "sudoclaude", "version": VERSION},
            "instructions": INSTRUCTIONS}}
    if method == "ping":
        return {"jsonrpc": "2.0", "id": mid, "result": {}}
    if method == "tools/list":
        return {"jsonrpc": "2.0", "id": mid, "result": {"tools": TOOLS}}
    if method == "tools/call":
        p = msg.get("params") or {}
        name, args = p.get("name"), p.get("arguments") or {}
        t0 = time.perf_counter()
        try:
            try:
                content = call_tool(name, args)
            except (WaylandError, BrokenPipeError, ConnectionError) as e:
                log("reconnecting after:", e)
                D.reset()
                content = call_tool(name, args)
            log(f"{name} {round((time.perf_counter() - t0) * 1000)}ms")
            return {"jsonrpc": "2.0", "id": mid, "result": {"content": content}}
        except Exception as e:
            if not isinstance(e, (PermissionError, InterruptedError, ValueError)):
                log(traceback.format_exc())
            try:
                if D.kbd:
                    D.kbd.release_all()
                    D.conn.roundtrip()
            except Exception:
                pass
            return {"jsonrpc": "2.0", "id": mid, "result": {
                "content": [txt(f"Error: {e}")], "isError": True}}
    if mid is None:
        return None
    return {"jsonrpc": "2.0", "id": mid,
            "error": {"code": -32601, "message": f"method not found: {method}"}}


def main():
    global D
    D = Desktop()
    log(f"v{VERSION} compositor={D.comp.name if D.comp else None}")
    out = sys.stdout.buffer
    try:
        for line in sys.stdin.buffer:
            line = line.strip()
            if not line:
                continue
            try:
                msg = json.loads(line)
            except Exception:
                continue
            for m in (msg if isinstance(msg, list) else [msg]):
                resp = handle(m)
                if resp is not None:
                    out.write(json.dumps(resp).encode() + b"\n")
                    out.flush()
    finally:
        D.policy.cleanup()
        D.overlay.stop()
