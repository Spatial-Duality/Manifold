# Mail Authentication

Manifold Mail is local-first and read-only. The app connects directly from the user's Mac to the mail provider and stores secrets in macOS Keychain.

Provider defaults:

- Gmail: app-password IMAP at `imap.gmail.com:993`.
- Outlook / Microsoft 365: OAuth IMAP/XOAUTH2 at `outlook.office365.com:993` when Microsoft OAuth config is present.
- iCloud Mail: app-specific password IMAP at `imap.mail.me.com:993`.
- Yahoo Mail: app-password IMAP at `imap.mail.yahoo.com:993`.
- Fastmail: app-password IMAP at `imap.fastmail.com:993`.
- Other IMAP: manual host, port, TLS, username, and password/app password.

Gmail OAuth is not a normal v1 path because public Gmail mail scopes create verification and assessment obligations that do not fit Manifold's no-budget open-source constraint.

Manifold must not send, delete, move, archive, or mark mail as read on the provider.
