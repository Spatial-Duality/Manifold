# TODOS

## .manifoldignore support
**What:** Gitignore-style exclusion file per source folder, filtering paths from materialization and MCP tools.
**Why:** Users who add large folders (~/Documents, ~/Desktop) need per-path exclusion, not just all-or-nothing pause/resume.
**Context:** MaterializationEngine currently copies everything. ManifoldBridge listFiles/searchFiles enumerate everything. A .manifoldignore at the source root would exclude matching paths from both. Use gitignore syntax (fnmatch patterns, negation with !).
**Files:** MaterializationEngine.swift (skip during copy), ManifoldBridge.swift (filter from listFiles/searchFiles), GrantStore.swift (store exclusion patterns per source).
**Depends on:** Nothing. Can be built independently.

## Materialization cleanup on session end
**What:** Delete the /tmp/manifold-grant-{id}/ directory after successful promotion.
**Why:** Each session leaves a full copy of source files in /tmp. 5 sessions x 2GB source = 10GB orphaned. macOS cleans /tmp on reboot but not proactively.
**Context:** endSession() calls PromoteEngine.promote() but never cleans up. Add `try? FileManager.default.removeItem(at: matRootURL)` after all promotions are recorded. Safety check: verify all grantSources were promoted before deleting.
**Files:** ManifoldStore.swift (endSession method).
**Depends on:** Nothing. Can be built independently.

## Pre-session preview
**What:** Before materializing, show the user: file count per source, total size, email count, and a "Start" confirmation.
**Why:** Users should see what the agent will access before granting it. Connects to the size guard (warn above 5GB). The product review flagged this as the #3 priority.
**Context:** Currently startSession() materializes immediately with no preview. Add a pre-session state to ManifoldStore that computes the preview, shows it in DashboardView, and waits for user confirmation before materializing.
**Files:** ManifoldStore.swift (pre-session state), DashboardView.swift (preview UI), MaterializationEngine.swift (size estimation method).
**Depends on:** Size guard (Issue 3A from eng review).

## Wire domain presets into session behavior
**What:** DomainPreset.emailSensitivity and summaryFraming are defined but ignored by startSession(). The user picks "Legal Review" and the session behaves identically to "General."
**Why:** UI promises behavior it doesn't deliver. Users will notice when "strict" email sensitivity doesn't filter differently than "moderate."
**Context:** DomainPreset.swift defines 6 presets with emailSensitivity (strict/moderate/open) and summaryFraming. ManifoldStore.selectedPreset holds the selection. startSession() needs to: (1) pass emailSensitivity to EmailFilter's classification threshold, (2) use summaryFraming as the prefix in generateSessionSummary(). PresetPickerView.swift in HomeView already shows the selection.
**Files:** ManifoldStore.swift (startSession, generateSessionSummary), EmailFilter.swift (classification threshold), DomainPreset.swift (data model).
**Depends on:** Nothing. Can be built independently.
