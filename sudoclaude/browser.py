"""Bridge to the SudoClaude browser extension.

The extension drives tabs through Chrome's debugger API (the DevTools
protocol), the same way Claude in Chrome does: it reads the page's
accessibility tree, clicks and types into elements by reference, and takes
screenshots of the tab itself. None of that needs the window focused or the
real mouse, so Claude can work in a tab while the user does something else.

The extension connects to ws://127.0.0.1:PORT. The first SudoClaude process
to bind that port is the hub; any other one (the voice assistant's, a second
Claude session) connects to the hub as a client and its requests are passed
through. Every connection must present the token in ~/.config/sudoclaude.
"""

import base64
import hashlib
import json
import os
import secrets
import socket
import struct
import threading
import time

PORT = 47823
TOKEN_FILE = os.path.expanduser("~/.config/sudoclaude/browser_token")
GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


def token():
    try:
        with open(TOKEN_FILE) as f:
            t = f.read().strip()
            if t:
                return t
    except OSError:
        pass
    os.makedirs(os.path.dirname(TOKEN_FILE), exist_ok=True)
    t = secrets.token_hex(16)
    fd = os.open(TOKEN_FILE, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(t)
    return t


# ---- minimal RFC 6455 ---------------------------------------------------------

def _recv_exact(sock, n):
    buf = b""
    while len(buf) < n:
        d = sock.recv(n - len(buf))
        if not d:
            raise ConnectionError("closed")
        buf += d
    return buf


def ws_recv(sock):
    """Returns a text message, or None on close. Handles ping and fragments."""
    parts = []
    while True:
        b1, b2 = _recv_exact(sock, 2)
        op, fin = b1 & 0x0F, b1 & 0x80
        n = b2 & 0x7F
        if n == 126:
            n = struct.unpack(">H", _recv_exact(sock, 2))[0]
        elif n == 127:
            n = struct.unpack(">Q", _recv_exact(sock, 8))[0]
        mask = _recv_exact(sock, 4) if b2 & 0x80 else None
        data = _recv_exact(sock, n)
        if mask:
            data = bytes(c ^ mask[i % 4] for i, c in enumerate(data))
        if op == 8:
            return None
        if op == 9:
            ws_send(sock, data, op=10)
            continue
        if op == 10:
            continue
        parts.append(data)
        if fin:
            return b"".join(parts).decode("utf-8", "replace")


def ws_send(sock, data, op=1, masked=False):
    if isinstance(data, str):
        data = data.encode()
    head = bytes([0x80 | op])
    n = len(data)
    mbit = 0x80 if masked else 0
    if n < 126:
        head += bytes([mbit | n])
    elif n < 65536:
        head += bytes([mbit | 126]) + struct.pack(">H", n)
    else:
        head += bytes([mbit | 127]) + struct.pack(">Q", n)
    if masked:
        key = os.urandom(4)
        data = bytes(c ^ key[i % 4] for i, c in enumerate(data))
        head += key
    sock.sendall(head + data)


def _server_handshake(conn):
    req = b""
    while b"\r\n\r\n" not in req:
        d = conn.recv(4096)
        if not d:
            raise ConnectionError("closed during handshake")
        req += d
        if len(req) > 16384:
            raise ConnectionError("handshake too large")
    headers = {}
    for line in req.decode(errors="replace").split("\r\n")[1:]:
        if ":" in line:
            k, v = line.split(":", 1)
            headers[k.strip().lower()] = v.strip()
    key = headers.get("sec-websocket-key")
    if not key:
        conn.sendall(b"HTTP/1.1 400 Bad Request\r\n\r\n")
        raise ConnectionError("not a websocket request")
    origin = headers.get("origin", "")
    # Only the extension or local tools; never an ordinary web page.
    if origin and not origin.startswith("chrome-extension://"):
        conn.sendall(b"HTTP/1.1 403 Forbidden\r\n\r\n")
        raise ConnectionError("rejected origin " + origin)
    accept = base64.b64encode(hashlib.sha1((key + GUID).encode()).digest()).decode()
    conn.sendall(("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n"
                  "Connection: Upgrade\r\nSec-WebSocket-Accept: " + accept + "\r\n\r\n").encode())


def _client_connect(port):
    s = socket.create_connection(("127.0.0.1", port), timeout=3)
    key = base64.b64encode(os.urandom(16)).decode()
    s.sendall((f"GET / HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\nUpgrade: websocket\r\n"
               f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\n"
               "Sec-WebSocket-Version: 13\r\n\r\n").encode())
    resp = b""
    while b"\r\n\r\n" not in resp:
        d = s.recv(4096)
        if not d:
            raise ConnectionError("hub closed")
        resp += d
    if b" 101 " not in resp.split(b"\r\n", 1)[0]:
        raise ConnectionError("hub refused")
    s.settimeout(None)
    return s


# ---- hub / client -------------------------------------------------------------

class Browser:
    def __init__(self, log=lambda *a: None):
        self.log = log
        self.token = token()
        self.lock = threading.Lock()
        self.ext = None            # extension socket (hub only)
        self.ext_lock = threading.Lock()
        self.hub = None            # socket to the hub (client mode)
        self.pending = {}
        self.seq = 0
        self.mode = None
        self._start()

    # setup
    def _start(self):
        try:
            srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            srv.bind(("127.0.0.1", PORT))
            srv.listen(8)
            self.mode = "hub"
            threading.Thread(target=self._accept, args=(srv,), daemon=True).start()
        except OSError:
            self.mode = "client"

    def _accept(self, srv):
        while True:
            conn, _ = srv.accept()
            threading.Thread(target=self._serve, args=(conn,), daemon=True).start()

    def _serve(self, conn):
        try:
            _server_handshake(conn)
            hello = json.loads(ws_recv(conn) or "{}")
            if not secrets.compare_digest(str(hello.get("token", "")), self.token):
                ws_send(conn, json.dumps({"error": "bad token"}))
                conn.close()
                return
            if hello.get("role") == "extension":
                with self.ext_lock:
                    old, self.ext = self.ext, conn
                if old:
                    try:
                        old.close()
                    except OSError:
                        pass
                self.log("browser extension connected")
                self._read_ext(conn)
            else:
                self._relay_client(conn)
        except (ConnectionError, OSError, ValueError):
            pass
        finally:
            try:
                conn.close()
            except OSError:
                pass

    def _read_ext(self, conn):
        while True:
            msg = ws_recv(conn)
            if msg is None:
                break
            try:
                m = json.loads(msg)
            except ValueError:
                continue
            slot = self.pending.get(m.get("id"))
            if slot:
                slot["res"] = m
                slot["ev"].set()
        with self.ext_lock:
            if self.ext is conn:
                self.ext = None

    def _relay_client(self, conn):
        while True:
            msg = ws_recv(conn)
            if msg is None:
                return
            req = json.loads(msg)
            try:
                res = self._ext_call(req.get("cmd"), req.get("args") or {}, req.get("timeout", 30))
                out = {"id": req.get("id"), "result": res}
            except Exception as e:
                out = {"id": req.get("id"), "error": str(e)}
            ws_send(conn, json.dumps(out))

    # calls
    def _ext_call(self, cmd, args, timeout=30):
        end = time.time() + 6
        while True:
            with self.ext_lock:
                ext = self.ext
            if ext or time.time() > end:
                break
            time.sleep(0.2)
        if not ext:
            raise RuntimeError(
                "the SudoClaude browser extension isn't connected. It loads with Chromium "
                "(see README: browser). Open Chromium, or reload the extension.")
        with self.lock:
            self.seq += 1
            mid = self.seq
            slot = {"ev": threading.Event(), "res": None}
            self.pending[mid] = slot
            ws_send(ext, json.dumps({"id": mid, "cmd": cmd, "args": args}))
        try:
            if not slot["ev"].wait(timeout):
                raise TimeoutError(f"browser {cmd} timed out")
            res = slot["res"]
            if res.get("error"):
                raise RuntimeError(res["error"])
            return res.get("result")
        finally:
            self.pending.pop(mid, None)

    def _hub_call(self, cmd, args, timeout):
        with self.lock:
            if not self.hub:
                self.hub = _client_connect(PORT)
                ws_send(self.hub, json.dumps({"role": "client", "token": self.token}), masked=True)
            self.seq += 1
            mid = self.seq
            ws_send(self.hub, json.dumps({"id": mid, "cmd": cmd, "args": args,
                                          "timeout": timeout}), masked=True)
            self.hub.settimeout(timeout + 5)
            try:
                while True:
                    m = json.loads(ws_recv(self.hub) or "{}")
                    if m.get("id") == mid:
                        break
            except Exception:
                try:
                    self.hub.close()
                except OSError:
                    pass
                self.hub = None
                raise
        if m.get("error"):
            raise RuntimeError(m["error"])
        return m.get("result")

    def call(self, cmd, timeout=30, **args):
        if self.mode == "hub":
            return self._ext_call(cmd, args, timeout)
        try:
            return self._hub_call(cmd, args, timeout)
        except (ConnectionError, OSError):
            # the hub went away; try to become it
            self._start()
            if self.mode == "hub":
                time.sleep(2.5)
                return self._ext_call(cmd, args, timeout)
            raise

    def connected(self):
        if self.mode == "hub":
            return self.ext is not None
        try:
            self.call("ping", timeout=3)
            return True
        except Exception:
            return False
