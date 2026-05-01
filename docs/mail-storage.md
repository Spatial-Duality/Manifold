# Mail Storage

Canonical mail storage is encrypted and local to the Mac.

Fresh-start mail migrations purge old mail rows and legacy backup state. Newly synced canonical messages are written only as archive v2 objects:

- encrypted canonical RFC822 message blobs;
- encrypted extracted attachment blobs;
- keyed content IDs rather than raw plaintext hashes;
- manifests authenticated with blob metadata;
- staging and startup reconciliation for crash safety.

Readable `.eml` files and attachment folders should only be created through explicit export. Encrypted archive objects must not be presented as ordinary readable EML files.

`EmailSyncEngine.readStoredMessage` still has a legacy encrypted-EML fallback for tests and developer safety, but legacy storage is not a supported production path for new sync.

Private index mode must not retain plaintext body text, subjects, snippets, sender names, or attachment text in SQLite. New body search terms are stored in `mail_private_terms` as account-local HMAC tokens derived from the archive root key. Plaintext FTS is only for explicit `plaintextFTSWithDisclosure` accounts.
