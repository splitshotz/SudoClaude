import json
import os
import shutil
import socket
import subprocess
import threading
import time

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
QML = os.path.join(HERE, "overlay", "overlay.qml")
RUNTIME = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
SOCK = os.path.join(RUNTIME, "sudoclaude-overlay.sock")
LOG = os.path.join(RUNTIME, "sudoclaude-overlay.log")


class Overlay:
    """Client for the shared overlay process. Several clients (the MCP server
    in each Claude session, the voice daemon) talk to one Quickshell instance."""

    def __init__(self, on_stop=None, comp=None, on_event=None):
        self.on_stop = on_stop
        self.on_event = on_event
        self.comp = comp
        self.sock = None
        self.bin = shutil.which("qs") or shutil.which("quickshell")
        self.failed_at = 0
        self.error = None
        self._lock = threading.Lock()
        self.state = {}
        try:
            with open(os.path.expanduser("~/.config/sudoclaude/config.json")) as f:
                style = json.load(f).get("overlay_style")
            if style:
                self.state["style"] = style
        except (OSError, ValueError):
            pass
        self._shape_sent = False

    def _shape(self):
        """Corner radii that match this desktop: Hyprland's window rounding, and
        end-4's rounded screen corners when that shell is installed."""
        msg = {}
        r = self.comp.rounding() if self.comp and hasattr(self.comp, "rounding") else None
        if r is not None:
            msg["windowRadius"] = r
        cfg = os.path.expanduser("~/.config/illogical-impulse/config.json")
        try:
            with open(cfg) as f:
                corners = json.load(f).get("appearance", {}).get("fakeScreenRounding", 1)
            msg["screenRadius"] = 23 if corners else 0
        except (OSError, ValueError):
            msg["screenRadius"] = 0 if not os.path.isdir(os.path.dirname(cfg)) else 23
        return msg

    def _rules(self):
        if self.comp:
            try:
                self.comp.overlay_rules()
            except Exception:
                pass
    def available(self):
        return bool(self.bin) and os.path.exists(QML)

    def _connect(self):
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.connect(SOCK)
        self.sock = s
        threading.Thread(target=self._reader, args=(s,), daemon=True).start()

    def _spawn(self):
        if os.path.exists(SOCK):
            os.unlink(SOCK)
        os.makedirs(os.path.expanduser("~/.local/state/sudoclaude"), exist_ok=True)
        env = dict(os.environ, SUDOCLAUDE_SOCK=SOCK, QT_QPA_PLATFORM="wayland")
        log = open(LOG, "w")
        subprocess.Popen([self.bin, "-p", QML], env=env, stdout=log, stderr=subprocess.STDOUT,
                         stdin=subprocess.DEVNULL, start_new_session=True)

    def _ensure(self):
        if self.sock:
            return True
        if not self.available or time.time() - self.failed_at < 30:
            return False
        try:
            try:
                self._connect()
            except OSError:
                self._rules()
                self._spawn()
                deadline = time.time() + 6
                while True:
                    try:
                        self._connect()
                        break
                    except OSError:
                        if time.time() > deadline:
                            raise RuntimeError("overlay did not start; see " + LOG)
                        time.sleep(0.08)
            if not self._shape_sent:
                try:
                    self.state.update(self._shape())
                except Exception:
                    pass
                self._shape_sent = True
            if self.state:
                self._raw(self.state)
            self.error = None
            return True
        except Exception as e:
            self.error = str(e)
            self.failed_at = time.time()
            self.sock = None
            return False

    def _reader(self, s):
        buf = b""
        while True:
            try:
                d = s.recv(4096)
            except OSError:
                break
            if not d:
                break
            buf += d
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                try:
                    m = json.loads(line)
                except Exception:
                    continue
                if m.get("event") == "stop" and self.on_stop and \
                        (self.state.get("active") or self.state.get("voice")):
                    self.on_stop()
                elif m.get("event") and m.get("event") != "stop" and self.on_event:
                    try:
                        self.on_event(m)
                    except Exception:
                        pass
        with self._lock:
            if self.sock is s:
                self.sock = None

    def _raw(self, msg):
        try:
            self.sock.sendall((json.dumps(msg) + "\n").encode())
            return True
        except OSError:
            self.sock = None
            return False

    def send(self, **msg):
        was = bool(self.state.get("active") or self.state.get("voice"))
        if (msg.get("active") or msg.get("voice")) and not was:
            # Runtime layer rules are dropped whenever Hyprland reloads its config.
            self._rules()
        for k, v in msg.items():
            if k not in ("click", "quit"):
                self.state[k] = v
        with self._lock:
            if not self.sock and not ((msg.get("active") or msg.get("voice")) and self._ensure()):
                return
            if not self._raw(msg) and self._ensure():
                self._raw(msg)

    def capture_hide(self):
        if self.sock and (self.state.get("active") or self.state.get("voice")):
            self._raw({"capturing": True})
            return True
        return False

    def capture_show(self):
        if self.sock:
            self._raw({"capturing": False})

    def stop(self):
        try:
            if self.sock:
                if self.state.get("active"):
                    self._raw({"active": False})
                self.sock.close()
        except Exception:
            pass
        self.sock = None
