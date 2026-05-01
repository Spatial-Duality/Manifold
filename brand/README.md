# Manifold Brand

The mark `{ | }` is the product thesis as a glyph. Curly braces are the trust boundary; the bar between them is the content authority that flows through.

## Files

- `mark-light.svg` / `mark-dark.svg` — the canonical mark, light- and dark-mode variants. Used by the README hero (via `<picture>`). **Don't move or rename without updating `README.md`.**
- `assets/sources/` — vector source files (Affinity Designer). Not consumed by the build.
- `assets/legacy/` — older icon exports kept for reference. Not consumed by the build.
- `exploration/` — earlier mark variants. Not canonical.
- `scripts/` — Python utilities used to author the SF Symbol and generate variants.

## App icon

The icon the running app actually uses lives at:

```
ManifoldApp/ManifoldApp/Assets.xcassets/Symbols/Manifold Icon SF.symbolset/
```

That's the source of truth for in-app rendering. The files in `brand/` are for documentation, marketing, and the README hero.

## Color

- Primary text on light: `#141413`
- Primary text on dark: `#faf9f5`

The current `mark-light.svg` and `mark-dark.svg` are intentionally minimal placeholders rendered with a system mono font. Replace with hand-drawn paths when the mark is finalized for press use.

## Third-party marks

This repo does not redistribute Anthropic, Claude, OpenAI, or Codex wordmarks. The app refers to those agents through SF Symbols and tinted dots. If you need vendor wordmarks for a docs page, source them from the vendor's official brand site and respect their guidelines — don't commit them here.
