# Rule Creation Forms + Unified Sharing Control — Claude Code Implementation Prompt

> **What this is**: Implementation brief for two new interaction systems: (A) inline rule creation forms for Domain/Contact/Keyword rules in the Emails → Rules tab, and (B) a unified sharing popover that works identically for files, folders, and emails. Read this entire document before writing any code.
>
> **Reference files you MUST read first**:
> - `design/manifold-prototype.jsx` — The interactive React prototype. Find these new components: `AddDomainForm`, `AddContactForm`, `AddKeywordForm`, `SharePopover`, `ShareToolbarButton`, `AgentCheckboxSelector`, `ActionSegmented`, `RulePreview`. These are the visual source of truth.
> - `design/EMAIL-CONTROLS-SPEC.md` — Full spec for the rules engine (priority order, shield categories, rule semantics).
> - `design/DESIGN-STANDARDS.md` — Design tokens, component specs.
> - The existing implementation of `Views/Email/Rules/DomainRulesView.swift`, `ContactRulesView.swift`, `KeywordRulesView.swift` — you are ADDING creation forms to these views, not rewriting them.
> - `Views/ReviewAccessSheet.swift` — The green "what's changing" pattern you must replicate in the rule creation forms.
> - `Models/EmailRulesModel.swift` — Already has `DomainRule`, `ContactRule`, `KeywordRule`, `RuleAction`, `KeywordMatchLocation`, `TargetApp` etc.

---

## Existing Codebase Inventory

### Models Already Implemented (in `Models/EmailRulesModel.swift`)

These exist and are correct. **Do not recreate them.**

```swift
@Observable @MainActor
final class EmailRulesModel {
    var shields: [EmailShield]
    var domainRules: [DomainRule]
    var contactRules: [ContactRule]
    var keywordRules: [KeywordRule]
    var claudeDefaultPolicy: AgentDefaultPolicy
    var codexDefaultPolicy: AgentDefaultPolicy
}

struct DomainRule: Identifiable, Sendable {
    let id: UUID
    let domain: String
    var action: RuleAction          // .allow or .block
    let category: String            // "Work", "Financial", "Automated", "Personal"
    var agents: [TargetApp]
    let emailCount: Int
    var shieldOverlap: String?
}

struct ContactRule: Identifiable, Sendable {
    let id: UUID
    let name: String
    let email: String
    var action: RuleAction
    let overridesDescription: String
    var agents: [TargetApp]
}

struct KeywordRule: Identifiable, Sendable {
    let id: UUID
    let pattern: String
    let matchLocation: KeywordMatchLocation  // .subject, .subjectAndBody, .anywhere
    var action: RuleAction
    var matchedCount: Int
    var agents: [TargetApp]
    var isRegex: Bool
}

enum RuleAction: String, CaseIterable, Sendable { case allow, block }
enum KeywordMatchLocation: String, CaseIterable, Sendable { ... }
```

### Design Tokens Already Implemented (in `Components/DesignTokens.swift`)

- `Color.claudeBlue`, `Color.codexPurple`, `Color.statusActive`, `Color.statusDanger`, `Color.agent(_ type:)`
- `Typ.sectionTitle`, `Typ.heading`, `Typ.body`, `Typ.caption`, `Typ.mono`, `Typ.numericCaption`
- `Opacity.rowTint` (0.04), `Opacity.badgeFill` (0.12)
- `Anim.stateChange` (.snappy), `Anim.structural` (.spring), `Anim.entrance`
- Shadow extensions: `.cardElevation()`, `.popoverElevation()`

### Existing Components (use these, don't duplicate)

- `Badge.swift`, `StatusBadge.swift`, `AgentBadge.swift` — Pill badges
- `ColorIndicator.swift` — Status dots
- `AgentFocusControl.swift` — Claude | Codex | Compare segmented control
- `ReviewAccessSheet.swift` — Full-height sheet with green "what's changing" section. **Study this for the preview strip pattern.**

### Existing Rule Views (you're ADDING to these, not rewriting)

