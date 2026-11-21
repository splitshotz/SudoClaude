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
STAMP = os.path.join(RUNTIME, "sudoclaude-overlay.stamp")
PIDFILE = os.path.join(RUNTIME, "sudoclaude-overlay.pid")
CONFIG = os.path.expanduser("~/.config/sudoclaude/config.json")


def _end_previous():
    """Close the overlay this module last started, if it's still around, so a
    restart never leaves two of them drawing."""
    try:
        with open(PIDFILE) as f:
            pid = int(f.read().strip())
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            cmd = f.read()
    except (OSError, ValueError):
        return
    args = [a for a in cmd.split(b"\0") if a]
    ours = QML.encode() in cmd
    # Quickshell's crash relauncher runs under a bare name with no arguments.
    relaunched = len(args) == 1 and os.path.basename(args[0]) in (b"quickshell", b"qs")
    if not (ours or relaunched):
        return
    try:
        os.kill(pid, 15)
    except OSError:
        return
    for _ in range(30):
        if not os.path.exists(f"/proc/{pid}"):
            return
        time.sleep(0.05)


def code_mtime():
    """Newest change to the overlay's QML or shaders."""
    newest = 0.0
    for root, _, files in os.walk(os.path.dirname(QML)):
        for n in files:
            try:
                newest = max(newest, os.path.getmtime(os.path.join(root, n)))
            except OSError:
                pass
    return newest


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
            with open(CONFIG) as f:
                style = json.load(f).get("overlay_style")
            if style:
                self.state["style"] = style
        except (OSError, ValueError):
            pass
        self._shape_sent = False
        self._cfg = (None, True)
        self._game = None
        threading.Thread(target=self._game_watch, daemon=True).start()

    def enabled(self):
        """config "overlay": false turns the overlay off for every client."""
        try:
            mtime = os.stat(CONFIG).st_mtime
        except OSError:
            return True
        if mtime != self._cfg[0]:
            try:
                with open(CONFIG) as f:
                    on = json.load(f).get("overlay", True) is not False
            except (OSError, ValueError):
                on = True
            self._cfg = (mtime, on)
        return self._cfg[1]

    def blocked(self):
        """Why nothing should be drawn right now, or None. Games don't block it:
        the overlay process quits itself a few seconds after it stops showing
        anything (overlay.qml), so over a game it only exists while you're
        actually using it."""
        if not self.enabled():
            return "off"
        return None

    def _game_watch(self):
        # "overlay": false switched on while it's up: take it down within a second.
        while True:
            time.sleep(1)
            try:
                if self.blocked():
                    self.shutdown_process()
                # The overlay quits itself when idle; collect it so no zombie lingers.
                proc = getattr(self, "_proc", None)
                if proc is not None and proc.poll() is not None:
                    self._proc = None
            except Exception:
                pass

    def shutdown_process(self):
        """Quit the shared Quickshell overlay so nothing of it is left drawing or
        holding GPU memory. The next allowed send starts it again."""
        with self._lock:
            s, self.sock = self.sock, None
            if s:
                try:
                    s.sendall(b'{"quit": true}\n')
                except OSError:
                    pass
                try:
                    s.close()
                except OSError:
                    pass
        if not s:
            # Maybe another client (the voice assistant, another session) has it up.
            try:
                probe = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                probe.settimeout(0.5)
                probe.connect(SOCK)
                probe.sendall(b'{"quit": true}\n')
                probe.close()
            except OSError:
                return
        time.sleep(0.3)
        _end_previous()

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
    @property
    def available(self):
        return bool(self.bin) and os.path.exists(QML)

    def _connect(self):
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.connect(SOCK)
        self.sock = s
        threading.Thread(target=self._reader, args=(s,), daemon=True).start()

    def _spawn(self):
        _end_previous()
        if os.path.exists(SOCK):
            os.unlink(SOCK)
        os.makedirs(os.path.expanduser("~/.local/state/sudoclaude"), exist_ok=True)
        env = dict(os.environ, SUDOCLAUDE_SOCK=SOCK, QT_QPA_PLATFORM="wayland")
        with open(STAMP, "w") as f:
            f.write(str(code_mtime()))
        log = open(LOG, "w")
        proc = subprocess.Popen([self.bin, "-p", QML], env=env, stdout=log,
                                stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
                                start_new_session=True)
        self._proc = proc  # reaped by _game_watch once it quits itself
        with open(PIDFILE, "w") as f:
            f.write(str(proc.pid))

    def _ensure(self):
        if self.sock:
            return True
        if self.blocked() or not self.available or time.time() - self.failed_at < 30:
            return False
        try:
            try:
                self._connect()
                self._restart_if_stale()
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

    def _restart_if_stale(self):
        """An overlay left running from older code (Quickshell relaunches itself
        after a crash) gets asked to quit, so the caller spawns a fresh one."""
        try:
            with open(STAMP) as f:
                started = float(f.read().strip() or 0)
        except (OSError, ValueError):
            started = 0.0
        if code_mtime() <= started:
            return
        try:
            self.sock.sendall(b'{"quit": true}\n')
        except OSError:
            pass
        try:
            self.sock.close()
        except OSError:
            pass
        self.sock = None
        deadline = time.time() + 3
        while time.time() < deadline:
            try:
                probe = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                probe.connect(SOCK)
                probe.close()
                time.sleep(0.1)
            except OSError:
                break
        raise OSError("overlay was stale")

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
        if self.blocked():
            return
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
