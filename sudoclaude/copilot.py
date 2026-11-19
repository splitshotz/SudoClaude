"""Sharing the desktop with the person while they keep working.

There's one pointer and one keyboard focus, so working "beside" someone means
borrowing them politely: wait for the hand to rest before taking the pointer,
put it back afterwards, and send keys to Claude's own window in the background
instead of wherever the person's focus happens to be.
"""

import threading
import time

PRESENT_S = 20.0
REST_S = 0.45
WAIT_MAX_S = 2.5
RESTORE_AFTER_S = 1.4


class Copilot:
    def __init__(self, desk):
        self.d = desk
        self.enabled = True
        self.ptr_set = None
        self.last_obs = None
        self.user_seen = 0.0
        self.lease = None
        self.claude_win = None
        self.claude_at = 0.0
        self.restored_at = 0.0
        self.claude_windows = set()
        self.timer = None

    @property
    def comp(self):
        return self.d.comp

    def _hypr(self):
        return self.comp is not None and self.comp.name == "hyprland"

    def observe(self):
        cur = self.d.cursor()
        ref = self.ptr_set or self.last_obs
        if cur and ref and abs(cur[0] - ref[0]) + abs(cur[1] - ref[1]) > 3:
            self.user_seen = time.time()
            self.ptr_set = None
            self.lease = None
        self.last_obs = tuple(cur) if cur else None
        return cur

    def user_present(self):
        return time.time() - self.user_seen < PRESENT_S

    def cancel_restore(self):
        if self.timer:
            self.timer.cancel()
            self.timer = None

    def before_pointer(self, target):
        """Called before Claude moves the pointer to `target` (a window dict or None)."""
        self.cancel_restore()
        cur = self.observe()
        if not (self.enabled and self._hypr()):
            return
        if not self.user_present():
            time.sleep(0.1)
            cur = self.observe()
            if not self.user_present():
                return
        still_since, last = time.time(), cur
        deadline = time.time() + WAIT_MAX_S
        while time.time() < deadline:
            time.sleep(0.08)
            c = self.d.cursor()
            if c and last and abs(c[0] - last[0]) + abs(c[1] - last[1]) > 2:
                last, still_since = c, time.time()
                self.user_seen = still_since
            elif time.time() - still_since >= REST_S:
                break
        if self.lease is None:
            try:
                active = self.comp.j("activewindow") or {}
            except Exception:
                active = {}
            addr = active.get("address")
            if addr and (target is None or target.get("id") != addr) and last:
                self.lease = {"pos": tuple(last), "win": addr}

    def after_pointer(self, lx, ly, target):
        self.ptr_set = (lx, ly)
        if target and target.get("id"):
            self.claude_win = target["id"]
            self.claude_at = time.time()

    def end_call(self):
        cur = self.d.cursor() if self.comp else None
        if cur and self.ptr_set is not None and self.d.held_buttons:
            self.ptr_set = tuple(cur)
        elif self.ptr_set is None:
            self.last_obs = tuple(cur) if cur else None
        if self.lease and not self.d.held_buttons:
            self.cancel_restore()
            self.timer = threading.Timer(RESTORE_AFTER_S, self.restore)
            self.timer.daemon = True
            self.timer.start()

    def restore(self):
        with self.d.lock:
            lease, self.lease = self.lease, None
            if not lease:
                return
            cur = self.d.cursor()
            if cur and self.ptr_set and abs(cur[0] - self.ptr_set[0]) + abs(cur[1] - self.ptr_set[1]) > 3:
                self.user_seen = time.time()
                return
            try:
                self.d.wl()
                self.comp.focus_window(lease["win"])
                self.d.ptr.move_to(*lease["pos"])
                self.d.sync()
                self.ptr_set = lease["pos"]
                self.restored_at = time.time()
            except Exception:
                pass

    def key_target(self):
        """Where keys should go when Claude didn't name a window: its own window,
        if focus was handed back to the person since Claude last touched it."""
        if not (self.enabled and self._hypr() and self.claude_win):
            return None
        if self.restored_at < self.claude_at or time.time() - self.claude_at > 120:
            return None
        try:
            active = (self.comp.j("activewindow") or {}).get("address")
            if active == self.claude_win:
                return None
            if not any(w["id"] == self.claude_win for w in self.comp.windows()):
                return None
        except Exception:
            return None
        return self.claude_win

    def pick_workspace(self):
        """Where a new window for Claude should go: beside the person normally, on a
        free workspace when they're in a game, video or anything fullscreen."""
        c = self.comp
        active = c.j("activewindow") or {}
        cur = (active.get("workspace") or {}).get("id")
        if not self.d.flow_mode(active):
            return str(cur) if cur and cur > 0 else None
        used = {w.get("id") for w in c.j("workspaces") if w.get("windows", 0) > 0}
        used |= {(m.get("activeWorkspace") or {}).get("id") for m in c.j("monitors")}
        base = cur if cur and cur > 0 else 1
        for i in list(range(base + 1, 11)) + list(range(1, base)):
            if i not in used:
                return str(i)
        return "special:claude"

    def _keep_focus(self, prev, new):
        """Some apps grab focus despite the rule (they fork, or ask to be activated).
        Hand it straight back."""
        time.sleep(0.15)
        try:
            if (self.comp.j("activewindow") or {}).get("address") in new:
                with self.d.lock:
                    pos = self.d.cursor()
                    self.comp.focus_window(prev)
                    if pos:
                        self.d.wl()
                        self.d.ptr.move_to(*pos)
                        self.d.sync()
                        self.ptr_set = tuple(pos)
        except Exception:
            pass

    def forget(self):
        self.claude_win = None

    def track_new(self, before_ids, background, timeout=8.0):
        try:
            prev = (self.comp.j("activewindow") or {}).get("address") if background else None
        except Exception:
            prev = None

        def run():
            end = time.time() + timeout
            while time.time() < end:
                time.sleep(0.25)
                try:
                    new = [w["id"] for w in self.comp.windows() if w["id"] not in before_ids]
                except Exception:
                    continue
                if new:
                    if prev:
                        self._keep_focus(prev, new)
                    self.claude_windows.update(new)
                    self.claude_win, self.claude_at = new[0], time.time()
                    if background:
                        self.restored_at = self.claude_at + 0.001
                    return
        threading.Thread(target=run, daemon=True).start()
