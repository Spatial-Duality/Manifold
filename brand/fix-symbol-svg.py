#!/usr/bin/env python3
"""
fix-symbol-svg.py — repair an SF Symbols 7 custom-symbol template that
fails the "not interpolatable" check.

Strategy: copy the Regular-S weight group's path data into both
Ultralight-S and Black-S, and replace each of those groups' outer
wrapping transforms so the (now identical) artwork lands in its
correct column position.

Result: structurally identical paths in all three weights → guaranteed
interpolatable in SF Symbols.app.

Trade-off: the symbol renders at the same visual weight regardless of
the .fontWeight() / .imageScale() modifier the consumer applies. This
is the right trade-off for an identity mark; ship it and iterate later
if true variable rendering is needed.

Usage:
    python3 brand/fix-symbol-svg.py input.svg output.svg
"""

import copy
import re
import sys
import xml.etree.ElementTree as ET


# Standard SF Symbols template column centres, in the inner 3300×2200
# template coordinate space (before the ×4.16667 outer wrapper that
# v.7.0 templates use to map to a 13750×9167 viewBox). The same numbers
# work for v.6.0 templates, which don't have the outer wrapper.
COLUMN_CENTRES = {
    "Ultralight": 559.711,
    "Regular": 1449.84,
    "Black": 2933.4,
}

SVG_NS = "http://www.w3.org/2000/svg"
SVG = "{" + SVG_NS + "}"


def find_weight_group(root, weight_id):
    """Return (parent_g_with_outer_transform, weight_g_with_id, inner_g_with_paths).
    Walks the tree looking for the canonical structure used by SF Symbols
    template exports:
        <g transform="matrix(...)">
            <g id="Ultralight-S">
                <g>
                    <path d="..."/>
                    ...
                </g>
            </g>
        </g>
    """
    for parent in root.iter(SVG + "g"):
        for weight in parent.findall(SVG + "g"):
            if weight.get("id") != weight_id:
                continue
            inner = weight.find(SVG + "g")
            if inner is None:
                # Some templates put paths directly under the weight
                # group without a wrapping <g>. Treat the weight group
                # itself as the inner.
                inner = weight
            return parent, weight, inner
    return None, None, None


def parse_matrix(transform_attr):
    """Parse a matrix(sx, shy, shx, sy, tx, ty) transform string."""
    m = re.search(
        r"matrix\(\s*([-+\d.eE]+)\s*,\s*([-+\d.eE]+)\s*,\s*([-+\d.eE]+)\s*,"
        r"\s*([-+\d.eE]+)\s*,\s*([-+\d.eE]+)\s*,\s*([-+\d.eE]+)\s*\)",
        transform_attr,
    )
    if not m:
        raise ValueError(f"Cannot parse transform: {transform_attr}")
    return tuple(float(g) for g in m.groups())


def main(input_path: str, output_path: str) -> int:
    # Make sure the default namespace stays the SVG one in the output.
    ET.register_namespace("", SVG_NS)
    ET.register_namespace("xlink", "http://www.w3.org/1999/xlink")
    ET.register_namespace("serif", "http://www.serif.com/")

    tree = ET.parse(input_path)
    root = tree.getroot()

    # Locate Regular-S — our reference for the path data.
    regular_parent, regular_group, regular_inner = find_weight_group(root, "Regular-S")
    if regular_group is None:
        print("ERROR: <g id='Regular-S'> not found in input.", file=sys.stderr)
        return 1

    regular_transform = regular_parent.get("transform")
    if not regular_transform:
        print("ERROR: Regular-S parent has no transform attribute.", file=sys.stderr)
        return 1

    sx_R, _, _, sy_R, tx_R, ty_R = parse_matrix(regular_transform)
    print(f"Regular-S outer transform: scale={sx_R}, tx={tx_R}, ty={ty_R}")

    # For each of the broken weights, replace its inner artwork with
    # Regular's, and rewrite its outer transform to keep the same scale
    # but shift x to match its target column.
    for weight_name in ("Ultralight", "Black"):
        weight_id = f"{weight_name}-S"
        parent, weight_group, _ = find_weight_group(root, weight_id)
        if weight_group is None:
            print(f"WARNING: <g id='{weight_id}'> not found, skipping.", file=sys.stderr)
            continue

        # Compute new outer translation: same scale as Regular, but
        # shifted in x by the difference between target column centre
        # and Regular's column centre.
        column_shift = COLUMN_CENTRES[weight_name] - COLUMN_CENTRES["Regular"]
        new_tx = tx_R + column_shift
        new_transform = f"matrix({sx_R},0,0,{sy_R},{new_tx:.4f},{ty_R})"
        parent.set("transform", new_transform)
        print(f"  {weight_id}: new outer transform = {new_transform}")

        # Replace weight_group's children with a deep copy of Regular's
        # inner group. This gives us byte-identical path data in each
        # weight (= guaranteed interpolatable).
        for child in list(weight_group):
            weight_group.remove(child)
        weight_group.append(copy.deepcopy(regular_inner))

    tree.write(output_path, xml_declaration=True, encoding="utf-8")
    print(f"\n✓ Wrote fixed SVG to {output_path}")
    print(f"  Next: drag {output_path} into SF Symbols.app → Custom Symbols")
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(f"usage: {sys.argv[0]} <input.svg> <output.svg>", file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1], sys.argv[2]))
