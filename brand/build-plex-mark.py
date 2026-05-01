#!/usr/bin/env python3
"""
build-plex-mark.py — generate an SF Symbols custom-symbol template with
the user's IBM Plex Sans Medium {|} mark, in Apple's exact native
template format (one <path> per weight, viewBox 0 0 3300 2200,
class="SFSymbolsPreviewWireframe").

The IBM Plex Sans Medium artwork is replicated identically across
Ultralight-S, Regular-S, Black-S — guaranteed interpolatable. The
mark looks the same at every weight (no thinning/fattening with
.fontWeight()), which is correct for an identity mark.

Inputs:
    Manifold Icon SF Symbol SVG.svg — user's IBM Plex Sans Medium icon
    custom.ellipsis.curlybraces.svg — Apple's canonical template format
                                       (used for the Notes/Guides skeleton)

Output:
    brand/manifold.mark.svg — ready to drag into SF Symbols.app

Usage:
    python3 brand/build-plex-mark.py
"""

import re
import sys
import xml.etree.ElementTree as ET

SVG_NS = "http://www.w3.org/2000/svg"
SVG = "{" + SVG_NS + "}"

# Inputs
ICON_PATH = "Manifold Icon SF Symbol SVG.svg"
APPLE_TEMPLATE_PATH = "custom.ellipsis.curlybraces.svg"
OUTPUT_PATH = "brand/Manifold Icon SF.svg"

WEIGHTS = [
    ("Ultralight", 559.711),
    ("Thin", 856.422),
    ("Light", 1153.13),
    ("Regular", 1449.84),
    ("Medium", 1746.56),
    ("Semibold", 2043.27),
    ("Bold", 2339.98),
    ("Heavy", 2636.69),
    ("Black", 2933.4),
]

SCALES = [
    ("S", 696),
    ("M", 1126),
    ("L", 1556),
]


# --- IBM Plex Sans Medium {|} artwork (from Manifold Icon SF Symbol SVG.svg) ---
#
# Each glyph's path is in font-unit coordinates (px, py) with cap height
# at py=-0.76 and baseline at py=0. The original SVG uses an inner
# transform matrix(266.667, 0, 0, 266.667, X, 1020.12) per glyph and an
# outer matrix(3.75944, 0, 0, 3.75944, -73.193, -3011.29).
#
# We pre-compose those two transforms with our column-local scaling
# (cap-height of the SF Symbol target is 70.459 units, so scale =
# 70.459 / (1002.49 * 0.76) ≈ 0.0925) so the final coordinates land
# in column-local space:
#   final_x = 92.73 * px + tx_offset
#   final_y = 92.73 * py     (baseline at y=0)
# tx_offset depends on which glyph (left bracket / pipe / right bracket).

# Per-glyph horizontal offset in column-local space.
#
# The Apple template's per-weight outer transforms use the COLUMN CENTRE
# (e.g. matrix(1 0 0 1 1449.84 696) for Regular-S) as the translation
# origin. So our artwork must be CENTRED on x=0 in its local space —
# otherwise the mark slides to one side of each column.
#
# SCALE is sized so the mark fills more of the available menu-bar /
# sidebar height than a standard cap-height-only glyph would. Apple's
# default custom-symbol cap height is ~70; we use ~95 so the brackets
# read at the same visual weight as filled menu bar icons (Codex,
# ChatGPT) which span the full 18pt status bar height instead of the
# typographic cap height.
#
# At SCALE = 125, the mark cap-line lands at y ≈ -95 (vs. Apple's -70)
# and the visible bracket is ~35% taller than a standard custom-symbol
# rendering. The mark still aligns to baseline, just with a taller cap.
#
# Glyph offsets are recalculated from the user's nested transforms
# (3.75944 outer, 266.667 inner) plus our SCALE override. After
# composition each glyph's tx_offset becomes:
#   Path 1 (left bracket): final_x = SCALE * px + tx_left
#   Path 2 (pipe):         final_x = SCALE * px + tx_pipe
#   Path 3 (right bracket): final_x = SCALE * px + tx_right
# These are then SHIFTED so the mark is centred around x=0 (column
# transforms use column-CENTRE, not left margin).
SCALE = 125.0

