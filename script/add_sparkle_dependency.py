#!/usr/bin/env python3
# Copyright 2026 Spatial Duality
# SPDX-License-Identifier: Apache-2.0
#
# Idempotently add the Sparkle 2 SPM dependency to the Manifold app target.
# Adds XCRemoteSwiftPackageReference, XCSwiftPackageProductDependency, the
# PBXBuildFile in the Frameworks phase, and registers the product in the
# Manifold target's packageProductDependencies. Safe to re-run.
#
# Usage: python3 script/add_sparkle_dependency.py

import re
from pathlib import Path

PROJECT = Path("Manifold.xcodeproj/project.pbxproj")

# Sparkle 2.x is the only one with EdDSA + macOS-only deployment + SPM. Pin
# to a known-good range; bump intentionally.
SPARKLE_REPO = "https://github.com/sparkle-project/Sparkle"
SPARKLE_MIN_VERSION = "2.6.0"

# Stable UUIDs so reruns are idempotent.
PACKAGE_REF_UUID  = "5PARKLEPKG00000000000001"
PRODUCT_DEP_UUID  = "5PARKLEPKG00000000000002"
BUILD_FILE_UUID   = "5PARKLEPKG00000000000003"

text = PROJECT.read_text()
original = text

# 1. XCRemoteSwiftPackageReference
remote_ref_block = (
    f'\t\t{PACKAGE_REF_UUID} /* XCRemoteSwiftPackageReference "Sparkle" */ = {{\n'
    "\t\t\tisa = XCRemoteSwiftPackageReference;\n"
    f'\t\t\trepositoryURL = "{SPARKLE_REPO}";\n'
    "\t\t\trequirement = {\n"
    "\t\t\t\tkind = upToNextMajorVersion;\n"
    f'\t\t\t\tminimumVersion = {SPARKLE_MIN_VERSION};\n'
    "\t\t\t};\n"
    "\t\t};\n"
)
if PACKAGE_REF_UUID not in text:
    if "/* Begin XCRemoteSwiftPackageReference section */" in text:
        text = text.replace(
            "/* End XCRemoteSwiftPackageReference section */",
            remote_ref_block + "/* End XCRemoteSwiftPackageReference section */",
            1,
        )
    else:
        section = (
            "/* Begin XCRemoteSwiftPackageReference section */\n"
            + remote_ref_block
            + "/* End XCRemoteSwiftPackageReference section */\n\n"
        )
        # Insert before XCLocalSwiftPackageReference (or at end of XC* blocks).
        text = text.replace(
            "/* Begin XCLocalSwiftPackageReference section */",
            section + "/* Begin XCLocalSwiftPackageReference section */",
            1,
        )

# 2. XCSwiftPackageProductDependency
product_dep_block = (
    f'\t\t{PRODUCT_DEP_UUID} /* Sparkle */ = {{\n'
    "\t\t\tisa = XCSwiftPackageProductDependency;\n"
    f'\t\t\tpackage = {PACKAGE_REF_UUID} /* XCRemoteSwiftPackageReference "Sparkle" */;\n'
    "\t\t\tproductName = Sparkle;\n"
    "\t\t};\n"
)
if PRODUCT_DEP_UUID not in text:
    text = text.replace(
        "/* End XCSwiftPackageProductDependency section */",
        product_dep_block + "/* End XCSwiftPackageProductDependency section */",
        1,
    )

# 3. PBXBuildFile (links Sparkle into the Manifold target's Frameworks phase)
build_file_block = (
    f'\t\t{BUILD_FILE_UUID} /* Sparkle in Frameworks */ = '
    f'{{isa = PBXBuildFile; productRef = {PRODUCT_DEP_UUID} /* Sparkle */; }};\n'
)
if BUILD_FILE_UUID not in text:
    text = text.replace(
        "/* End PBXBuildFile section */",
        build_file_block + "/* End PBXBuildFile section */",
        1,
    )

# 4. Add to project's packageReferences list.
pkg_refs_pattern = re.compile(r'(packageReferences = \()([^)]*?)(\);)', re.DOTALL)
m = pkg_refs_pattern.search(text)
if m and PACKAGE_REF_UUID not in m.group(2):
    new_refs = m.group(2).rstrip()
    if new_refs and not new_refs.endswith(","):
        new_refs += ","
    new_refs += f'\n\t\t\t\t{PACKAGE_REF_UUID} /* XCRemoteSwiftPackageReference "Sparkle" */,\n\t\t\t'
    text = text[:m.start(2)] + new_refs + text[m.end(2):]

# 5. Add to Manifold target's packageProductDependencies.
target_pkg_pattern = re.compile(
    r'(A6679FE56DC4150E476E48D5 /\* Manifold \*/ = \{[^}]*?packageProductDependencies = \()([^)]*?)(\);)',
    re.DOTALL,
)
m = target_pkg_pattern.search(text)
if m and PRODUCT_DEP_UUID not in m.group(2):
    new_deps = m.group(2).rstrip()
    if new_deps and not new_deps.endswith(","):
        new_deps += ","
    new_deps += f"\n\t\t\t\t{PRODUCT_DEP_UUID} /* Sparkle */,\n\t\t\t"
    text = text[:m.start(2)] + new_deps + text[m.end(2):]

# 6. Add to Manifold target's Frameworks build phase (UUID 380E85CDE3445A5CAE94FE21).
frameworks_pattern = re.compile(
    r'(380E85CDE3445A5CAE94FE21 /\* Frameworks \*/ = \{[^}]*?files = \()([^)]*?)(\);)',
    re.DOTALL,
)
m = frameworks_pattern.search(text)
if m and BUILD_FILE_UUID not in m.group(2):
    new_files = m.group(2).rstrip()
    if new_files and not new_files.endswith(","):
        new_files += ","
    new_files += f"\n\t\t\t\t{BUILD_FILE_UUID} /* Sparkle in Frameworks */,\n\t\t\t"
    text = text[:m.start(2)] + new_files + text[m.end(2):]

if text != original:
    PROJECT.write_text(text)
    print(f"Added Sparkle {SPARKLE_MIN_VERSION}+ SPM dep to {PROJECT}")
else:
    print(f"No changes needed to {PROJECT}")
