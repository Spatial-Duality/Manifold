#!/usr/bin/env bash
# Copyright 2026 Spatial Duality
# SPDX-License-Identifier: Apache-2.0
#
# One-time EdDSA keypair generator for Sparkle. Locates Sparkle's bundled
# `generate_keys` tool from the resolved SPM artifacts and runs it.
#
# Output:
#   - Public key:  prints to stdout — paste into the Manifold Xcode project
#                  build setting `SPARKLE_PUBLIC_ED_KEY`.
#   - Private key: stored in macOS Keychain by `generate_keys`, NOT in this
#                  repo. Export it only if you need to sign updates on
#                  another Mac, then store it outside the repository.
#
# Run once. Rotating later means shipping a new app build with a new public
# key first, so existing installs can verify updates that follow. Document
# the procedure before you do it.
#
# Usage: bash scripts/sparkle_generate_keys.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# Make sure SPM has resolved Sparkle so the artifact directory exists.
echo "Resolving SPM dependencies..."
xcodebuild -resolvePackageDependencies \
    -project Manifold.xcodeproj -scheme Manifold >/dev/null 2>&1 || true

# Search both possible artifact locations: derived-data SourcePackages and
# any local checkout fallback. Prefer the binary artifact (xcframework
# distribution), fall back to the source checkout's binary.
GENERATE_KEYS=""
for candidate in \
    "$HOME/Library/Developer/Xcode/DerivedData"/Manifold-*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys \
    "$HOME/Library/Developer/Xcode/DerivedData"/Manifold-*/SourcePackages/checkouts/Sparkle/generate_keys; do
    if [[ -x "$candidate" ]]; then
        GENERATE_KEYS="$candidate"
        break
    fi
done

if [[ -z "$GENERATE_KEYS" ]]; then
    echo "error: could not find Sparkle's generate_keys binary." >&2
    echo "       run 'xcodebuild -resolvePackageDependencies' first, then retry." >&2
    exit 1
fi

echo "Using: $GENERATE_KEYS"
echo ""
echo "Generating EdDSA keypair (private key stored in macOS Keychain):"
echo "================================================================"
"$GENERATE_KEYS"
echo ""
echo "================================================================"
echo "Next steps:"
echo "1. Copy the public key printed above (the line starting with"
echo "   'A new EdDSA signing key has been generated' and the value below)."
echo "2. Open Manifold.xcodeproj in Xcode."
echo "3. Project -> Manifold target -> Build Settings -> search 'SPARKLE_PUBLIC_ED_KEY'."
echo "4. Paste the public key into both Debug and Release."
echo "5. Export the private key only if another signing machine needs it:"
echo "     $GENERATE_KEYS -x sparkle_private_key.pem"
echo "6. Store sparkle_private_key.pem outside this repository. Prefer"
echo "   the Keychain on this Mac for signing."
echo "7. Securely delete the local pem file after moving it to secret storage:"
echo "     rm sparkle_private_key.pem"
echo "8. Commit the updated project.pbxproj."
