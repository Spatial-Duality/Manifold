---
name: health
description: Audit Manifold for code health, maintainability, main-thread work, state ownership, and architecture drift. Use for code quality checks and health reviews.
---

# Health Check

Audit the codebase with emphasis on issues that quietly degrade a pro desktop app.

## Focus areas

- Main-thread IO or expensive work in SwiftUI-facing models
- State that can drift from reality
- Architecture leaks across the app/XPC/runtime boundary
- Navigation models that split selection state across multiple owners
- Verification gaps where changes compile but user flows still fail

## Output

- Rank issues by impact.
- Prefer specific, actionable fixes over generic cleanup advice.
- Flag anything that makes the product less truthful, less responsive, or less desktop-native.
