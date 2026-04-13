---
paths:
  - "ManifoldApp/ManifoldApp/Views/**/*.swift"
  - "ManifoldApp/ManifoldApp/Components/**/*.swift"
  - "ManifoldApp/ManifoldApp/ManifoldApp.swift"
---

# App UI Rules

- Target a pro macOS app feel, not an internal tool feel.
- Favor native desktop patterns: split views, inspectors, commands, context menus, selection-driven navigation, toolbar clarity, and keyboard support.
- Prefer data-dense, scannable views for files and activity. Consider `Table` when users benefit from sortable columns and desktop affordances.
- Avoid nested or ambiguous navigation models that make a sidebar selection open the wrong content.
- Do not show “connected”, “active”, or “shared” affordances unless backed by real runtime state.
- Visual polish is welcome, but only after interaction correctness and responsiveness are solid.
