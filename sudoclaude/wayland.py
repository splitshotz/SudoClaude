import array
import os
import select
import socket
import struct
import time


class WaylandError(Exception):
    pass


def u32(v):
    return struct.pack("=I", int(v) & 0xFFFFFFFF)


def i32(v):
    return struct.pack("=i", int(v))


def fixed(v):
    return struct.pack("=i", int(round(v * 256)))


def string(s):
    b = s.encode() + b"\0"
    return u32(len(b)) + b + b"\0" * ((4 - len(b) % 4) % 4)


def _read_string(p, off):
    (n,) = struct.unpack_from("=I", p, off)
    s = p[off + 4: off + 4 + n - 1].decode(errors="replace")
    return s, off + 4 + ((n + 3) & ~3)


def _now_ms():
    return int(time.monotonic() * 1000) & 0xFFFFFFFF


def find_socket():
    rt = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    disp = os.environ.get("WAYLAND_DISPLAY")
    if disp:
        return disp if disp.startswith("/") else os.path.join(rt, disp)
    for name in sorted(os.listdir(rt)):
        if name.startswith("wayland-") and not name.endswith(".lock"):
            return os.path.join(rt, name)
    raise WaylandError("no Wayland socket found (WAYLAND_DISPLAY unset)")


class Output:
    def __init__(self, wl_id):
        self.wl_id = wl_id
        self.name = None
        self.description = ""
        self.x = self.y = 0
        self.width = self.height = 0          # logical size
        self.mode_w = self.mode_h = 0         # physical mode
        self.scale = 1
        self.transform = 0

    def as_dict(self):
        return {"name": self.name, "x": self.x, "y": self.y,
                "width": self.width, "height": self.height,
                "physical": [self.mode_w, self.mode_h], "scale": self.scale,
                "description": self.description}


