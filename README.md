# Manifold

Native macOS app and local runtime for governing access to selected files and email through the Manifold runtime boundary.

## Requirements

- macOS 26.0 or later
- Xcode 26.0 or later
- Swift 6

## Build

```bash
swift build
```

```bash
xcodebuild -project Manifold.xcodeproj \
           -scheme Manifold \
           -configuration Debug \
           -derivedDataPath /tmp/manifold-derived-data \
           build CODE_SIGNING_ALLOWED=NO
```

## Test

```bash
swift test
```

Focused app tests can be run with:

```bash
xcodebuild -project Manifold.xcodeproj \
           -scheme Manifold \
           -configuration Debug \
           -derivedDataPath /tmp/manifold-derived-data \
           test CODE_SIGNING_ALLOWED=NO
```

## Run

Open `Manifold.xcodeproj` and run the `Manifold` scheme, or use:

```bash
bash scripts/build_and_run.sh
```

## Release Utilities

The release scripts live in `scripts/` and `ManifoldApp/build.sh`.

- `ManifoldApp/build.sh release` builds the app bundle and DMG.
- `scripts/sparkle_generate_keys.sh` generates the Sparkle EdDSA keypair.
- `scripts/generate_appcast.sh` writes an appcast XML file for a signed DMG.
- `scripts/validate_appcast.sh` validates an appcast before publication.
- `scripts/validate_release_posture.sh` checks signed app release posture.

## License

Licensed under the Apache License, Version 2.0. See `LICENSE`.
