import fcntl
import json
import os
import re
import shutil
import subprocess
import threading
import time

CONFIG_DIR = os.path.join(os.environ.get("XDG_CONFIG_HOME") or
                          os.path.expanduser("~/.config"), "sudoclaude")
CONFIG_PATH = os.path.join(CONFIG_DIR, "config.json")
RUNTIME = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
ABORT_FILE = os.path.join(RUNTIME, "sudoclaude.abort")
LOCK_FILE = os.path.join(RUNTIME, "sudoclaude.lock")

DEFAULTS = {
    "approvals": "smart",           # smart | strict | off
    "session_minutes": 60,
    "always_allow": [],
    "denied": [],
    "sensitive": [],                # extra window classes that should ask first
    "tier_overrides": {},
    "mask_unapproved": True,
    "esc_to_stop": True,
    "notifications": True,
    "overlay": True,
    "idle_seconds": 25,
}

SENSITIVE = r"^(bitwarden|keepassxc|org\.keepassxc\.keepassxc|1password|proton-pass|" \
    r"proton\.pass|enpass|seahorse|org\.gnome\.seahorse.*|kwalletmanager.*|" \
    r"octopi|pamac.*|bauh|gnome-software|org\.gnome\.software|plasma-discover|" \
    r"org\.kde\.discover|garuda-.*|timeshift.*|gparted|org\.gnome\.disks|" \
    r"gnome-disks|partitionmanager|org\.kde\.partitionmanager|" \
    r"systemsettings|org\.kde\.systemsettings|gnome-control-center|" \
    r"__clipboard__)$"

VIEW_ONLY = r"^(firefox|zen|zen-.*|app\.zen_browser\.zen|chromium|google-chrome.*|brave.*|" \
    r"vivaldi.*|opera|microsoft-edge.*|librewolf|floorp|firedragon|falkon|" \
    r"org\.gnome\.epiphany|thorium.*|waterfox|mullvad.*|torbrowser|tor browser|" \
    r"tradingview|thinkorswim|webull|robinhood|ibkr|tws)$"
CLICK_ONLY = r"^(kitty|foot|footclient|alacritty|org\.wezfurlong\.wezterm|wezterm|" \
    r"konsole|org\.kde\.konsole|gnome-terminal.*|org\.gnome\.terminal|" \
    r"org\.gnome\.console|kgx|xterm|urxvt|st|st-256color|dev\.warp\.warp|warp|" \
    r"com\.mitchellh\.ghostty|ghostty|tilix|terminator|ptyxis|org\.gnome\.ptyxis|" \
    r"blackbox|code|code-oss|code-url-handler|vscodium|codium|cursor|zed|dev\.zed\.zed|" \
    r"jetbrains-.*|eclipse|android-studio|neovide|lapce|helix)$"
SENTINELS = [
    (CLICK_ONLY, "Equivalent to shell access (terminal / IDE)"),
    (r"^(org\.gnome\.nautilus|nautilus|dolphin|org\.kde\.dolphin|thunar|nemo|pcmanfm.*|"
     r"caja|yazi|spacefm)$", "Can read or write any file (file manager)"),
    (r"^(gnome-control-center|systemsettings|org\.kde\.systemsettings|"
     r"nwg-look|garuda-settings-manager|qt5ct|qt6ct|octopi|pamac.*|bauh)$",
     "Can change system settings / install software"),
    (r"^(bitwarden|keepassxc|.*keepassxc|1password|proton-pass|proton\.pass|enpass|"
     r"seahorse|.*seahorse.*|kwalletmanager.*)$", "Password manager"),
    (r"^(timeshift.*|gparted|.*disks|partitionmanager|.*partitionmanager)$",
     "Can modify disks and partitions"),
    (r"^(__clipboard__)$", "Clipboard often holds passwords and private text"),
    (r"^(__shell__)$", "Desktop shell: bar, launcher, notifications, overview"),
    (r"^(__launch__)$", "Can run any command (equivalent to shell access)"),
]
HARD_BLOCK = r"^(claude|claude-desktop|com\.anthropic\.claude.*|zenity|org\.kde\.kdialog|" \
    r"kdialog|hyprpolkitagent|polkit-.*|org\.kde\.polkit.*|lxpolkit|" \
    r"pinentry.*|gcr-prompter|org\.gnome\.keyring.*)$"

PRETTY = {"__shell__": "Desktop shell (bar, launcher, overview)",
          "__launch__": "Run commands / launch programs",
          "__clipboard__": "Read your clipboard"}


def _norm(app):
    return (app or "").strip().lower()


