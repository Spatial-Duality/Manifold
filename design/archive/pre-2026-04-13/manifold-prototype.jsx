import { useState, useRef, useEffect } from "react";
import { Search, ChevronDown, ChevronRight, Plus, Folder, Mail, Eye, Clock, Shield, Circle, Activity, Settings, MoreHorizontal, FileText, Globe, Inbox, Star, Filter, ArrowUpDown, Paperclip, Download } from "lucide-react";

// Checkbox components (lucide 0.383 compat)
function CheckboxIcon({ checked, color = "#999", size = 14 }) {
  if (checked) {
    return (
      <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round">
        <rect x="3" y="3" width="18" height="18" rx="3" fill={color} stroke={color} />
        <path d="M9 12l2 2 4-4" stroke="white" strokeWidth={2.5} />
      </svg>
    );
  }
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round">
      <rect x="3" y="3" width="18" height="18" rx="3" />
    </svg>
  );
}

// ─── Design Tokens (from DESIGN-STANDARDS.md) ──────────────────────────
const Color = {
  claudeBlue: "#4A90D9",
  claudeBlueTint: "rgba(74,144,217,0.04)",
  claudeBlueBadge: "rgba(74,144,217,0.12)",
  codexPurple: "#8B5CF6",
  codexPurpleTint: "rgba(139,92,246,0.04)",
  codexPurpleBadge: "rgba(139,92,246,0.12)",
  statusActive: "#34C759",
  statusActiveBadge: "rgba(52,199,89,0.12)",
  statusPaused: "#FF9500",
  statusPausedBadge: "rgba(255,149,0,0.12)",
  statusDanger: "#FF3B30",
  statusDangerBadge: "rgba(255,59,48,0.12)",
  bg: "#FFFFFF",
  sidebar: "rgba(246,246,246,0.85)",
  sidebarBorder: "rgba(0,0,0,0.06)",
  border: "rgba(0,0,0,0.08)",
  textPrimary: "#1D1D1F",
  textSecondary: "rgba(0,0,0,0.55)",
  textTertiary: "rgba(0,0,0,0.35)",
  hover: "rgba(0,0,0,0.04)",
  selected: "rgba(0,122,255,0.12)",
  glass: "rgba(255,255,255,0.72)",
};

const Type = {
  sectionTitle: { fontSize: 17, fontWeight: 600, letterSpacing: "-0.2px" },
  heading: { fontSize: 14, fontWeight: 600, letterSpacing: "-0.1px" },
  body: { fontSize: 13, fontWeight: 400 },
  secondary: { fontSize: 13, fontWeight: 400, color: Color.textSecondary },
  caption: { fontSize: 11, fontWeight: 400, color: Color.textSecondary },
  mono: { fontSize: 11, fontWeight: 400, fontFamily: "SF Mono, Menlo, monospace" },
  numericCaption: { fontSize: 11, fontWeight: 500, fontFamily: "SF Mono, Menlo, monospace", fontVariantNumeric: "tabular-nums" },
};

const Shadow = {
  card: "0 1px 3px rgba(0,0,0,0.08)",
  cardHover: "0 2px 5px rgba(0,0,0,0.12)",
};

// ─── Shared Components ─────────────────────────────────────────────────

function Badge({ variant = "info", children, agent = "claude" }) {
  const styles = {
    info: { bg: agent === "codex" ? Color.codexPurpleBadge : Color.claudeBlueBadge, fg: agent === "codex" ? Color.codexPurple : Color.claudeBlue },
    success: { bg: Color.statusActiveBadge, fg: Color.statusActive },
    warning: { bg: Color.statusPausedBadge, fg: Color.statusPaused },
    danger: { bg: Color.statusDangerBadge, fg: Color.statusDanger },
    neutral: { bg: "rgba(0,0,0,0.06)", fg: Color.textSecondary },
  };
  const s = styles[variant];
  return (
    <span style={{
      display: "inline-flex", alignItems: "center", gap: 4,
      padding: "2px 8px", borderRadius: 99, fontSize: 11, fontWeight: 500,
      background: s.bg, color: s.fg, whiteSpace: "nowrap",
    }}>
      <span style={{ width: 6, height: 6, borderRadius: 3, background: s.fg, flexShrink: 0 }} />
      {children}
    </span>
  );
}

function StatusDot({ color, size = 10 }) {
  return <span style={{ width: size, height: size, borderRadius: size / 2, background: color, display: "inline-block", flexShrink: 0 }} />;
}

function SectionHeader({ children, count, style: extraStyle }) {
  return (
    <div style={{ padding: "8px 12px 4px", display: "flex", justifyContent: "space-between", alignItems: "center", ...extraStyle }}>
      <span style={{ ...Type.caption, fontWeight: 600, textTransform: "uppercase", letterSpacing: "0.5px", fontSize: 10, color: Color.textTertiary }}>{children}</span>
      {count !== undefined && <span style={{ ...Type.numericCaption, color: Color.textTertiary }}>{count}</span>}
    </div>
  );
}

function ToolbarButton({ children, active, onClick }) {
  return (
    <button onClick={onClick} style={{
      background: active ? Color.selected : "transparent", border: "none", borderRadius: 6,
      padding: "4px 8px", cursor: "pointer", display: "flex", alignItems: "center", gap: 4,
      color: Color.textPrimary, fontSize: 12, transition: "background 0.15s",
    }}>{children}</button>
  );
}

function AgentToggle({ value, onChange, agent }) {
  const color = agent === "codex" ? Color.codexPurple : Color.claudeBlue;
  return (
    <button onClick={() => onChange(!value)} style={{
      width: 36, height: 20, borderRadius: 10, border: value ? "none" : "1.5px solid rgba(0,0,0,0.2)",
      background: value ? color : "rgba(0,0,0,0.05)", cursor: "pointer", position: "relative",
      transition: "all 0.2s ease", padding: 0,
    }}>
      <span style={{
        width: 16, height: 16, borderRadius: 8, background: "white",
        position: "absolute", top: value ? 2 : 1, left: value ? 18 : 2,
        boxShadow: "0 1px 2px rgba(0,0,0,0.2)", transition: "left 0.2s ease",
      }} />
    </button>
  );
}

// ─── Global Toolbar (Fix 1.3, 1.6, 1.7, X.4) ─────────────────────────

function AppToolbar({ tab, onTabChange, agentStatus }) {
  return (
    <div style={{
      height: 52, display: "flex", alignItems: "center", justifyContent: "space-between",
      padding: "0 16px", borderBottom: `1px solid ${Color.border}`,
      background: Color.glass, backdropFilter: "blur(20px)", WebkitBackdropFilter: "blur(20px)",
    }}>
      {/* Left: Title + Status (Fix 1.3) */}
      <div style={{ display: "flex", alignItems: "center", gap: 8, minWidth: 200 }}>
        <span style={{ ...Type.sectionTitle }}>Manifold</span>
        <span style={{ ...Type.caption, color: Color.textTertiary }}>
          {agentStatus === "both" ? "Claude + Codex active" : agentStatus === "partial" ? "Claude active · Codex paused" : "Connecting…"}
        </span>
      </div>

      {/* Center: Tab bar (Fix 1.6 — keep clean, no badges) */}
      <div style={{
        display: "flex", background: "rgba(0,0,0,0.06)", borderRadius: 8, padding: 2,
      }}>
        {["Overview", "Files", "Emails"].map(t => (
          <button key={t} onClick={() => onTabChange(t)} style={{
            padding: "5px 16px", borderRadius: 6, border: "none", cursor: "pointer",
            background: tab === t ? "white" : "transparent", fontSize: 13, fontWeight: tab === t ? 500 : 400,
            color: tab === t ? Color.textPrimary : Color.textSecondary,
            boxShadow: tab === t ? "0 1px 2px rgba(0,0,0,0.08)" : "none",
            transition: "all 0.15s",
          }}>{t}</button>
        ))}
      </div>

      {/* Right: Status dot + search (Fix X.4, Fix 1.7 — no "Agent" label) */}
      <div style={{ display: "flex", alignItems: "center", gap: 8, minWidth: 200, justifyContent: "flex-end" }}>
        <div style={{ display: "flex", alignItems: "center", gap: 5 }}>
          <StatusDot color={agentStatus === "both" ? Color.statusActive : agentStatus === "partial" ? Color.statusPaused : Color.statusDanger} size={8} />
          <span style={{ ...Type.caption }}>
            {agentStatus === "both" ? "Connected" : agentStatus === "partial" ? "1 agent paused" : "Disconnected"}
          </span>
        </div>
        <div style={{ width: 1, height: 16, background: Color.border }} />
        <ToolbarButton><Search size={14} /></ToolbarButton>
        <ToolbarButton><Settings size={14} /></ToolbarButton>
      </div>
    </div>
  );
}

// ─── Agent Focus Control (Fix 1.7 — no "Agent" label) ─────────────────

function AgentFocusControl({ value, onChange }) {
  return (
    <div style={{ display: "flex", background: "rgba(0,0,0,0.06)", borderRadius: 6, padding: 2 }}>
      {["Claude", "Codex", "Compare"].map(a => (
        <button key={a} onClick={() => onChange(a)} style={{
          padding: "3px 12px", borderRadius: 4, border: "none", cursor: "pointer", fontSize: 12,
          background: value === a ? "white" : "transparent", fontWeight: value === a ? 500 : 400,
          color: value === a ? (a === "Claude" ? Color.claudeBlue : a === "Codex" ? Color.codexPurple : Color.textPrimary) : Color.textSecondary,
          boxShadow: value === a ? "0 0.5px 1px rgba(0,0,0,0.1)" : "none", transition: "all 0.15s",
        }}>{a}</button>
      ))}
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════════════
// OVERVIEW TAB (Fixes 1.1–1.5)
// ═══════════════════════════════════════════════════════════════════════

function OverviewTab() {
  return (
    <div style={{ padding: 24, maxWidth: 960, margin: "0 auto", display: "flex", flexDirection: "column", gap: 16, height: "100%" }}>
      {/* Agent Cards — side by side (Fix 1.1: rich dashboards, Fix 1.2: agent color identity) */}
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 16, flex: 1 }}>
        <AgentCard
          name="Claude"
          color={Color.claudeBlue}
          tint={Color.claudeBlueTint}
          status="active"
          sources={[
            { name: "web-app", files: 247, access: true },
            { name: "api-server", files: 89, access: true },
            { name: "docs", files: 34, access: false },
          ]}
          domains={[
            { name: "github.com", emails: 53 },
            { name: "linear.app", emails: 12 },
          ]}
          activity={[
            { action: "Read", target: "src/index.ts", time: "2 min ago" },
            { action: "Read", target: "package.json", time: "5 min ago" },
            { action: "Connected", target: "", time: "12 min ago" },
          ]}
        />
        <AgentCard
          name="Codex"
          color={Color.codexPurple}
          tint={Color.codexPurpleTint}
          status="paused"
          sources={[
            { name: "web-app", files: 247, access: true },
            { name: "design-assets", files: 156, access: true },
          ]}
          domains={[
            { name: "figma.com", emails: 8 },
          ]}
          activity={[
            { action: "Paused", target: "by user", time: "8 min ago" },
            { action: "Write", target: "styles/theme.css", time: "20 min ago" },
            { action: "Read", target: "README.md", time: "22 min ago" },
          ]}
        />
      </div>

      {/* Tracked Work Block CTA — shared footer (Fix 1.4) */}
      <div style={{
        padding: "14px 20px", borderRadius: 10, border: `1px solid ${Color.border}`,
        display: "flex", alignItems: "center", justifyContent: "space-between",
        background: "rgba(0,0,0,0.015)",
      }}>
        <div>
          <div style={{ ...Type.body, fontWeight: 500 }}>Tracked Work Block</div>
          <div style={{ ...Type.caption }}>Monitor and review all AI file changes in real time</div>
        </div>
        <button style={{
          padding: "7px 16px", borderRadius: 6, border: "none", cursor: "pointer",
          background: Color.claudeBlue, color: "white", fontSize: 13, fontWeight: 500,
        }}>Start Tracked Work Block</button>
      </div>
    </div>
  );
}

