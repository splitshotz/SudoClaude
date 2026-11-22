"""The user's Android phone over wireless ADB: see the screen, read its UI, tap,
swipe, type, open apps, read notifications.

Wireless debugging needs pairing once per computer (a six-digit code from the
phone's Wireless debugging screen). After that the phone advertises itself over
mDNS and we connect on our own whenever it's on the same network.
"""
import base64
import io
import json
import os
import re
import shlex
import shutil
import subprocess
import time
import xml.etree.ElementTree as ET

STATE = os.path.expanduser("~/.config/sudoclaude/phone.json")
CONFIG = os.path.expanduser("~/.config/sudoclaude/config.json")
OVERLAY = "io.github.splitshotz.sudoclaude.phone"
APK = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "phone",
                   "sudoclaude-phone.apk")
STOP_FILE = f"/sdcard/Android/data/{OVERLAY}/files/stop"
KEYS = {
    "home": "KEYCODE_HOME", "back": "KEYCODE_BACK", "recents": "KEYCODE_APP_SWITCH",
    "enter": "KEYCODE_ENTER", "delete": "KEYCODE_DEL", "backspace": "KEYCODE_DEL",
    "tab": "KEYCODE_TAB", "escape": "KEYCODE_ESCAPE", "space": "KEYCODE_SPACE",
    "power": "KEYCODE_POWER", "wake": "KEYCODE_WAKEUP", "sleep": "KEYCODE_SLEEP",
    "volume_up": "KEYCODE_VOLUME_UP", "volume_down": "KEYCODE_VOLUME_DOWN",
    "mute": "KEYCODE_VOLUME_MUTE", "play_pause": "KEYCODE_MEDIA_PLAY_PAUSE",
    "next": "KEYCODE_MEDIA_NEXT", "previous": "KEYCODE_MEDIA_PREVIOUS",
    "search": "KEYCODE_SEARCH", "menu": "KEYCODE_MENU", "camera": "KEYCODE_CAMERA",
    "up": "KEYCODE_DPAD_UP", "down": "KEYCODE_DPAD_DOWN", "left": "KEYCODE_DPAD_LEFT",
    "right": "KEYCODE_DPAD_RIGHT", "select_all": "--longpress KEYCODE_A",
}
# Apps where a wrong tap costs money or exposes secrets get their own approval.
SENSITIVE = re.compile(r"bank|wallet|pay(?!load)|venmo|cashapp|zelle|paypal|coinbase|crypto|"
                       r"robinhood|fidelity|schwab|chase|wellsfargo|citi|amex|capitalone|"
                       r"authenticator|authy|1password|bitwarden|lastpass|keepass|dashlane|"
                       r"\.vault|packageinstaller|permissioncontroller|com\.android\.settings",
                       re.I)
ALIASES = {
    "youtube": "com.google.android.youtube", "chrome": "com.android.chrome",
    "gmail": "com.google.android.gm", "maps": "com.google.android.apps.maps",
    "photos": "com.google.android.apps.photos", "play store": "com.android.vending",
    "settings": "com.android.settings", "camera": "camera", "messages": "messaging",
    "phone": "dialer", "contacts": "contacts", "calendar": "calendar", "clock": "deskclock",
    "spotify": "com.spotify.music", "discord": "com.discord", "instagram": "com.instagram.android",
    "snapchat": "com.snapchat.android", "whatsapp": "com.whatsapp", "tiktok": "musically",
    "x": "com.twitter.android", "twitter": "com.twitter.android", "reddit": "com.reddit.frontpage",
    "files": "files", "drive": "com.google.android.apps.docs", "keep": "com.google.android.keep",
}


class PhoneError(Exception):
    pass


def find_adb():
    for p in (shutil.which("adb"),
              os.path.join(os.environ.get("ANDROID_HOME", ""), "platform-tools", "adb"),
              os.path.join(os.environ.get("ANDROID_SDK_ROOT", ""), "platform-tools", "adb"),
              os.path.expanduser("~/Android/Sdk/platform-tools/adb"),
              "/opt/android-sdk/platform-tools/adb"):
        if p and os.path.isfile(p) and os.access(p, os.X_OK):
            return p
    return None


