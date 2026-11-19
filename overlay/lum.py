"""Average brightness (0-1) of a ring around a rectangle on screen, leaving the
rectangle itself out. Used by the overlay so the glass pill knows whether it
sits on something dark or light.  usage: lum.py X Y W H MARGIN"""
import subprocess
import sys

x, y, w, h, m = map(int, sys.argv[1:6])
s = 0.25
out = subprocess.run(["grim", "-g", f"{x - m},{y - m} {w + 2 * m}x{h + 2 * m}", "-s", str(s),
                      "-t", "ppm", "-"], capture_output=True, timeout=2).stdout
_, dims, _, px = out.split(b"\n", 3)
pw, ph = map(int, dims.split())
x0, y0, x1, y1 = m * s, m * s, (m + w) * s, (m + h) * s
tot = n = 0
for j in range(ph):
    inside_row = y0 <= j < y1
    for i in range(pw):
        if inside_row and x0 <= i < x1:
            continue
        o = (j * pw + i) * 3
        tot += 0.2126 * px[o] + 0.7152 * px[o + 1] + 0.0722 * px[o + 2]
        n += 1
print(round(tot / n / 255, 4) if n else 0.1)
