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

    def __init__(self, on_stop=None, comp=None):
        self.on_stop = on_stop
        self.comp = comp
        self.sock = None
        self.bin = shutil.which("qs") or shutil.which("quickshell")
        self.failed_at = 0
        self.error = None
        self._lock = threading.Lock()
        self.state = {}

    @property
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
                if self.comp:
                    try:
                        self.comp.overlay_rules()
                    except Exception:
                        pass
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
                if m.get("event") == "stop" and self.on_stop and self.state.get("active"):
                    self.on_stop()
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
        for k, v in msg.items():
            if k not in ("click", "quit"):
                self.state[k] = v
        with self._lock:
            if not self.sock and not ((msg.get("active") or msg.get("voice")) and self._ensure()):
                return
            if not self._raw(msg) and self._ensure():
                self._raw(msg)

    def capture_hide(self):
        if self.sock and self.state.get("active") and not (self.comp and self.comp.lua):
            self._raw({"capturing": True})
            return True
        return False

    def capture_show(self):
        if self.sock and not (self.comp and self.comp.lua):
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