- `Views/Email/Rules/DomainRulesView.swift` — Has a Table of domain rules + empty "Add Domain" toolbar button
- `Views/Email/Rules/ContactRulesView.swift` — Has a Table of contact rules + empty "Add Contact" button
- `Views/Email/Rules/KeywordRulesView.swift` — Has a Table of keyword rules + empty "Add Pattern" button
- `Views/Email/Rules/EmailRulesView.swift` — Container with sidebar navigation

### Existing Sharing Views (you're REPLACING the old one)

- `Views/Email/ShareWithCowork/ShareWithCoworkSheet.swift` — OLD single-agent sharing sheet. Shows only a purple "Share with Cowork" button. Does NOT support per-agent toggles or Codex. **This will be replaced by the new SharePopover.**

---

## TASK 1: Shared Components (Create First)

**File to create**: `ManifoldApp/ManifoldApp/Components/RuleFormComponents.swift`

These are reusable building blocks shared by all three rule creation forms and the sharing popover.

### 1A: AgentCheckboxSelector

A horizontal row of agent checkboxes with colored squares. Used in every rule form to choose which agents a rule applies to.

```swift
/// Colored checkbox row for selecting which agents a rule applies to.
/// At least one agent must always be selected.
struct AgentCheckboxSelector: View {
    @Binding var selectedAgents: Set<TargetApp>
    
    var body: some View {
        HStack(spacing: 10) {
            agentCheckbox(.cowork, "Claude", Color.claudeBlue)
            agentCheckbox(.codex, "Codex", Color.codexPurple)
            
            Button("Both") {
                selectedAgents = [.cowork, .codex]
            }
            .font(.caption)
            .foregroundStyle(selectedAgents.count == 2 ? .primary : .tertiary)
            .buttonStyle(.plain)
        }
    }
    
    private func agentCheckbox(_ agent: TargetApp, _ label: String, _ color: Color) -> some View {
        // Colored square checkbox: filled with agent color when selected,
        // outlined when not. White checkmark inside when selected.
        // Use Toggle with custom ToggleStyle for accessibility.
        // Minimum tap target 16x16, label in Typ.body.
        // Prevent deselecting the last agent (at least one must remain).
    }
}
```

**Visual spec** (from prototype):
- 16×16pt rounded rectangle (cornerRadius: 4)
- Selected: filled with agent color, white checkmark SVG inside
- Deselected: 1.5pt border in `Color.secondary.opacity(0.3)`
- Label: 12pt, primary color when selected, secondary when not
- "Both" text button at right end, plain style

### 1B: ActionSegmented

Allow/Block segmented picker:

```swift
/// Allow / Block segmented picker for rule actions.
struct ActionSegmented: View {
    @Binding var action: RuleAction
    
    var body: some View {
        // macOS-native Picker with .segmented style
        // OR a custom segmented control matching the prototype:
        //   - Gray rounded background (rgba(0,0,0,0.05))
        //   - Two segments: "Allow" (green text when selected) and "Block" (red text when selected)
        //   - Selected segment has white background with subtle shadow
        //   - Use Anim.micro for transition
    }
}
```

**Recommendation**: Use `Picker("Action", selection: $action) { ... }.pickerStyle(.segmented)` and apply foreground color to the labels. If the native segmented control doesn't allow per-segment coloring, build a custom one with `HStack` + `Button` — but prefer native first.

### 1C: RulePreviewStrip

Green "what this will do" banner — the most important UI element in the creation forms. This is directly from the ReviewAccessSheet "what's changing" pattern.

```swift
/// Green-tinted preview strip showing the plain-English effect of a rule.
/// This is the user's confirmation that the rule does what they expect.
struct RulePreviewStrip: View {
    let text: String?
    
    var body: some View {
        if let text {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.statusActive)
                Text(text)
                    .font(.callout)
                    .foregroundStyle(Color(red: 0.18, green: 0.43, blue: 0.24))  // dark green
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.statusActive.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.statusActive.opacity(0.2), lineWidth: 1))
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}
```

**Visual spec**: Background `rgba(52,199,89,0.06)`, border `rgba(52,199,89,0.2)`, text color `#2d6e3e`, checkmark in `Color.statusActive`. Animate in with `Anim.entrance` when the rule becomes valid.