def _load():
    try:
        with open(STATE) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def _save(d):
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    with open(STATE, "w") as f:
        json.dump(d, f, indent=2)


class Phone:
    def __init__(self, log=print):
        self.log = log
        self.adb = find_adb()
        self.serial = None
        self.size = None          # real screen size in pixels
        self.scale = 1.0          # screenshot pixels -> real pixels
        self.marks = {}           # ref -> (x, y) in real pixels
        self.state = _load()
        self.fx_ready = None      # overlay app installed and allowed to draw
        self.fx_until = 0.0       # the overlay is showing until about then
        self.stop_seen = None

    # ---- plumbing ----------------------------------------------------------------
    def _run(self, args, timeout=20, binary=False, check=True, serial=True):
        if not self.adb:
            raise PhoneError("adb isn't installed. Install android-tools "
                             "(sudo pacman -S android-tools) or the Android SDK platform-tools.")
        cmd = [self.adb] + (["-s", self.serial] if serial and self.serial else []) + args
        try:
            r = subprocess.run(cmd, capture_output=True, timeout=timeout)
        except subprocess.TimeoutExpired:
            raise PhoneError(f"adb timed out: {' '.join(args[:3])}. The phone may have dropped "
                             "off Wi-Fi or locked wireless debugging.")
        out = r.stdout if binary else r.stdout.decode(errors="replace")
        if check and r.returncode != 0:
            err = (r.stderr.decode(errors="replace") or (out if not binary else "")).strip()
            raise PhoneError(err or f"adb {args[0]} failed")
        return out

    def sh(self, command, timeout=20, binary=False, check=True):
        self.ensure()
        return self._run(["exec-out" if binary else "shell", command], timeout=timeout,
                         binary=binary, check=check)

    def devices(self):
        out = self._run(["devices", "-l"], serial=False)
        devs = []
        for line in out.splitlines()[1:]:
            parts = line.split()
            if len(parts) >= 2:
                info = dict(p.split(":", 1) for p in parts[2:] if ":" in p)
                devs.append({"serial": parts[0], "state": parts[1], **info})
        return devs

    def mdns(self, kind="connect"):
        """Phones advertising wireless debugging on the network: [(name, host, port)]."""
        found = []
        try:
            out = self._run(["mdns", "services"], serial=False, timeout=8, check=False)
            for line in out.splitlines():
                m = re.match(rf"(\S+)\s+_adb-tls-{kind}\._tcp\.?\s+([\d.]+):(\d+)", line.strip())
                if m:
                    found.append((m.group(1), m.group(2), int(m.group(3))))
        except PhoneError:
            pass
        if not found and shutil.which("avahi-browse"):
            try:
                out = subprocess.run(["avahi-browse", "-rpt", f"_adb-tls-{kind}._tcp"],
                                     capture_output=True, text=True, timeout=6).stdout
                for line in out.splitlines():
                    f = line.split(";")
                    if f[0] == "=" and len(f) > 8 and f[2] == "IPv4":
                        found.append((f[3], f[7], int(f[8])))
            except (OSError, subprocess.TimeoutExpired, ValueError):
                pass
        return found

    def ensure(self):
        """Pick a connected phone, connecting over Wi-Fi if none is."""
        if self.serial and any(d["serial"] == self.serial and d["state"] == "device"
                               for d in self.devices()):
            return
        self.serial = None
        devs = [d for d in self.devices() if d["state"] == "device"]
        if not devs:
            self._reconnect()
            devs = [d for d in self.devices() if d["state"] == "device"]
        if not devs:
            bad = [d for d in self.devices() if d["state"] in ("unauthorized", "offline")]
            if bad:
                raise PhoneError(f"The phone is {bad[0]['state']}. Unlock it and accept the "
                                 "debugging prompt if there is one.")
            raise PhoneError(
                "No phone connected. Make sure it's on and on the same Wi-Fi with Wireless "
                "debugging on. If this computer was never paired, ask the user to open "
                "Developer options > Wireless debugging > Pair device with pairing code, "
                "then call phone pair with the six-digit code.")
        last = self.state.get("serial")
        pick = next((d for d in devs if d["serial"] == last), None) or \
            next((d for d in devs if d.get("model") == self.state.get("model")), None) or devs[0]
        self.serial = pick["serial"]
        if pick.get("model") and pick.get("model") != self.state.get("model"):
            self.state.update(model=pick.get("model"))
        self.state["serial"] = self.serial
        _save(self.state)

    def _reconnect(self):
        targets = [f"{h}:{p}" for _, h, p in self.mdns("connect")]
        if self.state.get("address"):
            targets.append(self.state["address"])
        for t in dict.fromkeys(targets):
            out = self._run(["connect", t], serial=False, timeout=8, check=False)
            if "connected" in out and "cannot" not in out and "failed" not in out:
                self.log(f"phone: connected {t}")
                self.state["address"] = t
                _save(self.state)
                return True
        return False

    # ---- connecting --------------------------------------------------------------
    def pair(self, code, host=None, port=None):
        code = re.sub(r"\D", "", str(code or ""))
        if len(code) != 6:
            raise PhoneError("The pairing code is the six digits under 'Pair device with "
                             "pairing code' in Wireless debugging.")
        if host and not port and ":" in host:
            host, port = host.rsplit(":", 1)
        if not (host and port):
            svc = self.mdns("pairing")
            if not svc:
                raise PhoneError("Couldn't find the phone's pairing screen on the network. Keep "
                                 "the 'Pair device with pairing code' dialog open, or pass the IP "
                                 "address and port it shows.")
            _, host, port = svc[0]
        out = self._run(["pair", f"{host}:{port}", code], serial=False, timeout=20, check=False)
        if "Successfully paired" not in out:
            raise PhoneError(out.strip() or "Pairing failed.")
        time.sleep(1.5)
        self._reconnect()
        self.ensure()
        return f"Paired and connected: {self.describe()}"

    def connect(self, host=None, port=None):
        if host:
            t = f"{host}:{port}" if port and ":" not in host else host
            out = self._run(["connect", t], serial=False, timeout=10, check=False)
            if "connected" not in out or "cannot" in out or "failed" in out:
                raise PhoneError(out.strip() or f"Couldn't connect to {t}")
            self.state["address"] = t
            _save(self.state)
        self.ensure()
        return f"Connected: {self.describe()}"

    def describe(self):
        props = self.sh("getprop ro.product.manufacturer; getprop ro.product.model; "
                        "getprop ro.build.version.release").split("\n")
        props = [p.strip() for p in props if p.strip()]
        name = " ".join(props[:2]) if len(props) >= 2 else self.serial
        ver = props[2] if len(props) > 2 else "?"
        return f"{name}, Android {ver} ({self.serial})"

    # ---- the overlay on the phone ------------------------------------------------
    def overlay_on(self):
        """Installs the small overlay app the first time (and when it changes), so the
        phone shows Claude's edge glow and cursor like the desktop does."""
        if self.fx_ready is not None:
            return self.fx_ready
        try:
            with open(CONFIG) as f:
                if json.load(f).get("phone_overlay") is False:
                    self.fx_ready = False
                    return False
        except (OSError, ValueError):
            pass
        self.fx_ready = False
        if not os.path.exists(APK):
            return False
        stamp = f"{os.path.getsize(APK)}-{int(os.path.getmtime(APK))}"
        have = "package:" in self.sh(f"pm path {OVERLAY}", check=False)
        if not have or self.state.get("overlay_apk") != stamp:
            out = self._run(["install", "-r", "-g", APK], timeout=90, check=False)
            if "Success" not in out:
                self._run(["uninstall", OVERLAY], timeout=30, check=False)
                out = self._run(["install", "-g", APK], timeout=90, check=False)
            if "Success" not in out:
                self.log(f"phone overlay install failed: {out.strip()[:200]}")
                return False
            self.state["overlay_apk"] = stamp
            _save(self.state)
        self.sh(f"appops set {OVERLAY} SYSTEM_ALERT_WINDOW allow; "
                f"pm grant {OVERLAY} android.permission.POST_NOTIFICATIONS", check=False)
        self.fx_ready = True
        return True

    def fx(self, op, **extras):
        """Shell prefix that tells the overlay what's about to happen ('' if it's off)."""
        if not self.overlay_on():
            return ""
        args = []
        for k, v in extras.items():
            if v is None:
                continue
            args += ["--ei" if isinstance(v, int) else "--es", k,
                     str(v) if isinstance(v, int) else shlex.quote(str(v))]
        self.fx_until = time.time() + 7
        return (f"cmd activity start-foreground-service -n {OVERLAY}/.OverlayService "
                f"-a {op} {' '.join(args)} >/dev/null 2>&1; ")

    def check_stop(self):
        """True once if the user pressed Stop in the phone's notification."""
        if not self.fx_ready:
            return False
        out = self.sh(f"stat -c %Y {STOP_FILE} 2>/dev/null", check=False).strip()
        seen, self.stop_seen = self.stop_seen, out
        return seen is not None and out != seen and out != ""

    # ---- looking -----------------------------------------------------------------
    def screen_size(self):
        if not self.size:
            out = self.sh("wm size")
            m = re.findall(r"(\d+)x(\d+)", out)
            if not m:
                raise PhoneError("couldn't read the screen size")
            w, h = map(int, m[-1])  # override size if one is set
            self.size = (w, h)
        return self.size

    def capture(self):
        from PIL import Image
        cmd = "screencap -p"
        if self.fx_ready and time.time() < self.fx_until:
            # keep Claude's own glow and cursor out of what it looks at
            cmd = self.fx("peek") + "sleep 0.06; screencap -p; " + self.fx("unpeek")
        data = self.sh(cmd, binary=True, timeout=25)
        if not data.startswith(b"\x89PNG"):
            raise PhoneError("screenshot failed (the phone may be locked or showing a secure "
                             "screen)")
        img = Image.open(io.BytesIO(data)).convert("RGB")
        self.size = img.size  # follows rotation
        return img

    def _encode(self, img, edge):
        from PIL import Image
        w, h = img.size
        sc = min(1.0, edge / max(w, h))
        if sc < 1:
            img = img.resize((round(w * sc), round(h * sc)), Image.LANCZOS)
        self.scale = 1 / sc
        buf = io.BytesIO()
        img.save(buf, "JPEG", quality=80)
        return buf.getvalue(), img.size

    def screenshot(self, detail="normal"):
        img = self.capture()
        edge = {"low": 900, "normal": 1280, "high": 1800}.get(detail, 1280)
        data, size = self._encode(img, edge)
        return data, {"image": list(size), "screen": list(self.size),
                      "foreground": self.foreground(), "hint": "tap x,y in this image's pixels"}

    def dump(self):
        out = self.sh("uiautomator dump /dev/tty", timeout=25, check=False)
        i, j = out.find("<?xml"), out.rfind("</hierarchy>")
        if i < 0 or j < 0:
            if "idle state" in out:
                raise PhoneError("The screen is animating (video or live content), so the UI "
                                 "tree isn't available. Use a screenshot instead.")
            raise PhoneError(out.strip()[:200] or "UI dump failed")
        return ET.fromstring(out[i:j + len("</hierarchy>")])

    def elements(self, root):
        els = []
        for n in root.iter("node"):
            a = n.attrib
            m = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", a.get("bounds", ""))
            if not m:
                continue
            x0, y0, x1, y1 = map(int, m.groups())
            if x1 - x0 < 4 or y1 - y0 < 4:
                continue
            text = (a.get("text") or "").strip()
            desc = (a.get("content-desc") or "").strip()
            cls = a.get("class", "").rsplit(".", 1)[-1]
            act = a.get("clickable") == "true" or a.get("long-clickable") == "true" or \
                a.get("checkable") == "true" or a.get("scrollable") == "true" or \
                "EditText" in cls
            if not (text or desc or act):
                continue
            rid = a.get("resource-id", "").rsplit("/", 1)[-1]
            els.append({"box": (x0, y0, x1, y1), "text": text, "desc": desc, "cls": cls,
                        "id": rid, "click": a.get("clickable") == "true",
                        "scroll": a.get("scrollable") == "true", "edit": "EditText" in cls,
                        "checked": a.get("checked") == "true" if a.get("checkable") == "true"
                        else None, "selected": a.get("selected") == "true",
                        "focused": a.get("focused") == "true",
                        "enabled": a.get("enabled") != "false"})
        # A label inside a clickable row: keep one entry, named by the label.
        keep = []
        for e in els:
            dup = next((k for k in keep if k["box"] == e["box"]), None)
            if dup:
                dup["text"] = dup["text"] or e["text"]
                dup["desc"] = dup["desc"] or e["desc"]
                dup["click"] = dup["click"] or e["click"]
                continue
            keep.append(e)
        return keep

    def see(self, detail="normal", interactive_only=False):
        """Screenshot with every element numbered, plus the list. Refs work with tap."""
        from PIL import ImageDraw, ImageFont
        img = self.capture()
        try:
            els = self.elements(self.dump())
        except PhoneError as e:
            els, note = [], f" ({e})"
        else:
            note = ""
        if interactive_only:
            els = [e for e in els if e["click"] or e["edit"] or e["scroll"]
                   or e["checked"] is not None]
        edge = {"low": 900, "normal": 1280, "high": 1800}.get(detail, 1280)
        sc = min(1.0, edge / max(img.size))
        self.marks, legend = {}, []
        draw = ImageDraw.Draw(img, "RGBA")
        try:
            font = ImageFont.truetype("DejaVuSans-Bold.ttf", max(14, round(13 / sc)))
        except Exception:
            font = None
        for n, e in enumerate(els[:150], 1):
            ref = f"p{n}"
            x0, y0, x1, y1 = e["box"]
            self.marks[ref] = ((x0 + x1) // 2, (y0 + y1) // 2)
            draw.rectangle([x0, y0, x1, y1], outline=(217, 119, 87, 210), width=max(2, round(1 / sc)))
            tw = draw.textlength(ref, font=font) if font else 7 * len(ref)
            th = (font.size if font else 11) + 4
            draw.rectangle([x0, max(0, y0 - th), x0 + tw + 6, max(th, y0)], fill=(217, 119, 87, 235))
            draw.text((x0 + 3, max(0, y0 - th) + 1), ref, fill=(255, 255, 255, 255), font=font)
            kind = "field" if e["edit"] else "scroll" if e["scroll"] and not e["click"] else \
                e["cls"] if e["cls"] not in ("View", "ViewGroup", "FrameLayout", "LinearLayout") \
                else ("button" if e["click"] else "text")
            label = e["text"] or e["desc"] or e["id"] or ""
            flags = [f for f, on in (("checked", e["checked"]), ("selected", e["selected"]),
                                     ("focused", e["focused"]), ("disabled", not e["enabled"]))
                     if on]
            extra = f' "{e["desc"][:50]}"' if e["text"] and e["desc"] else ""
            legend.append(f'[{ref}] {kind} "{label[:80]}"{extra}'
                          + (f" ({', '.join(flags)})" if flags else ""))
        data, size = self._encode(img, edge)
        head = (f"Phone screen, {self.foreground()}. {len(self.marks)} elements{note}. "
                f"tap ref=… to press one, or tap x,y in this image's pixels.")
        return data, head + "\n" + "\n".join(legend)

    def foreground(self):
        out = self.sh("dumpsys activity activities | grep -m1 -E 'mResumedActivity|topResumedActivity'"
                      " ; dumpsys window | grep -m1 mCurrentFocus", check=False)
        m = re.search(r"([a-zA-Z0-9_.]+)/([a-zA-Z0-9_.$]+)", out)
        return m.group(1) if m else "unknown app"

    def locked(self):
        out = self.sh("dumpsys window | grep -E 'mDreamingLockscreen|isStatusBarKeyguard|"
                      "mShowingLockscreen|KeyguardShowing'", check=False)
        return bool(re.search(r"(mDreamingLockscreen|mShowingLockscreen|isStatusBarKeyguard|"
                              r"KeyguardShowing)=true", out))

    def awake(self):
        out = self.sh("dumpsys power | grep -m1 -E 'mWakefulness='", check=False)
        return "Awake" in out

    # ---- doing -------------------------------------------------------------------
    def point(self, x=None, y=None, ref=None):
        if ref:
            if ref not in self.marks:
                raise PhoneError(f"{ref} isn't on the last phone see; call see again")
            return self.marks[ref]
        if x is None or y is None:
            raise PhoneError("give x,y (in the last phone image's pixels) or a ref")
        return round(x * self.scale), round(y * self.scale)

    def guard(self, approve):
        """Taps and typing in banking, password and settings apps need their own yes."""
        pkg = self.foreground()
        if SENSITIVE.search(pkg):
            approve(f"phone:{pkg}")
        return pkg

    def _lead(self, fx, wait):
        """Overlay command, then a beat so the cursor lands as the touch happens."""
        return fx + (f"sleep {wait}; " if fx else "")

    def tap(self, x=None, y=None, ref=None):
        px, py = self.point(x, y, ref)
        self.sh(self._lead(self.fx("tap", x=px, y=py, label="Tap"), 0.24) + f"input tap {px} {py}")
        return px, py

    def long_press(self, x=None, y=None, ref=None, ms=700):
        px, py = self.point(x, y, ref)
        self.sh(self._lead(self.fx("tap", x=px, y=py, label="Hold", ms=int(ms)), 0.24)
                + f"input swipe {px} {py} {px} {py} {int(ms)}")
        return px, py

    def double_tap(self, x=None, y=None, ref=None):
        px, py = self.point(x, y, ref)
        self.sh(self._lead(self.fx("tap", x=px, y=py, label="Double tap"), 0.24)
                + f"input tap {px} {py}; input tap {px} {py}")
        return px, py

    def _swipe(self, a, b, ms, label):
        self.sh(self._lead(self.fx("swipe", x=a[0], y=a[1], x2=b[0], y2=b[1], ms=int(ms),
                                   label=label), 0.17)
                + f"input swipe {a[0]} {a[1]} {b[0]} {b[1]} {int(ms)}")

    def swipe(self, x, y, x2, y2, ms=300):
        self._swipe(self.point(x, y), self.point(x2, y2), ms, "Swipe")

    def scroll(self, direction="down", amount=1.0, x=None, y=None, ref=None):
        w, h = self.screen_size()
        if self.size:
            w, h = self.size
        cx, cy = self.point(x, y, ref) if (ref or x is not None) else (w // 2, h // 2)
        d = min(0.8, 0.35 * float(amount or 1))
        dx, dy = {"down": (0, -d * h), "up": (0, d * h), "left": (d * w, 0),
                  "right": (-d * w, 0)}[direction]
        x0 = max(5, min(w - 5, cx - dx / 2)); y0 = max(5, min(h - 5, cy - dy / 2))
        x1 = max(5, min(w - 5, cx + dx / 2)); y1 = max(5, min(h - 5, cy + dy / 2))
        self._swipe((int(x0), int(y0)), (int(x1), int(y1)), 350, "Scroll")

    def type(self, text, submit=False):
        if not text and not submit:
            return
        lead = self.fx("show", label="Typing")
        if lead:
            self.sh(lead, check=False)
        lines = text.split("\n")
        for i, line in enumerate(lines):
            if line:
                if all(32 <= ord(c) < 127 for c in line):
                    # input text reads %s as a space
                    esc = line.replace(" ", "%s")
                    for k in range(0, len(esc), 400):
                        self.sh("input text " + shlex.quote(esc[k:k + 400]))
                else:
                    self._type_unicode(line)
            if i < len(lines) - 1:
                self.sh("input keyevent KEYCODE_ENTER")
        if submit:
            self.sh("input keyevent KEYCODE_ENTER")

    def _type_unicode(self, text):
        if "com.android.adbkeyboard" in self.sh("pm list packages com.android.adbkeyboard",
                                                check=False):
            b64 = base64.b64encode(text.encode()).decode()
            prev = self.sh("settings get secure default_input_method", check=False).strip()
            self.sh("ime set com.android.adbkeyboard/.AdbIME", check=False)
            self.sh(f"am broadcast -a ADB_INPUT_B64 --es msg {b64}")
            if prev and "adbkeyboard" not in prev:
                time.sleep(0.2)
                self.sh(f"ime set {shlex.quote(prev)}", check=False)
            return
        raise PhoneError("adb can only type plain ASCII. For emoji or accented letters, "
                         "install ADBKeyboard on the phone, or tap them on the keyboard.")

    def key(self, name):
        n = str(name).strip().lower().replace(" ", "_")
        if n in ("notifications", "notification_shade"):
            return self.sh("cmd statusbar expand-notifications")
        if n in ("quick_settings",):
            return self.sh("cmd statusbar expand-settings")
        if n in ("collapse", "close_shade"):
            return self.sh("cmd statusbar collapse")
        code = KEYS.get(n) or (name if str(name).upper().startswith("KEYCODE_") or
                               str(name).isdigit() else f"KEYCODE_{str(name).upper()}")
        label = n.replace("_", " ").capitalize() if n in KEYS else "Key"
        self.sh(self.fx("show", label=label) + f"input keyevent {code}")

    def wake(self):
        self.sh("input keyevent KEYCODE_WAKEUP")
        if self.locked():
            # Swipe up past the lock screen; a PIN or fingerprint is the user's to enter.
            w, h = self.screen_size()
            self.sh(f"input swipe {w // 2} {int(h * 0.85)} {w // 2} {int(h * 0.3)} 250")
            time.sleep(0.4)
            if self.locked():
                return "The phone is awake but locked. Ask the user to unlock it."
        return "Awake and unlocked."

    def apps(self, query=None):
        out = self.sh("cmd package query-activities --brief -a android.intent.action.MAIN "
                      "-c android.intent.category.LAUNCHER", check=False)
        pkgs = sorted({l.strip().split("/")[0] for l in out.splitlines() if "/" in l})
        if not pkgs:
            out = self.sh("pm list packages -3")
            pkgs = sorted(l.split(":", 1)[1].strip() for l in out.splitlines() if ":" in l)
        if query:
            q = query.lower().replace(" ", "")
            pkgs = [p for p in pkgs if q in p.lower()]
        return pkgs

    def open_app(self, name):
        if re.fullmatch(r"[a-zA-Z0-9_]+(\.[a-zA-Z0-9_]+)+", name or ""):
            pkg = name
        else:
            q = (name or "").lower().strip()
            want = ALIASES.get(q, q).replace(" ", "")
            pkgs = self.apps()
            exact = [p for p in pkgs if p == want]
            hits = exact or [p for p in pkgs if want in p.lower()] or \
                [p for p in pkgs if any(w and w in p.lower() for w in q.split())]
            if not hits:
                raise PhoneError(f"No app matching '{name}'. phone apps lists what's installed.")
            hits.sort(key=lambda p: (not p.endswith("." + want), len(p)))
            pkg = hits[0]
        out = self.sh(self.fx("show", label="Opening")
                      + f"monkey -p {shlex.quote(pkg)} -c android.intent.category.LAUNCHER 1",
                      check=False)
        if "No activities found" in out or "not found" in out.lower():
            raise PhoneError(f"{pkg} has nothing to open")
        return pkg

    def open_url(self, url):
        self.sh(self.fx("show", label="Opening")
                + f"am start -a android.intent.action.VIEW -d {shlex.quote(url)}")

    def notifications(self):
        out = self.sh("dumpsys notification --noredact", timeout=25, check=False)
        items, cur = [], None
        for line in out.splitlines():
            s = line.strip()
            m = re.match(r"NotificationRecord\(.*?pkg=(\S+)", s)
            if m:
                cur = {"app": m.group(1)}
                items.append(cur)
                continue
            if cur is None:
                continue
            for key, field in (("android.title=", "title"), ("android.text=", "text"),
                               ("android.bigText=", "big")):
                if s.startswith(key):
                    v = re.sub(r"^\w+ \((.*)\)$", r"\1", s[len(key):]).strip()
                    if v and v != "null":
                        cur[field] = v[:300]
        seen, res = set(), []
        for it in items:
            if "title" not in it and "text" not in it:
                continue
            k = (it["app"], it.get("title"), it.get("text"))
            if k in seen:
                continue
            seen.add(k)
            body = it.get("big") or it.get("text") or ""
            res.append(f'{it["app"]}: {it.get("title", "")} {("- " + body) if body else ""}'.strip())
        return res

    def status(self):
        bat = self.sh("dumpsys battery", check=False)
        lvl = re.search(r"level: (\d+)", bat)
        chg = re.search(r"(AC|USB|Wireless) powered: true", bat)
        return {"device": self.describe(), "battery": f"{lvl.group(1)}%" if lvl else "?",
                "charging": bool(chg), "awake": self.awake(), "locked": self.locked(),
                "foreground": self.foreground(), "screen": list(self.screen_size())}
