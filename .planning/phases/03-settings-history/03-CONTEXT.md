# Phase 3: Settings + History - Context

**Gathered:** 2026-03-02
**Status:** Ready for planning

<domain>
## Phase Boundary

A Settings window covering all app configuration (destinations, schedule, retention, watch folders) and a version history browser for inspecting past backup versions per project. No restore or delete functionality — browse only. No new backup logic.

</domain>

<decisions>
## Implementation Decisions

### Settings window structure
- Use SwiftUI `Settings` scene — renders as native macOS tabbed inspector window
- Five tabs: **General / Watch Folders / Destinations / History / About**
- General pane contains: auto-backup toggle (save-triggered), version retention setting, schedule interval picker, Launch at Login toggle
- Schedule interval is configurable (30 min / 1 hr / 2 hr / 4 hr) — Phase 2 shipped SchedulerTask at a hardcoded 1-hour interval; APP-04 requires the interval to be user-configurable. Original "save-triggered only, no timer" decision superseded by post-execution gap finding (03-VERIFICATION.md).

### Watch folder management
- Watch Folders pane: list with **+/− buttons below** (macOS standard pattern)
- Each row shows: folder name + full path + last triggered time (e.g. "MyProject — ~/Music/Ableton — Last backup: 2 hours ago")
- Adding a folder: pressing + opens macOS NSOpenPanel (standard folder picker sheet)
- Version history is NOT accessible from this pane — it lives in the dedicated History tab

### Version history browser
- History tab (5th tab in Settings)
- **Two-panel layout**: project list on the left, version list on the right
- Each version row shows: timestamp + destination icons + verification status (e.g. "Mar 2, 2:14 PM — 💾 Local ✓ — Verified")
- Version rows satisfy the roadmap requirement to show which destinations each version exists on
- **Read-only** — no restore, no delete actions in this phase

### Destructive action safety
- **Remove watch folder**: confirmation sheet ("Stop watching 'X'? Existing backups are not affected.") → stops future monitoring, no backup data deleted
- **Reduce retention number**: silent change, pruning happens on next backup run (same as normal retention behavior, no immediate deletion dialog)
- **Remove destination**: confirmation sheet warns "X versions only exist on this destination and will become inaccessible" before proceeding

### Claude's Discretion
- Exact icon choices for destination indicators in history rows
- Spacing, typography, and visual polish within each pane
- Error state handling (e.g. watch folder path no longer accessible)
- About pane content and layout

</decisions>

<specifics>
## Specific Ideas

- No specific UI references given — standard macOS Settings conventions apply throughout
- "Read-only for now" on history was an explicit call — restore is a future phase

</specifics>

<deferred>
## Deferred Ideas

- None — discussion stayed within phase scope

</deferred>

---

*Phase: 03-settings-history*
*Context gathered: 2026-03-02*