---

## TASK 2: Rule Creation Forms

**Design pattern**: Inline expanding forms. When the user clicks "Add Domain/Contact/Pattern", a form expands between the toolbar and the table. This keeps the existing rules visible for context. The form has input fields, action picker, agent selector, preview strip, and Cancel/Add buttons. Pressing Escape or Cancel closes the form. Pressing Enter (when valid) submits.

### Why inline, not a sheet/modal:

1. User can see existing rules while creating — no context loss
2. Faster flow: click Add → type → Enter → done. No modal dismissal.
3. Matches Little Snitch's inline rule creation in the connection alert dialog.
4. Follows macOS pattern of "form above table" seen in Calendar event creation, Reminders, etc.

### 2A: AddDomainRuleForm

**File to modify**: `Views/Email/Rules/DomainRulesView.swift`

Add `@State private var showAddForm = false` to `DomainRulesView`. Wire the existing toolbar "Add Domain" button to toggle `showAddForm`. When true, show `AddDomainRuleForm` between the toolbar and the Table.

```swift
struct AddDomainRuleForm: View {
    @Binding var isPresented: Bool
    @Bindable var rulesModel: EmailRulesModel
    
    @State private var domain = ""
    @State private var action: RuleAction = .block
    @State private var category = "Work"
    @State private var selectedAgents: Set<TargetApp> = [.cowork, .codex]
    @FocusState private var domainFieldFocused: Bool
    
    private var cleanDomain: String { domain.replacingOccurrences(of: "@", with: "").trimmingCharacters(in: .whitespaces) }
    private var isValid: Bool { cleanDomain.contains(".") && cleanDomain.count > 2 }
    
    private var previewText: String? {
        guard isValid else { return nil }
        let agentLabel = selectedAgents.count == 2 ? "both agents" :
            selectedAgents.contains(.cowork) ? "Claude" : "Codex"
        return action == .block
            ? "Block \(agentLabel) from seeing emails from @\(cleanDomain)"
            : "Allow \(agentLabel) to see emails from @\(cleanDomain)"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("New Domain Rule").font(Typ.heading).font(.system(size: 13))
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark").font(.caption).foregroundStyle(.tertiary)
                }.buttonStyle(.plain)
            }
            
            HStack(alignment: .top, spacing: 16) {
                // Domain input
                VStack(alignment: .leading, spacing: 3) {
                    Text("Domain").font(.caption).fontWeight(.semibold)
                    HStack(spacing: 4) {
                        Text("@").foregroundStyle(.secondary)
                        TextField("example.com", text: $domain)
                            .textFieldStyle(.plain)
                            .focused($domainFieldFocused)
                            .onSubmit { if isValid { addRule() } }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.white))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(
                        isValid ? Color.statusActive.opacity(0.4) :
                        domain.isEmpty ? Color.secondary.opacity(0.2) :
                        Color.statusDanger.opacity(0.3), lineWidth: 1
                    ))
                    Text("Use *.domain.com for subdomains")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                .frame(minWidth: 200)
                
                // Category picker
                VStack(alignment: .leading, spacing: 3) {
                    Text("Category").font(.caption).fontWeight(.semibold)
                    Picker("Category", selection: $category) {
                        ForEach(["Work", "Financial", "Automated", "Personal", "Other"], id: \.self) { Text($0) }
                    }.labelsHidden()
                }.frame(width: 120)
                
                // Action
                VStack(alignment: .leading, spacing: 3) {
                    Text("Action").font(.caption).fontWeight(.semibold)
                    ActionSegmented(action: $action)
                }
                
                // Agents
                VStack(alignment: .leading, spacing: 3) {
                    Text("Applies to").font(.caption).fontWeight(.semibold)
                    AgentCheckboxSelector(selectedAgents: $selectedAgents)
                }
            }
            
            // Green preview strip
            RulePreviewStrip(text: previewText)
                .animation(Anim.entrance, value: previewText != nil)
            
            // Actions
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Add Rule") { addRule() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .background(Color.accentColor.opacity(0.02))
        .onAppear { domainFieldFocused = true }
    }
    
    private func addRule() {
        let rule = DomainRule(
            id: UUID(), domain: cleanDomain, action: action,
            category: category, agents: Array(selectedAgents),
            emailCount: 0, shieldOverlap: nil
        )
        rulesModel.domainRules.append(rule)
        isPresented = false
    }
}
```

