#!/usr/bin/env python3
"""
diagnose-symbol-svg.py — find why an SF Symbol custom template fails the
"not interpolatable" check.

Reads an SF Symbols variable template SVG, finds the Ultralight-S /
Regular-S / Black-S groups, counts paths and anchors per group, and
reports any structural mismatch that would cause the
"variants are not interpolatable" error on import.

Usage:
    python3 brand/diagnose-symbol-svg.py path/to/your-template.svg

Reports:
- Number of paths per weight group
- Number of anchors per path per weight (compared across weights)
- Path direction (cw/ccw) per path per weight
- First-node coordinate per path per weight
"""

import re
import sys
import xml.etree.ElementTree as ET
from collections import defaultdict


SVG_NS = "http://www.w3.org/2000/svg"
WEIGHT_GROUPS = ("Ultralight-S", "Regular-S", "Black-S")


def count_anchors(d_attribute: str) -> int:
    """Count drawing commands (M/L/C/Q/A/Z and lowercase) in a path d-string.
    Approximate but gives a useful number for comparison."""
    # Strip arguments — we just want the command letters
    return len(re.findall(r"[MLCQAZHVSTmlcqazhvst]", d_attribute))


def count_subpaths(d_attribute: str) -> int:
    """Count separate sub-shapes (each starts with M or m)."""
    return len(re.findall(r"[Mm]", d_attribute))


def first_point(d_attribute: str) -> str:
    """Extract the first M/m coordinate as a normalized string."""
    m = re.search(r"[Mm]\s*([-\d.]+[,\s]+[-\d.]+)", d_attribute)
    return m.group(1).strip() if m else "?"


def path_direction(d_attribute: str) -> str:
    """Approximate winding direction by computing the signed area of
    the path's bounding polygon."""
    points = re.findall(r"[-+]?\d*\.?\d+", d_attribute)
    coords = [float(p) for p in points]
    if len(coords) < 6:
        return "?"
    # Take pairs as (x, y) — approximate, ignores curve handles
    pairs = list(zip(coords[::2], coords[1::2]))
    area = 0.0
    for i in range(len(pairs)):
        x1, y1 = pairs[i]
        x2, y2 = pairs[(i + 1) % len(pairs)]
        area += (x2 - x1) * (y2 + y1)
    return "cw" if area > 0 else "ccw"


def find_weight_groups(root: ET.Element) -> dict:
    """Return {weight_name: <g> element}."""
    found = {}
    for elem in root.iter(f"{{{SVG_NS}}}g"):
        gid = elem.get("id", "")
        if gid in WEIGHT_GROUPS:
            found[gid] = elem
    return found


def collect_paths(group: ET.Element) -> list:
    """Return list of d-attribute strings for all paths under group."""
    paths = []
    for path in group.iter(f"{{{SVG_NS}}}path"):
        d = path.get("d")
        if d:
            paths.append(d)
    # Treat <rect> as a path too — they're auto-converted by SF Symbols
    for rect in group.iter(f"{{{SVG_NS}}}rect"):
        # Synthesize a "rect equivalent path" with 4 anchors
        x = float(rect.get("x", 0))
        y = float(rect.get("y", 0))
        w = float(rect.get("width", 0))
        h = float(rect.get("height", 0))
        d = f"M{x},{y} L{x+w},{y} L{x+w},{y+h} L{x},{y+h} Z"
        paths.append(d)
    return paths


def main(svg_path: str):
    tree = ET.parse(svg_path)
    root = tree.getroot()
    groups = find_weight_groups(root)

    missing = [w for w in WEIGHT_GROUPS if w not in groups]
    if missing:
        print(f"❌ MISSING WEIGHT GROUPS: {missing}")
        print(f"   Your SVG must contain <g id='Ultralight-S'>, <g id='Regular-S'>, <g id='Black-S'>.")
        return 1

    # Collect paths per weight
    weight_paths = {w: collect_paths(g) for w, g in groups.items()}

    # Check 1: same number of paths per weight
    counts = {w: len(p) for w, p in weight_paths.items()}
    if len(set(counts.values())) > 1:
        print(f"❌ PATH COUNT MISMATCH:")
        for w, n in counts.items():
            print(f"   {w}: {n} paths")
        print(f"   All three weights must have the same number of paths.")
        return 1

    n_paths = counts[WEIGHT_GROUPS[0]]
    print(f"✓ Path count matches: {n_paths} paths per weight")
    print()

    # Per-path comparison
    any_mismatch = False
    for i in range(n_paths):
        anchors = {w: count_anchors(weight_paths[w][i]) for w in WEIGHT_GROUPS}
        subpaths = {w: count_subpaths(weight_paths[w][i]) for w in WEIGHT_GROUPS}
        firsts = {w: first_point(weight_paths[w][i]) for w in WEIGHT_GROUPS}
        directions = {w: path_direction(weight_paths[w][i]) for w in WEIGHT_GROUPS}

        ok = (
            len(set(anchors.values())) == 1 and
            len(set(subpaths.values())) == 1 and
            len(set(directions.values())) == 1
        )
        marker = "✓" if ok else "❌"
        print(f"{marker} Path #{i+1}")
        for w in WEIGHT_GROUPS:
            print(f"     {w:13}  anchors={anchors[w]:3d}  subpaths={subpaths[w]}  first=({firsts[w]})  dir={directions[w]}")
        if not ok:
            any_mismatch = True
            if len(set(anchors.values())) > 1:
                print(f"     → Anchor count mismatch — most common cause of 'not interpolatable'")
            if len(set(subpaths.values())) > 1:
                print(f"     → Subpath count mismatch — paths must be split the same way in every weight")
            if len(set(directions.values())) > 1:
                print(f"     → Direction mismatch — use Layer → Reverse Path Direction in Affinity to fix")
        print()

    if any_mismatch:
        print("Fix the mismatches above, re-export from Affinity, retry import.")
        return 1
    print("All paths look interpolatable. If SF Symbols.app still rejects:")
    print(" • Check that <g id='Symbols'> contains the three weight groups")
    print(" • Check that the file uses standard SVG path commands (no Affinity-specific tags)")
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(f"usage: {sys.argv[0]} <path-to-svg>")
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
