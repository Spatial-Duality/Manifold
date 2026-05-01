# Files, Folders, and Email Feature Map

This document maps the current SwiftUI implementation for Manifold's file,
folder, and email governance surfaces.

## Domain Overview

```mermaid
flowchart TD
    A["ManifoldStore"] --> B["AccessView"]
    A --> C["MailView"]

    B --> B1["FoldersMatrixView"]
    B --> B2["FilesFlatView"]
    B --> B3["SessionDiffView"]
    B --> B4["AccessHistoryView"]
    B --> B5["AccessMemoryView"]

    C --> C1["MailReviewView"]
    C1 --> C2["MailScopeRail"]
    C1 --> C3["MailReviewTableArea"]
    C1 --> C4["ThreadInspector"]

    A --> D["RuntimeClientProtocol"]
    D --> D1["Sources"]
    D --> D2["Agent access policies"]
    D --> D3["File visibility overrides"]
    D --> D4["Email sharing state"]
    D --> D5["Snapshots and exposures"]
```

At a high level:

- **Folders** control default source scope per AI.
- **Files** control explicit per-file allow or deny overrides inside those sources.
- **Email** controls per-message visibility inside backed-up mail.
- **Agents** are rendered through shared metadata and controls: `AgentMeta`, `AccessChipStack`, and `AccessCheckboxStrip`.

## Shared Access Model

```mermaid
flowchart LR
    A["Connected agents"] --> B["AgentMeta.connected(from:)"]
    B --> C["Claude / Codex rows, columns, chips"]

    D["Source policy allowedSourceIDs"] --> E["Default visibility"]
    F["FileVisibilityOverrideRecord"] --> G["Explicit file visibility"]
    E --> H["FileVisibilityResolver.evaluate"]
    G --> H
    H --> I["Visible / hidden"]
    H --> J["Inherited / explicit origin"]

    I --> K["AccessChipStack"]
    J --> L["Override underline / folder override dot"]
```

Visibility is layered:

| Layer | Scope | Meaning |
|---|---|---|
| Source policy | Folder/source | The folder is shared with an agent by default. |
| File override | File or subfolder | A specific file path is explicitly allowed or denied. |
| Resolver result | Effective file state | Combines the source default with overrides. |
| Origin | UI explanation | Indicates whether state is inherited or explicit. |

## Folders

```mermaid
flowchart TD
    A["AccessView: Folders tab"] --> B["FoldersMatrixView"]
    B --> C["Search folders"]
    B --> D["Folder table"]
    B --> E["Bulk bar"]
    B --> F["FileTreeInspector"]

    D --> D1["Folder column"]
    D1 --> D1a["Display name"]
    D1 --> D1b["Original path"]
    D1 --> D1c["Removed / Offline health pill"]
    D1 --> D1d["Drift badge"]

    D --> D2["Both / All column when multi-agent"]
    D --> D3["Per-agent checkbox columns"]
    D --> D4["Access chip fallback for many agents"]
    D --> D5["Sharing status column"]

    D5 --> D5a["Not shared"]
    D5 --> D5b["Shared with Claude/Codex"]
    D5 --> D5c["Partly shared"]
    D5 --> D5d["Shared with all"]
    D5 --> D5e["Dot when file overrides exist"]

    F --> F1["Folder header"]
    F --> F2["Per-agent sharing strip"]
    F --> F3["Agent picker when multiple agents"]
    F --> F4["Truncated file tree"]
    F4 --> F5["Allow / hide / reset node overrides"]
```

Folder features:

- Add folders from the toolbar, empty state, Finder request file, or drag and drop.
- Toggle folder default access per connected AI.
- Toggle all agents through the `Both`/`All` control.
- Search and sort folder rows.
- Multi-select folders for bulk share, bulk unshare, or remove.
- Show sharing state in plain English rather than relying only on color.
- Show source health inline with the folder name.
- Show drift counts for files changed since an agent's last session.
- Inspect files inside a selected folder and write file-level overrides.
- Surface explicit file overrides back to the folder row with a small dot.
- Mark deeper tree levels as truncated with “More items not shown”; the Files tab is the full-depth management surface.

## Folder Add and Drop Flow

```mermaid
flowchart TD
    A["User adds content"] --> B{"Input type"}

    B -->|"Folder picker"| C["chooseSourcePathsFromPicker"]
    C --> D["addSource(path:)"]

    B -->|"Folder drop"| E["manifoldFileDropTarget"]
    E --> F["addSourceFromURL(folder)"]

    B -->|"File picker"| G["chooseFilePathsFromPicker"]
    G --> H["addSourceForSingleFile(file)"]

    B -->|"File drop"| I["Confirmation dialog"]
    I -->|"Add whole folder"| J["addSourceFromURL(file parent)"]
    I -->|"Add only this file"| H

    H --> K["Add containing folder"]
    K --> L["Scope folder for connected agents"]
    L --> M["Deny existing top-level file siblings"]
```