**Integration into DomainRulesView.swift**:

```swift
struct DomainRulesView: View {
    @Bindable var rulesModel: EmailRulesModel
    @State private var showAddForm = false    // ← ADD THIS

    var body: some View {
        VStack(spacing: 0) {
            // ← INSERT FORM HERE, between toolbar and table
            if showAddForm {
                AddDomainRuleForm(isPresented: $showAddForm, rulesModel: rulesModel)
                Divider()
            }
            
            if rulesModel.domainRules.isEmpty && !showAddForm {
                // existing empty state...
            } else {
                // existing Table...
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Domain", systemImage: "plus") {
                    withAnimation(Anim.structural) { showAddForm.toggle() }
                }
                .controlSize(.small)
            }
        }
    }
}
```

### 2B: AddContactRuleForm

**File to modify**: `Views/Email/Rules/ContactRulesView.swift`

Same pattern as domain form, but with different fields:

```swift
struct AddContactRuleForm: View {
    @Binding var isPresented: Bool
    @Bindable var rulesModel: EmailRulesModel
    
    @State private var name = ""
    @State private var email = ""
    @State private var action: RuleAction = .allow    // NOTE: default to allow for contacts
    @State private var selectedAgents: Set<TargetApp> = [.cowork, .codex]
    @FocusState private var nameFieldFocused: Bool
    
    // Email validation
    private var isValid: Bool { email.contains("@") && email.contains(".") }
    private var emailDomain: String { email.split(separator: "@").last.map(String.init) ?? "" }
    
    private var previewText: String? {
        guard isValid else { return nil }
        let agentLabel = selectedAgents.count == 2 ? "both agents" :
            selectedAgents.contains(.cowork) ? "Claude" : "Codex"
        let who = name.isEmpty ? email : name
        let domainNote = emailDomain.isEmpty ? "" : " — overrides any @\(emailDomain) domain rule or shield"
        return action == .allow
            ? "Allow \(agentLabel) to see emails from \(who)\(domainNote)"
            : "Block \(agentLabel) from seeing emails from \(who)\(domainNote)"
    }
    
    // Fields: Name (optional), Email (required), Action, Agents
    // Show explanatory text: "Contact rules are the most specific — they override domain rules and shields for this sender."
    // Green preview strip includes the domain override note
}
```

**Key differences from Domain form**:
- Default action is **allow** (contacts are usually exceptions to blocks)
- Name field is **optional** — label it "(optional)"
- Email input validates with `@` and `.`
- Preview text mentions what this overrides: "overrides any @domain.com domain rule or shield"
- Brief explanation text: "Contact rules are the most specific — they override domain rules and shields for this sender."

### 2C: AddKeywordRuleForm

**File to modify**: `Views/Email/Rules/KeywordRulesView.swift`

```swift
struct AddKeywordRuleForm: View {
    @Binding var isPresented: Bool
    @Bindable var rulesModel: EmailRulesModel
    
    @State private var pattern = ""
    @State private var matchIn: KeywordMatchLocation = .subjectAndBody
    @State private var action: RuleAction = .block
    @State private var isRegex = false
    @State private var selectedAgents: Set<TargetApp> = [.cowork, .codex]
    @FocusState private var patternFieldFocused: Bool
    
    private var isValid: Bool { !pattern.trimmingCharacters(in: .whitespaces).isEmpty }
    
    private var previewText: String? {
        guard isValid else { return nil }
        let agentLabel = selectedAgents.count == 2 ? "both agents" :
            selectedAgents.contains(.cowork) ? "Claude" : "Codex"
        let location = matchIn == .subject ? "in subject lines" :
            matchIn == .subjectAndBody ? "in subjects and bodies" : "anywhere"
        let regexNote = isRegex ? " (regex pattern)" : ""
        return "\(action == .block ? "Block" : "Flag") emails containing \"\(pattern)\" \(location) for \(agentLabel)\(regexNote)"
    }
    
    // Fields: Pattern input with inline REGEX toggle, Match Location picker, Action, Agents
    // Pattern input: monospace font when isRegex is true, normal font otherwise
    // Inline checkbox for "REGEX" with purple badge styling
    // Help text changes: "Case-insensitive text match" vs "Use | for alternation, \\b for word boundaries"
    // Placeholder changes: "confidential" vs "SSN|social\\s+security" based on regex mode
}
```