class Connection:
    def __init__(self, path=None):
        self.path = path or find_socket()
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect(self.path)
        self.next_id = 2
        self.free_ids = []
        self.handlers = {1: self._on_display}
        self.buf = b""
        self.globals = {}       # name -> (interface, version)
        self.outputs = {}       # global name -> Output
        self.error = None
        self.registry = self._new_id(self._on_registry)
        self._send(1, 1, u32(self.registry))
        self.roundtrip()
        self.seat = self._bind_first("wl_seat", 1)
        self.xdg_mgr = self._bind_first("zxdg_output_manager_v1", 3)
        for name in list(self.outputs):
            self._setup_output(name)
        self.roundtrip()

    # ---- low level -------------------------------------------------------
    def _new_id(self, handler=None):
        if self.free_ids:
            i = self.free_ids.pop()
        else:
            i = self.next_id
            self.next_id += 1
        self.handlers[i] = handler
        return i

    def _send(self, obj, opcode, payload=b"", fds=()):
        msg = struct.pack("=II", obj, ((8 + len(payload)) << 16) | opcode) + payload
        if fds:
            self.sock.sendmsg([msg], [(socket.SOL_SOCKET, socket.SCM_RIGHTS,
                                       array.array("i", fds))])
        else:
            self.sock.sendall(msg)

    def _pump(self, timeout):
        r, _, _ = select.select([self.sock], [], [], timeout)
        if not r:
            raise WaylandError("timed out waiting for compositor")
        data, _anc, _flags, _addr = self.sock.recvmsg(65536, socket.CMSG_SPACE(64))
        if not data:
            raise WaylandError("compositor closed the connection")
        self.buf += data
        while len(self.buf) >= 8:
            obj, so = struct.unpack_from("=II", self.buf)
            size, op = so >> 16, so & 0xFFFF
            if len(self.buf) < size:
                break
            payload = self.buf[8:size]
            self.buf = self.buf[size:]
            h = self.handlers.get(obj)
            if h:
                h(op, payload)
        if self.error:
            raise WaylandError(self.error)

    def roundtrip(self, timeout=3.0):
        state = {"done": False}

        def on_done(op, p):
            state["done"] = True

        cb = self._new_id(on_done)
        self._send(1, 0, u32(cb))
        deadline = time.monotonic() + timeout
        while not state["done"]:
            self._pump(max(0.01, deadline - time.monotonic()))

    def flush_events(self):
        """Non-blocking: process whatever the compositor has sent."""
        while select.select([self.sock], [], [], 0)[0]:
            self._pump(0)

    # ---- core events -----------------------------------------------------
    def _on_display(self, op, p):
        if op == 0:
            obj, code = struct.unpack_from("=II", p)
            msg, _ = _read_string(p, 8)
            self.error = f"protocol error on object {obj} code {code}: {msg}"
        elif op == 1:
            (i,) = struct.unpack_from("=I", p)
            self.handlers.pop(i, None)
            self.free_ids.append(i)

    def _on_registry(self, op, p):
        if op == 0:
            (name,) = struct.unpack_from("=I", p)
            iface, off = _read_string(p, 4)
            (ver,) = struct.unpack_from("=I", p, off)
            self.globals[name] = (iface, ver)
            if iface == "wl_output":
                self.outputs[name] = None
                if hasattr(self, "xdg_mgr"):
                    self._setup_output(name)
        elif op == 1:
            (name,) = struct.unpack_from("=I", p)
            self.globals.pop(name, None)
            self.outputs.pop(name, None)

    def _bind(self, name, iface, version, handler=None):
        i = self._new_id(handler)
        self._send(self.registry, 0, u32(name) + string(iface) + u32(version) + u32(i))
        return i

    def _bind_first(self, iface, max_ver, handler=None):
        for name, (gi, gv) in self.globals.items():
            if gi == iface:
                return self._bind(name, iface, min(gv, max_ver), handler)
        return None

    def has(self, iface):
        return any(gi == iface for gi, _ in self.globals.values())

    # ---- outputs ---------------------------------------------------------
    def _setup_output(self, gname):
        iface, ver = self.globals[gname]
        out = Output(None)

        def on_wl(op, p):
            if op == 0:  # geometry: x y pw ph subpixel make model transform
                try:
                    _, off = _read_string(p, 20)
                    _, off = _read_string(p, off)
                    (out.transform,) = struct.unpack_from("=i", p, off)
                except struct.error:
                    pass
            elif op == 1:  # mode
                flags, w, h, _r = struct.unpack_from("=Iiii", p)
                if flags & 1:
                    out.mode_w, out.mode_h = w, h
            elif op == 3:
                (out.scale,) = struct.unpack_from("=i", p)
            elif op == 4:
                out.name, _ = _read_string(p, 0)
            elif op == 5:
                out.description, _ = _read_string(p, 0)

        out.wl_id = self._bind(gname, "wl_output", min(ver, 4), on_wl)

        def on_xdg(op, p):
            if op == 0:
                out.x, out.y = struct.unpack_from("=ii", p)
            elif op == 1:
                out.width, out.height = struct.unpack_from("=ii", p)
            elif op == 3 and not out.name:
                out.name, _ = _read_string(p, 0)
            elif op == 4 and not out.description:
                out.description, _ = _read_string(p, 0)

        if self.xdg_mgr is not None:
            xid = self._new_id(on_xdg)
            self._send(self.xdg_mgr, 1, u32(xid) + u32(out.wl_id))
        self.outputs[gname] = out

    def output_list(self):
        outs = [o for o in self.outputs.values() if o is not None and o.name]
        for o in outs:
            if not o.width and o.mode_w:
                o.width, o.height = o.mode_w // max(o.scale, 1), o.mode_h // max(o.scale, 1)
        return sorted(outs, key=lambda o: (o.x, o.y))

    def layout_box(self):
        outs = self.output_list()
        if not outs:
            raise WaylandError("no outputs reported by compositor")
        x0 = min(o.x for o in outs)
        y0 = min(o.y for o in outs)
        x1 = max(o.x + o.width for o in outs)
        y1 = max(o.y + o.height for o in outs)
        return x0, y0, x1 - x0, y1 - y0


# evdev button codes
BUTTONS = {"left": 0x110, "right": 0x111, "middle": 0x112,
           "back": 0x113, "forward": 0x114}


