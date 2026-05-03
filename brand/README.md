# Manifold Brand

The mark `{ | }` is the product thesis as a glyph. Curly braces are the trust boundary; the bar between them is the content authority that flows through.

## Files

- `Icon/` — app icon source files (Affinity Designer source, exported PNGs, the macOS `.icon` bundle).
- `assets/sources/` — vector source files (Affinity Designer). Not consumed by the build.
- `assets/legacy/` — older icon exports kept for reference. Not consumed by the build.
- `exploration/` — earlier mark variants. Not canonical.
- `scripts/` — Python utilities used to author the SF Symbol and generate variants.

## App icon

The icon the running app actually uses lives at:

```
ManifoldApp/ManifoldApp/Assets.xcassets/Symbols/Manifold Icon SF.symbolset/
```

That's the source of truth for in-app rendering. The exported PNGs in `brand/Icon/Icon Exports/` are what the README and external surfaces reference.

## Color

- Primary text on light: `#141413`
- Primary text on dark: `#faf9f5`

## Third-party marks

This repo does not redistribute Anthropic, Claude, OpenAI, or Codex wordmarks. The app refers to those agents through SF Symbols and tinted dots. If you need vendor wordmarks for a docs page, source them from the vendor's official brand site and respect their guidelines — don't commit them here.