**Key differences**:
- Pattern input has an inline REGEX toggle (checkbox + purple "REGEX" badge label)
- When regex is on: monospace font in input, different placeholder, different help text
- Match Location uses `Picker` with `.menu` style for the three `KeywordMatchLocation` cases
- Default action is **block** (keywords are usually content filters)

---

## TASK 3: Unified Sharing Popover

**Files to create**: `ManifoldApp/ManifoldApp/Components/SharePopover.swift`
**Files to modify**: `Views/Email/MessageList/` (bulk share button), `Views/FilesView.swift` (row share action)
**File to retire**: `Views/Email/ShareWithCowork/ShareWithCoworkSheet.swift` — replace all usages with SharePopover

### Design Intent

The old `ShareWithCoworkSheet` is a modal that only supports one agent (Cowork/Claude) with a single "Share" button. The new SharePopover:

1. Shows **both agents simultaneously** with independent toggles
2. Shows a **change preview** (green strip when toggling)
3. Shows a **summary** ("Visible to Claude and Codex" or "Not visible to any agent")
4. Works for **all content types**: files, folders, and emails
5. Is a **popover**, not a modal — keeps context visible

### Why this matters (incentive logic)

The old single-agent "Share with Claude" button made it trivially easy to accidentally over-share: whatever agent was focused got the data, and the user never saw the *other* agent's status. The new popover forces a deliberate two-toggle decision. Both agents are visible simultaneously, so the user can see exactly what's shared with whom.

### SharePopover.swift

```swift
/// Unified sharing popover for files, folders, and emails.
/// Shows both agent toggles, summary, and change preview.
struct SharePopover<Content: View>: View {
    let itemType: String             // "file", "folder", "email"
    let itemLabel: String            // display name or "3 emails"
    let currentSharing: AgentSharing // current state
    let onApply: (AgentSharing) -> Void
    @ViewBuilder let anchor: () -> Content
    
    @State private var isPresented = false
    @State private var claude: Bool
    @State private var codex: Bool
    
    struct AgentSharing {
        var claude: Bool
        var codex: Bool
    }
    
    init(itemType: String, itemLabel: String, currentSharing: AgentSharing, onApply: @escaping (AgentSharing) -> Void, @ViewBuilder anchor: @escaping () -> Content) {
        self.itemType = itemType
        self.itemLabel = itemLabel
        self.currentSharing = currentSharing
        self.onApply = onApply
        self.anchor = anchor
        _claude = State(initialValue: currentSharing.claude)
        _codex = State(initialValue: currentSharing.codex)
    }
    
    private var hasChanges: Bool {
        claude != currentSharing.claude || codex != currentSharing.codex
    }
    
    private var summary: String {
        if !claude && !codex { return "Not visible to any agent" }
        let names = [claude ? "Claude" : nil, codex ? "Codex" : nil].compactMap { $0 }
        return "Visible to \(names.joined(separator: " and "))"
    }
    
    private var changeDescription: String? {
        guard hasChanges else { return nil }
        var parts: [String] = []
        if claude != currentSharing.claude {
            parts.append(claude ? "share with Claude" : "unshare from Claude")
        }
        if codex != currentSharing.codex {
            parts.append(codex ? "share with Codex" : "unshare from Codex")
        }
        return "Will " + parts.joined(separator: " and ")
    }
    
    var body: some View {
        anchor()
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Text("Share \(itemLabel)").font(Typ.heading).font(.system(size: 12))
                        Spacer()
                        Button { isPresented = false } label: {
                            Image(systemName: "xmark").font(.caption).foregroundStyle(.tertiary)
                        }.buttonStyle(.plain)
                    }
                    .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 8)
                    
                    Divider()
                    
                    // Agent toggles
                    VStack(spacing: 0) {
                        agentRow("Claude", Color.claudeBlue, $claude)
                        agentRow("Codex", Color.codexPurple, $codex)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    
                    // Summary
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.04))
                    
                    // Change preview (green strip)
                    if let change = changeDescription {
                        Text(change)
                            .font(.caption)
                            .foregroundStyle(Color(red: 0.18, green: 0.43, blue: 0.24))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(Color.statusActive.opacity(0.06))
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    
                    Divider()
                    
                    // Actions
                    HStack {
                        Spacer()
                        Button("Cancel") { isPresented = false }
                        Button("Apply") {
                            onApply(AgentSharing(claude: claude, codex: codex))
                            isPresented = false
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!hasChanges)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                }
                .frame(width: 280)
            }
            .onTapGesture { isPresented.toggle() }
    }
    
    private func agentRow(_ name: String, _ color: Color, _ isOn: Binding<Bool>) -> some View {
        HStack {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(name).font(.callout).fontWeight(.medium)
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .tint(color)
                .labelsHidden()
        }
        .padding(.vertical, 6)
    }
}
```

