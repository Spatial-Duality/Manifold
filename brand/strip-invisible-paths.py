#!/usr/bin/env python3
"""
strip-invisible-paths.py — remove paths with fill-opacity:0 or
visibility:hidden from an SVG. These are typically Affinity Designer
artifacts left behind by certain edit operations (boolean ops, expand
stroke, split path) that don't render but DO count structurally — and
break SF Symbols variable-template interpolation when one weight ends
up with more paths than another.

Usage:
    python3 brand/strip-invisible-paths.py input.svg output.svg
"""

import re
import sys
import xml.etree.ElementTree as ET

SVG_NS = "http://www.w3.org/2000/svg"
SVG = "{" + SVG_NS + "}"


def is_invisible(path_element) -> bool:
    """A path is invisible if its style declares fill-opacity:0,
    opacity:0, visibility:hidden, or display:none."""
    style = path_element.get("style", "")
    if not style:
        return False
    # Normalise: lowercase, strip whitespace
    s = re.sub(r"\s+", "", style.lower())
    invisible_markers = (
        "fill-opacity:0",
        "fill-opacity:0.0",
        "opacity:0;",
        "opacity:0)",
        "visibility:hidden",
        "display:none",
    )
    # Check exact patterns plus end-of-string variants
    if "fill-opacity:0;" in s or s.endswith("fill-opacity:0"):
        return True
    if "opacity:0;" in s or s.endswith("opacity:0"):
        # Distinguish from fill-opacity / stroke-opacity
        if "fill-opacity" not in s.split("opacity:0")[0][-13:]:
            return True
    if "visibility:hidden" in s:
        return True
    if "display:none" in s:
        return True
    return False


def main(input_path: str, output_path: str) -> int:
    ET.register_namespace("", SVG_NS)
    ET.register_namespace("xlink", "http://www.w3.org/1999/xlink")
    ET.register_namespace("serif", "http://www.serif.com/")

    tree = ET.parse(input_path)
    root = tree.getroot()

    # Walk every <g> and remove invisible <path> children. We iterate
    # parents so we can mutate their child lists.
    removed = 0
    for parent in root.iter():
        # Tag may have namespace; we want any element that can contain paths
        children_to_remove = []
        for child in list(parent):
            if child.tag == SVG + "path" and is_invisible(child):
                children_to_remove.append(child)
        for c in children_to_remove:
            parent.remove(c)
            removed += 1

    tree.write(output_path, xml_declaration=True, encoding="utf-8")
    print(f"Removed {removed} invisible path(s)")
    print(f"Wrote cleaned SVG to {output_path}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(f"usage: {sys.argv[0]} <input.svg> <output.svg>", file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1], sys.argv[2]))
