#!/usr/bin/env python3
# Copyright 2026 Spatial Duality
# SPDX-License-Identifier: Apache-2.0
#
# Idempotently add a Swift source file to the Manifold app target's Sources
# build phase. Designed for files under ManifoldApp/ManifoldApp/Models/ and
# similar regular groups. Safe to re-run.
#
# Usage:
#   python3 script/add_app_source_file.py <relpath-from-ManifoldApp/ManifoldApp> <group> <stable-uuid-prefix>
#
# Example:
#   python3 script/add_app_source_file.py Models/DiagnosticsModel.swift Models DIAGM0DEL00000001

import re
import sys
from pathlib import Path

if len(sys.argv) != 4:
    print(__doc__)
    sys.exit(2)

rel_path  = sys.argv[1]                  # e.g. Models/DiagnosticsModel.swift
group     = sys.argv[2]                  # e.g. Models
prefix    = sys.argv[3]                  # 16-char stable UUID prefix

PROJECT = Path("Manifold.xcodeproj/project.pbxproj")
filename = rel_path.split("/")[-1]
file_ref_uuid   = (prefix + "FREF").ljust(24, "0")[:24]
build_file_uuid = (prefix + "BFIL").ljust(24, "0")[:24]

text = PROJECT.read_text()
original = text

file_ref_block = (
    f'\t\t{file_ref_uuid} /* {filename} */ = '
    f'{{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {filename}; sourceTree = "<group>"; }};\n'
)
if file_ref_uuid not in text:
    text = text.replace(
        "/* End PBXFileReference section */",
        f"{file_ref_block}/* End PBXFileReference section */",
        1,
    )

build_file_block = (
    f'\t\t{build_file_uuid} /* {filename} in Sources */ = '
    f'{{isa = PBXBuildFile; fileRef = {file_ref_uuid} /* {filename} */; }};\n'
)
if build_file_uuid not in text:
    text = text.replace(
        "/* End PBXBuildFile section */",
        f"{build_file_block}/* End PBXBuildFile section */",
        1,
    )

# Insert into named group's children list.
group_pattern = re.compile(
    r'(\b[A-F0-9]+ /\* ' + re.escape(group) + r' \*/ = \{[^}]*?children = \()',
    re.DOTALL,
)
match = group_pattern.search(text)
if match and file_ref_uuid not in match.group(0):
    insertion = f"\n\t\t\t\t{file_ref_uuid} /* {filename} */,"
    text = text[:match.end()] + insertion + text[match.end():]

# Insert into Manifold app target's Sources build phase.
sources_pattern = re.compile(
    r'(8263F2E00A2E489F2090951C /\* Sources \*/ = \{[^}]*?files = \()([^)]*?)(\);)',
    re.DOTALL,
)
m = sources_pattern.search(text)
if m and build_file_uuid not in m.group(2):
    new_files = m.group(2).rstrip()
    if new_files and not new_files.endswith(","):
        new_files += ","
    new_files += f"\n\t\t\t\t{build_file_uuid} /* {filename} in Sources */,\n\t\t\t"
    text = text[:m.start(2)] + new_files + text[m.end(2):]

if text != original:
    PROJECT.write_text(text)
    print(f"Added {rel_path} to Manifold target")
else:
    print(f"No changes needed for {rel_path}")