### Integration Points

**1. Email bulk actions (Messages toolbar)**

In `MessageFilterBar.swift` or wherever the bulk action bar lives, replace the old "Share with [Agent]" button:

```swift
// OLD:
Button("Share with \(agentName)") { ... }

// NEW:
SharePopover(
    itemType: "email",
    itemLabel: "\(selectedCount) emails",
    currentSharing: .init(claude: false, codex: false),
    onApply: { sharing in
        // Call store method to update sharing for selected email IDs
        Task {
            await store.updateEmailSharing(ids: selectedIDs, claude: sharing.claude, codex: sharing.codex)
        }
    }
) {
    Label("Share…", systemImage: "shield")
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.claudeBlue.opacity(Opacity.badgeFill))
        .foregroundStyle(Color.claudeBlue)
        .clipShape(RoundedRectangle(cornerRadius: 5))
}
```

**2. Email inline preview (single message)**

In the inline message preview panel (InlineMessagePreview.swift or similar), replace the "Share with Claude"/"Shared with Claude" badge:

```swift
SharePopover(
    itemType: "email",
    itemLabel: message.senderName,
    currentSharing: .init(
        claude: message.sharedWith == .cowork,
        codex: message.sharedWith == .codex
    ),
    onApply: { sharing in
        Task { await store.updateEmailSharing(ids: [message.id], claude: sharing.claude, codex: sharing.codex) }
    }
) {
    Label("Share…", systemImage: "shield")
        // ... button styling
}
```

**3. Files source table (folder-level sharing)**

In `SourcesTableView.swift`, add a share button or make the existing checkboxes use SharePopover for the Compare mode where both agents are shown:

```swift
// In the source row, replace the plain checkbox with a popover for Compare mode:
SharePopover(
    itemType: "folder",
    itemLabel: source.name,
    currentSharing: .init(
        claude: store.policy.isSourceAllowed(source.id, for: .cowork),
        codex: store.policy.isSourceAllowed(source.id, for: .codex)
    ),
    onApply: { sharing in
        Task { await store.updateSourceSharing(sourceID: source.id, claude: sharing.claude, codex: sharing.codex) }
    }
) {
    // Inline dots showing current sharing state
    HStack(spacing: 3) {
        if store.policy.isSourceAllowed(source.id, for: .cowork) {
            Circle().fill(Color.claudeBlue).frame(width: 7, height: 7)
        }
        if store.policy.isSourceAllowed(source.id, for: .codex) {
            Circle().fill(Color.codexPurple).frame(width: 7, height: 7)
        }
    }
}
```

**4. Files table (individual file sharing)**

In the file table row, make the "Shared" column dot clickable:

```swift
// In the Shared column of the file Table:
SharePopover(
    itemType: "file",
    itemLabel: file.name,
    currentSharing: .init(
        claude: file.sharedWith == .cowork,
        codex: file.sharedWith == .codex
    ),
    onApply: { sharing in
        Task { await store.updateFileSharing(fileID: file.id, claude: sharing.claude, codex: sharing.codex) }
    }
) {
    // Current sharing dots, or "—" if not shared
    // Clickable — cursor changes to pointer
}
```

