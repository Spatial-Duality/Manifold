---
paths:
  - "Sources/ManifoldRuntime/**/*.swift"
  - "Sources/ManifoldXPC/**/*.swift"
  - "Sources/ManifoldAgent/**/*.swift"
  - "ManifoldApp/ManifoldApp/Models/**/*.swift"
  - "Resources/com.spatialduality.manifold.runtime.plist"
  - "Manifold.xcodeproj/project.pbxproj"
---

# Runtime and XPC Rules

- `ManifoldRuntime` is the only composition root for stores. Do not recreate the store graph in the app, CLI, or MCP server.
- The app is an XPC client. Prefer `AppRuntimeClient` changes over backsliding into direct runtime/database access.
- Connection state must be derived from real runtime responses, not heuristics, remembered agent focus, or optimistic guesses.
- LaunchAgent and XPC lifecycle bugs are product-critical because they break core trust flows like adding folders and showing status.
- When changing registration, startup, or bundle structure, verify both build success and actual runtime behavior.
- Be explicit about fallback behavior in dev builds versus installed builds.
