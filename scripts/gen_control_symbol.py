#!/usr/bin/env python3
"""Regenerate bashx.mark SF Symbol — BashX brand badge (Control Center)."""
import json
import math
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "BashXControls/Assets.xcassets/bashx.mark.symbolset")


def capsule(cx, cy, half_len, thick, angle):
    c, s = math.cos(angle), math.sin(angle)
    px, py = -s, c
    r = thick / 2
    x1, y1 = cx - c * half_len, cy - s * half_len
    x2, y2 = cx + c * half_len, cy + s * half_len
    ox, oy = px * r, py * r
    return (
        f"M{x1 + ox:.3f},{y1 + oy:.3f} "
        f"L{x2 + ox:.3f},{y2 + oy:.3f} "
        f"A{r:.3f},{r:.3f} 0 0 1 {x2 - ox:.3f},{y2 - oy:.3f} "
        f"L{x1 - ox:.3f},{y1 - oy:.3f} "
        f"A{r:.3f},{r:.3f} 0 0 1 {x1 + ox:.3f},{y1 + oy:.3f} Z"
    )


def rounded_rect(cx, cy, half, corner):
    h, c = half, corner
    return (
        f"M{cx - h + c:.3f},{cy - h:.3f} "
        f"H{cx + h - c:.3f} "
        f"A{c:.3f},{c:.3f} 0 0 1 {cx + h:.3f},{cy - h + c:.3f} "
        f"V{cy + h - c:.3f} "
        f"A{c:.3f},{c:.3f} 0 0 1 {cx + h - c:.3f},{cy + h:.3f} "
        f"H{cx - h + c:.3f} "
        f"A{c:.3f},{c:.3f} 0 0 1 {cx - h:.3f},{cy + h - c:.3f} "
        f"V{cy - h + c:.3f} "
        f"A{c:.3f},{c:.3f} 0 0 1 {cx - h + c:.3f},{cy - h:.3f} Z"
    )


def circle(cx, cy, r):
    return (
        f"M{cx - r:.3f},{cy:.3f} "
        f"A{r:.3f},{r:.3f} 0 1,0 {cx + r:.3f},{cy:.3f} "
        f"A{r:.3f},{r:.3f} 0 1,0 {cx - r:.3f},{cy:.3f} Z"
    )


def mark_paths(cx=64.0, cy=64.0, scale=1.0):
    """
    BashX mark for Control Center — matches app icon structure:
    rounded badge frame + bold round-cap X + center hub.
    """
    s = scale
    half = 45.8 * s
    corner = 13.6 * s
    frame = 8.6 * s
    inner_half = half - frame
    inner_corner = max(7.2 * s, corner - frame * 0.52)

    x_len = 25.8 * s
    x_thick = 13.8 * s
    hub = 3.6 * s

    return " ".join([
        rounded_rect(cx, cy, half, corner),
        rounded_rect(cx, cy, inner_half, inner_corner),
        capsule(cx, cy, x_len, x_thick, math.pi / 4),
        capsule(cx, cy, x_len, x_thick, -math.pi / 4),
        circle(cx, cy, hub),
    ])


def guides(suffix, baseline, capline, left, right):
    return f"""
        <path d="M0,{baseline} L128,{baseline}" id="Baseline-{suffix}" stroke="#FF00FF" stroke-width="0.5"/>
        <path d="M0,{capline} L128,{capline}" id="Capline-{suffix}" stroke="#FF00FF" stroke-width="0.5"/>
        <path d="M{left},0 L{left},128" id="Left-margin-{suffix}" stroke="#00FFFF" stroke-width="0.5"/>
        <path d="M{right},0 L{right},128" id="Right-margin-{suffix}" stroke="#00FFFF" stroke-width="0.5"/>"""


def main():
    scales = {"S": 0.98, "M": 1.06, "L": 1.15}
    groups = []
    for suffix, sc in scales.items():
        path = mark_paths(scale=sc)
        groups.append(
            f'    <g id="Regular-{suffix}">'
            f'<path d="{path}" fill="#000000" fill-rule="evenodd"/></g>'
        )

    svg = f"""<?xml version="1.0" encoding="UTF-8"?>
<svg version="1.1" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128" width="128" height="128">
  <g id="Notes"></g>
  <g id="Guides" stroke="none" fill="none">
    {guides("S", 100, 32, 22, 106)}
    {guides("M", 100, 28, 16, 112)}
    {guides("L", 100, 24, 10, 118)}
  </g>
  <g id="Symbols">
{chr(10).join(groups)}
  </g>
</svg>
"""
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "bashx.mark.svg"), "w", encoding="utf-8") as f:
        f.write(svg)
    with open(os.path.join(OUT, "Contents.json"), "w", encoding="utf-8") as f:
        json.dump({
            "info": {"author": "xcode", "version": 1},
            "properties": {
                "preserves-vector-representation": True,
                "symbol-rendering-intent": "template",
            },
            "symbols": [{"filename": "bashx.mark.svg", "idiom": "universal"}],
        }, f, indent=2)
        f.write("\n")
    print("wrote", OUT)


if __name__ == "__main__":
    main()
