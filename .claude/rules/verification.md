# Verification Rules

- For any non-trivial code change, run the narrowest meaningful verification and report exactly what ran.
- For app-facing changes, include an `xcodebuild` verification pass, not just `swift build`.
- For runtime/package changes, run `swift build` and `swift test` unless the task is explicitly documentation-only.
- If a user-reported bug involves startup, launchd, XPC, folder access, or runtime connection state, verify the real behavior path instead of stopping at compilation.
- If you cannot verify something locally, say that plainly and explain what remains uncertain.
