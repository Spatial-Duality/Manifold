# Spatial Duality Site Scaffold

Static Cloudflare Pages scaffold for `spatialduality.com`.

This directory is meant to become its own repository named `spatialduality-site`.
It has no build step and no GitHub Actions requirement.

## Deploy

```bash
npx wrangler pages deploy . --project-name spatialduality
```

Run that command from this directory after replacing:

- `updates/appcast.xml` placeholder Sparkle signature, length, and release URL
- `assets/analytics-consent.js` Cloudflare Web Analytics token
- download links if the public GitHub repository changes

## Paths

- `/` product page
- `/download` app download page
- `/updates/appcast.xml` Sparkle feed path
- `/privacy` website and app privacy policy
- `/source` redirect to GitHub
- `/releases` release notes and verification links

Large artifacts do not live here. The signed `.dmg` is uploaded to GitHub
Releases. The optional OpenAI privacy filter model remains on the pinned
Hugging Face snapshot.
