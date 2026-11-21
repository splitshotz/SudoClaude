"""Everything the settings app does to the system: finding the install, running
the installer and updates, reading and writing settings, and checking status.

Inside the Flatpak sandbox, commands that touch the host go through
`flatpak-spawn --host`; run from a source checkout they run directly."""

import json
import os
import re
import shlex
import shutil
import subprocess
import threading
import time
import urllib.request

from PySide6.QtCore import Property, QObject, QProcess, QTimer, Signal, Slot

APP_VERSION = "1.0.1"
REPO = "splitshotz/SudoClaude"
REPO_URL = f"https://github.com/{REPO}"
HOME = os.path.expanduser("~")
CONFIG = os.path.join(HOME, ".config", "sudoclaude", "config.json")
APP_PREFS = os.path.join(HOME, ".config", "sudoclaude", "app.json")
PILL_STATE = os.path.join(HOME, ".local", "state", "sudoclaude", "pill.json")
IN_FLATPAK = os.path.exists("/.flatpak-info")

# Settings shown in the app, grouped the way the Reset buttons work. Keys are
# paths into config.json; the value is the default SudoClaude uses when unset.
SECTIONS = {
    "appearance": {
        "overlay": True,
        "overlay_style": "hairline",
        "glass.frost": 5.0,
        "glass.lens": 1.0,
        "glass.tint": 0.12,
        "glass.appearance": "auto",
    },
    "voice": {
        "voice.enabled": True,
        "voice.name": "",
        "voice.tts": "chatterbox",
        "voice.tts_kokoro.voice": "af_heart",
        "voice.followup_seconds": 6.0,
        "voice.duck": 0.2,
        "voice.chime": True,
        "voice.wake_threshold": 0.55,
        "voice.voice_interrupt": False,
        "voice.pause_for_games": True,
        "voice.pause_on_low_memory": True,
        "voice.low_memory_gb": 4.0,
        "voice.model": "sonnet",
        "voice.deep_model": "opus",
    },
    "computer": {
        "approvals": "smart",
        "copilot": True,
        "notifications": True,
        "esc_to_stop": True,
        "mask_unapproved": True,
        "idle_seconds": 25,
        "session_minutes": 60,
    },
}
GUARD_KEYS = {"voice.pause_for_games", "voice.pause_on_low_memory", "voice.low_memory_gb"}
DEFAULTS = {k: v for sec in SECTIONS.values() for k, v in sec.items()}


def host(args):
    """argv that runs on the host, from inside or outside the sandbox. From the
    sandbox, the host command gets the user's usual PATH (Claude Code lives in
    ~/.local/bin) and the Hyprland/Wayland session it needs."""
    if not IN_FLATPAK:
        return list(args)
    env = [f"--env=PATH={HOME}/.local/bin:{HOME}/.cargo/bin:/usr/local/bin:/usr/bin:/bin"]
    for k in ("HYPRLAND_INSTANCE_SIGNATURE", "WAYLAND_DISPLAY", "XDG_RUNTIME_DIR", "DISPLAY",
              "XDG_CURRENT_DESKTOP", "XDG_SESSION_TYPE", "DBUS_SESSION_BUS_ADDRESS"):
        if os.environ.get(k):
            env.append(f"--env={k}={os.environ[k]}")
    return ["flatpak-spawn", "--host"] + env + list(args)


def run(args, timeout=20, shell=False):
    """Run a host command; returns (exit code, stdout)."""
    argv = host(["sh", "-c", args]) if shell else host(args)
    try:
        r = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
        return r.returncode, r.stdout.strip()
    except Exception as e:
        return 127, str(e)


def version_tuple(v):
    nums = re.findall(r"\d+", v or "")
    return tuple(int(n) for n in nums[:3]) + (0,) * (3 - len(nums[:3]))


def _get(d, path, default=None):
    for part in path.split("."):
        if not isinstance(d, dict) or part not in d:
            return default
        d = d[part]
    return d


def _set(d, path, value):
    parts = path.split(".")
    for part in parts[:-1]:
        d = d.setdefault(part, {})
        if not isinstance(d, dict):
            return
    d[parts[-1]] = value


def _del(d, path):
    parts = path.split(".")
    stack = []
    for part in parts[:-1]:
        if not isinstance(d, dict) or part not in d:
            return
        stack.append((d, part))
        d = d[part]
    if isinstance(d, dict):
        d.pop(parts[-1], None)
    for parent, key in reversed(stack):
        if parent[key] == {}:
            parent.pop(key)