function AgentCard({ name, color, tint, status, sources, domains, activity }) {
  const [hovered, setHovered] = useState(false);
  return (
    <div
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
      style={{
        borderRadius: 10, overflow: "hidden",
        border: `1px solid ${Color.border}`,
        boxShadow: hovered ? Shadow.cardHover : Shadow.card,
        transition: "box-shadow 0.2s ease",
        display: "flex", flexDirection: "column",
        background: Color.bg,
      }}
    >
      {/* Left border accent (Fix 1.2) */}
      <div style={{ display: "flex", flex: 1 }}>
        <div style={{ width: 4, background: color, flexShrink: 0 }} />
        <div style={{ flex: 1, padding: 16, display: "flex", flexDirection: "column", gap: 14, background: tint }}>
          {/* Header */}
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
            <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
              <StatusDot color={color} />
              <span style={{ ...Type.heading, fontSize: 15 }}>{name}</span>
              <Badge variant={status === "active" ? "success" : "warning"} agent={name.toLowerCase()}>
                {status === "active" ? "Active" : "Paused"}
              </Badge>
            </div>
            {/* Per-agent control (Fix 1.5) */}
            <button style={{
              padding: "4px 10px", borderRadius: 5, border: `1px solid ${Color.border}`,
              background: "white", cursor: "pointer", fontSize: 12, color: Color.textSecondary,
            }}>{status === "active" ? "Pause Access" : "Resume Access"}</button>
          </div>

          {/* Sources summary (Fix 1.1 — cards as dashboards) */}
          <div>
            <div style={{ ...Type.caption, fontWeight: 600, marginBottom: 6, textTransform: "uppercase", fontSize: 10, letterSpacing: "0.5px" }}>Sources</div>
            {sources.map(s => (
              <div key={s.name} style={{
                display: "flex", alignItems: "center", justifyContent: "space-between",
                padding: "4px 0", gap: 8,
              }}>
                <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
                  <Folder size={13} color={Color.textTertiary} />
                  <span style={{ ...Type.body }}>{s.name}</span>
                </div>
                <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                  <span style={{ ...Type.numericCaption, color: Color.textTertiary }}>{s.files} files</span>
                  <StatusDot color={s.access ? Color.statusActive : Color.textTertiary} size={6} />
                </div>
              </div>
            ))}
          </div>

          {/* Email domains summary */}
          <div>
            <div style={{ ...Type.caption, fontWeight: 600, marginBottom: 6, textTransform: "uppercase", fontSize: 10, letterSpacing: "0.5px" }}>Email Domains</div>
            {domains.map(d => (
              <div key={d.name} style={{
                display: "flex", alignItems: "center", justifyContent: "space-between",
                padding: "3px 0",
              }}>
                <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
                  <Globe size={13} color={Color.textTertiary} />
                  <span style={{ ...Type.body }}>@{d.name}</span>
                </div>
                <span style={{ ...Type.numericCaption, color: Color.textTertiary }}>{d.emails}</span>
              </div>
            ))}
          </div>

          {/* Recent activity (Fix 1.1 — inline activity) */}
          <div style={{ borderTop: `1px solid ${Color.border}`, paddingTop: 10, marginTop: "auto" }}>
            <div style={{ ...Type.caption, fontWeight: 600, marginBottom: 6, textTransform: "uppercase", fontSize: 10, letterSpacing: "0.5px" }}>Recent Activity</div>
            {activity.map((a, i) => (
              <div key={i} style={{
                display: "flex", alignItems: "center", justifyContent: "space-between",
                padding: "3px 0",
              }}>
                <span style={{ ...Type.caption }}>
                  <span style={{ fontWeight: 500, color: Color.textPrimary }}>{a.action}</span>
                  {a.target && <> <span style={{ ...Type.mono, color: Color.textSecondary }}>{a.target}</span></>}
                </span>
                <span style={{ ...Type.numericCaption, color: Color.textTertiary }}>{a.time}</span>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════════════
// FILES TAB (Fixes 2.1–2.7) — Sources + drill-in file browsing
// ═══════════════════════════════════════════════════════════════════════

const fileSources = [
  { name: "web-app", path: "~/Projects/web-app", items: 247, access: true },
  { name: "api-server", path: "~/Projects/api-server", items: 89, access: true },
  { name: "docs", path: "~/Documents/docs", items: 34, access: true },
  { name: "design-assets", path: "~/Projects/design-assets", items: 156, access: false },
  { name: "IBM_Plex_Sans", path: "~/Downloads/IBM_Plex_Sans", items: null, access: true },
];

const sourceFiles = {
  "web-app": [
    { name: "index.ts", path: "src/index.ts", size: "4.2 KB", modified: "2 min ago", ext: "ts", shared: "claude" },
    { name: "package.json", path: "package.json", size: "1.1 KB", modified: "5 min ago", ext: "json", shared: "claude" },
    { name: "tsconfig.json", path: "tsconfig.json", size: "0.8 KB", modified: "3 days ago", ext: "json", shared: "claude" },
    { name: "App.tsx", path: "src/App.tsx", size: "6.3 KB", modified: "1 hr ago", ext: "tsx", shared: "claude" },
    { name: "auth.ts", path: "src/middleware/auth.ts", size: "2.1 KB", modified: "20 min ago", ext: "ts", shared: "claude" },
    { name: "theme.css", path: "styles/theme.css", size: "3.4 KB", modified: "20 min ago", ext: "css", shared: "codex" },
    { name: "README.md", path: "README.md", size: "2.8 KB", modified: "1 day ago", ext: "md", shared: "claude" },
    { name: ".env.example", path: ".env.example", size: "0.3 KB", modified: "2 weeks ago", ext: "env", shared: null },
    { name: "vite.config.ts", path: "vite.config.ts", size: "0.9 KB", modified: "5 days ago", ext: "ts", shared: null },
    { name: "Layout.tsx", path: "src/components/Layout.tsx", size: "4.8 KB", modified: "3 hrs ago", ext: "tsx", shared: "claude" },
  ],
  "api-server": [
    { name: "main.swift", path: "Sources/main.swift", size: "1.2 KB", modified: "1 day ago", ext: "swift", shared: "claude" },
    { name: "Package.swift", path: "Package.swift", size: "2.4 KB", modified: "3 days ago", ext: "swift", shared: "claude" },
    { name: "routes.swift", path: "Sources/Routes/routes.swift", size: "5.6 KB", modified: "6 hrs ago", ext: "swift", shared: "claude" },
    { name: "Auth.swift", path: "Sources/Middleware/Auth.swift", size: "3.1 KB", modified: "2 days ago", ext: "swift", shared: null },
  ],
  "docs": [
    { name: "architecture.md", path: "architecture.md", size: "8.2 KB", modified: "1 week ago", ext: "md", shared: "claude" },
    { name: "api-reference.md", path: "api-reference.md", size: "12.4 KB", modified: "3 days ago", ext: "md", shared: "claude" },
    { name: "changelog.md", path: "changelog.md", size: "6.1 KB", modified: "1 day ago", ext: "md", shared: null },
  ],
  "design-assets": [
    { name: "icon-1024.png", path: "AppIcon/icon-1024.png", size: "245 KB", modified: "2 days ago", ext: "png", shared: null },
    { name: "mockup-v5.fig", path: "Figma/mockup-v5.fig", size: "18.2 MB", modified: "1 week ago", ext: "fig", shared: null },
    { name: "palette.json", path: "tokens/palette.json", size: "1.8 KB", modified: "4 days ago", ext: "json", shared: "codex" },
  ],
  "IBM_Plex_Sans": [
    { name: "IBMPlexSans-Regular.ttf", path: "IBMPlexSans-Regular.ttf", size: "142 KB", modified: "2 months ago", ext: "ttf", shared: null },
    { name: "IBMPlexSans-Bold.ttf", path: "IBMPlexSans-Bold.ttf", size: "148 KB", modified: "2 months ago", ext: "ttf", shared: null },
    { name: "IBMPlexSans-Italic.ttf", path: "IBMPlexSans-Italic.ttf", size: "151 KB", modified: "2 months ago", ext: "ttf", shared: null },
  ],
};

// Flatten all files with source info
const allFilesList = Object.entries(sourceFiles).flatMap(([source, files]) =>
  files.map(f => ({ ...f, source }))
);

function fileIcon(ext) {
  const colors = { ts: "#3178C6", tsx: "#3178C6", swift: "#F05138", json: "#F5A623", md: "#555", css: "#264de4", png: "#34C759", fig: "#A259FF", ttf: "#888", env: "#FF9500" };
  return colors[ext] || Color.textTertiary;
}

function FilesTab() {
  const [agent, setAgent] = useState("Claude");
  const [selectedSource, setSelectedSource] = useState("Dashboard");
  const [searchText, setSearchText] = useState("");
  const agentColor = agent === "Codex" ? Color.codexPurple : Color.claudeBlue;
  const agentTint = agent === "Codex" ? Color.codexPurpleTint : Color.claudeBlueTint;

  // Determine what to show
  const isDashboard = selectedSource === "Dashboard";
  const isSourceView = selectedSource === "All Sources";
  const isAllFiles = selectedSource === "All Files";
  const isFileView = !isSourceView && !isDashboard;

  // Get files for current view
  const currentFiles = isAllFiles
    ? allFilesList
    : isSourceView
    ? []
    : (sourceFiles[selectedSource] || []).map(f => ({ ...f, source: selectedSource }));

  const filteredFiles = currentFiles.filter(f => {
    if (!searchText) return true;
    const q = searchText.toLowerCase();
    return f.name.toLowerCase().includes(q) || f.path.toLowerCase().includes(q) || f.source.toLowerCase().includes(q);
  });

  const currentSource = fileSources.find(s => s.name === selectedSource);

  return (
    <div style={{ display: "flex", height: "100%" }}>
      {/* Sidebar */}
      <div style={{
        width: 220, borderRight: `1px solid ${Color.sidebarBorder}`,
        background: Color.sidebar, display: "flex", flexDirection: "column",
        overflow: "auto",
      }}>
        <SectionHeader>Overview</SectionHeader>
        <button onClick={() => { setSelectedSource("Dashboard"); setSearchText(""); }} style={{
          display: "flex", alignItems: "center", gap: 8, padding: "5px 12px",
          border: "none", cursor: "pointer", width: "100%", textAlign: "left",
          background: selectedSource === "Dashboard" ? Color.selected : "transparent",
          borderRadius: 6, margin: "0 4px", maxWidth: "calc(100% - 8px)",
          fontSize: 13, color: Color.textPrimary,
        }}>
          <Activity size={14} color={Color.textTertiary} />
          <span style={{ flex: 1 }}>Dashboard</span>
        </button>

        <div style={{ height: 8 }} />
        <SectionHeader>Browse</SectionHeader>
        {["All Files", "All Sources"].map(s => (
          <button key={s} onClick={() => { setSelectedSource(s); setSearchText(""); }} style={{
            display: "flex", alignItems: "center", gap: 8, padding: "5px 12px",
            border: "none", cursor: "pointer", width: "100%", textAlign: "left",
            background: selectedSource === s ? Color.selected : "transparent",
            borderRadius: 6, margin: "0 4px", maxWidth: "calc(100% - 8px)",
            fontSize: 13, color: Color.textPrimary,
          }}>
            {s === "All Files" ? <FileText size={14} color={Color.textTertiary} /> : <Folder size={14} color={Color.textTertiary} />}
            <span style={{ flex: 1 }}>{s}</span>
            {s === "All Files" && <span style={{ ...Type.numericCaption, color: Color.textTertiary }}>{allFilesList.length}</span>}
          </button>
        ))}

        <div style={{ height: 8 }} />
        <SectionHeader count={5}>Sources</SectionHeader>
        {fileSources.map(s => (
          <button key={s.name} onClick={() => { setSelectedSource(s.name); setSearchText(""); }} style={{
            display: "flex", alignItems: "center", gap: 8, padding: "5px 12px",
            border: "none", cursor: "pointer", width: "100%", textAlign: "left",
            background: selectedSource === s.name ? Color.selected : "transparent",
            borderRadius: 6, margin: "0 4px", maxWidth: "calc(100% - 8px)",
            fontSize: 13, color: Color.textPrimary,
          }}>
            <Folder size={14} color={s.access ? agentColor : Color.textTertiary} />
            <span style={{ flex: 1, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{s.name}</span>
            <span style={{ ...Type.numericCaption, color: Color.textTertiary }}>{s.items || "…"}</span>
          </button>
        ))}
        <button style={{
          display: "flex", alignItems: "center", gap: 6, padding: "5px 12px",
          border: "none", cursor: "pointer", background: "transparent",
          fontSize: 13, color: Color.claudeBlue,
        }}>
          <Plus size={14} /> Add Folder…
        </button>

        <div style={{ height: 12 }} />
        <SectionHeader>Versions</SectionHeader>
        <button style={{
          display: "flex", alignItems: "center", gap: 8, padding: "5px 12px",
          border: "none", cursor: "pointer", background: "transparent",
          fontSize: 13, color: Color.textPrimary, width: "100%", textAlign: "left",
        }}>
          <Clock size={14} color={Color.textTertiary} /> Recently Modified
        </button>
        <button style={{
          display: "flex", alignItems: "center", gap: 8, padding: "5px 12px",
          border: "none", cursor: "pointer", background: "transparent",
          fontSize: 13, color: Color.textPrimary, width: "100%", textAlign: "left",
        }}>
          <Eye size={14} color={Color.textTertiary} /> AI-Touched Files
        </button>
      </div>

      {/* Main content */}
      <div style={{ flex: 1, display: "flex", flexDirection: "column" }}>
        {/* Toolbar */}
        <div style={{
          padding: "8px 16px", display: "flex", alignItems: "center", justifyContent: "space-between",
          borderBottom: `1px solid ${Color.border}`,
        }}>
          <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
            <span style={{ ...Type.sectionTitle }}>
              {isDashboard ? "Files" : isAllFiles ? "All Files" : isSourceView ? "Sources" : selectedSource}
            </span>
            {currentSource && (
              <span style={{ ...Type.mono, color: Color.textTertiary }}>{currentSource.path}</span>
            )}
          </div>
          <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
            {/* Search (for file views, not dashboard) */}
            {isFileView && !isDashboard && (
              <div style={{
                display: "flex", alignItems: "center", gap: 6,
                background: "rgba(0,0,0,0.04)", borderRadius: 6, padding: "4px 8px",
              }}>
                <Search size={12} color={Color.textTertiary} />
                <input
                  type="text" placeholder="Filter files…"
                  value={searchText} onChange={e => setSearchText(e.target.value)}
                  style={{ border: "none", background: "transparent", outline: "none", fontSize: 12, width: 140, color: Color.textPrimary }}
                />
              </div>
            )}
            <AgentFocusControl value={agent} onChange={setAgent} />
          </div>
        </div>

        <div style={{ flex: 1, overflow: "auto" }}>
          {/* ── DASHBOARD ── */}
          {isDashboard && (() => {
            const totalFiles = allFilesList.length;
            const sharedClaude = allFilesList.filter(f => f.shared === "claude").length;
            const sharedCodex = allFilesList.filter(f => f.shared === "codex").length;
            const notShared = allFilesList.filter(f => !f.shared).length;
            const sourcesShared = fileSources.filter(s => s.access).length;
            // File type breakdown
            const extCounts = {};
            allFilesList.forEach(f => { extCounts[f.ext] = (extCounts[f.ext] || 0) + 1; });
            const topTypes = Object.entries(extCounts).sort((a, b) => b[1] - a[1]).slice(0, 6);
            // Recent activity (sorted by most recent)
            const recentFiles = [...allFilesList].sort((a, b) => {
              const order = {"min ago": 1, "hr ago": 2, "hrs ago": 2, "day ago": 3, "days ago": 4, "week ago": 5, "weeks ago": 6, "month ago": 7, "months ago": 8};
              const scoreA = Object.entries(order).find(([k]) => a.modified.includes(k))?.[1] || 9;
              const scoreB = Object.entries(order).find(([k]) => b.modified.includes(k))?.[1] || 9;
              return scoreA - scoreB;
            }).slice(0, 5);

            return (
              <div style={{ padding: 20, maxWidth: 740 }}>
                <div style={{ ...Type.sectionTitle, marginBottom: 4 }}>Files Dashboard</div>
                <div style={{ ...Type.body, color: Color.textSecondary, marginBottom: 20 }}>
                  {fileSources.length} sources · {totalFiles} files tracked · {sourcesShared} source{sourcesShared !== 1 ? "s" : ""} shared with agents
                </div>

                {/* Agent access cards */}
                <div style={{ display: "flex", gap: 12, marginBottom: 20 }}>
                  {[
                    { name: "Claude", color: Color.claudeBlue, tint: Color.claudeBlueTint, files: sharedClaude, total: totalFiles },
                    { name: "Codex", color: Color.codexPurple, tint: Color.codexPurpleTint, files: sharedCodex, total: totalFiles },
                  ].map(a => (
                    <div key={a.name} style={{
                      flex: 1, borderRadius: 10, border: `1px solid ${Color.border}`,
                      padding: 16, borderLeft: `3px solid ${a.color}`,
                    }}>
                      <div style={{ ...Type.heading, marginBottom: 10 }}>{a.name}</div>
                      <div style={{ display: "flex", gap: 16 }}>
                        <div>
                          <div style={{ fontSize: 22, fontWeight: 600, color: a.color }}>{a.files}</div>
                          <div style={{ ...Type.caption, color: Color.textSecondary }}>files shared</div>
                        </div>
                        <div>
                          <div style={{ fontSize: 22, fontWeight: 600, color: Color.textTertiary }}>{a.total - a.files}</div>
                          <div style={{ ...Type.caption, color: Color.textSecondary }}>not shared</div>
                        </div>
                        <div style={{ flex: 1 }}>
                          <div style={{ height: 6, borderRadius: 3, background: "rgba(0,0,0,0.06)", marginTop: 8 }}>
                            <div style={{
                              height: "100%", borderRadius: 3, background: a.color,
                              width: `${(a.files / a.total) * 100}%`,
                              transition: "width 0.3s",
                            }} />
                          </div>
                          <div style={{ ...Type.caption, color: Color.textTertiary, marginTop: 3, textAlign: "right" }}>
                            {Math.round((a.files / a.total) * 100)}% accessible
                          </div>
                        </div>
                      </div>
                    </div>
                  ))}
                </div>

                {/* Source breakdown + file types side by side */}
                <div style={{ display: "flex", gap: 16, marginBottom: 20 }}>
                  {/* Sources */}
                  <div style={{ flex: 1 }}>
                    <div style={{ ...Type.heading, marginBottom: 8 }}>Sources</div>
                    <div style={{ border: `1px solid ${Color.border}`, borderRadius: 8, overflow: "hidden" }}>
                      {fileSources.map((s, i) => (
                        <div key={s.name} onClick={() => setSelectedSource(s.name)} style={{
                          display: "flex", alignItems: "center", justifyContent: "space-between",
                          padding: "8px 12px", cursor: "pointer",
                          borderBottom: i < fileSources.length - 1 ? "1px solid rgba(0,0,0,0.04)" : "none",
                          background: s.access ? "rgba(52,199,89,0.03)" : "transparent",
                        }}>
                          <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                            <Folder size={13} color={s.access ? Color.statusActive : Color.textTertiary} />
                            <span style={{ fontSize: 13, fontWeight: 500 }}>{s.name}</span>
                          </div>
                          <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                            <span style={{ ...Type.numericCaption, color: Color.textTertiary }}>{s.items || "…"} files</span>
                            {s.access ? (
                              <span style={{ width: 7, height: 7, borderRadius: "50%", background: Color.statusActive }} />
                            ) : (
                              <span style={{ width: 7, height: 7, borderRadius: "50%", background: Color.textTertiary, opacity: 0.3 }} />
                            )}
                          </div>
                        </div>
                      ))}
                    </div>
                  </div>

                  {/* File types */}
                  <div style={{ flex: 1 }}>
                    <div style={{ ...Type.heading, marginBottom: 8 }}>File Types</div>
                    <div style={{ border: `1px solid ${Color.border}`, borderRadius: 8, overflow: "hidden" }}>
                      {topTypes.map(([ext, count], i) => (
                        <div key={ext} style={{
                          display: "flex", alignItems: "center", justifyContent: "space-between",
                          padding: "8px 12px",
                          borderBottom: i < topTypes.length - 1 ? "1px solid rgba(0,0,0,0.04)" : "none",
                        }}>
                          <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                            <div style={{ width: 4, height: 14, borderRadius: 2, background: fileIcon(ext), flexShrink: 0 }} />
                            <span style={{ fontSize: 13 }}>.{ext}</span>
                          </div>
                          <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                            <div style={{ width: 60, height: 4, borderRadius: 2, background: "rgba(0,0,0,0.06)" }}>
                              <div style={{ height: "100%", borderRadius: 2, background: fileIcon(ext), width: `${(count / totalFiles) * 100}%` }} />
                            </div>
                            <span style={{ ...Type.numericCaption, color: Color.textTertiary, minWidth: 16, textAlign: "right" }}>{count}</span>
                          </div>
                        </div>
                      ))}
                    </div>
                  </div>
                </div>

                {/* Recent activity */}
                <div style={{ ...Type.heading, marginBottom: 8 }}>Recently Modified</div>
                <div style={{ border: `1px solid ${Color.border}`, borderRadius: 8, overflow: "hidden" }}>
                  <div style={{
                    display: "grid", gridTemplateColumns: "1fr 120px 80px 80px",
                    padding: "7px 14px", background: "rgba(0,0,0,0.02)",
                    borderBottom: `1px solid ${Color.border}`,
                  }}>
                    <span style={{ ...Type.caption, fontWeight: 600 }}>File</span>
                    <span style={{ ...Type.caption, fontWeight: 600 }}>Source</span>
                    <span style={{ ...Type.caption, fontWeight: 600, textAlign: "right" }}>Modified</span>
                    <span style={{ ...Type.caption, fontWeight: 600, textAlign: "center" }}>Shared</span>
                  </div>
                  {recentFiles.map((f, i) => (
                    <div key={`${f.source}-${f.name}`} style={{
                      display: "grid", gridTemplateColumns: "1fr 120px 80px 80px",
                      padding: "7px 14px", alignItems: "center",
                      borderBottom: i < recentFiles.length - 1 ? "1px solid rgba(0,0,0,0.04)" : "none",
                    }}>
                      <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
                        <div style={{ width: 4, height: 14, borderRadius: 2, background: fileIcon(f.ext), flexShrink: 0 }} />
                        <span style={{ fontSize: 13, fontWeight: 500, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{f.name}</span>
                      </div>
                      <span style={{ ...Type.caption, color: Color.textSecondary, cursor: "pointer" }} onClick={() => setSelectedSource(f.source)}>{f.source}</span>
                      <span style={{ ...Type.numericCaption, color: Color.textTertiary, textAlign: "right" }}>{f.modified}</span>
                      <div style={{ display: "flex", justifyContent: "center", gap: 3 }}>
                        {f.shared === "claude" && <StatusDot color={Color.claudeBlue} size={7} />}
                        {f.shared === "codex" && <StatusDot color={Color.codexPurple} size={7} />}
                        {!f.shared && <span style={{ ...Type.caption, color: Color.textTertiary }}>—</span>}
                      </div>
                    </div>
                  ))}
                </div>

                {/* Unshared files callout */}
                <div style={{
                  marginTop: 16, padding: "10px 14px", borderRadius: 8,
                  background: "rgba(0,0,0,0.02)", border: `1px solid ${Color.border}`,
                  fontSize: 12, color: Color.textSecondary, display: "flex", justifyContent: "space-between", alignItems: "center",
                }}>
                  <span>{notShared} file{notShared !== 1 ? "s" : ""} not shared with any agent</span>
                  <span style={{ color: Color.claudeBlue, cursor: "pointer" }} onClick={() => setSelectedSource("All Files")}>Browse all files →</span>
                </div>
              </div>
            );
          })()}

          {/* ── SOURCES TABLE (when "All Sources" selected) ── */}
          {isSourceView && (
            <>
              <div style={{
                display: "grid",
                gridTemplateColumns: agent === "Compare" ? "1fr 2fr 80px 80px 80px" : "1fr 2fr 80px 80px",
                padding: "8px 16px", borderBottom: `1px solid ${Color.border}`,
                position: "sticky", top: 0, background: Color.bg, zIndex: 1,
              }}>
                <span style={{ ...Type.caption, fontWeight: 600 }}>Name</span>
                <span style={{ ...Type.caption, fontWeight: 600 }}>Path</span>
                <span style={{ ...Type.caption, fontWeight: 600, textAlign: "right" }}>Files</span>
                {agent === "Compare" ? (
                  <>
                    <span style={{ ...Type.caption, fontWeight: 600, textAlign: "center", color: Color.claudeBlue }}>Claude</span>
                    <span style={{ ...Type.caption, fontWeight: 600, textAlign: "center", color: Color.codexPurple }}>Codex</span>
                  </>
                ) : (
                  <span style={{ ...Type.caption, fontWeight: 600, textAlign: "center", color: agentColor }}>{agent}</span>
                )}
              </div>
              {fileSources.map((s, i) => (
                <div key={s.name} onClick={() => setSelectedSource(s.name)} style={{
                  display: "grid",
                  gridTemplateColumns: agent === "Compare" ? "1fr 2fr 80px 80px 80px" : "1fr 2fr 80px 80px",
                  padding: "8px 16px", alignItems: "center", cursor: "pointer",
                  borderBottom: "1px solid rgba(0,0,0,0.04)",
                  background: s.access ? agentTint : "transparent",
                  transition: "background 0.15s",
                }}>
                  <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                    <Folder size={14} color={s.access ? agentColor : Color.textTertiary} />
                    <span style={{ ...Type.body, fontWeight: 500 }}>{s.name}</span>
                    <span style={{ ...Type.caption, color: Color.claudeBlue }}>→</span>
                  </div>
                  <span style={{ ...Type.mono, color: Color.textSecondary, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{s.path}</span>
                  <span style={{ ...Type.numericCaption, textAlign: "right", color: Color.textSecondary }}>{s.items || "…"}</span>
                  {agent === "Compare" ? (
                    <>
                      <div style={{ textAlign: "center" }}><input type="checkbox" checked={s.access} readOnly style={{ accentColor: Color.claudeBlue }} /></div>
                      <div style={{ textAlign: "center" }}><input type="checkbox" checked={i < 3} readOnly style={{ accentColor: Color.codexPurple }} /></div>
                    </>
                  ) : (
                    <div style={{ textAlign: "center" }}><input type="checkbox" checked={s.access} readOnly style={{ accentColor: agentColor }} /></div>
                  )}
                </div>
              ))}
              <div style={{ padding: "12px 16px", ...Type.caption, color: Color.textTertiary }}>
                5 sources · {allFilesList.length} files total · Click a source to browse files
              </div>
            </>
          )}

          {/* ── FILES TABLE (when a source or "All Files" selected) ── */}
          {isFileView && (
            <>
              <div style={{
                display: "grid",
                gridTemplateColumns: isAllFiles ? "1fr 2fr 100px 80px 90px 70px" : "1fr 2fr 80px 90px 70px",
                padding: "8px 16px", borderBottom: `1px solid ${Color.border}`,
                position: "sticky", top: 0, background: Color.bg, zIndex: 1, alignItems: "center",
              }}>
                <span style={{ ...Type.caption, fontWeight: 600 }}>Name</span>
                <span style={{ ...Type.caption, fontWeight: 600 }}>Path</span>
                {isAllFiles && <span style={{ ...Type.caption, fontWeight: 600 }}>Source</span>}
                <span style={{ ...Type.caption, fontWeight: 600, textAlign: "right" }}>Size</span>
                <span style={{ ...Type.caption, fontWeight: 600, textAlign: "right" }}>Modified</span>
                <span style={{ ...Type.caption, fontWeight: 600, textAlign: "center", color: agentColor }}>Shared</span>
              </div>

              {filteredFiles.map((f, i) => {
                const isShared = (agent === "Claude" && f.shared === "claude") || (agent === "Codex" && f.shared === "codex") || (agent === "Compare" && f.shared);
                return (
                  <div key={`${f.source}-${f.name}-${i}`} style={{
                    display: "grid",
                    gridTemplateColumns: isAllFiles ? "1fr 2fr 100px 80px 90px 70px" : "1fr 2fr 80px 90px 70px",
                    padding: "7px 16px", alignItems: "center",
                    borderBottom: "1px solid rgba(0,0,0,0.04)",
                    background: isShared ? agentTint : "transparent",
                    transition: "background 0.15s",
                  }}>
                    <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                      <div style={{ width: 4, height: 14, borderRadius: 2, background: fileIcon(f.ext), flexShrink: 0 }} />
                      <span style={{ ...Type.body, fontWeight: 500, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{f.name}</span>
                    </div>
                    <span style={{ ...Type.mono, color: Color.textSecondary, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{f.path}</span>
                    {isAllFiles && (
                      <span style={{
                        ...Type.caption, color: Color.textSecondary, cursor: "pointer",
                        overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
                      }} onClick={(e) => { e.stopPropagation(); setSelectedSource(f.source); }}>{f.source}</span>
                    )}
                    <span style={{ ...Type.numericCaption, textAlign: "right", color: Color.textSecondary }}>{f.size}</span>
                    <span style={{ ...Type.numericCaption, textAlign: "right", color: Color.textTertiary }}>{f.modified}</span>
                    <div style={{ display: "flex", justifyContent: "center", alignItems: "center", gap: 3, position: "relative" }}>
                      {f.shared === "claude" && <StatusDot color={Color.claudeBlue} size={7} />}
                      {f.shared === "codex" && <StatusDot color={Color.codexPurple} size={7} />}
                      {!f.shared && <span style={{ color: Color.textTertiary, cursor: "pointer", fontSize: 11 }} title="Click to share…">—</span>}
                    </div>
                  </div>
                );
              })}

              {/* Footer */}
              <div style={{ padding: "10px 16px", ...Type.caption, color: Color.textTertiary, display: "flex", justifyContent: "space-between" }}>
                <span>
                  {filteredFiles.length} {filteredFiles.length === 1 ? "file" : "files"}
                  {searchText && ` matching "${searchText}"`}
                  {!isAllFiles && currentSource && ` in ${selectedSource}`}
                </span>
                <span>
                  {filteredFiles.filter(f => f.shared).length} shared with agents
                </span>
              </div>
            </>
          )}
        </div>
      </div>
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════════════
// EMAILS — RULES VIEW (replaces flat Domains tab)
// Progressive disclosure: Shields (auto) → Domain/Contact/Keyword rules → Default policy
// Inspired by Little Snitch's per-connection governance + DLP shield categories
// ═══════════════════════════════════════════════════════════════════════

const shields = [
  {
    id: "security", name: "Security & 2FA", enabled: true,
    description: "Blocks AI agents from accessing one-time passwords, verification codes, password resets, login alerts, and account recovery emails.",
    domains: ["accounts.google.com", "appleid.apple.com", "login.microsoft.com", "id.heroku.com"],
    patterns: ["verification code", "one-time password", "security alert", "sign-in attempt", "reset your password", "confirm your email", "expires in \\d+ minutes"],
    blocked: 23, recent: [
      { subject: "Your verification code is 847291", from: "noreply@google.com", date: "Apr 11", agent: "claude" },
      { subject: "Sign-in from new device", from: "appleid@id.apple.com", date: "Apr 10", agent: "codex" },
      { subject: "Reset your GitHub password", from: "noreply@github.com", date: "Apr 8", agent: "claude" },
    ],
  },
  {
    id: "financial", name: "Financial", enabled: true,
    description: "Blocks access to bank statements, transaction alerts, credit card notifications, invoices with account numbers, and tax documents.",
    domains: ["alerts.chase.com", "statements.amex.com", "venmo.com", "receipts.stripe.com", "turbotax.intuit.com"],
    patterns: ["statement ready", "transaction alert", "payment received", "your balance", "tax document", "account ****"],
    blocked: 14, recent: [
      { subject: "Your March statement is ready", from: "statements@chase.com", date: "Apr 1", agent: "claude" },
      { subject: "You paid $49.00 to Stripe", from: "venmo@venmo.com", date: "Mar 28", agent: "codex" },
    ],
  },
  {
    id: "medical", name: "Medical", enabled: true,
    description: "Blocks access to appointment confirmations, lab results, prescription notifications, insurance claims, and provider messages.",
    domains: ["mychart.com", "messages.healthsystem.org", "portal.onemedical.com"],
    patterns: ["appointment confirmation", "lab results", "prescription ready", "your visit summary", "health record"],
    blocked: 3, recent: [
      { subject: "Appointment confirmed: Apr 15 at 2:00 PM", from: "noreply@mychart.com", date: "Apr 9", agent: "claude" },
    ],
  },
  {
    id: "legal", name: "Legal", enabled: false,
    description: "Blocks emails containing legal notices, attorney correspondence, NDAs, and content marked privileged or confidential.",
    domains: [],
    patterns: ["attorney-client", "privileged and confidential", "do not forward", "legal notice", "NDA", "subpoena"],
    blocked: 0, recent: [],
  },
  {
    id: "personal", name: "Personal", enabled: false,
    description: "Blocks emails from contacts you mark as personal — family, friends, and private services. Configure your personal contacts below.",
    domains: [],
    patterns: [],
    blocked: 0, recent: [],
  },
];

const domainRules = [
  { domain: "github.com", emails: 412, action: "allow", category: "Work", agents: ["claude", "codex"] },
  { domain: "linear.app", emails: 89, action: "allow", category: "Work", agents: ["claude"] },
  { domain: "email.apple.com", emails: 805, action: "allow", category: "Work", agents: ["claude"] },
  { domain: "figma.com", emails: 45, action: "allow", category: "Work", agents: ["codex"] },
  { domain: "notion.so", emails: 67, action: "allow", category: "Work", agents: ["claude"] },
  { domain: "stripe.com", emails: 38, action: "block", category: "Financial", agents: ["all"], shieldOverlap: "Financial" },
  { domain: "amazonses.com", emails: 234, action: "block", category: "Automated", agents: ["all"] },
  { domain: "sendgrid.net", emails: 156, action: "block", category: "Automated", agents: ["all"] },
  { domain: "mailchimp.com", emails: 23, action: "block", category: "Automated", agents: ["all"] },
  { domain: "icloud.com", emails: 34, action: "block", category: "Personal", agents: ["all"] },
  { domain: "gmail.com", emails: 12, action: "block", category: "Personal", agents: ["all"] },
  { domain: "e.nfl.com", emails: 1, action: "block", category: "Automated", agents: ["all"] },
];

const contactRules = [
  { name: "Sarah Chen", email: "sarah@figma.com", action: "allow", overrides: "Figma domain (Codex only) → allow both agents", agents: ["claude", "codex"] },
  { name: "Dr. Kumar", email: "dkumar@onemedical.com", action: "block", overrides: "Medical shield + domain block", agents: ["all"] },
  { name: "Mom", email: "priya.gandhi@gmail.com", action: "block", overrides: "Gmail domain block", agents: ["all"] },
];

const keywordRules = [
  { pattern: "confidential", matchIn: "Subject + Body", action: "block", matched: 7, agents: ["all"] },
  { pattern: "SSN|social security", matchIn: "Body", action: "block", matched: 0, agents: ["all"], isRegex: true },
];

// ═══════════════════════════════════════════════════════════════════════
// RULE CREATION FORMS — Inline expanding forms for Add Domain/Contact/Keyword
// Pattern: expand below toolbar, green "what this will do" preview,
// agent selection with colored checkboxes, Allow/Block segmented control.
// Follows ReviewAccessSheet pattern from the Swift codebase.
// ═══════════════════════════════════════════════════════════════════════

// Agent checkbox selector — colored squares for Claude/Codex/Both
function AgentCheckboxSelector({ selected, onChange }) {
  const toggle = (agent) => {
    const next = new Set(selected);
    if (next.has(agent)) { if (next.size > 1) next.delete(agent); } // at least one
    else next.add(agent);
    onChange([...next]);
  };
  return (
    <div style={{ display: "flex", gap: 10, alignItems: "center" }}>
      {[
        { key: "claude", label: "Claude", color: Color.claudeBlue },
        { key: "codex", label: "Codex", color: Color.codexPurple },
      ].map(a => (
        <label key={a.key} style={{ display: "flex", alignItems: "center", gap: 5, cursor: "pointer", fontSize: 12 }}>
          <div onClick={() => toggle(a.key)} style={{
            width: 16, height: 16, borderRadius: 4, border: `1.5px solid ${selected.includes(a.key) ? a.color : "rgba(0,0,0,0.2)"}`,
            background: selected.includes(a.key) ? a.color : "transparent",
            display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer", transition: "all 0.15s",
          }}>
            {selected.includes(a.key) && (
              <svg width={10} height={10} viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth={3} strokeLinecap="round" strokeLinejoin="round">
                <path d="M9 12l2 2 4-4" />
              </svg>
            )}
          </div>
          <span style={{ color: selected.includes(a.key) ? Color.textPrimary : Color.textSecondary }}>{a.label}</span>
        </label>
      ))}
      <button onClick={() => onChange(["claude", "codex"])} style={{
        border: "none", background: "none", cursor: "pointer", fontSize: 11, color: Color.textTertiary,
        padding: "2px 6px", borderRadius: 4,
        fontWeight: selected.length === 2 ? 500 : 400,
      }}>Both</button>
    </div>
  );
}

// Action segmented control — Allow / Block
function ActionSegmented({ value, onChange }) {
  return (
    <div style={{ display: "flex", background: "rgba(0,0,0,0.05)", borderRadius: 6, padding: 2 }}>
      {[
        { key: "allow", label: "Allow", color: "#2d9e4e", bg: "rgba(52,199,89,0.12)" },
        { key: "block", label: "Block", color: "#d63030", bg: "rgba(255,59,48,0.1)" },
      ].map(opt => (
        <button key={opt.key} onClick={() => onChange(opt.key)} style={{
          padding: "4px 14px", borderRadius: 4, border: "none", cursor: "pointer", fontSize: 12, fontWeight: 500,
          background: value === opt.key ? "white" : "transparent",
          color: value === opt.key ? opt.color : Color.textSecondary,
          boxShadow: value === opt.key ? "0 0.5px 2px rgba(0,0,0,0.1)" : "none",
          transition: "all 0.15s",
        }}>{opt.label}</button>
      ))}
    </div>
  );
}

// "What this will do" green preview strip (matches ReviewAccessSheet pattern)
function RulePreview({ text }) {
  if (!text) return null;
  return (
    <div style={{
      padding: "8px 12px", borderRadius: 6, marginTop: 10,
      background: "rgba(52,199,89,0.06)", border: "1px solid rgba(52,199,89,0.2)",
      fontSize: 12, color: "#2d6e3e", lineHeight: 1.4,
      display: "flex", alignItems: "flex-start", gap: 6,
    }}>
      <span style={{ flexShrink: 0, marginTop: 1 }}>✓</span>
      <span>{text}</span>
    </div>
  );
}

// ─── ADD DOMAIN RULE FORM ────────────────────────────────────────────
function AddDomainForm({ onClose, onAdd }) {
  const [domain, setDomain] = useState("");
  const [action, setAction] = useState("block");
  const [category, setCategory] = useState("Work");
  const [agents, setAgents] = useState(["claude", "codex"]);

  const cleanDomain = domain.replace(/^@/, "").trim();
  const isValid = cleanDomain.length > 0 && cleanDomain.includes(".");
  const agentLabel = agents.length === 2 ? "both agents" : agents[0] === "claude" ? "Claude" : "Codex";
  const preview = isValid
    ? `${action === "block" ? "Block" : "Allow"} ${agentLabel} ${action === "block" ? "from seeing" : "to see"} emails from @${cleanDomain}`
    : null;

  return (
    <div style={{
      padding: "14px 16px", borderBottom: `1px solid ${Color.border}`,
      background: "rgba(0,122,255,0.02)",
    }}>
      <div style={{ display: "flex", alignItems: "flex-start", justifyContent: "space-between", marginBottom: 10 }}>
        <span style={{ ...Type.heading, fontSize: 13 }}>New Domain Rule</span>
        <button onClick={onClose} style={{ border: "none", background: "transparent", cursor: "pointer", padding: 0, color: Color.textTertiary, fontSize: 14 }}>✕</button>
      </div>

      <div style={{ display: "flex", gap: 16, alignItems: "flex-start", flexWrap: "wrap" }}>
        {/* Domain input */}
        <div style={{ flex: "1 1 200px" }}>
          <div style={{ ...Type.caption, fontWeight: 600, marginBottom: 4 }}>Domain</div>
          <div style={{
            display: "flex", alignItems: "center", gap: 4, background: "white",
            border: `1px solid ${isValid ? "rgba(52,199,89,0.4)" : domain ? "rgba(255,59,48,0.3)" : Color.border}`,
            borderRadius: 6, padding: "5px 8px", transition: "border 0.15s",
          }}>
            <span style={{ color: Color.textTertiary, fontSize: 13 }}>@</span>
            <input
              type="text" placeholder="example.com" value={domain} onChange={e => setDomain(e.target.value)}
              autoFocus
              style={{ border: "none", background: "transparent", outline: "none", flex: 1, fontSize: 13, color: Color.textPrimary }}
            />
          </div>
          <div style={{ ...Type.caption, color: Color.textTertiary, marginTop: 3 }}>Use *.domain.com for subdomains</div>
        </div>

        {/* Category */}
        <div style={{ flex: "0 0 120px" }}>
          <div style={{ ...Type.caption, fontWeight: 600, marginBottom: 4 }}>Category</div>
          <select value={category} onChange={e => setCategory(e.target.value)} style={{
            width: "100%", padding: "5px 8px", borderRadius: 6, border: `1px solid ${Color.border}`,
            fontSize: 13, color: Color.textPrimary, background: "white", outline: "none", cursor: "pointer",
          }}>
            {["Work", "Financial", "Automated", "Personal", "Other"].map(c => (
              <option key={c} value={c}>{c}</option>
            ))}
          </select>
        </div>

        {/* Action */}
        <div>
          <div style={{ ...Type.caption, fontWeight: 600, marginBottom: 4 }}>Action</div>
          <ActionSegmented value={action} onChange={setAction} />
        </div>

        {/* Agents */}
        <div>
          <div style={{ ...Type.caption, fontWeight: 600, marginBottom: 4 }}>Applies to</div>
          <AgentCheckboxSelector selected={agents} onChange={setAgents} />
        </div>
      </div>

      {/* Preview strip */}
      <RulePreview text={preview} />

      {/* Actions */}
      <div style={{ display: "flex", justifyContent: "flex-end", gap: 8, marginTop: 12 }}>
        <button onClick={onClose} style={{
          padding: "5px 14px", borderRadius: 6, border: `1px solid ${Color.border}`,
          background: "white", cursor: "pointer", fontSize: 12, color: Color.textSecondary,
        }}>Cancel</button>
        <button disabled={!isValid} onClick={() => { onAdd?.({ domain: cleanDomain, action, category, agents }); onClose(); }} style={{
          padding: "5px 14px", borderRadius: 6, border: "none",
          background: isValid ? Color.claudeBlue : "rgba(0,0,0,0.06)",
          cursor: isValid ? "pointer" : "default", fontSize: 12, fontWeight: 500,
          color: isValid ? "white" : Color.textTertiary,
          transition: "all 0.15s",
        }}>Add Rule</button>
      </div>
    </div>
  );
}

// ─── ADD CONTACT RULE FORM ───────────────────────────────────────────
function AddContactForm({ onClose, onAdd }) {
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [action, setAction] = useState("allow");
  const [agents, setAgents] = useState(["claude", "codex"]);

  const isValid = email.includes("@") && email.includes(".");
  const agentLabel = agents.length === 2 ? "both agents" : agents[0] === "claude" ? "Claude" : "Codex";
  const emailDomain = email.split("@")[1] || "";
  const preview = isValid
    ? `${action === "allow" ? "Allow" : "Block"} ${agentLabel} ${action === "allow" ? "to see" : "from seeing"} emails from ${name || email}${emailDomain ? ` — overrides any @${emailDomain} domain rule or shield` : ""}`
    : null;

  return (
    <div style={{
      padding: "14px 16px", borderBottom: `1px solid ${Color.border}`,
      background: "rgba(0,122,255,0.02)",
    }}>
      <div style={{ display: "flex", alignItems: "flex-start", justifyContent: "space-between", marginBottom: 10 }}>
        <span style={{ ...Type.heading, fontSize: 13 }}>New Contact Rule</span>
        <button onClick={onClose} style={{ border: "none", background: "transparent", cursor: "pointer", padding: 0, color: Color.textTertiary, fontSize: 14 }}>✕</button>
      </div>

      <div style={{ display: "flex", gap: 16, alignItems: "flex-start", flexWrap: "wrap" }}>
        {/* Name */}
        <div style={{ flex: "0 1 160px" }}>
          <div style={{ ...Type.caption, fontWeight: 600, marginBottom: 4 }}>Name <span style={{ fontWeight: 400 }}>(optional)</span></div>
          <input type="text" placeholder="Sarah Chen" value={name} onChange={e => setName(e.target.value)} autoFocus style={{
            width: "100%", padding: "5px 8px", borderRadius: 6, border: `1px solid ${Color.border}`,
            fontSize: 13, color: Color.textPrimary, background: "white", outline: "none", boxSizing: "border-box",
          }} />
        </div>

        {/* Email */}
        <div style={{ flex: "1 1 220px" }}>
          <div style={{ ...Type.caption, fontWeight: 600, marginBottom: 4 }}>Email address</div>
          <input type="email" placeholder="sarah@company.com" value={email} onChange={e => setEmail(e.target.value)} style={{
            width: "100%", padding: "5px 8px", borderRadius: 6,
            border: `1px solid ${isValid ? "rgba(52,199,89,0.4)" : email ? "rgba(255,59,48,0.3)" : Color.border}`,
            fontSize: 13, color: Color.textPrimary, background: "white", outline: "none", boxSizing: "border-box",
            transition: "border 0.15s",
          }} />
        </div>

        {/* Action */}
        <div>
          <div style={{ ...Type.caption, fontWeight: 600, marginBottom: 4 }}>Action</div>
          <ActionSegmented value={action} onChange={setAction} />
        </div>

        {/* Agents */}
        <div>
          <div style={{ ...Type.caption, fontWeight: 600, marginBottom: 4 }}>Applies to</div>
          <AgentCheckboxSelector selected={agents} onChange={setAgents} />
        </div>
      </div>

      <div style={{ marginTop: 6, ...Type.caption, color: Color.textTertiary, lineHeight: 1.4 }}>
        Contact rules are the most specific — they override domain rules and shields for this sender.
      </div>

      <RulePreview text={preview} />

      <div style={{ display: "flex", justifyContent: "flex-end", gap: 8, marginTop: 12 }}>
        <button onClick={onClose} style={{
          padding: "5px 14px", borderRadius: 6, border: `1px solid ${Color.border}`,
          background: "white", cursor: "pointer", fontSize: 12, color: Color.textSecondary,
        }}>Cancel</button>
        <button disabled={!isValid} onClick={() => { onAdd?.({ name, email, action, agents }); onClose(); }} style={{
          padding: "5px 14px", borderRadius: 6, border: "none",
          background: isValid ? Color.claudeBlue : "rgba(0,0,0,0.06)",
          cursor: isValid ? "pointer" : "default", fontSize: 12, fontWeight: 500,
          color: isValid ? "white" : Color.textTertiary, transition: "all 0.15s",
        }}>Add Rule</button>
      </div>
    </div>
  );
}

// ─── ADD KEYWORD RULE FORM ───────────────────────────────────────────
function AddKeywordForm({ onClose, onAdd }) {
  const [pattern, setPattern] = useState("");
  const [matchIn, setMatchIn] = useState("Subject + Body");
  const [action, setAction] = useState("block");
  const [isRegex, setIsRegex] = useState(false);
  const [agents, setAgents] = useState(["claude", "codex"]);

  const isValid = pattern.trim().length > 0;
  const agentLabel = agents.length === 2 ? "both agents" : agents[0] === "claude" ? "Claude" : "Codex";
  const matchLabel = matchIn === "Subject" ? "in subject lines" : matchIn === "Body" ? "in email bodies" : "in subjects and bodies";
  const preview = isValid
    ? `${action === "block" ? "Block" : "Flag"} emails containing "${pattern}" ${matchLabel} for ${agentLabel}${isRegex ? " (regex pattern)" : ""}`
    : null;

  return (
    <div style={{
      padding: "14px 16px", borderBottom: `1px solid ${Color.border}`,
      background: "rgba(0,122,255,0.02)",
    }}>
      <div style={{ display: "flex", alignItems: "flex-start", justifyContent: "space-between", marginBottom: 10 }}>
        <span style={{ ...Type.heading, fontSize: 13 }}>New Keyword Rule</span>
        <button onClick={onClose} style={{ border: "none", background: "transparent", cursor: "pointer", padding: 0, color: Color.textTertiary, fontSize: 14 }}>✕</button>
      </div>

      <div style={{ display: "flex", gap: 16, alignItems: "flex-start", flexWrap: "wrap" }}>
        {/* Pattern input */}
        <div style={{ flex: "1 1 240px" }}>
          <div style={{ ...Type.caption, fontWeight: 600, marginBottom: 4 }}>Pattern</div>
          <div style={{
            display: "flex", alignItems: "center", gap: 6, background: "white",
            border: `1px solid ${isValid ? "rgba(52,199,89,0.4)" : Color.border}`,
            borderRadius: 6, padding: "5px 8px", transition: "border 0.15s",
          }}>
            <input
              type="text" placeholder={isRegex ? "SSN|social\\s+security" : "confidential"} value={pattern} onChange={e => setPattern(e.target.value)}
              autoFocus
              style={{
                border: "none", background: "transparent", outline: "none", flex: 1,
                fontSize: 13, fontFamily: isRegex ? "SF Mono, Menlo, monospace" : "inherit",
                color: Color.textPrimary,
              }}
            />
            <label style={{ display: "flex", alignItems: "center", gap: 3, cursor: "pointer", flexShrink: 0 }}>
              <input type="checkbox" checked={isRegex} onChange={e => setIsRegex(e.target.checked)} style={{ margin: 0 }} />
              <span style={{
                fontSize: 10, fontWeight: 600, color: isRegex ? Color.codexPurple : Color.textTertiary,
                padding: "1px 4px", borderRadius: 3,
                background: isRegex ? "rgba(139,92,246,0.12)" : "transparent",
              }}>REGEX</span>
            </label>
          </div>
          <div style={{ ...Type.caption, color: Color.textTertiary, marginTop: 3 }}>
            {isRegex ? "Use | for alternation, \\b for word boundaries" : "Case-insensitive text match"}
          </div>
        </div>

        {/* Match location */}
        <div style={{ flex: "0 0 140px" }}>
          <div style={{ ...Type.caption, fontWeight: 600, marginBottom: 4 }}>Match in</div>
          <select value={matchIn} onChange={e => setMatchIn(e.target.value)} style={{
            width: "100%", padding: "5px 8px", borderRadius: 6, border: `1px solid ${Color.border}`,
            fontSize: 13, color: Color.textPrimary, background: "white", outline: "none", cursor: "pointer",
          }}>
            {["Subject + Body", "Subject", "Body"].map(m => (
              <option key={m} value={m}>{m}</option>
            ))}
          </select>
        </div>

        {/* Action */}
        <div>
          <div style={{ ...Type.caption, fontWeight: 600, marginBottom: 4 }}>Action</div>
          <ActionSegmented value={action} onChange={setAction} />
        </div>

        {/* Agents */}
        <div>
          <div style={{ ...Type.caption, fontWeight: 600, marginBottom: 4 }}>Applies to</div>
          <AgentCheckboxSelector selected={agents} onChange={setAgents} />
        </div>
      </div>

      <RulePreview text={preview} />

      <div style={{ display: "flex", justifyContent: "flex-end", gap: 8, marginTop: 12 }}>
        <button onClick={onClose} style={{
          padding: "5px 14px", borderRadius: 6, border: `1px solid ${Color.border}`,
          background: "white", cursor: "pointer", fontSize: 12, color: Color.textSecondary,
        }}>Cancel</button>
        <button disabled={!isValid} onClick={() => { onAdd?.({ pattern, matchIn, action, isRegex, agents }); onClose(); }} style={{
          padding: "5px 14px", borderRadius: 6, border: "none",
          background: isValid ? Color.claudeBlue : "rgba(0,0,0,0.06)",
          cursor: isValid ? "pointer" : "default", fontSize: 12, fontWeight: 500,
          color: isValid ? "white" : Color.textTertiary, transition: "all 0.15s",
        }}>Add Rule</button>
      </div>
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════════════
// SHARE POPOVER — Unified sharing control for files, folders, and emails
// Same mental model everywhere: two agent toggles + plain-English summary.
// Appears contextually: on row actions, bulk toolbar, or right-click.
// ═══════════════════════════════════════════════════════════════════════

function SharePopover({ itemType = "file", itemName, itemCount, currentSharing, onClose, onApply, position }) {
  // currentSharing: { claude: bool, codex: bool }
  const [claude, setClaude] = useState(currentSharing?.claude ?? false);
  const [codex, setCodex] = useState(currentSharing?.codex ?? false);
  const isMultiple = itemCount && itemCount > 1;
  const label = isMultiple ? `${itemCount} ${itemType}s` : (itemName || `this ${itemType}`);

  const changes = [];
  if (claude !== (currentSharing?.claude ?? false)) changes.push(claude ? "share with Claude" : "unshare from Claude");
  if (codex !== (currentSharing?.codex ?? false)) changes.push(codex ? "share with Codex" : "unshare from Codex");
  const hasChanges = changes.length > 0;

  const summary = !claude && !codex
    ? `${isMultiple ? "These" : "This"} ${itemType}${isMultiple ? "s" : ""} won't be visible to any agent`
    : `Visible to ${[claude && "Claude", codex && "Codex"].filter(Boolean).join(" and ")}`;

  return (
    <div style={{
      position: position ? "absolute" : "relative",
      ...(position || {}),
      width: 280, background: "white", borderRadius: 10, border: `1px solid ${Color.border}`,
      boxShadow: "0 4px 16px rgba(0,0,0,0.12), 0 1px 3px rgba(0,0,0,0.08)",
      zIndex: 100, overflow: "hidden",
    }}>
      {/* Header */}
      <div style={{
        padding: "10px 14px 8px", borderBottom: `1px solid ${Color.border}`,
        display: "flex", justifyContent: "space-between", alignItems: "center",
      }}>
        <span style={{ ...Type.heading, fontSize: 12 }}>Share {label}</span>
        <button onClick={onClose} style={{ border: "none", background: "transparent", cursor: "pointer", padding: 0, color: Color.textTertiary, fontSize: 13 }}>✕</button>
      </div>

      {/* Agent toggles */}
      <div style={{ padding: "10px 14px" }}>
        {[
          { key: "claude", label: "Claude", color: Color.claudeBlue, value: claude, set: setClaude },
          { key: "codex", label: "Codex", color: Color.codexPurple, value: codex, set: setCodex },
        ].map(a => (
          <div key={a.key} style={{
            display: "flex", alignItems: "center", justifyContent: "space-between",
            padding: "6px 0",
          }}>
            <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
              <StatusDot color={a.color} size={8} />
              <span style={{ fontSize: 13, fontWeight: 500 }}>{a.label}</span>
            </div>
            <AgentToggle value={a.value} onChange={a.set} agent={a.key} />
          </div>
        ))}
      </div>

      {/* Summary */}
      <div style={{
        padding: "8px 14px", background: "rgba(0,0,0,0.02)", borderTop: `1px solid rgba(0,0,0,0.04)`,
        fontSize: 11, color: Color.textSecondary, lineHeight: 1.4,
      }}>
        {summary}
      </div>

      {/* Change preview (green strip when there are changes) */}
      {hasChanges && (
        <div style={{
          padding: "6px 14px", background: "rgba(52,199,89,0.06)",
          borderTop: "1px solid rgba(52,199,89,0.15)",
          fontSize: 11, color: "#2d6e3e",
        }}>
          Will {changes.join(" and ")}
        </div>
      )}

      {/* Actions */}
      <div style={{
        padding: "8px 14px 10px", display: "flex", justifyContent: "flex-end", gap: 6,
        borderTop: `1px solid ${Color.border}`,
      }}>
        <button onClick={onClose} style={{
          padding: "4px 12px", borderRadius: 5, border: `1px solid ${Color.border}`,
          background: "white", cursor: "pointer", fontSize: 11, color: Color.textSecondary,
        }}>Cancel</button>
        <button disabled={!hasChanges} onClick={() => { onApply?.({ claude, codex }); onClose(); }} style={{
          padding: "4px 12px", borderRadius: 5, border: "none",
          background: hasChanges ? Color.claudeBlue : "rgba(0,0,0,0.06)",
          cursor: hasChanges ? "pointer" : "default", fontSize: 11, fontWeight: 500,
          color: hasChanges ? "white" : Color.textTertiary, transition: "all 0.15s",
        }}>Apply</button>
      </div>
    </div>
  );
}

// Toolbar share button that toggles the SharePopover
function ShareToolbarButton({ itemType, itemCount, currentSharing }) {
  const [open, setOpen] = useState(false);
  return (
    <div style={{ position: "relative" }}>
      <button onClick={() => setOpen(!open)} style={{
        padding: "4px 10px", borderRadius: 5, border: `1px solid ${Color.claudeBlue}`,
        background: Color.claudeBlueBadge, cursor: "pointer", fontSize: 11, fontWeight: 500,
        color: Color.claudeBlue, display: "flex", alignItems: "center", gap: 4,
      }}>
        <Shield size={11} /> Share…
      </button>
      {open && (
        <SharePopover
          itemType={itemType}
          itemCount={itemCount}
          currentSharing={currentSharing || { claude: false, codex: false }}
          onClose={() => setOpen(false)}
          onApply={(sharing) => { /* would update state */ }}
          position={{ top: "100%", right: 0, marginTop: 4 }}
        />
      )}
    </div>
  );
}

// Small pill badge for rule actions
function ActionBadge({ action }) {
  const isAllow = action === "allow";
  return (
    <span style={{
      padding: "2px 8px", borderRadius: 4, fontSize: 11, fontWeight: 500,
      background: isAllow ? "rgba(52,199,89,0.12)" : "rgba(255,59,48,0.1)",
      color: isAllow ? "#2d9e4e" : "#d63030",
    }}>{isAllow ? "Allow" : "Block"}</span>
  );
}

// Agent dot cluster for multi-agent display
function AgentDots({ agents }) {
  if (!agents) return null;
  if (agents.includes("all")) return <span style={{ ...Type.caption, color: Color.textTertiary }}>All agents</span>;
  return (
    <div style={{ display: "flex", gap: 3, alignItems: "center" }}>
      {agents.includes("claude") && <StatusDot color={Color.claudeBlue} size={7} />}
      {agents.includes("codex") && <StatusDot color={Color.codexPurple} size={7} />}
    </div>
  );
}

function EmailsRulesTab() {
  const [section, setSection] = useState("Dashboard");
  const [shieldsState, setShieldsState] = useState(
    Object.fromEntries(shields.map(s => [s.id, s.enabled]))
  );
  const [agentDefaults, setAgentDefaults] = useState({ claude: "allow", codex: "allow" });
  const [expandedPatterns, setExpandedPatterns] = useState(false);
  const [showAddDomain, setShowAddDomain] = useState(false);
  const [showAddContact, setShowAddContact] = useState(false);
  const [showAddKeyword, setShowAddKeyword] = useState(false);

  const activeShields = shields.filter(s => shieldsState[s.id]);
  const totalBlocked = shields.reduce((sum, s) => sum + (shieldsState[s.id] ? s.blocked : 0), 0);
  const totalDomainRules = domainRules.length;
  const totalContactRules = contactRules.length;
  const totalKeywordRules = keywordRules.length;

  // Selected shield (if sidebar picked one)
  const selectedShield = shields.find(s => s.name === section);

  // Sidebar button helper
  const SidebarBtn = ({ label, icon, selected, onClick, trailing, indent }) => (
    <button onClick={onClick} style={{
      display: "flex", alignItems: "center", justifyContent: "space-between",
      padding: `5px ${indent ? 18 : 12}px`, gap: 8,
      border: "none", cursor: "pointer", width: "100%", textAlign: "left",
      background: selected ? Color.selected : "transparent",
      borderRadius: 6, margin: "0 4px", maxWidth: "calc(100% - 8px)",
      fontSize: 13, color: Color.textPrimary, lineHeight: 1.3,
    }}>
      <span style={{ display: "flex", alignItems: "center", gap: 7 }}>
        {icon}
        {label}
      </span>
      {trailing && <span style={{ ...Type.numericCaption, color: Color.textTertiary }}>{trailing}</span>}
    </button>
  );

  return (
    <div style={{ display: "flex", height: "100%" }}>
      {/* ── Sidebar ── */}
      <div style={{
        width: 220, borderRight: `1px solid ${Color.sidebarBorder}`,
        background: Color.sidebar, display: "flex", flexDirection: "column",
        overflow: "auto",
      }}>
        <SectionHeader>Overview</SectionHeader>
        <SidebarBtn
          label="Dashboard" selected={section === "Dashboard"} onClick={() => setSection("Dashboard")}
          icon={<Activity size={14} color={Color.textTertiary} />}
        />

        <div style={{ height: 8 }} />
        <SectionHeader count={activeShields.length}>Shields</SectionHeader>
        {shields.map(s => (
          <SidebarBtn key={s.id}
            label={s.name} selected={section === s.name} onClick={() => setSection(s.name)}
            icon={
              <Shield size={13} color={shieldsState[s.id] ? Color.statusActive : Color.textTertiary} />
            }
            trailing={shieldsState[s.id] ? `${s.blocked}` : "off"}
          />
        ))}

        <div style={{ height: 8 }} />
        <SectionHeader>Rules</SectionHeader>
        <SidebarBtn
          label="Domains" selected={section === "Domains"} onClick={() => setSection("Domains")}
          icon={<Globe size={14} color={Color.textTertiary} />}
          trailing={totalDomainRules}
        />
        <SidebarBtn
          label="Contacts" selected={section === "Contacts"} onClick={() => setSection("Contacts")}
          icon={<Mail size={14} color={Color.textTertiary} />}
          trailing={totalContactRules}
        />
        <SidebarBtn
          label="Keywords" selected={section === "Keywords"} onClick={() => setSection("Keywords")}
          icon={<Search size={14} color={Color.textTertiary} />}
          trailing={totalKeywordRules}
        />

        <div style={{ height: 8 }} />
        <SectionHeader>Policy</SectionHeader>
        <SidebarBtn
          label="Defaults" selected={section === "Defaults"} onClick={() => setSection("Defaults")}
          icon={<Settings size={14} color={Color.textTertiary} />}
        />

        <div style={{ flex: 1 }} />
        <div style={{ padding: "6px 12px 10px", fontSize: 11, color: Color.textTertiary }}>
          Priority: Contact → Keyword → Domain → Shield → Default
        </div>
      </div>

      {/* ── Main Content ── */}
      <div style={{ flex: 1, display: "flex", flexDirection: "column", overflow: "auto" }}>

        {/* ─── DASHBOARD ─── */}
        {section === "Dashboard" && (
          <div style={{ padding: 20, maxWidth: 740 }}>
            <div style={{ ...Type.sectionTitle, marginBottom: 4 }}>Protection Dashboard</div>
            <div style={{ ...Type.body, color: Color.textSecondary, marginBottom: 20 }}>
              {activeShields.length} shield{activeShields.length !== 1 ? "s" : ""} active · {totalDomainRules} domain rules · {totalContactRules} contact override{totalContactRules !== 1 ? "s" : ""} · {totalKeywordRules} keyword pattern{totalKeywordRules !== 1 ? "s" : ""}
            </div>

            {/* Agent stats cards */}
            <div style={{ display: "flex", gap: 12, marginBottom: 20 }}>
              {[
                { name: "Claude", color: Color.claudeBlue, tint: Color.claudeBlueTint, accessible: 342, blocked: 89 },
                { name: "Codex", color: Color.codexPurple, tint: Color.codexPurpleTint, accessible: 201, blocked: 230 },
              ].map(a => (
                <div key={a.name} style={{
                  flex: 1, borderRadius: 10, border: `1px solid ${Color.border}`,
                  padding: 16, borderLeft: `3px solid ${a.color}`,
                }}>
                  <div style={{ ...Type.heading, marginBottom: 10 }}>{a.name}</div>
                  <div style={{ display: "flex", gap: 16 }}>
                    <div>
                      <div style={{ fontSize: 22, fontWeight: 600, color: a.color }}>{a.accessible}</div>
                      <div style={{ ...Type.caption, color: Color.textSecondary }}>accessible</div>
                    </div>
                    <div>
                      <div style={{ fontSize: 22, fontWeight: 600, color: Color.textTertiary }}>{a.blocked}</div>
                      <div style={{ ...Type.caption, color: Color.textSecondary }}>blocked</div>
                    </div>
                    <div style={{ flex: 1 }}>
                      {/* Visual bar */}
                      <div style={{ height: 6, borderRadius: 3, background: "rgba(0,0,0,0.06)", marginTop: 8 }}>
                        <div style={{
                          height: "100%", borderRadius: 3, background: a.color,
                          width: `${(a.accessible / (a.accessible + a.blocked)) * 100}%`,
                          transition: "width 0.3s",
                        }} />
                      </div>
                      <div style={{ ...Type.caption, color: Color.textTertiary, marginTop: 3, textAlign: "right" }}>
                        {Math.round((a.accessible / (a.accessible + a.blocked)) * 100)}% visible
                      </div>
                    </div>
                  </div>
                </div>
              ))}
            </div>

            {/* Shield summary */}
            <div style={{ ...Type.heading, marginBottom: 8 }}>Active Shields</div>
            <div style={{ display: "flex", gap: 8, flexWrap: "wrap", marginBottom: 20 }}>
              {shields.map(s => (
                <div key={s.id} style={{
                  padding: "6px 12px", borderRadius: 8,
                  border: `1px solid ${shieldsState[s.id] ? "rgba(52,199,89,0.3)" : Color.border}`,
                  background: shieldsState[s.id] ? "rgba(52,199,89,0.06)" : "transparent",
                  display: "flex", alignItems: "center", gap: 6, cursor: "pointer",
                  fontSize: 12, color: shieldsState[s.id] ? Color.textPrimary : Color.textTertiary,
                }} onClick={() => setSection(s.name)}>
                  <Shield size={12} color={shieldsState[s.id] ? Color.statusActive : Color.textTertiary} />
                  {s.name}
                  {shieldsState[s.id] && <span style={{ color: Color.textSecondary, marginLeft: 4 }}>· {s.blocked} blocked</span>}
                </div>
              ))}
            </div>

            {/* Recent activity */}
            <div style={{ ...Type.heading, marginBottom: 8 }}>Recent Shield Activity</div>
            <div style={{ border: `1px solid ${Color.border}`, borderRadius: 8, overflow: "hidden" }}>
              <div style={{
                display: "grid", gridTemplateColumns: "1fr 180px 80px 70px",
                padding: "7px 14px", background: "rgba(0,0,0,0.02)",
                borderBottom: `1px solid ${Color.border}`,
              }}>
                <span style={{ ...Type.caption, fontWeight: 600 }}>Subject</span>
                <span style={{ ...Type.caption, fontWeight: 600 }}>From</span>
                <span style={{ ...Type.caption, fontWeight: 600 }}>Shield</span>
                <span style={{ ...Type.caption, fontWeight: 600 }}>Date</span>
              </div>
              {shields.filter(s => shieldsState[s.id]).flatMap(s =>
                s.recent.map((r, i) => ({ ...r, shieldName: s.name, shieldId: s.id }))
              ).sort((a, b) => b.date < a.date ? -1 : 1).slice(0, 6).map((r, i) => (
                <div key={i} style={{
                  display: "grid", gridTemplateColumns: "1fr 180px 80px 70px",
                  padding: "7px 14px", borderBottom: "1px solid rgba(0,0,0,0.04)",
                  fontSize: 13,
                }}>
                  <span style={{ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", color: Color.textPrimary }}>{r.subject}</span>
                  <span style={{ color: Color.textSecondary, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{r.from}</span>
                  <span style={{ ...Type.caption, color: Color.textTertiary }}>{r.shieldName.split(" ")[0]}</span>
                  <span style={{ ...Type.caption, color: Color.textTertiary }}>{r.date}</span>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* ─── SHIELD DETAIL ─── */}
        {selectedShield && (
          <div style={{ padding: 20, maxWidth: 700 }}>
            <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 4 }}>
              <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
                <Shield size={18} color={shieldsState[selectedShield.id] ? Color.statusActive : Color.textTertiary} />
                <span style={{ ...Type.sectionTitle }}>{selectedShield.name}</span>
              </div>
              {/* Toggle */}
              <button onClick={() => setShieldsState(prev => ({ ...prev, [selectedShield.id]: !prev[selectedShield.id] }))} style={{
                display: "flex", alignItems: "center", gap: 6, padding: "5px 14px",
                borderRadius: 6, border: `1px solid ${Color.border}`, cursor: "pointer",
                background: shieldsState[selectedShield.id] ? "rgba(52,199,89,0.1)" : "rgba(0,0,0,0.04)",
                fontSize: 13, fontWeight: 500,
                color: shieldsState[selectedShield.id] ? "#2d9e4e" : Color.textSecondary,
              }}>
                {shieldsState[selectedShield.id] ? "Active" : "Disabled"}
              </button>
            </div>
            <div style={{ ...Type.body, color: Color.textSecondary, marginBottom: 20, lineHeight: 1.5 }}>
              {selectedShield.description}
            </div>

            {/* Per-agent overrides */}
            <div style={{ ...Type.heading, marginBottom: 8 }}>Agent Access</div>
            <div style={{
              border: `1px solid ${Color.border}`, borderRadius: 8, padding: 12, marginBottom: 20,
              display: "flex", gap: 24,
            }}>
              {[
                { name: "Claude", color: Color.claudeBlue },
                { name: "Codex", color: Color.codexPurple },
              ].map(a => (
                <div key={a.name} style={{ display: "flex", alignItems: "center", gap: 8 }}>
                  <StatusDot color={a.color} size={8} />
                  <span style={{ fontSize: 13 }}>{a.name}</span>
                  <span style={{
                    padding: "2px 8px", borderRadius: 4, fontSize: 11, fontWeight: 500,
                    background: shieldsState[selectedShield.id] ? "rgba(255,59,48,0.1)" : "rgba(0,0,0,0.04)",
                    color: shieldsState[selectedShield.id] ? "#d63030" : Color.textTertiary,
                  }}>
                    {shieldsState[selectedShield.id] ? "Blocked" : "No shield"}
                  </span>
                </div>
              ))}
            </div>

            {/* Detection patterns */}
            <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 8 }}>
              <span style={{ ...Type.heading }}>Detection Patterns</span>
              <button onClick={() => setExpandedPatterns(!expandedPatterns)} style={{
                border: "none", background: "none", cursor: "pointer",
                fontSize: 12, color: Color.textSecondary,
              }}>{expandedPatterns ? "Collapse" : "Expand"}</button>
            </div>
            {(expandedPatterns || selectedShield.domains.length <= 4) && (
              <div style={{
                border: `1px solid ${Color.border}`, borderRadius: 8, padding: 14, marginBottom: 12,
                background: "rgba(0,0,0,0.015)",
              }}>
                {selectedShield.domains.length > 0 && (
                  <div style={{ marginBottom: 10 }}>
                    <div style={{ ...Type.caption, fontWeight: 600, marginBottom: 4, color: Color.textSecondary }}>Monitored domains</div>
                    <div style={{ display: "flex", flexWrap: "wrap", gap: 4 }}>
                      {selectedShield.domains.map(d => (
                        <span key={d} style={{
                          padding: "2px 8px", borderRadius: 4, fontSize: 11,
                          background: "rgba(0,0,0,0.05)", color: Color.textSecondary,
                        }}>@{d}</span>
                      ))}
                    </div>
                  </div>
                )}
                {selectedShield.patterns.length > 0 && (
                  <div>
                    <div style={{ ...Type.caption, fontWeight: 600, marginBottom: 4, color: Color.textSecondary }}>Subject & body patterns</div>
                    <div style={{ display: "flex", flexWrap: "wrap", gap: 4 }}>
                      {selectedShield.patterns.map(p => (
                        <span key={p} style={{
                          padding: "2px 8px", borderRadius: 4, fontSize: 11, fontFamily: "SF Mono, Menlo, monospace",
                          background: "rgba(255,149,0,0.08)", color: "#b37400",
                        }}>"{p}"</span>
                      ))}
                    </div>
                  </div>
                )}
              </div>
            )}

            {/* Recent matches */}
            {selectedShield.recent.length > 0 && (
              <>
                <div style={{ ...Type.heading, marginBottom: 8, marginTop: 8 }}>
                  Recent Matches ({selectedShield.blocked} total)
                </div>
                <div style={{ border: `1px solid ${Color.border}`, borderRadius: 8, overflow: "hidden" }}>
                  {selectedShield.recent.map((r, i) => (
                    <div key={i} style={{
                      display: "grid", gridTemplateColumns: "1fr 200px 60px",
                      padding: "7px 14px", borderBottom: i < selectedShield.recent.length - 1 ? "1px solid rgba(0,0,0,0.04)" : "none",
                      fontSize: 13,
                    }}>
                      <span style={{ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{r.subject}</span>
                      <span style={{ color: Color.textSecondary, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{r.from}</span>
                      <span style={{ ...Type.caption, color: Color.textTertiary }}>{r.date}</span>
                    </div>
                  ))}
                </div>
              </>
            )}

            {selectedShield.recent.length === 0 && shieldsState[selectedShield.id] && (
              <div style={{ padding: "24px 0", textAlign: "center", color: Color.textTertiary, fontSize: 13 }}>
                No emails matched this shield yet.
              </div>
            )}

            {/* Footer CTA */}
            <div style={{
              marginTop: 20, padding: "10px 14px", borderRadius: 8,
              background: "rgba(0,0,0,0.02)", border: `1px solid ${Color.border}`,
              fontSize: 12, color: Color.textSecondary,
            }}>
              Shield missing something? <span style={{ color: Color.claudeBlue, cursor: "pointer" }} onClick={() => setSection("Keywords")}>Add a keyword rule →</span>
            </div>
          </div>
        )}

        {/* ─── DOMAINS ─── */}
        {section === "Domains" && (
          <div style={{ display: "flex", flexDirection: "column", height: "100%" }}>
            <div style={{
              padding: "10px 16px", display: "flex", alignItems: "center", justifyContent: "space-between",
              borderBottom: `1px solid ${Color.border}`,
            }}>
              <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
                <span style={{ ...Type.sectionTitle }}>Domain Rules</span>
                <span style={{ ...Type.caption, color: Color.textSecondary }}>{totalDomainRules} rules</span>
              </div>
              <button onClick={() => setShowAddDomain(!showAddDomain)} style={{
                padding: "4px 12px", borderRadius: 6, border: `1px solid ${showAddDomain ? Color.claudeBlue : Color.border}`,
                background: showAddDomain ? Color.claudeBlueBadge : "white", cursor: "pointer", fontSize: 12, display: "flex", alignItems: "center", gap: 4,
                color: showAddDomain ? Color.claudeBlue : Color.textPrimary, fontWeight: showAddDomain ? 500 : 400,
              }}>
                <Plus size={13} /> Add Domain
              </button>
            </div>
            {showAddDomain && <AddDomainForm onClose={() => setShowAddDomain(false)} />}
            <div style={{ flex: 1, overflow: "auto" }}>
              <div style={{
                display: "grid", gridTemplateColumns: "1fr 90px 80px 60px 90px",
                padding: "7px 16px", borderBottom: `1px solid ${Color.border}`,
                position: "sticky", top: 0, background: Color.bg, zIndex: 1,
              }}>
                <span style={{ ...Type.caption, fontWeight: 600 }}>Domain</span>
                <span style={{ ...Type.caption, fontWeight: 600 }}>Category</span>
                <span style={{ ...Type.caption, fontWeight: 600, textAlign: "right" }}>Emails</span>
                <span style={{ ...Type.caption, fontWeight: 600, textAlign: "center" }}>Rule</span>
                <span style={{ ...Type.caption, fontWeight: 600, textAlign: "center" }}>Agents</span>
              </div>
              {domainRules.map((d, i) => {
                const textStyle = d.emails >= 100 ? { ...Type.body, fontWeight: 500 } : d.emails >= 10 ? { ...Type.body, color: Color.textSecondary } : { ...Type.caption, fontSize: 13 };
                return (
                  <div key={d.domain} style={{
                    display: "grid", gridTemplateColumns: "1fr 90px 80px 60px 90px",
                    padding: "7px 16px", alignItems: "center",
                    borderBottom: "1px solid rgba(0,0,0,0.04)",
                    background: d.action === "allow" ? "rgba(52,199,89,0.03)" : "transparent",
                  }}>
                    <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
                      <span style={textStyle}>@{d.domain}</span>
                      {d.shieldOverlap && (
                        <Shield size={10} color={Color.statusActive} title={`Also covered by ${d.shieldOverlap} shield`} />
                      )}
                    </div>
                    <span style={{ ...Type.caption, color: Color.textTertiary }}>{d.category}</span>
                    <span style={{ ...Type.numericCaption, textAlign: "right", color: Color.textSecondary }}>
                      {d.emails}
                    </span>
                    <div style={{ display: "flex", justifyContent: "center" }}>
                      <ActionBadge action={d.action} />
                    </div>
                    <div style={{ display: "flex", justifyContent: "center" }}>
                      <AgentDots agents={d.agents} />
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        )}

        {/* ─── CONTACTS ─── */}
        {section === "Contacts" && (
          <div style={{ display: "flex", flexDirection: "column", height: "100%" }}>
            <div style={{
              padding: "10px 16px", display: "flex", alignItems: "center", justifyContent: "space-between",
              borderBottom: `1px solid ${Color.border}`,
            }}>
              <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
                <span style={{ ...Type.sectionTitle }}>Contact Rules</span>
                <span style={{ ...Type.caption, color: Color.textSecondary }}>{totalContactRules} overrides</span>
              </div>
              <button onClick={() => setShowAddContact(!showAddContact)} style={{
                padding: "4px 12px", borderRadius: 6, border: `1px solid ${showAddContact ? Color.claudeBlue : Color.border}`,
                background: showAddContact ? Color.claudeBlueBadge : "white", cursor: "pointer", fontSize: 12, display: "flex", alignItems: "center", gap: 4,
                color: showAddContact ? Color.claudeBlue : Color.textPrimary, fontWeight: showAddContact ? 500 : 400,
              }}>
                <Plus size={13} /> Add Contact
              </button>
            </div>
            {showAddContact && <AddContactForm onClose={() => setShowAddContact(false)} />}
            {!showAddContact && (
              <div style={{ padding: 16, color: Color.textSecondary, fontSize: 13, lineHeight: 1.5, maxWidth: 560 }}>
                Contact rules override domain rules and shields for specific senders. Use them when you need an exception — for example, allowing a specific person at a domain you've otherwise blocked.
              </div>
            )}
            <div style={{ flex: 1, overflow: "auto", padding: "0 16px" }}>
              <div style={{
                display: "grid", gridTemplateColumns: "120px 200px 60px 1fr 80px",
                padding: "7px 0", borderBottom: `1px solid ${Color.border}`,
              }}>
                <span style={{ ...Type.caption, fontWeight: 600 }}>Name</span>
                <span style={{ ...Type.caption, fontWeight: 600 }}>Email</span>
                <span style={{ ...Type.caption, fontWeight: 600, textAlign: "center" }}>Rule</span>
                <span style={{ ...Type.caption, fontWeight: 600 }}>Overrides</span>
                <span style={{ ...Type.caption, fontWeight: 600, textAlign: "center" }}>Agents</span>
              </div>
              {contactRules.map((c, i) => (
                <div key={c.email} style={{
                  display: "grid", gridTemplateColumns: "120px 200px 60px 1fr 80px",
                  padding: "8px 0", alignItems: "center",
                  borderBottom: "1px solid rgba(0,0,0,0.04)",
                }}>
                  <span style={{ ...Type.body, fontWeight: 500 }}>{c.name}</span>
                  <span style={{ ...Type.mono, color: Color.textSecondary }}>{c.email}</span>
                  <div style={{ display: "flex", justifyContent: "center" }}>
                    <ActionBadge action={c.action} />
                  </div>
                  <span style={{ ...Type.caption, color: Color.textTertiary }}>{c.overrides}</span>
                  <div style={{ display: "flex", justifyContent: "center" }}>
                    <AgentDots agents={c.agents} />
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* ─── KEYWORDS ─── */}
        {section === "Keywords" && (
          <div style={{ display: "flex", flexDirection: "column", height: "100%" }}>
            <div style={{
              padding: "10px 16px", display: "flex", alignItems: "center", justifyContent: "space-between",
              borderBottom: `1px solid ${Color.border}`,
            }}>
              <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
                <span style={{ ...Type.sectionTitle }}>Keyword Rules</span>
                <span style={{ ...Type.caption, color: Color.textSecondary }}>{totalKeywordRules} patterns</span>
              </div>
              <button onClick={() => setShowAddKeyword(!showAddKeyword)} style={{
                padding: "4px 12px", borderRadius: 6, border: `1px solid ${showAddKeyword ? Color.claudeBlue : Color.border}`,
                background: showAddKeyword ? Color.claudeBlueBadge : "white", cursor: "pointer", fontSize: 12, display: "flex", alignItems: "center", gap: 4,
                color: showAddKeyword ? Color.claudeBlue : Color.textPrimary, fontWeight: showAddKeyword ? 500 : 400,
              }}>
                <Plus size={13} /> Add Pattern
              </button>
            </div>
            {showAddKeyword && <AddKeywordForm onClose={() => setShowAddKeyword(false)} />}
            {!showAddKeyword && (
              <div style={{ padding: 16, color: Color.textSecondary, fontSize: 13, lineHeight: 1.5, maxWidth: 560 }}>
                Keyword rules catch emails containing specific text patterns, regardless of sender or domain. Use regex for advanced matching.
              </div>
            )}
            <div style={{ flex: 1, overflow: "auto", padding: "0 16px" }}>
              <div style={{
                display: "grid", gridTemplateColumns: "1fr 120px 60px 70px 80px",
                padding: "7px 0", borderBottom: `1px solid ${Color.border}`,
              }}>
                <span style={{ ...Type.caption, fontWeight: 600 }}>Pattern</span>
                <span style={{ ...Type.caption, fontWeight: 600 }}>Match In</span>
                <span style={{ ...Type.caption, fontWeight: 600, textAlign: "center" }}>Rule</span>
                <span style={{ ...Type.caption, fontWeight: 600, textAlign: "right" }}>Matched</span>
                <span style={{ ...Type.caption, fontWeight: 600, textAlign: "center" }}>Agents</span>
              </div>
              {keywordRules.map((k, i) => (
                <div key={k.pattern} style={{
                  display: "grid", gridTemplateColumns: "1fr 120px 60px 70px 80px",
                  padding: "8px 0", alignItems: "center",
                  borderBottom: "1px solid rgba(0,0,0,0.04)",
                }}>
                  <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
                    <span style={{ fontFamily: "SF Mono, Menlo, monospace", fontSize: 12, color: Color.textPrimary }}>
                      "{k.pattern}"
                    </span>
                    {k.isRegex && (
                      <span style={{
                        padding: "1px 5px", borderRadius: 3, fontSize: 9, fontWeight: 600,
                        background: "rgba(139,92,246,0.12)", color: Color.codexPurple,
                      }}>REGEX</span>
                    )}
                  </div>
                  <span style={{ ...Type.caption, color: Color.textSecondary }}>{k.matchIn}</span>
                  <div style={{ display: "flex", justifyContent: "center" }}>
                    <ActionBadge action={k.action} />
                  </div>
                  <span style={{ ...Type.numericCaption, textAlign: "right", color: Color.textSecondary }}>
                    {k.matched}
                  </span>
                  <div style={{ display: "flex", justifyContent: "center" }}>
                    <AgentDots agents={k.agents} />
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* ─── DEFAULTS ─── */}
        {section === "Defaults" && (
          <div style={{ padding: 20, maxWidth: 600 }}>
            <div style={{ ...Type.sectionTitle, marginBottom: 4 }}>Default Policy</div>
            <div style={{ ...Type.body, color: Color.textSecondary, marginBottom: 20, lineHeight: 1.5 }}>
              When an email doesn't match any shield, domain rule, contact rule, or keyword rule, the default policy decides whether the agent can see it. Set this per agent to match your trust level.
            </div>

            {[
              { name: "Claude", color: Color.claudeBlue, key: "claude" },
              { name: "Codex", color: Color.codexPurple, key: "codex" },
            ].map(a => (
              <div key={a.key} style={{
                border: `1px solid ${Color.border}`, borderRadius: 10,
                borderLeft: `3px solid ${a.color}`, padding: 16, marginBottom: 12,
              }}>
                <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 10 }}>
                  <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                    <StatusDot color={a.color} size={8} />
                    <span style={{ ...Type.heading }}>{a.name}</span>
                  </div>
                </div>
                <div style={{ display: "flex", background: "rgba(0,0,0,0.05)", borderRadius: 8, padding: 3 }}>
                  {[
                    { value: "allow", label: "Allow unless blocked", desc: "Agent sees all emails except those caught by shields and rules" },
                    { value: "block", label: "Block unless allowed", desc: "Agent sees nothing unless a rule explicitly allows it" },
                  ].map(opt => (
                    <button key={opt.value} onClick={() => setAgentDefaults(prev => ({ ...prev, [a.key]: opt.value }))} style={{
                      flex: 1, padding: "8px 12px", borderRadius: 6, border: "none", cursor: "pointer",
                      background: agentDefaults[a.key] === opt.value ? "white" : "transparent",
                      boxShadow: agentDefaults[a.key] === opt.value ? "0 1px 3px rgba(0,0,0,0.1)" : "none",
                      textAlign: "left",
                    }}>
                      <div style={{ fontSize: 12, fontWeight: agentDefaults[a.key] === opt.value ? 500 : 400, color: Color.textPrimary }}>{opt.label}</div>
                      <div style={{ fontSize: 11, color: Color.textTertiary, marginTop: 2 }}>{opt.desc}</div>
                    </button>
                  ))}
                </div>
                {agentDefaults[a.key] === "block" && (
                  <div style={{
                    marginTop: 10, padding: "8px 12px", borderRadius: 6,
                    background: "rgba(255,149,0,0.08)", fontSize: 12, color: "#b37400",
                  }}>
                    ⚠ {a.name} won't see any emails unless you add allow rules above. This is high-security mode.
                  </div>
                )}
              </div>
            ))}

            <div style={{
              marginTop: 12, padding: 14, borderRadius: 8,
              background: "rgba(0,0,0,0.02)", border: `1px solid ${Color.border}`,
              fontSize: 12, color: Color.textSecondary, lineHeight: 1.5,
            }}>
              <strong>Evaluation order:</strong> When an email arrives, Manifold checks Contact rules first (most specific), then Keywords, then Domains, then Shields. If none match, this default applies. This means a contact "allow" override will always beat a domain "block" rule.
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════════════
// EMAILS — MESSAGES VIEW (Synology Active Backup–style governance browser)
// NOT a mail client. Focus: selection, search, bulk operations, access control.
// Click-to-preview, table with checkboxes, agent access toggles.
// ═══════════════════════════════════════════════════════════════════════

const allMessages = [
  { id: 1, from: "noreply@github.com", fromName: "GitHub", to: "amar.gandhi@me.com", subject: "Pull request #42 merged", date: "Apr 11, 10:23 AM", domain: "github.com", hasAttachment: false, shared: "claude", folder: "INBOX", preview: "Your pull request 'Fix auth middleware' was merged into main by @amar-gandhi.\n\nChanges: 12 files changed, 234 insertions(+), 89 deletions(-)\n\nThe CI pipeline completed successfully. All 47 tests passed." },
  { id: 2, from: "notifications@linear.app", fromName: "Linear", to: "amar.gandhi@me.com", subject: "MAN-234 moved to In Review", date: "Apr 11, 9:45 AM", domain: "linear.app", hasAttachment: false, shared: "claude", folder: "INBOX", preview: "Amar moved MAN-234 'Polish sidebar hierarchy' to In Review.\n\nAssignee: Amar Gandhi\nPriority: High\nProject: Manifold v5.2" },
  { id: 3, from: "no_reply@email.apple.com", fromName: "Apple Developer", to: "amar.gandhi@me.com", subject: "Your app has been approved", date: "Apr 10", domain: "email.apple.com", hasAttachment: true, shared: null, folder: "INBOX", preview: "Dear Developer,\n\nManifold version 1.0 (build 42) has been approved for distribution on the Mac App Store.\n\nYou can now release this version to users." },
  { id: 4, from: "receipts@stripe.com", fromName: "Stripe", to: "amar.gandhi@me.com", subject: "Your March invoice is ready", date: "Apr 1", domain: "stripe.com", hasAttachment: true, shared: null, folder: "INBOX", preview: "Your invoice for March 2026 is ready.\n\nAmount: $49.00\nPlan: Manifold Pro\nNext billing date: May 1, 2026" },
  { id: 5, from: "notifications@figma.com", fromName: "Figma", to: "amar.gandhi@me.com", subject: "Sarah commented on your design", date: "Mar 29", domain: "figma.com", hasAttachment: false, shared: "codex", folder: "INBOX", preview: "Sarah left a comment on 'Manifold v5.2 Mockups':\n\n\"The sidebar section headers look great. Can we tighten the spacing between the source rows?\"" },
  { id: 6, from: "noreply@github.com", fromName: "GitHub", to: "amar.gandhi@me.com", subject: "[manifold] Issue #18: Menu bar icon too small", date: "Mar 28", domain: "github.com", hasAttachment: false, shared: "claude", folder: "INBOX", preview: "New issue opened by @designreviewer:\n\nThe menu bar icon at 18×18pt is barely distinguishable from other menu bar items. Consider testing at different sizes." },
  { id: 7, from: "team@notion.so", fromName: "Notion", to: "amar.gandhi@me.com", subject: "Weekly digest: Manifold workspace", date: "Mar 27", domain: "notion.so", hasAttachment: false, shared: null, folder: "INBOX", preview: "Here's what changed in your Manifold workspace this week:\n\n• 3 pages updated\n• 2 new comments\n• 1 new database entry" },
  { id: 8, from: "noreply@github.com", fromName: "GitHub", to: "amar.gandhi@me.com", subject: "Dependabot: bump swift-nio from 2.6 to 2.7", date: "Mar 26", domain: "github.com", hasAttachment: false, shared: "claude", folder: "INBOX", preview: "Dependabot created a pull request to bump swift-nio from 2.6.0 to 2.7.1.\n\nThis update includes security fixes for CVE-2026-1234." },
];

function EmailsMessagesTab() {
  const [selectedFolder, setSelectedFolder] = useState("INBOX");
  const [favoritesOpen, setFavoritesOpen] = useState(true);
  const [smartOpen, setSmartOpen] = useState(true);
  const [accountOpen, setAccountOpen] = useState(true);
  const [agent, setAgent] = useState("Claude");
  const [searchText, setSearchText] = useState("");
  const [selectedIds, setSelectedIds] = useState(new Set());
  const [previewId, setPreviewId] = useState(null);
  const [sortBy, setSortBy] = useState("date");

  const agentColor = agent === "Codex" ? Color.codexPurple : Color.claudeBlue;
  const agentTint = agent === "Codex" ? Color.codexPurpleTint : Color.claudeBlueTint;
  const agentKey = agent.toLowerCase();

  // Filter messages
  const messages = allMessages.filter(m => {
    if (selectedFolder === "Shared with Claude") return m.shared === "claude";
    if (selectedFolder === "Shared with Codex") return m.shared === "codex";
    if (selectedFolder === "Not Shared") return m.shared === null;
    if (selectedFolder !== "All Mail" && selectedFolder !== "INBOX") return m.folder === selectedFolder;
    return true;
  }).filter(m => {
    if (!searchText) return true;
    const q = searchText.toLowerCase();
    return m.subject.toLowerCase().includes(q) || m.fromName.toLowerCase().includes(q) || m.from.toLowerCase().includes(q) || m.domain.toLowerCase().includes(q);
  });

  const previewMessage = previewId ? allMessages.find(m => m.id === previewId) : null;
  const allSelected = messages.length > 0 && messages.every(m => selectedIds.has(m.id));
  const someSelected = selectedIds.size > 0;

  const toggleAll = () => {
    if (allSelected) {
      setSelectedIds(new Set());
    } else {
      setSelectedIds(new Set(messages.map(m => m.id)));
    }
  };

  const toggleOne = (id) => {
    const next = new Set(selectedIds);
    if (next.has(id)) next.delete(id);
    else next.add(id);
    setSelectedIds(next);
  };

  return (
    <div style={{ display: "flex", height: "100%" }}>
      {/* ── Sidebar: folder navigation + smart filters ── */}
      <div style={{
        width: 220, minWidth: 200, borderRight: `1px solid ${Color.sidebarBorder}`,
        background: Color.sidebar, display: "flex", flexDirection: "column",
        overflow: "auto", flexShrink: 0,
      }}>
        {/* Favorites */}
        <button onClick={() => setFavoritesOpen(!favoritesOpen)} style={{
          display: "flex", alignItems: "center", gap: 4, padding: "8px 12px 4px",
          border: "none", cursor: "pointer", background: "transparent", width: "100%",
        }}>
          {favoritesOpen ? <ChevronDown size={10} color={Color.textTertiary} /> : <ChevronRight size={10} color={Color.textTertiary} />}
          <span style={{ ...Type.caption, fontWeight: 600, textTransform: "uppercase", fontSize: 10, letterSpacing: "0.5px", color: Color.textTertiary }}>Favorites</span>
        </button>
        {favoritesOpen && [
          { name: "All Mail", icon: <Mail size={14} />, count: 776 },
          { name: "INBOX", icon: <Inbox size={14} />, count: 234 },
        ].map(m => (
          <button key={m.name} onClick={() => { setSelectedFolder(m.name); setPreviewId(null); setSelectedIds(new Set()); }} style={{
            display: "flex", alignItems: "center", gap: 8, padding: "5px 12px 5px 22px",
            border: "none", cursor: "pointer", width: "100%", textAlign: "left",
            background: selectedFolder === m.name ? Color.selected : "transparent",
            borderRadius: 6, margin: "0 4px", maxWidth: "calc(100% - 8px)", fontSize: 13, color: Color.textPrimary,
          }}>
            {m.icon}
            <span style={{ flex: 1 }}>{m.name}</span>
            <span style={{ ...Type.numericCaption, color: Color.textTertiary }}>{m.count}</span>
          </button>
        ))}

        {/* Smart Filters — agent-centric */}
        <button onClick={() => setSmartOpen(!smartOpen)} style={{
          display: "flex", alignItems: "center", gap: 4, padding: "8px 12px 4px",
          border: "none", cursor: "pointer", background: "transparent", width: "100%", marginTop: 4,
        }}>
          {smartOpen ? <ChevronDown size={10} color={Color.textTertiary} /> : <ChevronRight size={10} color={Color.textTertiary} />}
          <span style={{ ...Type.caption, fontWeight: 600, textTransform: "uppercase", fontSize: 10, letterSpacing: "0.5px", color: Color.textTertiary }}>Agent Access</span>
        </button>
        {smartOpen && [
          { name: "Shared with Claude", color: Color.claudeBlue, count: 4 },
          { name: "Shared with Codex", color: Color.codexPurple, count: 1 },
          { name: "Not Shared", color: Color.textTertiary, count: 3 },
        ].map(m => (
          <button key={m.name} onClick={() => { setSelectedFolder(m.name); setPreviewId(null); setSelectedIds(new Set()); }} style={{
            display: "flex", alignItems: "center", gap: 8, padding: "5px 12px 5px 22px",
            border: "none", cursor: "pointer", width: "100%", textAlign: "left",
            background: selectedFolder === m.name ? Color.selected : "transparent",
            borderRadius: 6, margin: "0 4px", maxWidth: "calc(100% - 8px)", fontSize: 13, color: Color.textPrimary,
          }}>
            <StatusDot color={m.color} size={8} />
            <span style={{ flex: 1 }}>{m.name}</span>
            <span style={{ ...Type.numericCaption, color: Color.textTertiary }}>{m.count}</span>
          </button>
        ))}

        {/* Account folders */}
        <button onClick={() => setAccountOpen(!accountOpen)} style={{
          display: "flex", alignItems: "center", gap: 4, padding: "8px 12px 4px",
          border: "none", cursor: "pointer", background: "transparent", width: "100%", marginTop: 4,
        }}>
          {accountOpen ? <ChevronDown size={10} color={Color.textTertiary} /> : <ChevronRight size={10} color={Color.textTertiary} />}
          <span style={{ ...Type.caption, fontWeight: 600, textTransform: "uppercase", fontSize: 10, letterSpacing: "0.5px", color: Color.textTertiary }}>amar.gandhi@me.com</span>
        </button>
        {accountOpen && ["Sent", "Drafts", "Trash", "Archive"].map(f => (
          <button key={f} onClick={() => { setSelectedFolder(f); setPreviewId(null); setSelectedIds(new Set()); }} style={{
            display: "flex", alignItems: "center", gap: 8, padding: "5px 12px 5px 22px",
            border: "none", cursor: "pointer", width: "100%", textAlign: "left",
            background: selectedFolder === f ? Color.selected : "transparent",
            borderRadius: 6, margin: "0 4px", maxWidth: "calc(100% - 8px)", fontSize: 13, color: Color.textPrimary,
          }}>
            <Folder size={13} color={Color.textTertiary} />
            <span>{f}</span>
          </button>
        ))}

        {/* Add Account "+" */}
        <div style={{ marginTop: "auto", padding: "8px 12px", borderTop: `1px solid ${Color.sidebarBorder}` }}>
          <button title="Add Email Account…" style={{
            width: 24, height: 24, borderRadius: 6, border: "none", cursor: "pointer",
            background: "transparent", display: "flex", alignItems: "center", justifyContent: "center",
            color: Color.textTertiary,
          }}><Plus size={16} /></button>
        </div>
      </div>

      {/* ── Main area: search toolbar + table + click-to-preview ── */}
      <div style={{ flex: 1, display: "flex", flexDirection: "column", overflow: "hidden" }}>

        {/* Toolbar: search + agent focus + actions */}
        <div style={{
          padding: "8px 16px", display: "flex", alignItems: "center", gap: 12,
          borderBottom: `1px solid ${Color.border}`, flexShrink: 0,
        }}>
          {/* Search */}
          <div style={{
            display: "flex", alignItems: "center", gap: 6, flex: 1, maxWidth: 320,
            background: "rgba(0,0,0,0.04)", borderRadius: 6, padding: "5px 8px",
          }}>
            <Search size={13} color={Color.textTertiary} />
            <input
              type="text" placeholder="Search by sender, subject, domain…"
              value={searchText} onChange={e => setSearchText(e.target.value)}
              style={{
                border: "none", background: "transparent", outline: "none", flex: 1,
                fontSize: 12, color: Color.textPrimary,
              }}
            />
            {searchText && (
              <button onClick={() => setSearchText("")} style={{ border: "none", background: "transparent", cursor: "pointer", padding: 0, display: "flex" }}>
                <span style={{ fontSize: 12, color: Color.textTertiary, lineHeight: 1 }}>✕</span>
              </button>
            )}
          </div>

          {/* Bulk actions (visible when items selected) */}
          {someSelected && (
            <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
              <span style={{ ...Type.caption, fontWeight: 500 }}>{selectedIds.size} selected</span>
              <ShareToolbarButton
                itemType="email"
                itemCount={selectedIds.size}
                currentSharing={{ claude: false, codex: false }}
              />
              <button style={{
                padding: "4px 10px", borderRadius: 5, border: `1px solid ${Color.border}`,
                background: "white", cursor: "pointer", fontSize: 11, color: Color.textSecondary,
                display: "flex", alignItems: "center", gap: 4,
              }}>
                <Download size={11} /> Export
              </button>
            </div>
          )}

          <div style={{ flex: 1 }} />

          {/* Agent focus */}
          <AgentFocusControl value={agent} onChange={setAgent} />
        </div>

        {/* Content: table + optional preview panel */}
        <div style={{ flex: 1, display: "flex", overflow: "hidden" }}>

          {/* Email table — Synology-style with checkboxes */}
          <div style={{ flex: 1, display: "flex", flexDirection: "column", overflow: "hidden" }}>

            {/* Table header — sortable columns */}
            <div style={{
              display: "grid",
              gridTemplateColumns: "36px 1fr 2fr 100px 80px 60px 70px",
              padding: "7px 12px", borderBottom: `1px solid ${Color.border}`,
              background: Color.bg, position: "sticky", top: 0, zIndex: 1, alignItems: "center",
            }}>
              <div style={{ display: "flex", justifyContent: "center" }}>
                <button onClick={toggleAll} style={{ border: "none", background: "transparent", cursor: "pointer", padding: 0, display: "flex" }}>
                  {<CheckboxIcon checked={allSelected} color={allSelected ? agentColor : Color.textTertiary} />}
                </button>
              </div>
              <span style={{ ...Type.caption, fontWeight: 600, cursor: "pointer" }}>From</span>
              <span style={{ ...Type.caption, fontWeight: 600, cursor: "pointer" }}>Subject</span>
              <span style={{ ...Type.caption, fontWeight: 600, cursor: "pointer" }}>Domain</span>
              <span style={{ ...Type.caption, fontWeight: 600, cursor: "pointer", textAlign: "right" }}>Date ↓</span>
              <span style={{ ...Type.caption, fontWeight: 600, textAlign: "center" }}>
                <Paperclip size={10} />
              </span>
              <span style={{ ...Type.caption, fontWeight: 600, textAlign: "center", color: agentColor }}>Shared</span>
            </div>

            {/* Message rows */}
            <div style={{ flex: 1, overflow: "auto" }}>
              {messages.length > 0 ? messages.map(m => {
                const isSelected = selectedIds.has(m.id);
                const isPreviewing = previewId === m.id;
                const isSharedWithAgent = (agentKey === "claude" && m.shared === "claude") || (agentKey === "codex" && m.shared === "codex");

                return (
                  <div key={m.id}>
                    <div
                      onClick={() => setPreviewId(isPreviewing ? null : m.id)}
                      style={{
                        display: "grid",
                        gridTemplateColumns: "36px 1fr 2fr 100px 80px 60px 70px",
                        padding: "7px 12px", alignItems: "center", cursor: "pointer",
                        borderBottom: isPreviewing ? "none" : "1px solid rgba(0,0,0,0.04)",
                        background: isPreviewing ? "rgba(0,122,255,0.06)" : isSharedWithAgent ? agentTint : "transparent",
                        transition: "background 0.15s",
                      }}
                    >
                      {/* Checkbox */}
                      <div style={{ display: "flex", justifyContent: "center" }} onClick={e => { e.stopPropagation(); toggleOne(m.id); }}>
                        {<CheckboxIcon checked={isSelected} color={isSelected ? agentColor : Color.textTertiary} />}
                      </div>
                      {/* From */}
                      <span style={{ ...Type.body, fontWeight: 500, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{m.fromName}</span>
                      {/* Subject */}
                      <span style={{ ...Type.body, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", paddingRight: 8 }}>{m.subject}</span>
                      {/* Domain */}
                      <span style={{ ...Type.mono, color: Color.textSecondary, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>@{m.domain}</span>
                      {/* Date */}
                      <span style={{ ...Type.numericCaption, textAlign: "right", color: Color.textSecondary }}>{m.date}</span>
                      {/* Attachment */}
                      <div style={{ textAlign: "center" }}>
                        {m.hasAttachment && <Paperclip size={12} color={Color.textTertiary} />}
                      </div>
                      {/* Shared status — agent colored dot */}
                      <div style={{ display: "flex", justifyContent: "center", alignItems: "center", gap: 4 }}>
                        {m.shared === "claude" && <StatusDot color={Color.claudeBlue} size={8} />}
                        {m.shared === "codex" && <StatusDot color={Color.codexPurple} size={8} />}
                        {m.shared === "claude" && m.shared === agentKey && <span style={{ ...Type.caption, color: Color.claudeBlue, fontSize: 10 }}>Claude</span>}
                        {m.shared === "codex" && m.shared === agentKey && <span style={{ ...Type.caption, color: Color.codexPurple, fontSize: 10 }}>Codex</span>}
                        {!m.shared && <span style={{ ...Type.caption, color: Color.textTertiary, fontSize: 10 }}>—</span>}
                      </div>
                    </div>

                    {/* Click-to-preview panel — slides open below the row */}
                    {isPreviewing && (
                      <div style={{
                        padding: "16px 20px 16px 48px", borderBottom: `1px solid ${Color.border}`,
                        background: "rgba(0,122,255,0.03)",
                      }}>
                        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", marginBottom: 12 }}>
                          <div>
                            <div style={{ ...Type.heading, fontSize: 14, marginBottom: 4 }}>{m.subject}</div>
                            <div style={{ ...Type.caption }}>
                              From: <span style={{ color: Color.textPrimary }}>{m.from}</span> · To: {m.to} · {m.date}
                            </div>
                          </div>
                          <div style={{ display: "flex", gap: 6, flexShrink: 0, alignItems: "center" }}>
                            {m.shared ? (
                              <ShareToolbarButton
                                itemType="email"
                                itemName={m.fromName}
                                currentSharing={{ claude: m.shared === "claude", codex: m.shared === "codex" }}
                              />
                            ) : (
                              <ShareToolbarButton
                                itemType="email"
                                itemName={m.fromName}
                                currentSharing={{ claude: false, codex: false }}
                              />
                            )}
                            <button style={{
                              padding: "4px 10px", borderRadius: 5, border: `1px solid ${Color.border}`,
                              background: "white", cursor: "pointer", fontSize: 11, fontWeight: 500,
                              color: Color.textPrimary, display: "flex", alignItems: "center", gap: 4,
                            }} title="Open in default email app">
                              <Mail size={11} /> Open
                            </button>
                            <button onClick={(e) => { e.stopPropagation(); setPreviewId(null); }} style={{
                              border: "none", background: "transparent", cursor: "pointer", padding: 2,
                            }}>
                              <span style={{ fontSize: 14, color: Color.textTertiary, lineHeight: 1 }}>✕</span>
                            </button>
                          </div>
                        </div>
                        <div style={{
                          ...Type.body, lineHeight: 1.65, whiteSpace: "pre-wrap",
                          maxHeight: 160, overflow: "auto", color: Color.textSecondary,
                        }}>
                          {m.preview}
                        </div>
                        {m.hasAttachment && (
                          <div style={{
                            marginTop: 10, padding: "6px 10px", borderRadius: 6,
                            background: "rgba(0,0,0,0.04)", display: "inline-flex", alignItems: "center", gap: 6,
                          }}>
                            <Paperclip size={12} color={Color.textTertiary} />
                            <span style={{ ...Type.caption }}>1 attachment</span>
                          </div>
                        )}
                      </div>
                    )}
                  </div>
                );
              }) : (
                <div style={{
                  display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center",
                  height: "100%", padding: 24, textAlign: "center",
                }}>
                  <Mail size={32} color={Color.textTertiary} style={{ marginBottom: 12 }} />
                  {searchText ? (
                    <>
                      <div style={{ ...Type.body, fontWeight: 500, marginBottom: 4 }}>No results for "{searchText}"</div>
                      <div style={{ ...Type.caption }}>Try a different search term or clear filters.</div>
                    </>
                  ) : (
                    <>
                      <div style={{ ...Type.body, fontWeight: 500, marginBottom: 4 }}>No messages</div>
                      <div style={{ ...Type.caption }}>This mailbox is empty.</div>
                    </>
                  )}
                </div>
              )}
            </div>

            {/* Footer: count + status */}
            <div style={{
              padding: "6px 12px", borderTop: `1px solid ${Color.border}`,
              display: "flex", justifyContent: "space-between", alignItems: "center", flexShrink: 0,
            }}>
              <span style={{ ...Type.caption }}>
                {messages.length} {messages.length === 1 ? "message" : "messages"}
                {someSelected && ` · ${selectedIds.size} selected`}
              </span>
              <span style={{ ...Type.caption, color: Color.textTertiary }}>
                Last synced: 2 min ago
              </span>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════════════
// APP SHELL
// ═══════════════════════════════════════════════════════════════════════

export default function ManifoldPrototype() {
  const [tab, setTab] = useState("Overview");
  const [emailView, setEmailView] = useState("Rules");

  return (
    <div style={{
      width: "100%", height: "100vh", display: "flex", flexDirection: "column",
      fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Helvetica Neue', sans-serif",
      color: Color.textPrimary, background: Color.bg,
      WebkitFontSmoothing: "antialiased",
    }}>
      {/* Toolbar */}
      <AppToolbar tab={tab} onTabChange={(t) => { setTab(t); setEmailView("Rules"); }} agentStatus="partial" />

      {/* Email sub-nav — Rules (governance) vs Messages (browse) */}
      {tab === "Emails" && (
        <div style={{
          padding: "6px 16px", borderBottom: `1px solid ${Color.border}`,
          display: "flex", gap: 4,
        }}>
          {["Rules", "Messages"].map(v => (
            <button key={v} onClick={() => setEmailView(v)} style={{
              padding: "3px 10px", borderRadius: 5, border: "none", cursor: "pointer", fontSize: 12,
              background: emailView === v ? "rgba(0,0,0,0.06)" : "transparent",
              fontWeight: emailView === v ? 500 : 400,
              color: emailView === v ? Color.textPrimary : Color.textSecondary,
            }}>{v}</button>
          ))}
        </div>
      )}

      {/* Content */}
      <div style={{ flex: 1, overflow: "hidden" }}>
        {tab === "Overview" && <OverviewTab />}
        {tab === "Files" && <FilesTab />}
        {tab === "Emails" && emailView === "Rules" && <EmailsRulesTab />}
        {tab === "Emails" && emailView === "Messages" && <EmailsMessagesTab />}
      </div>

      {/* Annotation bar */}
      <div style={{
        padding: "6px 16px", background: "rgba(0,0,0,0.03)", borderTop: `1px solid ${Color.border}`,
        fontSize: 11, color: Color.textTertiary, display: "flex", justifyContent: "space-between",
      }}>
        <span>Manifold Design Prototype — Click "Add Domain/Contact/Pattern" to see creation forms · Click "Share…" for unified sharing popover</span>
        <span>Overview · Files · Emails (Rules / Messages)</span>
      </div>
    </div>
  );
}
