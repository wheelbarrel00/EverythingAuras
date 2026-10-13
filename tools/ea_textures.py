#!/usr/bin/env python3
"""Draws Everything Auras' own white-on-transparent textures into EverythingAuras/Media/EA/.

Usage: py tools/ea_textures.py
"""
import math
import os
import struct

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "EverythingAuras", "Media", "EA")
SS = 8  # supersamples per pixel side


def seg_dist(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def in_triangle(px, py, a, b, c):
    def side(p1, p2):
        return (px - p2[0]) * (p1[1] - p2[1]) - (p1[0] - p2[0]) * (py - p2[1])
    d1, d2, d3 = side(a, b), side(b, c), side(c, a)
    neg = d1 < 0 or d2 < 0 or d3 < 0
    pos = d1 > 0 or d2 > 0 or d3 > 0
    return not (neg and pos)


def render(size, shade):
    """shade(x, y) returns (gray, alpha) for a point in pixel units, top-left origin."""
    rows = []
    for y in range(size):
        row = []
        for x in range(size):
            g_sum = a_sum = 0.0
            for sy in range(SS):
                for sx in range(SS):
                    g, a = shade(x + (sx + 0.5) / SS, y + (sy + 0.5) / SS)
                    g_sum += g * a
                    a_sum += a
            n = SS * SS
            alpha = a_sum / n
            gray = g_sum / a_sum if a_sum else 0.0
            row.append((round(gray * 255), round(alpha * 255)))
        rows.append(row)
    return rows


def write_tga(name, rows):
    size = len(rows)
    # Bottom-left origin and 8 alpha bits, as the library's own textures are written.
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, size, size, 32, 8)
    body = bytearray()
    for row in reversed(rows):
        for gray, alpha in row:
            body += bytes((gray, gray, gray, alpha))
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, name), "wb") as f:
        f.write(header + bytes(body))
    print("wrote", name, size, "x", size)


def marker(x, y):
    # A white corner triangle on a dark one, so the hypotenuse keeps an edge on a light icon.
    s = 32
    if in_triangle(x, y, (5.5, 0), (s, 0), (s, s - 5.5)):
        return 1.0, 1.0
    if in_triangle(x, y, (0, 0), (s, 0), (s, s)):
        return 0.0, 0.85
    return 0.0, 0.0


SWORD = [
    # blade, guard and grip, in 16 px units
    ((2.5, 2.5), (10.2, 10.2)), ((7.6, 12.8), (12.8, 7.6)), ((10.6, 10.6), (13.4, 13.4)),
]


def sword(x, y):
    for (ax, ay), (bx, by) in SWORD:
        if seg_dist(x, y, ax, ay, bx, by) <= 0.8:
            return 1.0, 1.0
    return 0.0, 0.0


if __name__ == "__main__":
    write_tga("marker.tga", render(32, marker))
    write_tga("icon-combat.tga", render(16, sword))
