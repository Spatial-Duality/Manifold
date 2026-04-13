# Email Controls — Design Spec

## The Problem

The current "Domains" tab is a flat list of domains with toggles. It answers only one question: "Can this agent see emails from @stripe.com?" But email governance has several dimensions the current design completely ignores:

- **Content-based sensitivity**: 2FA codes from any domain should be off-limits, but the domain itself (e.g., apple.com) sends both security codes AND developer notifications
- **Contact-level overrides**: You might block bank.com broadly but want your agent to see emails from your specific banking advisor
- **Keyword patterns**: Anything containing "confidential" or "attorney-client" should be blocked regardless of domain
- **Default posture**: Is the system "allow unless blocked" or "block unless allowed"? The current design doesn't let you choose

## Design Philosophy: Progressive Disclosure of Control

Most users should get 90% of the protection they need from **pre-built Shields** — category-level protections they toggle on/off. Shields are the "set and forget" layer.

Power users who want fine-grained control can drill into Domains, Contacts, and Keywords — but these are optional refinements, not requirements.

This follows the Little Snitch pattern: approachable per-item decisions, with a visual summary of what's happening, and the ability to create granular rules when needed.

**It is NOT enterprise DLP.** No policy inheritance, no admin consoles, no SOC workflows. This is personal governance that feels like configuring a smart firewall, not deploying a security product.

## Control Hierarchy (Evaluation Order)

When an email arrives, Manifold evaluates access in this order. Most specific wins:

```
1. Contact Rules     (most specific — "allow john@bank.com")
2. Keyword Rules     (content match — "block if contains 'OTP'")
3. Domain Rules      (domain match — "block @bank.com")
4. Shields           (category match — "block Financial category")
5. Default Policy    (fallback — "allow all" or "block all")
```

If a Contact Rule says "allow", it overrides a Domain Rule or Shield that says "block." This lets users express nuance without fighting the system.

## Shield Categories

Shields are pre-built rule bundles that detect sensitive email categories using a combination of known domains, sender patterns, subject keywords, and body content signals.

### Security & 2FA (ON by default)
- **What it catches**: OTP codes, verification emails, password resets, login alerts, new device notifications, account recovery
- **Detection signals**: 
  - Domains: accounts.google.com, appleid.apple.com, noreply@github.com (security subset)
  - Subject patterns: "verification code", "one-time password", "security alert", "sign-in attempt", "reset your password", "confirm your email"
  - Body patterns: 6-digit codes, "expires in X minutes", "if this wasn't you"
- **Why default ON**: An agent with your 2FA codes could theoretically be used to bypass authentication. This is the single highest-risk email category.

### Financial (ON by default)
- **What it catches**: Bank statements, transaction alerts, credit card notifications, invoices with account numbers, tax documents
- **Detection signals**:
  - Domains: *.chase.com, *.bankofamerica.com, statements@amex.com, receipts@stripe.com, venmo@venmo.com
  - Subject patterns: "statement ready", "transaction alert", "payment received", "your balance", "tax document"
  - Body patterns: masked account numbers (****1234), dollar amounts with "balance"
- **Why default ON**: Financial data exposure is a clear privacy risk with real consequences.

### Medical (ON by default)
- **What it catches**: Appointment confirmations, lab results, prescription notifications, insurance claims, provider messages
- **Detection signals**:
  - Domains: mychart.*, messages@healthcare.*, portal@*health*
  - Subject patterns: "appointment confirmation", "lab results", "prescription", "your visit summary"
  - Body patterns: medical terminology, HIPAA-adjacent content
- **Why default ON**: Health information is among the most personal data categories. Even appointment details reveal information people want private.

### Legal (OFF by default)
- **What it catches**: Attorney correspondence, legal notices, NDA-related emails, contract reviews, court notices
- **Detection signals**:
  - Subject patterns: "attorney-client", "privileged", "NDA", "legal notice", "subpoena"
  - Body patterns: "privileged and confidential", "do not forward", legal disclaimers
- **Why default OFF**: Most indie developers/small teams don't have regular attorney correspondence. Turning this on unnecessarily could catch false positives (e.g., SaaS terms of service updates).

### Personal (OFF by default)  
- **What it catches**: Family/friend emails, dating, personal purchases, social invitations
- **Detection signals**: User-defined contacts marked "personal", known personal service domains
- **Why default OFF**: Highly subjective — what's "personal" varies enormously. Better as opt-in with user-configured contact lists.

## Custom Rules

### Domain Rules
Same concept as the current Domains tab but now explicitly part of a rule hierarchy. Each domain rule specifies:
- **Domain**: e.g., @stripe.com, @*.bankofamerica.com (wildcard subdomain support)
- **Action**: Allow / Block
- **Applies to**: Specific agent(s) or all agents
- **Category** (optional): Work, Automated, Personal — for organization only

