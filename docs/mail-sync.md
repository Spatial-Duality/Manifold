# Mail Sync

Manifold Mail sync is read-only. The IMAP layer should use `EXAMINE` and `BODY.PEEK` so fetching messages does not mark them as read.

Allowed protocol behavior:

- Discover capabilities and mailboxes.
- Fetch message metadata and RFC822 bytes.
- Maintain local sync cursors.
- Mark remote disappearance as local tombstones.
- Keep local encrypted backups until the user explicitly purges or removes the archive.

Disallowed protocol behavior:

- `STORE`, `UID STORE`, `APPEND`, `COPY`, `MOVE`, `EXPUNGE`, `CLOSE`, `CREATE`, `DELETE`, `RENAME`, `SUBSCRIBE`, `UNSUBSCRIBE`, `CHECK`.
- Any body fetch that is not `BODY.PEEK`.

Runtime startup registers every enabled account with `MailSyncCoordinator`. Account setup, sync toggles, manual sync, and startup all use durable `mail_sync_jobs` instead of ad hoc periodic loops.

Initial sync uses a recent-first pass: priority mailboxes fetch the newest messages first, advance the incremental high-water mark for new mail, and enqueue per-mailbox historical backfill jobs when older UIDs remain. Historical backfill fetches older UID ranges from stored mailbox membership and does not move the incremental high-water mark.

Incremental jobs fetch UIDs above the stored high-water mark. Reconciliation jobs and incremental sync mark missing server UIDs as tombstones; local archive blobs remain until explicit purge, retention policy, or account deletion with archive removal.

New sync writes fetched RFC822 bytes to archive v2 before recording the message row and sync cursor. The DB stores the archive manifest path and `canonical_blob_cid`; legacy encrypted EML fallback exists only for tests/developer safety.

Default private-index accounts should index extracted body text through HMAC tokens only. Do not call plaintext FTS/body backfill unless the account has opted into `plaintextFTSWithDisclosure`.