# Component offsets before centring — derived from user's nested SVG
# transforms (inner_tx values 14.0128, 108.782, 202.535 for
# left/pipe/right glyphs, multiplied through the outer ×3.75944 and our
# new ×SCALE/1002.49 ≈ 0.1247 vertical scale. tx_offset_raw =
# (inner_tx * 3.75944 - 73.193) * (SCALE / 1002.49)).
_TX_RAW = {
    "left":  (14.0128 * 3.75944 - 73.193) * (SCALE / 1002.49),
    "pipe":  (108.782 * 3.75944 - 73.193) * (SCALE / 1002.49),
    "right": (202.535 * 3.75944 - 73.193) * (SCALE / 1002.49),
}
# Mark width (after composition) = (1024 viewBox width) × (SCALE/1002.49)
_MARK_WIDTH = 1024 * (SCALE / 1002.49)
# Centre the mark around x=0 in column-local space.
_X_SHIFT = -_MARK_WIDTH / 2

GLYPH_OFFSETS = {
    "left":  _TX_RAW["left"]  + _X_SHIFT,
    "pipe":  _TX_RAW["pipe"]  + _X_SHIFT,
    "right": _TX_RAW["right"] + _X_SHIFT,
}

# Raw IBM Plex Sans Medium glyph paths (font-unit coordinates).
# Extracted verbatim from Manifold Icon SF Symbol SVG.svg.
LEFT_BRACKET_PATH_FONT = (
    "M0.3,0.138L0.205,0.138C0.178,0.138 0.157,0.13 0.141,0.113"
    "C0.126,0.097 0.118,0.075 0.118,0.048L0.118,-0.176"
    "C0.118,-0.205 0.109,-0.227 0.09,-0.242"
    "C0.072,-0.257 0.049,-0.265 0.021,-0.265L0.021,-0.358"
    "C0.049,-0.358 0.072,-0.365 0.09,-0.38"
    "C0.109,-0.396 0.118,-0.417 0.118,-0.446L0.118,-0.67"
    "C0.118,-0.697 0.126,-0.719 0.141,-0.735"
    "C0.157,-0.752 0.178,-0.76 0.205,-0.76L0.3,-0.76L0.3,-0.68"
    "L0.216,-0.68L0.216,-0.444"
    "C0.216,-0.423 0.211,-0.404 0.203,-0.386"
    "C0.194,-0.368 0.182,-0.352 0.167,-0.34"
    "C0.152,-0.328 0.136,-0.32 0.117,-0.316L0.117,-0.306"
    "C0.136,-0.302 0.152,-0.294 0.167,-0.282"
    "C0.182,-0.27 0.194,-0.255 0.203,-0.237"
    "C0.211,-0.219 0.216,-0.199 0.216,-0.178"
    "L0.216,0.058L0.3,0.058L0.3,0.138Z"
)

# Pipe is a rect in the source: x=0.129 y=-0.76 width=0.093 height=0.898
# Converted to a closed path (M, L, L, L, Z = 4 corners + close).
PIPE_PATH_FONT = "M0.129,-0.76L0.222,-0.76L0.222,0.138L0.129,0.138Z"

RIGHT_BRACKET_PATH_FONT = (
    "M0.056,-0.76L0.15,-0.76"
    "C0.177,-0.76 0.199,-0.752 0.214,-0.735"
    "C0.23,-0.719 0.238,-0.697 0.238,-0.67L0.238,-0.446"
    "C0.238,-0.417 0.247,-0.396 0.265,-0.38"
    "C0.284,-0.365 0.307,-0.358 0.335,-0.358L0.335,-0.265"
    "C0.307,-0.265 0.284,-0.257 0.265,-0.242"
    "C0.247,-0.227 0.238,-0.205 0.238,-0.176L0.238,0.048"
    "C0.238,0.075 0.23,0.097 0.214,0.113"
    "C0.199,0.13 0.177,0.138 0.15,0.138L0.056,0.138L0.056,0.058"
    "L0.14,0.058L0.14,-0.178"
    "C0.14,-0.2 0.144,-0.219 0.153,-0.237"
    "C0.161,-0.255 0.173,-0.271 0.188,-0.283"
    "C0.203,-0.295 0.22,-0.303 0.238,-0.306L0.238,-0.317"
    "C0.22,-0.321 0.203,-0.329 0.188,-0.341"
    "C0.173,-0.353 0.161,-0.368 0.153,-0.386"
    "C0.144,-0.404 0.14,-0.424 0.14,-0.445L0.14,-0.68"
    "L0.056,-0.68L0.056,-0.76Z"
)


