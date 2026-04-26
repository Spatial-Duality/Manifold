#!/usr/bin/env python3
# Copyright 2026 Spatial Duality
# SPDX-License-Identifier: Apache-2.0
#
# Idempotently inject PrivacyInfo.xcprivacy into the Manifold app target's
# PBXResourcesBuildPhase. If no Resources phase exists, create one and add it
# to the target's buildPhases. Safe to re-run.
#
# Usage: python3 script/add_privacy_manifest.py [path/to/project.pbxproj]

import re
import sys
import secrets
from pathlib import Path

PROJECT = Path(sys.argv[1] if len(sys.argv) > 1 else "Manifold.xcodeproj/project.pbxproj")

# Stable UUIDs so reruns don't accumulate duplicate refs.
FILE_REF_UUID    = "PRIV1NF0XCPRIV0001000001"
BUILD_FILE_UUID  = "PRIV1NF0XCPRIV0001000002"
RESOURCES_PHASE_UUID = "PRIV1NF0XCPRIV0001000003"

PRIVACY_FILE = "PrivacyInfo.xcprivacy"
TARGET_NAME  = "Manifold"

text = PROJECT.read_text()
original = text

# 1. Add PBXFileReference if missing.
file_ref_block = (
    f'\t\t{FILE_REF_UUID} /* {PRIVACY_FILE} */ = '
    f'{{isa = PBXFileReference; lastKnownFileType = text.xml; path = {PRIVACY_FILE}; sourceTree = "<group>"; }};\n'
)
if FILE_REF_UUID not in text:
    # Insert before the End PBXFileReference section marker.
    text = text.replace(
        "/* End PBXFileReference section */",
        f"{file_ref_block}/* End PBXFileReference section */",
        1,
    )

# 2. Add PBXBuildFile if missing.
build_file_block = (
    f'\t\t{BUILD_FILE_UUID} /* {PRIVACY_FILE} in Resources */ = '
    f'{{isa = PBXBuildFile; fileRef = {FILE_REF_UUID} /* {PRIVACY_FILE} */; }};\n'
)
if BUILD_FILE_UUID not in text:
    text = text.replace(
        "/* End PBXBuildFile section */",
        f"{build_file_block}/* End PBXBuildFile section */",
        1,
    )

# 3. Add to ManifoldApp group children if not already present.
group_pattern = re.compile(
    r'(A6F4968BF6A0BCAE922FEE85 /\* ManifoldApp \*/ = \{[^}]*?children = \()',
    re.DOTALL,
)
match = group_pattern.search(text)
if match and FILE_REF_UUID not in match.group(0):
    insertion = f"\n\t\t\t\t{FILE_REF_UUID} /* {PRIVACY_FILE} */,"
    text = text[:match.end()] + insertion + text[match.end():]

# 4. Create or extend a PBXResourcesBuildPhase, then ensure it's in the
#    Manifold target's buildPhases array.
if "Begin PBXResourcesBuildPhase section" not in text:
    # No Resources section in the file at all — create one with our phase.
    phase_section = (
        "/* Begin PBXResourcesBuildPhase section */\n"
        f"\t\t{RESOURCES_PHASE_UUID} /* Resources */ = {{\n"
        "\t\t\tisa = PBXResourcesBuildPhase;\n"
        "\t\t\tbuildActionMask = 2147483647;\n"
        "\t\t\tfiles = (\n"
        f"\t\t\t\t{BUILD_FILE_UUID} /* {PRIVACY_FILE} in Resources */,\n"
        "\t\t\t);\n"
        "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        "\t\t};\n"
        "/* End PBXResourcesBuildPhase section */\n\n"
    )
    # Insert before the PBXShellScriptBuildPhase section if present, otherwise
    # before PBXSourcesBuildPhase.
    insert_anchor = "/* Begin PBXShellScriptBuildPhase section */"
    if insert_anchor not in text:
        insert_anchor = "/* Begin PBXSourcesBuildPhase section */"
    text = text.replace(insert_anchor, phase_section + insert_anchor, 1)
elif RESOURCES_PHASE_UUID not in text:
    # A Resources section exists but doesn't include our phase — add it.
    phase_block = (
        f"\t\t{RESOURCES_PHASE_UUID} /* Resources */ = {{\n"
        "\t\t\tisa = PBXResourcesBuildPhase;\n"
        "\t\t\tbuildActionMask = 2147483647;\n"
        "\t\t\tfiles = (\n"
        f"\t\t\t\t{BUILD_FILE_UUID} /* {PRIVACY_FILE} in Resources */,\n"
        "\t\t\t);\n"
        "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        "\t\t};\n"
    )
    text = text.replace(
        "/* End PBXResourcesBuildPhase section */",
        phase_block + "/* End PBXResourcesBuildPhase section */",
        1,
    )

# 5. Add the new Resources phase UUID to the Manifold target's buildPhases.
target_phases_pattern = re.compile(
    r'(A6679FE56DC4150E476E48D5 /\* Manifold \*/ = \{[^}]*?buildPhases = \()([^)]*?)(\);)',
    re.DOTALL,
)
m = target_phases_pattern.search(text)
if m and RESOURCES_PHASE_UUID not in m.group(2):
    new_phases = m.group(2).rstrip()
    if new_phases and not new_phases.endswith(","):
        new_phases += ","
    new_phases += f"\n\t\t\t\t{RESOURCES_PHASE_UUID} /* Resources */,\n\t\t\t"
    text = text[:m.start(2)] + new_phases + text[m.end(2):]

if text != original:
    PROJECT.write_text(text)
    print(f"Updated {PROJECT}")
else:
    print(f"No changes needed to {PROJECT}")
