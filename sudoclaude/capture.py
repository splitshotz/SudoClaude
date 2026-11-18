import mmap
import os
import time

from .wayland import WaylandError, i32, u32

# frame event opcodes per protocol
_HYPR_EV = {"buffer": 0, "damage": 1, "flags": 2, "ready": 3, "failed": 4,
            "dmabuf": 5, "buffer_done": 6}
_WLR_EV = {"buffer": 0, "flags": 1, "ready": 2, "failed": 3, "damage": 4,
           "dmabuf": 5, "buffer_done": 6}

# wl_shm formats -> PIL raw mode (little-endian memory layout)
_FORMATS = {0: "BGRX", 1: "BGRX", 0x34324241: "RGBX", 0x34324258: "RGBX"}


class Capturer:
    def __init__(self, conn):
        self.c = conn
        self.shm = conn._bind_first("wl_shm", 1)
        self.hypr = conn._bind_first("hyprland_toplevel_export_manager_v1", 1)
        self.wlr = conn._bind_first("zwlr_screencopy_manager_v1", 3)
        conn.roundtrip()

    @property
    def can_window(self):
        return self.hypr is not None

    def _grab(self, request, ev, copy_payload_extra, timeout=4.0):
        import struct
        st = {"bufs": [], "flags": 0, "done": False, "ready": False, "failed": False}

        def on_frame(op, p):
            if op == ev["buffer"]:
                st["bufs"].append(struct.unpack_from("=IIII", p))
            elif op == ev["flags"]:
                (st["flags"],) = struct.unpack_from("=I", p)
            elif op == ev["buffer_done"]:
                st["done"] = True
            elif op == ev["ready"]:
                st["ready"] = True
            elif op == ev["failed"]:
                st["failed"] = True

        frame = self.c._new_id(on_frame)
        request(frame)
        deadline = time.monotonic() + timeout
        # wait for buffer_done (v3+) or at least one buffer + a roundtrip
        self.c.roundtrip(timeout)
        while not st["done"] and not st["failed"] and time.monotonic() < deadline:
            if st["bufs"]:
                self.c.roundtrip(timeout)
                break
            self.c._pump(max(0.01, deadline - time.monotonic()))
        if st["failed"]:
            self.c._send(frame, 1)
            raise WaylandError("capture failed (window gone or capture refused)")
        choice = next((b for b in st["bufs"] if b[0] in _FORMATS), None)
        if not choice:
            self.c._send(frame, 1)
            raise WaylandError(f"no supported shm format offered: {st['bufs']}")
        fmt, w, h, stride = choice
        size = stride * h
        fd = os.memfd_create("sudoclaude-capture", os.MFD_CLOEXEC)
        try:
            os.ftruncate(fd, size)
            pool = self.c._new_id()
            self.c._send(self.shm, 0, u32(pool) + i32(size), fds=[fd])
            buf = self.c._new_id()
            self.c._send(pool, 0, u32(buf) + i32(0) + i32(w) + i32(h) + i32(stride) + u32(fmt))
            self.c._send(frame, 0, u32(buf) + copy_payload_extra)
            while not (st["ready"] or st["failed"]):
                if time.monotonic() > deadline:
                    raise WaylandError("capture timed out")
                self.c._pump(max(0.01, deadline - time.monotonic()))
            self.c._send(frame, 1)
            self.c._send(buf, 0)
            self.c._send(pool, 1)
            if st["failed"]:
                raise WaylandError("capture failed during copy")
            mm = mmap.mmap(fd, size, mmap.MAP_SHARED, mmap.PROT_READ)
            data = bytes(mm)
            mm.close()
        finally:
            os.close(fd)
        return data, w, h, stride, fmt, st["flags"]

    def _to_image(self, raw):
        from PIL import Image
        data, w, h, stride, fmt, flags = raw
        img = Image.frombuffer("RGB", (w, h), data, "raw", _FORMATS[fmt], stride, 1)
        if flags & 1:
            img = img.transpose(Image.FLIP_TOP_BOTTOM)
        return img

    def window(self, address, cursor=False):
        """PIL image of a Hyprland window (by address), even off-screen."""
        if not self.hypr:
            raise WaylandError("compositor has no hyprland_toplevel_export (not Hyprland?)")
        handle = int(address, 16) & 0xFFFFFFFF

        def req(frame):
            self.c._send(self.hypr, 0, u32(frame) + i32(1 if cursor else 0) + u32(handle))
        return self._to_image(self._grab(req, _HYPR_EV, i32(1)))

    def output(self, out_wl_id, cursor=False):
        if not self.wlr:
            raise WaylandError("compositor has no zwlr_screencopy")

        def req(frame):
            self.c._send(self.wlr, 0, u32(frame) + i32(1 if cursor else 0) + u32(out_wl_id))
        return self._to_image(self._grab(req, _WLR_EV, b""))
