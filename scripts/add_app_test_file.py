#!/usr/bin/env python3
# Copyright 2026 Spatial Duality
# SPDX-License-Identifier: Apache-2.0
#
# Idempotently add a Swift test file under ManifoldAppTests/ to the
# ManifoldAppTests target's Sources phase and the ManifoldAppTests group.
# Safe to re-run.
#
# Usage:
#   python3 scripts/add_app_test_file.py <filename> <stable-uuid-prefix>
#
# Example:
#   python3 scripts/add_app_test_file.py DiagnosticsModelTests.swift DIAG0M0DEL0TEST00

import re
import sys
from pathlib import Path

if len(sys.argv) != 3:
    print(__doc__)
    sys.exit(2)

filename = sys.argv[1]
prefix   = sys.argv[2]

PROJECT = Path("Manifold.xcodeproj/project.pbxproj")
file_ref_uuid   = (prefix + "FREF").ljust(24, "0")[:24]
build_file_uuid = (prefix + "BFIL").ljust(24, "0")[:24]

# Anchors specific to the ManifoldAppTests target.
SOURCES_PHASE_UUID = "E10000000000000000000031"
GROUP_UUID         = "E10000000000000000000021"

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

# Add to ManifoldAppTests group children.
group_pattern = re.compile(
    r'(' + re.escape(GROUP_UUID) + r' /\* ManifoldAppTests \*/ = \{[^}]*?children = \()',
    re.DOTALL,
)
m = group_pattern.search(text)
if m and file_ref_uuid not in m.group(0):
    insertion = f"\n\t\t\t\t{file_ref_uuid} /* {filename} */,"
    text = text[:m.end()] + insertion + text[m.end():]

# Add to test target's Sources phase.
sources_pattern = re.compile(
    r'(' + re.escape(SOURCES_PHASE_UUID) + r' /\* Sources \*/ = \{[^}]*?files = \()([^)]*?)(\);)',
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
    print(f"Added {filename} to ManifoldAppTests target")
else:
    print(f"No changes needed for {filename}")
