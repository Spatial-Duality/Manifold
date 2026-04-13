---
name: review
description: Review Manifold code changes for bugs, regressions, product-risk, and missing verification. Use for code review and diff review.
---

# Review

Review with a bug-first mindset.

## What to prioritize

1. Behavioral regressions
2. Launch/runtime/XPC breakage
3. Incorrect or misleading UI state
4. Main-thread performance regressions
5. Missing verification

## Output

- Findings first, highest severity first
- Specific file references
- Brief residual risks after findings

## Manifold-specific watchpoints

- Any change that weakens the runtime/XPC boundary
- Any UI that implies trust or connection state not backed by real data
- Any expensive file or email operation running on the main actor
