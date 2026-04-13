---
name: plan-eng-review
description: Create an engineering plan for Manifold architecture, runtime/XPC changes, or multi-file app quality upgrades. Use for architecture review, sequencing, and implementation planning.
---

# Plan Engineering Review

Use this workflow when the change is too large or risky to jump straight into code.

## Workflow

1. Explore the affected slice first.
   Read the key files and identify the real boundary lines.
2. Name the constraints.
   Runtime/XPC boundary, macOS UX expectations, verification needs, and migration risk.
3. Break the work into phases.
   Prefer phases that preserve a working build and keep verification cheap.
4. Order the phases by leverage.
   For Manifold, fix runtime truth and responsiveness before cosmetic polish.
5. Call out verification per phase.

## Manifold-specific priorities

- Preserve `ManifoldRuntime` as the single store composition root.
- Keep the app as a pure XPC client.
- Fix product-critical trust issues before refactoring for beauty.
- Prefer plans that let Claude verify each phase with `swift build`, `swift test`, and `xcodebuild`.