class VirtualPointer:
    def __init__(self, conn):
        if not conn.has("zwlr_virtual_pointer_manager_v1"):
            raise WaylandError("compositor lacks zwlr_virtual_pointer_manager_v1")
        self.c = conn
        self.mgr = conn._bind_first("zwlr_virtual_pointer_manager_v1", 2)
        self.id = conn._new_id()
        conn._send(self.mgr, 0, u32(conn.seat) + u32(self.id))
        self.x = self.y = None

    def move_to(self, x, y):
        bx, by, bw, bh = self.c.layout_box()
        rx = min(max(int(round(x - bx)), 0), bw - 1)
        ry = min(max(int(round(y - by)), 0), bh - 1)
        self.c._send(self.id, 1, u32(_now_ms()) + u32(rx) + u32(ry) + u32(bw) + u32(bh))
        self.c._send(self.id, 4)
        self.x, self.y = rx + bx, ry + by

    def move_rel(self, dx, dy):
        self.c._send(self.id, 0, u32(_now_ms()) + fixed(dx) + fixed(dy))
        self.c._send(self.id, 4)
        if self.x is not None:
            self.x += dx
            self.y += dy

    def button(self, name, pressed):
        code = BUTTONS[name] if isinstance(name, str) else int(name)
        self.c._send(self.id, 2, u32(_now_ms()) + u32(code) + u32(1 if pressed else 0))
        self.c._send(self.id, 4)

    def scroll(self, dy=0, dx=0):
        """dy/dx in wheel clicks; positive dy scrolls down, positive dx right."""
        t = _now_ms()
        self.c._send(self.id, 5, u32(0))  # axis_source wheel
        for axis, n in ((0, dy), (1, dx)):
            if n:
                self.c._send(self.id, 7, u32(t) + u32(axis) + fixed(15.0 * n) + i32(n))
        self.c._send(self.id, 4)


# ---- keyboard ----------------------------------------------------------------
# evdev keycodes for a US layout: char -> (code, shifted)
_US_ROWS = [
    (41, "`~"), (2, "1!"), (3, "2@"), (4, "3#"), (5, "4$"), (6, "5%"), (7, "6^"),
    (8, "7&"), (9, "8*"), (10, "9("), (11, "0)"), (12, "-_"), (13, "=+"),
    (26, "[{"), (27, "]}"), (39, ";:"), (40, "'\""), (43, "\\|"),
    (51, ",<"), (52, ".>"), (53, "/?"),
]
_LETTERS = {**dict(zip("qwertyuiop", range(16, 26))),
            **dict(zip("asdfghjkl", range(30, 39))),
            **dict(zip("zxcvbnm", range(44, 51)))}

US_CHARS = {}
for code, pair in _US_ROWS:
    US_CHARS[pair[0]] = (code, False)
    US_CHARS[pair[1]] = (code, True)
for ch, code in _LETTERS.items():
    US_CHARS[ch] = (code, False)
    US_CHARS[ch.upper()] = (code, True)
US_CHARS[" "] = (57, False)
US_CHARS["\n"] = (28, False)
US_CHARS["\t"] = (15, False)

NAMED_KEYS = {
    "esc": 1, "escape": 1, "backspace": 14, "tab": 15, "enter": 28, "return": 28,
    "ctrl": 29, "control": 29, "lctrl": 29, "rctrl": 97,
    "shift": 42, "lshift": 42, "rshift": 54,
    "alt": 56, "lalt": 56, "ralt": 100, "altgr": 100,
    "super": 125, "meta": 125, "win": 125, "cmd": 125, "logo": 125, "rsuper": 126,
    "space": 57, "capslock": 58, "numlock": 69, "scrolllock": 70,
    "print": 99, "printscreen": 99, "sysrq": 99, "pause": 119, "menu": 127,
    "home": 102, "up": 103, "pageup": 104, "pgup": 104, "left": 105, "right": 106,
    "end": 107, "down": 108, "pagedown": 109, "pgdn": 109, "insert": 110,
    "delete": 111, "del": 111,
    "mute": 113, "volumedown": 114, "volumeup": 115,
    "playpause": 164, "nexttrack": 163, "prevtrack": 165, "stop": 166,
    "kp_enter": 96, "minus": 12, "equal": 13, "plus": 13, "comma": 51,
    "period": 52, "slash": 53, "backslash": 43, "semicolon": 39,
    "apostrophe": 40, "quote": 40, "grave": 41, "backtick": 41,
    "bracketleft": 26, "bracketright": 27,
}
for _i in range(1, 11):
    NAMED_KEYS[f"f{_i}"] = 58 + _i
NAMED_KEYS["f11"], NAMED_KEYS["f12"] = 87, 88
for _i in range(13, 25):
    NAMED_KEYS[f"f{_i}"] = 170 + _i
