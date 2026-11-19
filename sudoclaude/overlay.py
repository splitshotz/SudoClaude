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


class Overlay:
    def __init__(self, on_stop=None, comp=None):
        self.on_stop = on_stop
        self.comp = comp
        self.proc = None
        self.sock = None
        self.path = os.path.join(RUNTIME, f"sudoclaude-overlay-{os.getpid()}.sock")
        self.bin = shutil.which("qs") or shutil.which("quickshell")
        self.failed = False
        self.error = None
        self._lock = threading.Lock()
        self.state = {}

    @property
    def available(self):
        return bool(self.bin) and os.path.exists(QML) and not self.failed

    def _start(self):
        if self.sock:
            return True
        if not self.available:
            return False
        try:
            if os.path.exists(self.path):
                os.unlink(self.path)
            env = dict(os.environ, SUDOCLAUDE_SOCK=self.path)
            self.log = open(os.path.join(RUNTIME, "sudoclaude-overlay.log"), "w")
            self.proc = subprocess.Popen([self.bin, "-p", QML], env=env,
                                         stdout=self.log, stderr=subprocess.STDOUT,
                                         start_new_session=True)
            if self.comp and self.comp.name == "hyprland":
                for rule in ("noanim, claude-computer-use", "noanim, claude-cu-glass",
                             "blur, claude-cu-glass", "ignorealpha 0.05, claude-cu-glass"):
                    try:
                        self.comp.raw("keyword layerrule " + rule)
                    except Exception:
                        pass
            deadline = time.time() + 6
            while time.time() < deadline:
                if self.proc.poll() is not None:
                    raise RuntimeError("quickshell exited; see sudoclaude-overlay.log")
                try:
                    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                    s.connect(self.path)
                    self.sock = s
                    threading.Thread(target=self._reader, daemon=True).start()
                    # replay state
                    if self.state:
                        self._raw(self.state)
                    return True
                except OSError:
                    s.close()
                    time.sleep(0.08)
            raise RuntimeError("overlay socket never appeared")
        except Exception as e:
            self.error = str(e)
            self.failed = True
            self.stop()
            return False

    def _reader(self):
        buf = b""
        s = self.sock
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
                if m.get("event") == "stop" and self.on_stop:
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
        for k in ("active", "status", "detail", "action", "screen", "stopped", "idle"):
            if k in msg:
                self.state[k] = msg[k]
        if "x" in msg:
            self.state["x"], self.state["y"] = msg["x"], msg["y"]
        with self._lock:
            if not self.sock and not (msg.get("active") and self._start()):
                return
            if not self._raw(msg) and self._start():
                self._raw(msg)

    def capture_hide(self):
        if self.sock and self.state.get("active"):
            self._raw({"capturing": True})
            return True
        return False

    def capture_show(self):
        if self.sock:
            self._raw({"capturing": False})

    def stop(self):
        try:
            if self.sock:
                self._raw({"quit": True})
                self.sock.close()
        except Exception:
            pass
        self.sock = None
        if self.proc and self.proc.poll() is None:
            try:
                self.proc.terminate()
                self.proc.wait(timeout=2)
            except Exception:
                try:
                    self.proc.kill()
                except Exception:
                    pass
        self.proc = None
        try:
            os.unlink(self.path)
        except OSError:
            pass
