#!/usr/bin/env python3
"""Regenerate bashx.mark SF Symbol for Control Center (large X + hub)."""
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


def mark_path(cx=64.0, cy=64.0, half=42.0, thick=15.0, hub=6.5):
    return " ".join([
        capsule(cx, cy, half, thick, math.pi / 4),
        capsule(cx, cy, half, thick, -math.pi / 4),
        (
            f"M{cx + hub:.3f},{cy:.3f} A{hub:.3f},{hub:.3f} 0 1 1 "
            f"{cx - hub:.3f},{cy:.3f} A{hub:.3f},{hub:.3f} 0 1 1 {cx + hub:.3f},{cy:.3f} Z"
        ),
    ])


def guides(suffix, baseline, capline, left, right):
    return f"""
        <path d="M0,{baseline} L128,{baseline}" id="Baseline-{suffix}" stroke="#FF00FF" stroke-width="0.5"/>
        <path d="M0,{capline} L128,{capline}" id="Capline-{suffix}" stroke="#FF00FF" stroke-width="0.5"/>
        <path d="M{left},0 L{left},128" id="Left-margin-{suffix}" stroke="#00FFFF" stroke-width="0.5"/>
        <path d="M{right},0 L{right},128" id="Right-margin-{suffix}" stroke="#00FFFF" stroke-width="0.5"/>"""


def main():
    path = mark_path()
    svg = f"""<?xml version="1.0" encoding="UTF-8"?>
<svg version="1.1" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128" width="128" height="128">
  <g id="Notes"></g>
  <g id="Guides" stroke="none" fill="none">
    {guides("S", 100, 32, 22, 106)}
    {guides("M", 100, 28, 16, 112)}
    {guides("L", 100, 24, 10, 118)}
  </g>
  <g id="Symbols">
    <g id="Regular-S"><path d="{path}" fill="#000000"/></g>
    <g id="Regular-M"><path d="{path}" fill="#000000"/></g>
    <g id="Regular-L"><path d="{path}" fill="#000000"/></g>
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