class Policy:
    def __init__(self, comp=None):
        self.comp = comp
        self.cfg = dict(DEFAULTS)
        self._load()
        self.session = {}            # app -> expiry ts
        self.denied_session = {}     # app -> expiry ts (denied this session)
        self.active = False
        self.last_action = 0.0
        self.activated_at = 0.0
        self.lock_fd = None
        self.aborted_at = 0.0
        self.own_esc = []            # timestamps of Esc presses we injected
        self.overlay = None
        self.on_activate = []
        self.on_deactivate = []
        self._lock = threading.RLock()
        self._idle_thread = threading.Thread(target=self._idle_loop, daemon=True)
        self._idle_thread.start()

    # ---- config ---------------------------------------------------------------
    def _load(self):
        try:
            self._mtime = os.path.getmtime(CONFIG_PATH)
            with open(CONFIG_PATH) as f:
                self.cfg.update(json.load(f))
        except FileNotFoundError:
            self._save()
        except Exception:
            pass

    def _refresh(self):
        try:
            if os.path.getmtime(CONFIG_PATH) != getattr(self, "_mtime", None):
                self._load()
        except OSError:
            pass

    def _save(self, add_always=(), remove_always=()):
        os.makedirs(CONFIG_DIR, exist_ok=True)
        try:
            with open(CONFIG_PATH) as f:
                disk = json.load(f)
        except Exception:
            disk = {}
        merged = [_norm(x) for x in disk.get("always_allow", self.cfg.get("always_allow", []))]
        for a in add_always:
            if _norm(a) not in merged:
                merged.append(_norm(a))
        merged = [x for x in merged if x not in {_norm(r) for r in remove_always}]
        self.cfg.update({k: v for k, v in disk.items() if k != "always_allow"})
        self.cfg["always_allow"] = merged
        tmp = CONFIG_PATH + f".tmp{os.getpid()}"
        with open(tmp, "w") as f:
            json.dump(self.cfg, f, indent=2)
        os.replace(tmp, CONFIG_PATH)
        self._mtime = os.path.getmtime(CONFIG_PATH)

    # ---- classification -------------------------------------------------------
    def tier(self, app):
        a = _norm(app)
        ov = {_norm(k): v for k, v in self.cfg.get("tier_overrides", {}).items()}
        if a in ov:
            return ov[a]
        if self.cfg.get("approvals") != "strict" and self.cfg.get("approvals") != "prompt":
            return "full"
        if re.match(VIEW_ONLY, a):
            return "view"
        if re.match(CLICK_ONLY, a):
            return "click"
        return "full"

    def warning(self, app):
        a = _norm(app)
        for pat, msg in SENTINELS:
            if re.match(pat, a):
                return msg
        return None

    def hard_blocked(self, app):
        return bool(re.match(HARD_BLOCK, _norm(app)))

    def is_sensitive(self, app):
        a = _norm(app)
        return bool(re.match(SENSITIVE, a)) or a in {_norm(x) for x in
                                                     self.cfg.get("sensitive", [])}

    def is_denied(self, app):
        a = _norm(app)
        return a in {_norm(x) for x in self.cfg.get("denied", [])} or \
            self.denied_session.get(a, 0) > time.time()

    def is_approved(self, app):
        self._refresh()
        if self.hard_blocked(app):
            return False
        mode = self.cfg.get("approvals")
        if mode == "off":
            return not self.is_denied(app)
        a = _norm(app)
        if self.is_denied(app):
            return False
        if mode not in ("strict", "prompt") and not self.is_sensitive(app):
            return True
        if a in {_norm(x) for x in self.cfg.get("always_allow", [])}:
            return True
        return self.session.get(a, 0) > time.time()

    # ---- checks ---------------------------------------------------------------
    def require(self, app, kind, title=None):
        """kind: 'view' | 'click' | 'type'. Prompts if needed, raises if not allowed."""
        app = app or "__shell__"
        label = PRETTY.get(app, app)
        self.last_action = time.time()
        self._acquire_lock()
        if self.hard_blocked(app):
            raise PermissionError(
                f"{label} can never be controlled by computer use (it is Claude itself, "
                f"a permission dialog, or an authentication prompt). Ask the user to do "
                f"this step themselves.")
        if self.is_denied(app):
            raise PermissionError(f"{label} is denied for computer use. Ask the user.")
        if not self.is_approved(app):
            res = self.prompt([app], reason=title)
            if not res.get(app):
                raise PermissionError(f"User denied access to {label}.")
        t = self.tier(app)
        if kind == "type" and t != "full":
            raise PermissionError(
                f"{label} is {'view-only' if t == 'view' else 'click-only'} for computer "
                f"use, so typing and keyboard shortcuts are blocked. " +
                ("Use the browser tools (Claude in Chrome / built-in browser) instead."
                 if t == "view" else "Use the shell/Bash tool or edit files directly instead."))
        if kind == "click" and t == "view":
            raise PermissionError(
                f"{label} is view-only for computer use. Use the browser tools "
                f"(Claude in Chrome / built-in browser) for web work instead.")

    # ---- prompting --------------------------------------------------------------
    def prompt(self, apps, reason=None):
        """Show one approval dialog for several apps. Returns {app: bool}."""
        apps = [a for a in dict.fromkeys(apps) if not self.is_approved(a)]
        if not apps:
            return {}
        if self.cfg.get("approvals") == "off":
            return {a: not self.is_denied(a) for a in apps}
        blocked = [a for a in apps if self.hard_blocked(a) or self.is_denied(a)]
        ask = [a for a in apps if a not in blocked]
        result = {a: False for a in blocked}
        if not ask:
            return result
        lines = []
        for a in ask:
            t = self.tier(a)
            tier_s = {"view": "view only", "click": "click only", "full": "full control"}[t]
            w = self.warning(a)
            strict = self.cfg.get("approvals") in ("strict", "prompt")
            lines.append(f"• {PRETTY.get(a, a)}" + (f"  ({tier_s})" if strict else "") +
                         (f"\n   ⚠ {w}" if w else ""))
        body = "Claude wants to use:\n\n" + "\n".join(lines)
        if reason:
            body += f"\n\nFor: {reason[:160]}"
        choice = show_dialog("Allow Claude to use these apps?", body)
        now = time.time()
        for a in ask:
            n = _norm(a)
            if choice == "always":
                result[a] = True
            elif choice == "session":
                self.session[n] = now + 60 * float(self.cfg.get("session_minutes", 60))
                result[a] = True
            else:
                self.denied_session[n] = now + 120
                result[a] = False
        if choice == "always":
            self._save(add_always=ask)
        return result

    def alias(self, approved_app, other):
        a, b = _norm(approved_app), _norm(other)
        if not b or a == b:
            return
        if a in self.session:
            self.session[b] = self.session[a]
        elif a in {_norm(x) for x in self.cfg.get("always_allow", [])}:
            self.session[b] = time.time() + 60 * float(self.cfg.get("session_minutes", 60))

    def status(self):
        now = time.time()
        return {"mode": self.cfg.get("approvals"),
                "session": {k: f"{int((v - now) / 60)} min left"
                            for k, v in self.session.items() if v > now},
                "always_allow": self.cfg.get("always_allow", []),
                "denied": self.cfg.get("denied", []),
                "tier_overrides": self.cfg.get("tier_overrides", {}),
                "active": self.active, "config": CONFIG_PATH}

    def touch_soft(self):
        self.last_action = time.time()

    def abort_now(self):
        self.aborted_at = time.time()
        self.deactivate(stopped=True)

    def forget(self, app=None):
        if app is None:
            self.session.clear()
            self.denied_session.clear()
            return
        n = _norm(app)
        self.session.pop(n, None)
        self.denied_session.pop(n, None)
        self._save(remove_always=[n])

    # ---- activity / lock / esc ----------------------------------------------------
    def check_abort(self):
        try:
            m = os.stat(ABORT_FILE).st_mtime
        except FileNotFoundError:
            return
        if m <= self.activated_at:
            return
        if any(abs(m - t) < 0.6 for t in self.own_esc):
            return
        if time.time() - m < 20:
            self.aborted_at = m
            self.deactivate(stopped=True)
            raise InterruptedError(
                "The user stopped computer use. Stop now and ask them how they want to "
                "continue; do not retry.")

    def touch(self):
        with self._lock:
            if self.aborted_at and time.time() - self.aborted_at < 20:
                raise InterruptedError(
                    "Computer use was stopped by the user (Stop button or Esc). Ask the "
                    "user before continuing.")
            self.check_abort()
            self.last_action = time.time()
            if not self.active:
                self._acquire_lock()
                self.activate()

    def mark_own_esc(self):
        self.own_esc = [t for t in self.own_esc if time.time() - t < 5] + [time.time()]

    def _acquire_lock(self):
        if self.lock_fd is not None:
            return
        fd = os.open(LOCK_FILE, os.O_RDWR | os.O_CREAT, 0o600)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            try:
                holder = os.read(fd, 200).decode().strip()
            except Exception:
                holder = "?"
            os.close(fd)
            raise RuntimeError(
                f"Computer use is in use by another Claude session ({holder}). "
                f"Wait for it to finish (it releases after ~{self.cfg['idle_seconds']}s "
                f"idle) or stop that session.")
        os.ftruncate(fd, 0)
        os.write(fd, f"pid {os.getpid()}".encode())
        self.lock_fd = fd

    def _release_lock(self):
        if self.lock_fd is not None:
            try:
                fcntl.flock(self.lock_fd, fcntl.LOCK_UN)
                os.close(self.lock_fd)
            except OSError:
                pass
            self.lock_fd = None

    def activate(self):
        self.active = True
        self.activated_at = time.time()
        if self.cfg.get("esc_to_stop") and self.comp and self.comp.name == "hyprland":
            try:
                if not any(ABORT_FILE in (b.get("arg") or "")
                           for b in self.comp.j("binds")):
                    # bindn = non-consuming: Esc still reaches apps, and a crash
                    # can never leave Escape broken.
                    self.comp.raw(f"keyword bindn , Escape, exec, touch {ABORT_FILE}")
            except Exception:
                pass
        if self.cfg.get("notifications"):
            notify("Claude is using your computer", "Press Esc to stop")
        for cb in self.on_activate:
            try:
                cb()
            except Exception:
                pass

    def deactivate(self, stopped=False):
        with self._lock:
            if not self.active:
                return
            self.active = False
            self._unbind_esc()
            self._release_lock()
            if self.cfg.get("notifications"):
                notify("Claude stopped" if stopped else "Claude is done using your computer",
                       "Control returned to you" if stopped else "")
            for cb in self.on_deactivate:
                try:
                    cb(stopped)
                except Exception:
                    pass

    def _unbind_esc(self):
        if self.comp and self.comp.name == "hyprland":
            try:
                binds = self.comp.j("binds")
                users = [b for b in binds if b.get("key") == "Escape"
                         and not b.get("modmask") and ABORT_FILE not in (b.get("arg") or "")]
                # `unbind` would also drop the user's own plain-Escape binds; if
                # they have any, leave ours in place (it only touches a file).
                if not users:
                    self.comp.raw("keyword unbind , Escape")
            except Exception:
                pass

    def _idle_loop(self):
        while True:
            time.sleep(1.0)
            try:
                idle = time.time() - self.last_action > float(self.cfg.get("idle_seconds", 25))
                if self.active and idle:
                    self.deactivate()
                elif not self.active and idle and self.lock_fd is not None:
                    with self._lock:
                        self._release_lock()
                elif self.active:
                    try:
                        m = os.stat(ABORT_FILE).st_mtime
                        if m > self.activated_at and not any(
                                abs(m - t) < 0.6 for t in self.own_esc):
                            self.aborted_at = m
                            self.deactivate(stopped=True)
                    except FileNotFoundError:
                        pass
            except Exception:
                pass

    def cleanup(self):
        if self.active:
            self.deactivate()