def _read_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def _write_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    os.replace(tmp, path)


class Backend(QObject):
    changed = Signal()            # status / install state / versions
    configChanged = Signal()
    logLine = Signal(str)
    taskFinished = Signal(str, bool, str)   # task, ok, message
    toast = Signal(str)

    def __init__(self):
        super().__init__()
        self._prefs = _read_json(APP_PREFS)
        self._cfg = _read_json(CONFIG)
        self._status = {}
        self._checks = []
        self._latest = {}
        self._busy = ""
        self._log = []
        self._proc = None
        self._voice_restart = QTimer(self, singleShot=True, interval=1500)
        self._voice_restart.timeout.connect(self._restart_voice_now)
        self._name = ""
        threading.Thread(target=self._lookup_name, daemon=True).start()

    # ---- basics -----------------------------------------------------------------

    @Property(str, constant=True)
    def appVersion(self):
        return APP_VERSION

    @Property(str, constant=True)
    def repoUrl(self):
        return REPO_URL

    @Property(str, notify=changed)
    def repoPath(self):
        return self._prefs.get("repo") or os.path.join(HOME, "Projects", "SudoClaude")

    @Property(bool, notify=changed)
    def installed(self):
        return bool(self._status.get("installed"))

    @Property(str, notify=changed)
    def version(self):
        return self._status.get("version", "")

    @Property("QVariant", notify=changed)
    def status(self):
        return self._status

    @Property("QVariant", notify=changed)
    def checks(self):
        return self._checks

    @Property("QVariant", notify=changed)
    def latest(self):
        return self._latest

    @Property(bool, notify=changed)
    def updateAvailable(self):
        v = self._latest.get("version")
        return bool(v and self.version and version_tuple(v) > version_tuple(self.version))

    @Property(bool, notify=changed)
    def appUpdateAvailable(self):
        v = self._latest.get("version")
        return bool(v and version_tuple(v) > version_tuple(APP_VERSION))

    @Property(str, notify=changed)
    def busy(self):
        return self._busy

    @Property(str, notify=changed)
    def userName(self):
        return _get(self._cfg, "voice.name") or self._name

    @Property(str, notify=configChanged)
    def theme(self):
        return self._prefs.get("theme", "system")

    @Slot(str)
    def setTheme(self, t):
        self._prefs["theme"] = t
        _write_json(APP_PREFS, self._prefs)
        self.configChanged.emit()

    def _lookup_name(self):
        code, out = run(["getent", "passwd", os.environ.get("USER", "")], timeout=5)
        full = out.split(":")[4].split(",")[0].strip() if code == 0 and out.count(":") >= 4 else ""
        self._name = full.split()[0] if full else ""
        self.changed.emit()

    # ---- status -----------------------------------------------------------------

    @Slot()
    def refresh(self):
        threading.Thread(target=self._refresh, daemon=True).start()

    def _refresh(self):
        repo = self.repoPath
        st = {}
        try:
            with open(os.path.join(repo, "VERSION")) as f:
                st["version"] = f.read().strip()
        except OSError:
            st["version"] = ""
        st["repo"] = os.path.exists(os.path.join(repo, "bin", "sudoclaude"))
        code, _ = run(["claude", "mcp", "get", "sudoclaude"], timeout=15)
        st["claude_code"] = code == 0
        desk = _read_json(os.path.join(HOME, ".config", "Claude", "claude_desktop_config.json"))
        st["claude_desktop"] = "sudoclaude" in desk.get("mcpServers", {})
        st["installed"] = st["repo"] and (st["claude_code"] or st["claude_desktop"])
        code, _ = run(["pgrep", "-f", "overlay/overlay.qml"], timeout=5)
        st["overlay_running"] = code == 0
        st["quickshell"] = run(["sh", "-c", "command -v qs || command -v quickshell"])[0] == 0
        code, out = run(["systemctl", "--user", "is-active", "sudoclaude-voice"], timeout=5)
        st["voice_active"] = out.strip() == "active"
        st["voice_installed"] = os.path.exists(
            os.path.join(HOME, ".config", "systemd", "user", "sudoclaude-voice.service"))
        code, out = run(["python3", os.path.join(repo, "bin", "sudoclaude-guard"), "status"], timeout=5)
        st["voice_paused"] = out.strip()[len("paused: "):] if out.startswith("paused: ") else ""
        st["wake_trained"] = os.path.exists(
            os.path.join(HOME, ".local", "share", "sudoclaude", "models", "claude.onnx"))
        code, out = run("tail -n 400 \"${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/sudoclaude-voice.log\" "
                        "2>/dev/null", shell=True, timeout=5)
        acts = []
        for line in out.splitlines():
            m = re.match(r"(\d\d:\d\d):\d\d (ask|reply): (.*)", line)
            if m:
                text = m.group(3).strip().strip("'\"")
                text = re.sub(r"^\((typed|follow-up|interrupting)\)\s*", "", text)
                text = re.sub(r"\[(end|ignore)\]", "", text).strip()
                if text:
                    acts.append({"time": m.group(1), "who": "you" if m.group(2) == "ask" else "claude",
                                 "text": text[:160]})
        st["activity"] = acts[-6:]
        code, out = run("hyprctl binds -j 2>/dev/null", shell=True, timeout=5)
        binds = {}
        try:
            mods = {64: "Super", 1: "Shift", 4: "Ctrl", 8: "Alt"}
            for b in json.loads(out or "[]"):
                desc = b.get("description") or ""
                if desc in ("Claude: talk", "Claude: stop"):
                    m = b.get("modmask", 0)
                    names = [n for bit, n in mods.items() if m & bit]
                    binds[desc.split(": ")[1]] = "+".join(names + [b.get("key", "")])
        except ValueError:
            pass
        st["binds"] = binds
        st["hyprland"] = run(["sh", "-c", "command -v hyprctl"])[0] == 0
        self._status = st
        self.changed.emit()

    @Slot()
    def checkRequirements(self):
        threading.Thread(target=self._check_requirements, daemon=True).start()

    def _check_requirements(self):
        def has(cmd):
            return run(["sh", "-c", f"command -v {cmd}"], timeout=5)[0] == 0
        checks = []
        code, out = run(["sh", "-c", "echo $XDG_SESSION_TYPE; echo $HYPRLAND_INSTANCE_SIGNATURE;"
                         " hyprctl version -j 2>/dev/null | head -c 400"], timeout=5)
        hypr = has("hyprctl") and "\n" in out and out.split("\n")[1].strip() != ""
        checks.append({"id": "hyprland", "label": "Hyprland", "ok": hypr, "required": True,
                       "detail": "Running" if hypr else "SudoClaude drives your desktop through Hyprland"})
        arch = has("pacman")
        checks.append({"id": "pacman", "label": "Arch-based distro", "ok": arch, "required": False,
                       "detail": "Packages install automatically" if arch else
                       "No pacman, so the installer will list packages for you to install"})
        claude = has("claude")
        desktop = os.path.isdir(os.path.join(HOME, ".config", "Claude"))
        checks.append({"id": "claude", "label": "Claude Code or the Claude app", "ok": claude or desktop,
                       "required": True,
                       "detail": "Claude Code found" if claude else
                       "Claude desktop app found" if desktop else "Install Claude Code first"})
        checks.append({"id": "git", "label": "git", "ok": has("git"), "required": True,
                       "detail": "Used to download and update SudoClaude"})
        qs = has("qs") or has("quickshell")
        checks.append({"id": "quickshell", "label": "Quickshell", "ok": qs, "required": False,
                       "detail": "For the on-screen overlay and the glass pill" if not qs else "Found"})
        gpu = has("nvidia-smi")
        checks.append({"id": "gpu", "label": "NVIDIA GPU", "ok": gpu, "required": False,
                       "detail": "Natural voice runs on the GPU" if gpu else
                       "Voice will use the lighter CPU voice"})
        chromium = has("chromium") or has("google-chrome-stable")
        checks.append({"id": "chromium", "label": "Chromium", "ok": chromium, "required": False,
                       "detail": "Optional, for working inside browser tabs"})
        self._checks = checks
        self.changed.emit()

    # ---- settings ---------------------------------------------------------------

    @Slot(str, result="QVariant")
    def get(self, path):
        return _get(self._cfg, path, DEFAULTS.get(path))

    @Slot(str, "QVariant")
    def set(self, path, value):
        self._cfg = _read_json(CONFIG)
        if isinstance(value, float) and value.is_integer() and isinstance(DEFAULTS.get(path), int) \
                and not isinstance(DEFAULTS.get(path), bool):
            value = int(value)
        _set(self._cfg, path, value)
        _write_json(CONFIG, self._cfg)
        self.configChanged.emit()
        if path.startswith("voice.") and path not in GUARD_KEYS:
            self._voice_restart.start()

    @Slot(str)
    def resetSection(self, name):
        self._cfg = _read_json(CONFIG)
        for path in SECTIONS.get(name, {}):
            _del(self._cfg, path)
        _write_json(CONFIG, self._cfg)
        if name == "appearance":
            self.setPillPosition("bottom")
        self.configChanged.emit()
        if name == "voice":
            self._voice_restart.start()
        self.toast.emit("Back to defaults")

    @Slot(result=str)
    def pillPosition(self):
        return _read_json(PILL_STATE).get("at", "bottom")

    @Slot(str)
    def setPillPosition(self, at):
        _write_json(PILL_STATE, {"at": at})
        self.configChanged.emit()

    def _restart_voice_now(self):
        if self._status.get("voice_installed"):
            # Leave it off if the guard paused it for a game; otherwise restart,
            # which also starts it after it's been switched back on.
            code, _ = run('test -f "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/sudoclaude-voice-paused"',
                          timeout=5, shell=True)
            if code != 0:
                # try-restart: the voice runs on demand (Super+Space), so only
                # restart it if it's running; otherwise it picks changes up next start.
                run(["systemctl", "--user", "try-restart", "sudoclaude-voice"], timeout=10)
            self.toast.emit("Voice will use your changes")

    # ---- actions ----------------------------------------------------------------

    @Slot()
    def restartVoice(self):
        def go():
            run(["systemctl", "--user", "restart", "sudoclaude-voice"], timeout=10)
            self.toast.emit("Voice restarted")
            self._refresh()
        threading.Thread(target=go, daemon=True).start()

    @Slot()
    def restartOverlay(self):
        def go():
            run(["pkill", "-f", "overlay/overlay.qml"], timeout=5)
            time.sleep(0.5)
            self.toast.emit("Overlay restarted; it comes back the next time Claude needs it")
            self._refresh()
        threading.Thread(target=go, daemon=True).start()

    @Slot(str, str)
    def setKeybinds(self, talk, stop):
        self._stream("keybinds", [os.path.join(self.repoPath, "bin", "sudoclaude-keybind"),
                                  "--replace", talk, stop])

    @Slot("QVariant")
    def install(self, opts):
        opts = dict(opts or {})
        repo = self.repoPath
        flags = ["--yes"]
        flags.append("--ocr" if opts.get("ocr", True) else "--no-ocr")
        flags.append("--voice" if opts.get("voice") else "--no-voice")
        flags.append("--browser" if opts.get("browser") else "--no-browser")
        flags += ["--keybind", opts.get("talk") or "SUPER+Space",
                  opts.get("stop") or "SUPER+SHIFT+Escape"]
        script = (f"set -e; if [ ! -d {shlex.quote(repo)}/.git ]; then "
                  f"mkdir -p {shlex.quote(os.path.dirname(repo))}; "
                  f"git clone --depth 50 {REPO_URL}.git {shlex.quote(repo)}; fi; "
                  f"cd {shlex.quote(repo)}; ./install.sh {' '.join(shlex.quote(f) for f in flags)}")
        self._stream("install", ["sh", "-c", script])

    @Slot()
    def update(self):
        repo = shlex.quote(self.repoPath)
        units = os.path.join(HOME, ".config", "systemd", "user")
        script = (f"set -e; cd {repo}; git fetch --tags origin; git pull --ff-only; "
                  f"if [ -f {units}/sudoclaude-voice.service ]; then "
                  "for u in sudoclaude-voice.service sudoclaude-voice-guard.service; do "
                  f"sed \"s|%h/Projects/SudoClaude|$PWD|\" systemd/$u > {units}/$u; done; "
                  "systemctl --user daemon-reload; "
                  "systemctl --user enable --now sudoclaude-voice-guard.service || true; fi; "
                  "systemctl --user try-restart sudoclaude-voice sudoclaude-voice-guard || true; "
                  "pkill -f 'overlay/overlay.qml' || true; echo; echo \"Now on $(cat VERSION)\"")
        self._stream("update", ["sh", "-c", script])

    @Slot(bool)
    def uninstall(self, purge):
        args = [os.path.join(self.repoPath, "uninstall.sh")] + (["--purge"] if purge else [])
        self._stream("uninstall", args)

    @Slot()
    def doctor(self):
        req = ('{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}\n'
               '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"desktop",'
               '"arguments":{"action":"doctor"}}}\n')
        binp = shlex.quote(os.path.join(self.repoPath, "bin", "sudoclaude"))
        script = f"printf '%s' {shlex.quote(req)} | timeout 25 {binp} 2>/dev/null | tail -1"

        def go():
            code, out = run(["sh", "-c", script], timeout=30)
            try:
                text = json.loads(out)["result"]["content"][0]["text"]
                self.taskFinished.emit("doctor", True, text)
            except Exception:
                self.taskFinished.emit("doctor", False, out or "No answer from the server")
        threading.Thread(target=go, daemon=True).start()

    # ---- updates ----------------------------------------------------------------

    @Slot()
    def checkUpdates(self):
        threading.Thread(target=self._check_updates, daemon=True).start()

    def _check_updates(self):
        try:
            req = urllib.request.Request(f"https://api.github.com/repos/{REPO}/releases/latest",
                                         headers={"Accept": "application/vnd.github+json",
                                                  "User-Agent": "SudoClaude-settings"})
            with urllib.request.urlopen(req, timeout=10) as r:
                rel = json.load(r)
            bundle = next((a["browser_download_url"] for a in rel.get("assets", [])
                           if a.get("name", "").endswith(".flatpak")), "")
            self._latest = {"version": rel.get("tag_name", "").lstrip("v"),
                            "name": rel.get("name") or rel.get("tag_name", ""),
                            "notes": rel.get("body") or "", "url": rel.get("html_url", REPO_URL),
                            "bundle": bundle, "checked": time.strftime("%H:%M"), "error": ""}
        except Exception as e:
            self._latest = {**self._latest, "error": f"Couldn't check: {e}",
                            "checked": time.strftime("%H:%M")}
        self.changed.emit()

    @Slot()
    def updateApp(self):
        url = self._latest.get("bundle")
        if not url:
            self.taskFinished.emit("app-update", False, "This release has no app bundle.")
            return

        def go():
            self._set_busy("app-update")
            try:
                dest = os.path.join(HOME, "Downloads", os.path.basename(url))
                os.makedirs(os.path.dirname(dest), exist_ok=True)
                self.logLine.emit(f"Downloading {os.path.basename(url)}")
                urllib.request.urlretrieve(url, dest)
                self.logLine.emit("Installing")
                code, out = run(["flatpak", "install", "--user", "-y", "--bundle", dest], timeout=300)
                ok = code == 0
                self.taskFinished.emit("app-update", ok,
                                       "Installed. Close and reopen the app to use the new version."
                                       if ok else out[-400:])
            except Exception as e:
                self.taskFinished.emit("app-update", False, str(e))
            finally:
                self._set_busy("")
        threading.Thread(target=go, daemon=True).start()

    # ---- long-running commands ---------------------------------------------------

    def _set_busy(self, task):
        self._busy = task
        self.changed.emit()

    def _stream(self, task, argv):
        if self._proc:
            self.toast.emit("Something else is still running")
            return
        self._set_busy(task)
        self._log = []
        p = QProcess(self)
        argv = host(argv)
        env = p.processEnvironment()
        p.setProgram(argv[0])
        p.setArguments(argv[1:])
        p.setProcessChannelMode(QProcess.MergedChannels)
        buf = {"s": ""}

        def out():
            buf["s"] += bytes(p.readAll()).decode(errors="replace")
            buf["s"] = re.sub(r"\x1b\[[0-9;]*m", "", buf["s"])
            while "\n" in buf["s"] or "\r" in buf["s"]:
                line, _, buf["s"] = re.split(r"(\r?\n|\r)", buf["s"], maxsplit=1)
                if line.strip():
                    self._log.append(line)
                    self.logLine.emit(line)

        def done(code, _status):
            out()
            if buf["s"].strip():
                self.logLine.emit(buf["s"])
            self._proc = None
            self._set_busy("")
            self.taskFinished.emit(task, code == 0,
                                   "Done" if code == 0 else f"Stopped with exit code {code}")
            self._refresh()

        p.readyRead.connect(out)
        p.finished.connect(done)
        self._proc = p
        p.start()
        if not p.waitForStarted(5000):
            self._proc = None
            self._set_busy("")
            self.taskFinished.emit(task, False, f"Couldn't start {argv[0]}")
