# Distribution, Updates, And Export-Only Diagnostics

Date: 2026-05-02

## Hosting Shape

- `https://spatialduality.com` is a static Cloudflare Pages site.
- `https://spatialduality.com/download` links to GitHub Releases.
- `https://spatialduality.com/updates/appcast.xml` is the Sparkle feed.
- `https://github.com/amargandhi/Manifold/releases` stores the signed `.dmg`.
- The optional OpenAI privacy filter model remains on the pinned Hugging Face snapshot for v1.

No R2 bucket or telemetry ingest endpoint is required for v1. That keeps the public launch path close to a hard cost cap.

## Release Build

`ManifoldApp/build.sh` reads `MARKETING_VERSION` from `project.yml`. The old root `VERSION` file is not required.

Local unsigned debug build:

```bash
bash ManifoldApp/build.sh debug
```

Official release build:

```bash
MANIFOLD_REQUIRE_SIGNED_RELEASE=1 \
MANIFOLD_REQUIRE_NOTARIZATION=1 \
MANIFOLD_REQUIRE_SPARKLE=1 \
MANIFOLD_CODESIGN_IDENTITY="Developer ID Application: Example (TEAMID)" \
MANIFOLD_NOTARY_PROFILE="manifold-notary" \
MANIFOLD_SPARKLE_PUBLIC_ED_KEY="..." \
bash ManifoldApp/build.sh release
```

The release script produces:

- `ManifoldApp/build/Manifold.app`
- `ManifoldApp/build/Manifold-v<version>.dmg`
- `ManifoldApp/build/Manifold.dmg`

Upload both DMG files to the matching GitHub Release. The versioned DMG is used by Sparkle. The stable `Manifold.dmg` copy backs `/download/latest`.

## Appcast

Generate the appcast after producing and signing the DMG and after generating the Sparkle EdDSA signature:

```bash
bash scripts/generate_appcast.sh \
  ManifoldApp/build/Manifold-v0.4.0.dmg \
  "<sparkle-ed-signature>"
```

Then validate before deploying the site:

```bash
bash scripts/validate_appcast.sh website/spatialduality-site/updates/appcast.xml --skip-net
```

Use `--previous-feed https://spatialduality.com/updates/appcast.xml` when replacing an existing public feed.

## Diagnostics

V1 diagnostics are export-only:

- The app records local JSONL events in `~/Library/Application Support/Manifold/Diagnostics`.
- Users can preview and save `DiagnosticReportV1` JSON from Settings.
- The official app does not set `ManifoldTelemetryEndpoint`.
- No diagnostic report is uploaded by the app.

The allowed report shape remains deliberately small: app version/build/channel, OS major/minor/architecture, consent state, optional resettable install ID, runtime health, event rollups, and future aggregate MetricKit summaries. Reports never include file paths, prompts, email contents, governed data, raw stack traces, exact timestamps, cookies, or IP addresses.

## Website Analytics

The static site includes a consent banner. Cloudflare Web Analytics is loaded only after the visitor chooses Allow. Do not enable Cloudflare Pages automatic Web Analytics injection, because that would load the beacon before consent.
