import shutil
import subprocess

INTERACTIVE = {
    "push button", "toggle button", "check box", "radio button", "menu item",
    "check menu item", "radio menu item", "link", "entry", "password text", "text",
    "combo box", "list item", "page tab", "tree item", "slider", "spin button",
    "menu", "table cell", "icon", "button", "switch", "editbar", "terminal",
    "push button menu", "tab", "toggle", "scroll bar", "date editor", "search box",
}
CONTEXT = {"heading", "label", "static", "dialog", "alert", "notification", "status bar",
           "tool tip", "document web", "document frame", "page tab list", "menu bar",
           "tool bar", "panel", "frame", "window"}
ACTION_PREF = ["click", "press", "activate", "jump", "toggle", "open", "select",
               "expand or contract", "showmenu"]

_A = None


def atspi():
    global _A
    if _A is None:
        import gi
        gi.require_version("Atspi", "2.0")
        from gi.repository import Atspi
        Atspi.init()
        try:
            Atspi.set_timeout(1500, 15000)
        except Exception:
            pass
        _A = Atspi
    return _A


def available():
    try:
        atspi()
        return True
    except Exception:
        return False


def enable_toolkits():
    """Ask Qt / Chromium / Firefox to expose accessibility (like a screen reader)."""
    g = shutil.which("gdbus")
    if not g:
        return False
    ok = True
    for prop in ("IsEnabled", "ScreenReaderEnabled"):
        r = subprocess.run([g, "call", "--session", "--dest", "org.a11y.Bus",
                            "--object-path", "/org/a11y/bus", "--method",
                            "org.freedesktop.DBus.Properties.Set", "org.a11y.Status",
                            prop, "<true>"], capture_output=True, timeout=3)
        ok = ok and r.returncode == 0
    return ok


def _safe(f, default=None):
    try:
        return f()
    except Exception:
        return default