---

## TASK 4: Add Methods to EmailRulesModel

The creation forms need methods on `EmailRulesModel` to add rules. These are simple since the model already has the arrays:

```swift
extension EmailRulesModel {
    func addDomainRule(domain: String, action: RuleAction, category: String, agents: [TargetApp]) {
        let rule = DomainRule(
            id: UUID(), domain: domain, action: action,
            category: category, agents: agents,
            emailCount: 0, shieldOverlap: nil
        )
        domainRules.append(rule)
    }
    
    func addContactRule(name: String, email: String, action: RuleAction, agents: [TargetApp]) {
        let emailDomain = email.split(separator: "@").last.map(String.init) ?? ""
        let existingDomainRule = domainRules.first { $0.domain == emailDomain }
        let overridesDesc = existingDomainRule != nil
            ? "\(emailDomain) domain (\(existingDomainRule!.action.rawValue)) → \(action.rawValue) for this contact"
            : "No existing domain or shield override"
        let rule = ContactRule(
            id: UUID(), name: name, email: email,
            action: action, overridesDescription: overridesDesc,
            agents: agents
        )
        contactRules.append(rule)
    }
    
    func addKeywordRule(pattern: String, matchLocation: KeywordMatchLocation, action: RuleAction, agents: [TargetApp], isRegex: Bool) {
        let rule = KeywordRule(
            id: UUID(), pattern: pattern,
            matchLocation: matchLocation, action: action,
            matchedCount: 0, agents: agents, isRegex: isRegex
        )
        keywordRules.append(rule)
    }
    
    func removeDomainRule(id: UUID) { domainRules.removeAll { $0.id == id } }
    func removeContactRule(id: UUID) { contactRules.removeAll { $0.id == id } }
    func removeKeywordRule(id: UUID) { keywordRules.removeAll { $0.id == id } }
}
```

---

## TASK 5: Context Menu Integration

Add right-click context menus for editing/deleting existing rules, and for the share action on files/emails.

### Rule table context menus

On each rule row in the Domain/Contact/Keyword tables, add:

```swift
.contextMenu {
    Button("Edit Rule…") { /* Open edit form — reuse creation form with pre-filled values */ }
    Divider()
    Button("Delete Rule", role: .destructive) { rulesModel.removeDomainRule(id: rule.id) }
}
```

### File/email row context menus

On file table rows and email table rows, add:

```swift
.contextMenu {
    // Share submenu
    Menu("Share with…") {
        Button { /* toggle Claude sharing */ } label: {
            Label("Claude", systemImage: file.sharedWithClaude ? "checkmark.circle.fill" : "circle")
        }
        Button { /* toggle Codex sharing */ } label: {
            Label("Codex", systemImage: file.sharedWithCodex ? "checkmark.circle.fill" : "circle")
        }
        Divider()
        Button("Both Agents") { /* share with both */ }
        Button("Remove Sharing", role: .destructive) { /* unshare from all */ }
    }
}
```

This gives users TWO paths to the same action: the SharePopover (click the share column) and the context menu (right-click the row). Same mental model, different access patterns.

---

## Layout Reference

### Rule Creation Form (expands inline above table)

```
┌─────────────────────────────────────────────────────────────┐
│ Domain Rules                    12 rules    [+ Add Domain]  │
├─────────────────────────────────────────────────────────────┤
│ New Domain Rule                                         [✕] │
│                                                             │
│ Domain          Category     Action         Applies to      │
│ [@example.com]  [Work ▾]    [Allow|Block]   ☑ Claude       │
│ Use *.domain... │                           ☑ Codex  Both  │
│                                                             │
│ ┌─ ✓ Block both agents from seeing emails from @example.com │
│ └───────────────────────────────────────────────────────────│
│                                    [Cancel] [Add Rule]      │
├─────────────────────────────────────────────────────────────┤
│ ☐  Domain           Category  Emails  Rule   Agents         │
│ ────────────────────────────────────────────────────────────│
│    @github.com      Work       412   Allow    ●●            │
│    @linear.app      Work        89   Allow    ●             │
│    ...                                                      │
└─────────────────────────────────────────────────────────────┘
```

