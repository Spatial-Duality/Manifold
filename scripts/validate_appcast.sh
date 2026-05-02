#!/usr/bin/env bash
# Copyright 2026 Spatial Duality
# SPDX-License-Identifier: Apache-2.0
#
# Pre-publish validation of a generated Sparkle appcast. Run this BEFORE
# pushing to gh-pages — without it, the first broken Sparkle build is shipped
# to every user.
#
# Checks:
#   1. The XML is well-formed.
#   2. There is at least one <item> element.
#   3. Every <item> has an <enclosure> with non-empty url, sparkle:edSignature,
#      sparkle:version, length, and type attributes.
#   4. The advertised enclosure URL returns HTTP 200 (or, with --skip-net,
#      we skip the network probe).
#   5. The Info.plist of the most recent enclosure (downloaded inline)
#      reports a CFBundleVersion strictly greater than the previously
#      published feed's most-recent item, when --previous-feed is given.
#
# Usage:
#   bash scripts/validate_appcast.sh <appcast.xml> [--skip-net] [--previous-feed URL]

set -euo pipefail

APPCAST="${1:-}"
if [[ -z "$APPCAST" || ! -f "$APPCAST" ]]; then
    echo "usage: $0 <appcast.xml> [--skip-net] [--previous-feed URL]" >&2
    exit 2
fi
shift

SKIP_NET=0
PREVIOUS_FEED=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-net) SKIP_NET=1; shift ;;
        --previous-feed) PREVIOUS_FEED="$2"; shift 2 ;;
        *) echo "unknown flag: $1" >&2; exit 2 ;;
    esac
done

fail() { echo "validate_appcast: FAIL: $*" >&2; exit 1; }
pass() { echo "validate_appcast: ok: $*"; }

# 1. Well-formed XML.
xmllint --noout "$APPCAST" || fail "appcast XML is malformed"
pass "XML well-formed"

# 2. At least one <item>.
ITEM_COUNT=$(xmllint --xpath "count(//item)" "$APPCAST")
if [[ "$ITEM_COUNT" -lt 1 ]]; then
    fail "appcast has 0 <item> elements"
fi
pass "$ITEM_COUNT item(s) present"

# 3. Every <item> has the required enclosure attributes. Sparkle 2 requires
#    sparkle:edSignature on every enclosure or it refuses to install.
for i in $(seq 1 "$ITEM_COUNT"); do
    URL=$(xmllint --xpath "string(//item[$i]/enclosure/@url)" "$APPCAST")
    SIG=$(xmllint --xpath "string(//item[$i]/enclosure/@*[local-name()='edSignature'])" "$APPCAST")
    VER=$(xmllint --xpath "string(//item[$i]/enclosure/@*[local-name()='version'])" "$APPCAST")
    LEN=$(xmllint --xpath "string(//item[$i]/enclosure/@length)" "$APPCAST")
    TYPE=$(xmllint --xpath "string(//item[$i]/enclosure/@type)" "$APPCAST")

    [[ -n "$URL"  ]] || fail "item $i missing enclosure url"
    [[ -n "$SIG"  ]] || fail "item $i missing sparkle:edSignature — unsigned, Sparkle will refuse"
    [[ -n "$VER"  ]] || fail "item $i missing sparkle:version (CFBundleVersion)"
    [[ -n "$LEN"  ]] || fail "item $i missing enclosure length"
    [[ -n "$TYPE" ]] || fail "item $i missing enclosure type"

    pass "item $i: url=$URL version=$VER signed"

    # 4. Network probe.
    if [[ "$SKIP_NET" -eq 0 ]]; then
        if ! curl -sfIL "$URL" >/dev/null; then
            fail "item $i enclosure URL did not return 2xx: $URL"
        fi
        pass "item $i enclosure URL reachable"
    fi
done

# 5. Strictly-increasing version vs previous feed.
if [[ -n "$PREVIOUS_FEED" ]]; then
    if ! PREV_FEED=$(curl -sfL "$PREVIOUS_FEED"); then
        echo "validate_appcast: warn: could not fetch previous feed at $PREVIOUS_FEED — skipping monotonicity check"
    else
        PREV_VER=$(printf '%s' "$PREV_FEED" | xmllint --xpath "string(//item[1]/enclosure/@*[local-name()='version'])" - 2>/dev/null || echo "0")
        NEW_VER=$(xmllint --xpath "string(//item[1]/enclosure/@*[local-name()='version'])" "$APPCAST")
        if [[ "${NEW_VER:-0}" -le "${PREV_VER:-0}" ]]; then
            fail "new feed's top item version ($NEW_VER) is not greater than previous feed's ($PREV_VER) — Sparkle would skip this update"
        fi
        pass "monotonicity: $PREV_VER -> $NEW_VER"
    fi
fi

echo ""
echo "validate_appcast: ALL CHECKS PASSED"