Single-file adds are folder-backed because the runtime tracks sources at folder
granularity. The UI preserves user intent by adding explicit deny overrides for
existing sibling files when the user chooses a single file.

## Files

```mermaid
flowchart TD
    A["AccessView: Files tab"] --> B["FilesFlatView"]

    B --> C["Progressive source file enumeration"]
    C --> D["files state"]

    B --> E["Toolbar"]
    E --> E1["Scope filter menu"]
    E --> E2["Smart Views menu"]
    E --> E3["Visible count"]

    B --> F["Search"]
    B --> G["Table"]
    G --> G1["Access chip stack"]
    G --> G2["Name + type icon"]
    G --> G3["AI-touched sparkle"]
    G --> G4["Kind"]
    G --> G5["Path"]
    G --> G6["Source"]
    G --> G7["Size"]
    G --> G8["Modified"]
    G --> G9["Versions"]

    B --> H["Selection"]
    H --> H1["Bulk bar"]
    H --> H2["Context menu"]
    H --> H3["FileInspectorPane"]

    H3 --> I["Quick Look preview"]
    H3 --> J["Sharing selector"]
    H3 --> K["Audit exposure summary"]
    H3 --> L["Open / Reveal"]
    H3 --> M["Metadata"]
    H3 --> N["Version timeline"]
```

File features:

- Enumerate files progressively across active, accessible sources.
- Filter by all, shared, unshared, shared with a specific agent, allowed overrides, hidden overrides, changed, and AI-touched.
- Save and recall Smart Views as stored combinations of scope filter and search text.
- Search by file name, relative path, or source name.
- Sort by table columns.
- Toggle access inline per agent via `AccessChipStack`.
- Show explicit override status through effective visibility calculation.
- Mark AI-touched files with a sparkle indicator.
- Open files with the default app through primary action, context menu, or inspector.
- Quick Look selected files.
- Reveal selected files in Finder.
- Copy file paths.
- Bulk share, bulk unshare, or reset overrides across selected files.
- Inspect one file with preview, sharing controls, audit summary, metadata, and versions.
- Inspect many files with an aggregate selection summary.

## File Visibility Flow

```mermaid
flowchart LR
    A["SourceFile"] --> B["sourceID + relativePath"]
    C["Agent policy allowedSourceIDs"] --> D["defaultVisible"]
    E["Overrides for agent"] --> F["FileVisibilityResolver"]
    B --> F
    D --> F

    F --> G{"Evaluation origin"}
    G -->|"inheritedAllow"| H["Visible"]
    G -->|"explicitAllow"| H
    G -->|"inheritedHidden"| I["Hidden"]
    G -->|"explicitDeny"| I

    H --> J["Filled access chip"]
    I --> K["Hollow access chip"]
    G --> L["Explicit underline or reset control"]
```

## Email

```mermaid
flowchart TD
    A["MailView"] --> B{"Mail accounts loaded?"}
    B -->|"No"| C["Progress view"]
    B -->|"Loaded, no accounts"| D["EmptyMailView"]
    B -->|"Loaded, has accounts"| E["MailReviewView"]

    E --> F["MailScopeRail"]
    F --> F1["Accounts"]
    F --> F2["Mailboxes"]
    F --> F3["Quick filters"]

    E --> G["ThreadToolbar"]
    G --> G1["Search sender/subject/preview"]
    G --> G2["Selected account + mailbox"]
    G --> G3["Sync now"]
    G --> G4["Inspector toggle"]
    G --> G5["Summary line"]

    E --> H["MailReviewTableArea"]
    H --> H1["Loading/error/empty states"]
    H --> H2["Sync staleness banner"]
    H --> H3["Message table"]

    H3 --> I["Share chips"]
    H3 --> J["Sender"]
    H3 --> K["Subject + preview"]
    H3 --> L["Mailbox"]
    H3 --> M["Received"]
    H3 --> N["Attachments"]

    E --> O["ThreadInspector"]
    O --> O1["Subject and sender"]
    O --> O2["Visibility chip"]
    O --> O3["Per-agent sharing strip"]
    O --> O4["Received/account/mailbox metadata"]
    O --> O5["Scrollable safe message body"]
    O --> O6["Open original .eml in Mail"]
    O --> O7["Conversation context"]
```