### Contact Rules  
Override domain-level decisions for specific senders:
- **Contact**: email address or display name
- **Action**: Allow / Block
- **Overrides**: Shows what domain/shield rule this overrides
- **Applies to**: Specific agent(s) or all agents

Use case: block @bank.com broadly (via Financial shield), but allow your specific advisor sarah.jones@bank.com because she sends project-relevant emails.

### Keyword Rules
Content-based pattern matching:
- **Pattern**: text string or regex
- **Match location**: Subject only / Subject + Body / Anywhere
- **Action**: Block / Flag for review
- **Applies to**: Specific agent(s) or all agents

Use cases: block "SSN", block "confidential", flag "urgent" for review.

## Default Policy

A per-agent setting that determines what happens to emails that don't match any rule:

- **Allow unless blocked** (recommended default): Agents can see all emails except those caught by shields, domain rules, contact rules, or keyword rules. This maximizes agent utility while shields handle the sensitive stuff.

- **Block unless allowed** (high-security mode): Agents see NOTHING unless a rule explicitly allows it. For users who want to hand-pick exactly what each agent can access. Much more work to configure, but maximum control.

Per-agent defaults are important: you might trust Claude broadly ("allow unless blocked") but restrict a newer agent to "block unless allowed" until you've verified its behavior.

## Proposed Layout

### Navigation Change
Replace "Domains | Messages" sub-nav with "Rules | Messages"

### Sidebar

```
OVERVIEW
  Dashboard               ← protection summary + activity

SHIELDS
  Security & 2FA     [✓]  ← green = active, gray = off
  Financial          [✓]
  Medical            [✓]
  Legal              [○]
  Personal           [○]

RULES
  Domains             12  ← count of custom rules
  Contacts             3
  Keywords             2

POLICY
  Defaults                ← per-agent default policy
```

### Main Content Views

**Dashboard** (selected by default):
- Protection summary: "3 shields active · 12 domain rules · 3 contact overrides"
- Per-agent stats cards: 
  - Claude: 342 emails accessible, 89 blocked (pie chart or bar)
  - Codex: 201 accessible, 230 blocked
- "Recent activity" table: last 5–10 emails that were blocked, showing email subject, which rule caught it, and which agent was blocked
- This view answers: "Is my protection working? What's it doing?"

**Shield Detail** (when a shield is selected):
- Shield name + toggle (on/off)
- Description paragraph explaining what it catches
- Per-agent toggle (rare case: allow Claude through Financial shield but not Codex)
- "Detection patterns" collapsible section: shows the domains and keywords this shield monitors
- "Recent matches" table: emails caught by this shield (subject, from, date, which agent blocked)
- Footer link: "Not catching something? → Add a keyword rule"

**Domains** (when selected under Rules):
- Improved version of current domain table
- Columns: Domain, Category, Emails, Rule (Allow/Block badge), Agent(s)
- Agent focus switcher in toolbar
- Sensitivity segmented control moves here (Permissive/Moderate/Strict adjusts which auto-categorized domains get blocked)
- "Add domain rule" button
- Row click → shows emails from that domain in a slide-out or inline expand

**Contacts** (when selected under Rules):
- Table: Name, Email, Action (Allow/Block badge), Overrides (which shield/domain it overrides), Agent(s)
- "Add contact rule" button
- Empty state: "Contact rules override domain rules and shields for specific senders. Add one when you need an exception."

**Keywords** (when selected under Rules):
- Table: Pattern, Match In (Subject/Body/All), Action (Block/Flag), Matched (count), Agent(s)
- "Add keyword rule" button  
- Regex toggle for power users
- Empty state: "Keyword rules catch emails containing specific text patterns, regardless of sender or domain."

**Defaults** (when selected under Policy):
- Per-agent row with:
  - Agent name + color
  - Segmented control: "Allow unless blocked" | "Block unless allowed"
  - Stats: how many emails each policy would affect
- Explanatory text for each mode
- Warning banner if any agent is set to "Block unless allowed": "This agent won't see any emails unless you add allow rules above."

## Why This Design

**Incentive alignment**: The Shields are the "easy button." They're on by default for the highest-risk categories. Users who never touch custom rules still get meaningful protection. The incentive to configure more only kicks in when the default isn't quite right — which is the correct trigger.

**Second-order effect**: By making Shields visible and their activity transparent (dashboard, recent matches), users build trust in the system. Trust means they'll actually leave the shields on instead of disabling them because they don't understand what's happening. Opacity breeds distrust, transparency breeds delegation.

**Third-order effect**: The per-agent default policy creates a natural onboarding ramp for new agents. New agent → starts in "block unless allowed" → user reviews what it would need → promotes to "allow unless blocked" once trusted. This mirrors how organizations onboard new employees (restricted access → verified → full access).

**Little Snitch parallel**: Little Snitch succeeded because it made invisible network traffic visible and controllable without requiring networking expertise. Manifold's email controls should make invisible agent access visible and controllable without requiring email security expertise.