### Share Popover (attached to button/dot)

```
         ┌──────────────────────────┐
         │ Share 3 emails       [✕] │
         ├──────────────────────────┤
         │ ● Claude          [═══⦿] │
         │ ● Codex           [⦿═══] │
         ├──────────────────────────┤
         │ Visible to Claude        │
         ├──────────────────────────┤
         │ Will share with Claude   │  ← green, only when changed
         │ and unshare from Codex   │
         ├──────────────────────────┤
         │              [Cancel] [Apply] │
         └──────────────────────────┘
```

---

## Implementation Order

1. **Task 1** (Shared components) — build `AgentCheckboxSelector`, `ActionSegmented`, `RulePreviewStrip` first. These are used by everything else.
2. **Task 4** (Model methods) — add `addDomainRule`/`addContactRule`/`addKeywordRule`/`remove*` to `EmailRulesModel`.
3. **Task 2** (Rule creation forms) — Domain form first (simplest), then Contact, then Keyword. Each one integrates into its existing view.
4. **Task 3** (SharePopover) — build the component, then integrate into email bulk actions, email preview, file source rows, file table rows.
5. **Task 5** (Context menus) — add right-click menus last, these are the easiest.

Run `xcodebuild` after each task:

```bash
env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/swiftpm-module-cache xcodebuild -project Manifold.xcodeproj -scheme Manifold -configuration Debug -derivedDataPath /tmp/manifold-derived-data build CODE_SIGNING_ALLOWED=NO
```

---

## Keyboard Support Requirements

These are pro macOS patterns — keyboard support is not optional:

- **⌘N** in any Rules view opens the creation form for that rule type
- **Escape** closes the form without saving
- **Return/Enter** submits the form when valid (disabled state prevents submission)
- **Tab** moves between form fields in logical order
- **⌘Delete** on a selected rule row deletes it (with confirmation)
- The domain/email/pattern input field auto-focuses when the form opens (`@FocusState`)

---

## What NOT to Do

- Don't create modal sheets for rule creation. Use inline expanding forms.
- Don't create a new design token file. `DesignTokens.swift` has everything you need.
- Don't break the existing Table views. You're adding forms ABOVE the tables, not replacing them.
- Don't remove the old `ShareWithCoworkSheet.swift` until SharePopover is fully working everywhere.
- Don't fake rule creation — wire it to `EmailRulesModel` so the table updates immediately via `@Observable`.
- Don't use `.easeInOut` or custom animations. Use `Anim.structural` for form expansion and `Anim.entrance` for the preview strip.
- Don't push rule evaluation logic onto `@MainActor`. The forms themselves are UI, but any future matching engine should be async.
- Don't add Liquid Glass manually — use standard SwiftUI `.popover()` for SharePopover and the framework handles glass.

---

## Verification Checklist

After implementing, verify these interactions work:

1. [ ] Click "Add Domain" → form expands inline → type "github.com" → green preview appears → click "Add Rule" → rule appears in table → form closes
2. [ ] Click "Add Contact" → type email "sarah@figma.com" → preview mentions "@figma.com domain override" → "Add Rule" creates contact rule
3. [ ] Click "Add Pattern" → toggle REGEX on → font changes to monospace → type pattern → preview shows "(regex pattern)" → creates keyword rule
4. [ ] Press Escape while form is open → form closes without creating
5. [ ] Press Enter while form is valid → rule created
6. [ ] In Messages, select 3 emails → click "Share…" → popover shows both agent toggles → toggle Claude on → green strip says "Will share with Claude" → click Apply
7. [ ] In Messages, click a shared email → preview shows "Share…" button → popover shows current sharing state → can toggle agents
8. [ ] Right-click a file row → "Share with…" submenu shows Claude/Codex checkmarks matching current state
9. [ ] Right-click a domain rule → "Delete Rule" removes it from table
10. [ ] All forms auto-focus the primary input field on open