# ---- helpers -------------------------------------------------------------------
def notify(title, body=""):
    ns = shutil.which("notify-send")
    if not ns:
        return
    try:
        subprocess.Popen([ns, "-a", "Claude", "-i", "dialog-information", "-t", "3500",
                          "-h", "string:x-canonical-private-synchronous:claude-cu",
                          title, body], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass


def show_dialog(title, body, timeout=120):
    """Returns 'session' | 'always' | 'deny'."""
    z = shutil.which("zenity")
    if z:
        r = subprocess.run([z, "--question", "--title", title, "--text", body,
                            "--no-markup", "--width", "460", "--icon-name", "dialog-warning",
                            "--ok-label", "Allow for session", "--cancel-label", "Deny",
                            "--extra-button", "Always allow", f"--timeout={timeout}"],
                           capture_output=True, text=True)
        if r.returncode == 0:
            return "session"
        if "Always allow" in r.stdout:
            return "always"
        return "deny"
    k = shutil.which("kdialog")
    if k:
        r = subprocess.run([k, "--title", title, "--yesnocancel", body,
                            "--yes-label", "Allow for session", "--no-label", "Always allow",
                            "--cancel-label", "Deny"], capture_output=True, text=True,
                           timeout=timeout)
        return {0: "session", 1: "always"}.get(r.returncode, "deny")
    ns = shutil.which("notify-send")
    if ns:
        try:
            r = subprocess.run([ns, "-a", "Claude", "-u", "critical", "-w",
                                "-A", "session=Allow for session", "-A", "always=Always allow",
                                "-A", "deny=Deny", title, body], capture_output=True,
                               text=True, timeout=timeout)
            out = r.stdout.strip()
            if out in ("session", "always"):
                return out
        except Exception:
            pass
        return "deny"
    return "deny"