class Tree:
    def __init__(self):
        self.refs = {}
        self.n = 0

    # ---- locating apps/windows -------------------------------------------------
    def app_for(self, pid, app_name=None):
        A = atspi()
        desk = A.get_desktop(0)
        best = None
        for i in range(_safe(desk.get_child_count, 0)):
            a = _safe(lambda: desk.get_child_at_index(i))
            if a is None:
                continue
            if pid and _safe(a.get_process_id) == pid:
                return a
            nm = (_safe(a.get_name, "") or "").lower()
            if app_name and best is None and nm and (
                    nm in app_name.lower() or app_name.lower() in nm):
                best = a
        return best

    def apps(self):
        A = atspi()
        desk = A.get_desktop(0)
        out = []
        for i in range(_safe(desk.get_child_count, 0)):
            a = _safe(lambda: desk.get_child_at_index(i))
            if a is not None:
                out.append({"name": _safe(a.get_name, ""), "pid": _safe(a.get_process_id),
                            "windows": _safe(a.get_child_count, 0)})
        return out

    def frame_for(self, app, title=None):
        A = atspi()
        frames = []
        for i in range(_safe(app.get_child_count, 0)):
            f = _safe(lambda: app.get_child_at_index(i))
            if f is not None:
                frames.append(f)
        if not frames:
            return None
        if title:
            t = title.lower()
            for f in frames:
                nm = (_safe(f.get_name, "") or "").lower()
                if nm and (nm == t or nm in t or t in nm):
                    return f
        for f in frames:
            st = _safe(f.get_state_set)
            if st and st.contains(A.StateType.ACTIVE):
                return f
        return frames[0]

    # ---- walking ------------------------------------------------------------------
    def snapshot(self, frame, win, to_screen, interactive_only=True, max_nodes=500,
                 query=None, max_depth=60):
        """Return text lines describing the tree. `win` = window dict (logical
        geometry); `to_screen(lx, ly)` maps logical -> output coordinates."""
        A = atspi()
        self.refs = {}
        self.n = 0
        fx, fy = 0, 0
        fe = _safe(lambda: A.Component.get_extents(frame, A.CoordType.WINDOW))
        if fe is not None and 0 <= fe.x < 200 and 0 <= fe.y < 200:
            fx, fy = fe.x, fe.y   # CSD shadow margin
        lines = []
        q = (query or "").lower()

        def visit(node, depth):
            if self.n >= max_nodes or depth > max_depth:
                return
            st = _safe(node.get_state_set)
            if st is not None and depth > 0 and not st.contains(A.StateType.SHOWING) \
                    and not st.contains(A.StateType.VISIBLE):
                return
            role = _safe(node.get_role_name, "") or ""
            name = (_safe(node.get_name, "") or "").strip()
            keep = role in INTERACTIVE or (not interactive_only and (name or role in CONTEXT))
            if role in CONTEXT and name and role not in ("panel", "frame", "window"):
                keep = keep or not interactive_only or role in ("heading", "dialog", "alert")
            if q:
                desc = (_safe(node.get_description, "") or "")
                keep = q in name.lower() or q in desc.lower() or q in role
            if keep:
                e = _safe(lambda: A.Component.get_extents(node, A.CoordType.WINDOW))
                if e is not None and e.width > 0 and e.height > 0:
                    lx = win["x"] + (e.x - fx) + e.width / 2
                    ly = win["y"] + (e.y - fy) + e.height / 2
                    sx, sy = to_screen(lx, ly)
                    pos = f" @({sx},{sy})"
                    box = (win["x"] + e.x - fx, win["y"] + e.y - fy, e.width, e.height)
                else:
                    pos, box = "", None
                self.n += 1
                ref = f"e{self.n}"
                self.refs[ref] = (node, box)
                extra = []
                if st is not None:
                    for s, label in ((A.StateType.FOCUSED, "focused"),
                                     (A.StateType.CHECKED, "checked"),
                                     (A.StateType.SELECTED, "selected"),
                                     (A.StateType.EXPANDED, "expanded"),
                                     (A.StateType.PRESSED, "pressed")):
                        if st.contains(s):
                            extra.append(label)
                    if not st.contains(A.StateType.SENSITIVE) and role in INTERACTIVE:
                        extra.append("disabled")
                    if st.contains(A.StateType.EDITABLE) and role in (
                            "entry", "text", "password text", "terminal", "combo box"):
                        val = _safe(lambda: A.Text.get_text(node, 0, 120), "")
                        if role != "password text" and val:
                            extra.append(f'value="{val[:80]}"')
                if role in ("slider", "spin button", "scroll bar", "progress bar"):
                    v = _safe(lambda: A.Value.get_current_value(node))
                    if v is not None:
                        extra.append(f"value={round(v, 2)}")
                lines.append(f'{"  " * min(depth, 12)}[{ref}] {role} "{name[:80]}"{pos}'
                             + (" " + " ".join(extra) if extra else ""))
            for i in range(_safe(node.get_child_count, 0) or 0):
                if self.n >= max_nodes:
                    lines.append("  … (node limit reached; narrow with query=)")
                    return
                ch = _safe(lambda: node.get_child_at_index(i))
                if ch is not None:
                    visit(ch, depth + 1)

        visit(frame, 0)
        return lines

    # ---- actions ------------------------------------------------------------------
    def get(self, ref):
        if ref not in self.refs:
            raise ValueError(f"unknown element ref {ref!r}; call accessibility_tree again")
        return self.refs[ref]

    def act(self, ref, action, text=None, value=None):
        A = atspi()
        node, box = self.get(ref)
        if action in ("click", "press", "activate", "toggle", "expand", "default"):
            n = _safe(lambda: A.Action.get_n_actions(node), 0) or 0
            names = [(_safe(lambda: A.Action.get_action_name(node, i), "") or "").lower() for i in range(n)]
            idx = None
            for want in ([action] if action not in ("click", "default") else []) + ACTION_PREF:
                if want in names:
                    idx = names.index(want)
                    break
            if idx is None and n:
                idx = 0
            if idx is None:
                return {"ok": False, "fallback": box,
                        "reason": "element exposes no actions; click its box instead"}
            ok = _safe(lambda: A.Action.do_action(node, idx), False)
            return {"ok": bool(ok), "did": names[idx] if idx < len(names) else "action"}
        if action == "focus":
            return {"ok": bool(_safe(lambda: A.Component.grab_focus(node), False))}
        if action == "set_text":
            ok = _safe(lambda: A.EditableText.set_text_contents(node, text or ""), False)
            if not ok:
                return {"ok": False, "fallback": box,
                        "reason": "not editable via AT-SPI; focus it and type instead"}
            return {"ok": True}
        if action == "get_text":
            return {"ok": True, "text": _safe(lambda: A.Text.get_text(node, 0, -1), "")}
        if action == "set_value":
            return {"ok": bool(_safe(lambda: A.Value.set_current_value(node, float(value)), False))}
        if action == "scroll_into_view":
            return {"ok": bool(_safe(lambda: A.Component.scroll_to(node, A.ScrollType.ANYWHERE), False))}
        if action == "select":
            p = _safe(node.get_parent)
            i = _safe(node.get_index_in_parent)
            ok = p is not None and i is not None and _safe(lambda: A.Selection.select_child(p, i), False)
            return {"ok": bool(ok)}
        raise ValueError(f"unknown a11y action {action}")
