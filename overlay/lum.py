"""Brightness (0-1) of a ring around a rectangle on screen, leaving the
rectangle itself out: mean, 10th and 90th percentile. The overlay uses it so the
glass pill knows how dark or light, and how mixed, its surroundings are.
usage: lum.py X Y W H MARGIN"""
import subprocess
import sys

x, y, w, h, m = map(int, sys.argv[1:6])
s = 0.25
out = subprocess.run(["grim", "-g", f"{x - m},{y - m} {w + 2 * m}x{h + 2 * m}", "-s", str(s),
                      "-t", "ppm", "-"], capture_output=True, timeout=2).stdout
_, dims, _, px = out.split(b"\n", 3)
pw, ph = map(int, dims.split())
x0, y0, x1, y1 = m * s, m * s, (m + w) * s, (m + h) * s
vals = []
for j in range(ph):
    inside_row = y0 <= j < y1
    for i in range(pw):
        if inside_row and x0 <= i < x1:
            continue
        o = (j * pw + i) * 3
        vals.append((0.2126 * px[o] + 0.7152 * px[o + 1] + 0.0722 * px[o + 2]) / 255)
if not vals:
    print("0.1 0.1 0.1")
else:
    vals.sort()
    mean = sum(vals) / len(vals)
    print(f"{mean:.4f} {vals[len(vals) // 10]:.4f} {vals[len(vals) * 9 // 10]:.4f}")