Email features:

- Load backed-up mail accounts before rendering the review surface.
- Show an empty mail state when no accounts are configured.
- Browse backed-up mail by account and mailbox.
- Apply quick filters.
- Search sender, subject, or preview text with debounced reload.
- Sync the selected account.
- Show stale or paused backup state.
- Sort message rows.
- Toggle per-message sharing per connected AI.
- Use the same `AccessChipStack` pattern as file rows.
- Open the inspector by selecting/double-clicking a message or using the toolbar toggle.
- Show a scrollable message excerpt, falling back to preview text when body extraction is unavailable.
- Keep readable `.eml` creation behind explicit export.
- Show conversation context and per-message visibility.

## Email State Flow

```mermaid
flowchart LR
    A["MailAccountsModel"] --> B["Accounts"]
    A --> C["Mailboxes"]
    A --> D["Sync states"]

    B --> E["MailReviewModel.prepare"]
    C --> E
    E --> F["selectedAccountID"]
    E --> G["selectedMailboxName"]
    E --> H["messages"]

    I["Connected agents"] --> J["setConnectedAgents"]
    J --> K["refreshSharedState"]
    K --> L["sharedEmailIDsByAgent"]

    H --> M["MailReviewRow"]
    L --> M
    M --> N["Share chips in table"]
    M --> O["ThreadInspector sharing strip"]
```

Email sharing is per message. A thread is displayed as conversation context, but
the current review table and inspector operate on individual `emailID` values
when sharing or hiding.

## Cross-Surface Controls

```mermaid
flowchart TD
    A["Row-level fast controls"] --> A1["AccessChipStack"]
    A1 --> A2["Compact, icon-sized, per-agent"]
    A1 --> A3["Used by Files and Mail"]

    B["Inspector controls"] --> B1["AccessCheckboxStrip"]
    B1 --> B2["Labelled per-agent controls"]
    B1 --> B3["All/Both control when multi-agent"]
    B1 --> B4["Used by file and folder inspectors, plus mail inspector"]

    C["Bulk controls"] --> C1["Selection-driven bars"]
    C1 --> C2["Share with all / agent"]
    C1 --> C3["Unshare or hide from all / agent"]
    C1 --> C4["Reset overrides where applicable"]
```

## Feature Matrix

| Capability | Folders | Files | Email |
|---|---:|---:|---:|
| Add from picker | Yes | Yes, as single-file scoped parent source | No, mail setup path only |
| Drag/drop add | Yes | Yes, through shared drop target | Not implemented in current SwiftUI surface |
| Search | Folder name/path | File name/path/source | Sender/subject/preview |
| Sort | Table columns | Table columns | Table columns |
| Per-agent row toggle | Yes | Yes | Yes |
| All/Both toggle | Yes | Bulk/inspector | Inspector/context actions |
| Bulk actions | Share/unshare/remove | Share/hide/reset | Context actions, not bulk bar |
| Explicit overrides | File overrides flagged at folder level | File allow/deny overrides | Message shared/unshared state |
| Inspector | File tree | File preview/audit/versions | Message metadata/body/context |
| Smart Views | Not implemented | Implemented | Not implemented |
| AI-touched indicator | Drift badge by source | Sparkle/filter | Not implemented |
| Open externally | Reveal/copy from tree context | Open, Quick Look, Reveal | Open original `.eml` |

## Primary Code Map

| Area | Primary files |
|---|---|
| Access shell | `ManifoldApp/ManifoldApp/Views/Access/AccessWindowView.swift` |
| Folder matrix | `ManifoldApp/ManifoldApp/Views/Access/FoldersMatrixView.swift` |
| Folder inspector | `ManifoldApp/ManifoldApp/Views/Access/FileTreeInspector.swift` |
| File list | `ManifoldApp/ManifoldApp/Views/Access/FilesFlatView.swift` |
| File inspector | `ManifoldApp/ManifoldApp/Views/Access/FileInspectorPane.swift` |
| Drop target | `ManifoldApp/ManifoldApp/Components/Primitives/FileDropTarget.swift` |
| Shared access controls | `ManifoldApp/ManifoldApp/Components/Primitives/AccessChipStack.swift` |
| Store methods | `ManifoldApp/ManifoldApp/Models/ManifoldStore.swift` |
| Mail shell | `ManifoldApp/ManifoldApp/Views/Mail/MailWindowView.swift` |
| Mail review | `ManifoldApp/ManifoldApp/Views/Mail/ThreadsView.swift` |
| Mail state | `ManifoldApp/ManifoldApp/Models/EmailSelectionModel.swift` |