def transform_path(d_font: str, x_offset: float) -> str:
    """Apply the composed transform to a font-unit path string. Each
    coordinate (px, py) becomes (SCALE*px + x_offset, SCALE*py)."""
    # Tokenise: pull out commands and numbers separately
    tokens = re.findall(r"[MLCZ]|-?\d*\.?\d+", d_font)
    out = []
    i = 0
    n = len(tokens)
    while i < n:
        tok = tokens[i]
        if tok in "MLCZ":
            cmd = tok
            out.append(cmd)
            i += 1
            if cmd == "Z":
                continue
            # Number of coordinate PAIRS to consume per command
            pairs = 1 if cmd in "ML" else 3  # C
            for _ in range(pairs):
                px = float(tokens[i])
                py = float(tokens[i + 1])
                new_x = SCALE * px + x_offset
                new_y = SCALE * py
                out.append(f"{new_x:.4f}")
                out.append(f"{new_y:.4f}")
                i += 2
        else:
            # Bare number (shouldn't happen in well-formed path)
            i += 1
    # Join with spaces, then tighten by removing space after commands
    s = " ".join(out)
    s = re.sub(r"([MLCZ]) ", r"\1", s)
    return s


def main() -> int:
    # 1. Build the combined column-local path data
    left = transform_path(LEFT_BRACKET_PATH_FONT, GLYPH_OFFSETS["left"])
    pipe = transform_path(PIPE_PATH_FONT, GLYPH_OFFSETS["pipe"])
    right = transform_path(RIGHT_BRACKET_PATH_FONT, GLYPH_OFFSETS["right"])

    # Apple's format: one <path> per weight with all subpaths in one d.
    # Each subpath ends with Z; concatenating just works.
    combined_d = left + right + pipe
    print(f"Combined path: {len(combined_d)} chars")
    print(f"  Left bracket:  {len(left)} chars")
    print(f"  Right bracket: {len(right)} chars")
    print(f"  Pipe:          {len(pipe)} chars")

    # 2. Read Apple's template skeleton
    ET.register_namespace("", SVG_NS)
    ET.register_namespace("xlink", "http://www.w3.org/1999/xlink")
    tree = ET.parse(APPLE_TEMPLATE_PATH)
    root = tree.getroot()

    # 3. Replace the Symbols section with a full 9-weight x 3-scale grid.
    # The artwork stays identical everywhere because this is a brand mark,
    # not a typographic symbol that should gain optical weight.
    symbols_g = None
    for g in root.iter(SVG + "g"):
        if g.get("id") == "Symbols":
            symbols_g = g
            break
    if symbols_g is None:
        print("ERROR: <g id='Symbols'> not found in template", file=sys.stderr)
        return 1

    symbols_g.clear()
    symbols_g.set("id", "Symbols")
    replaced = 0
    for scale_name, baseline_y in SCALES:
        for weight_name, column_x in WEIGHTS:
            group = ET.SubElement(
                symbols_g,
                SVG + "g",
                {
                    "id": f"{weight_name}-{scale_name}",
                    "transform": f"matrix(1 0 0 1 {column_x:g} {baseline_y:g})",
                },
            )
            ET.SubElement(
                group,
                SVG + "path",
                {
                    "class": "SFSymbolsPreviewWireframe",
                    "d": combined_d,
                },
            )
            replaced += 1
            print(f"  ✓ Wrote {weight_name}-{scale_name}")

    # 4. Update the descriptive name in Notes
    for text in root.iter(SVG + "text"):
        if text.get("id") == "descriptive-name":
            text.text = "Generated from Manifold Icon SF"
            break

    # 5. Write
    tree.write(OUTPUT_PATH, xml_declaration=True, encoding="utf-8")
    with open(OUTPUT_PATH, "r", encoding="utf-8") as f:
        svg_text = f.read()
    svg_text = svg_text.replace(
        "?>\n",
        "?>\n"
        "<!--Generator: Manifold build-plex-mark.py from Apple SF Symbols template-->\n"
        "<!DOCTYPE svg PUBLIC \"-//W3C//DTD SVG 1.1//EN\" "
        "\"http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd\">\n",
        1,
    )
    with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
        f.write(svg_text)
    print(f"\n✓ Wrote {OUTPUT_PATH}")
    print(f"  All {replaced} slots now contain identical IBM Plex Sans Medium artwork")
    print(f"  Drag {OUTPUT_PATH} into SF Symbols.app → Custom Symbols")
    return 0


if __name__ == "__main__":
    sys.exit(main())