for _ch, (_c, _s) in US_CHARS.items():
    if not _s and _ch.strip():
        NAMED_KEYS.setdefault(_ch, _c)

MODIFIER_CODES = {29, 97, 42, 54, 56, 100, 125, 126}
# real modifier bits: Shift=1 Lock=2 Control=4 Mod1(Alt)=8 Mod4(Super)=64
MOD_MASKS = {42: 1, 54: 1, 29: 4, 97: 4, 56: 8, 100: 8, 125: 64, 126: 64}

# xkb keycode names for the dynamic unicode pool (evdev codes 200..247)
_POOL = [f"I{x}" for x in range(208, 256)]

_KEYMAP_HEAD = """xkb_keymap {
  xkb_keycodes "cu" { include "evdev+aliases(qwerty)" };
  xkb_types "cu" { include "complete" };
  xkb_compatibility "cu" { include "complete" };
  xkb_symbols "cu" {
    include "pc+us"
    key <MUTE> { [ XF86AudioMute ] };
    key <VOL-> { [ XF86AudioLowerVolume ] };
    key <VOL+> { [ XF86AudioRaiseVolume ] };
    key <I172> { [ XF86AudioPlay, XF86AudioPause ] };
    key <I171> { [ XF86AudioNext ] };
    key <I173> { [ XF86AudioPrev ] };
    key <I174> { [ XF86AudioStop ] };
"""


class VirtualKeyboard:
    def __init__(self, conn):
        if not conn.has("zwp_virtual_keyboard_manager_v1"):
            raise WaylandError("compositor lacks zwp_virtual_keyboard_manager_v1")
        self.c = conn
        self.mgr = conn._bind_first("zwp_virtual_keyboard_manager_v1", 1)
        self.id = conn._new_id()
        conn._send(self.mgr, 0, u32(conn.seat) + u32(self.id))
        self.extra = []          # unicode chars currently mapped into the pool
        self.down = set()
        self._upload()

    def _upload(self):
        body = "".join(
            f'    key <{_POOL[i]}> {{ [ U{ord(ch):04X} ] }};\n' for i, ch in enumerate(self.extra))
        text = (_KEYMAP_HEAD + body + "  };\n};\n").encode() + b"\0"
        fd = os.memfd_create("sudoclaude-keymap", os.MFD_CLOEXEC)
        try:
            os.write(fd, text)
            os.lseek(fd, 0, 0)
            self.c._send(self.id, 0, u32(1) + u32(len(text)), fds=[fd])
        finally:
            os.close(fd)

    def key(self, code, pressed):
        self.c._send(self.id, 1, u32(_now_ms()) + u32(code) + u32(1 if pressed else 0))
        if pressed:
            self.down.add(code)
        else:
            self.down.discard(code)
        if code in MOD_MASKS:
            # wlroots/Hyprland don't derive modifier state from virtual key
            # events, so publish it explicitly.
            mask = 0
            for c in self.down:
                mask |= MOD_MASKS.get(c, 0)
            self.c._send(self.id, 2, u32(mask) + u32(0) + u32(0) + u32(0))

    def tap(self, code, mods=(), delay=0.0):
        for m in mods:
            self.key(m, True)
        self.key(code, True)
        self.key(code, False)
        for m in reversed(mods):
            self.key(m, False)
        if delay:
            time.sleep(delay)

    def release_all(self):
        for code in list(self.down):
            self.key(code, False)

    def type_text(self, text, delay=0.0):
        """Type arbitrary unicode text. Chars outside US layout are mapped
        into spare keycodes, re-uploading the keymap in chunks as needed."""
        i = 0
        n = len(text)
        while i < n:
            # gather a segment whose non-US chars fit in the pool
            needed = []
            j = i
            while j < n:
                ch = text[j]
                if ch not in US_CHARS and ch not in needed:
                    if len(needed) >= len(_POOL):
                        break
                    needed.append(ch)
                j += 1
            if needed and not set(needed) <= set(self.extra):
                self.extra = needed
                self._upload()
            for ch in text[i:j]:
                if ch in US_CHARS:
                    code, shift = US_CHARS[ch]
                    self.tap(code, (42,) if shift else (), delay)
                elif ch == "\r":
                    continue
                else:
                    code = int(_POOL[self.extra.index(ch)][1:]) - 8
                    self.tap(code, (), delay)
            i = j
