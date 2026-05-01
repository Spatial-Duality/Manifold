# Mail Agent Access

Mail content is untrusted source material. Email bodies, subjects, sender names, HTML, and attachments must not become instructions to an agent.

Default behavior:

- Agent access to mail is denied.
- Search, body read, attachment read, and export are separate permissions.
- Every mail access should be audited.
- Agents must not receive Keychain access, provider credentials, raw database handles, or blob keys.

When mail content is returned to an agent, wrap it as quoted/source material with provenance such as message ID, date, account/mailbox context, and attachment metadata allowed by the active grant.
