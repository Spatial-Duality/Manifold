# Developer OAuth Config

Microsoft mail uses OAuth IMAP/XOAUTH2. Native public clients do not use a client secret.

Official builds may include a free public Microsoft client ID. Forks and developer builds can provide local config with either environment variables or an ignored plist.

Environment variables:

- `MANIFOLD_MICROSOFT_CLIENT_ID`
- `MANIFOLD_MICROSOFT_REDIRECT_URI`
- `MANIFOLD_MICROSOFT_CALLBACK_SCHEME`

Ignored plist name:

`ManifoldLocalAuthConfig.plist`

Supported keys:

- `MicrosoftClientID`
- `MicrosoftRedirectURI`
- `MicrosoftCallbackScheme`
- `GoogleClientID`
- `GoogleRedirectURI`

Gmail OAuth is advanced-only and should stay hidden from normal users. Gmail users should use app-password IMAP in v1.
