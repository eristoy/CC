# Phase 5: ALS Parser - Context

**Gathered:** 2026-03-06
**Status:** Ready for planning

<domain>
## Phase Boundary

When a project is backed up, the app parses the `.als` file to discover all externally-referenced samples and includes them in the backup — using Ableton's own "Collect All and Save" layout so every backup is self-contained and fully restorable. Missing or offline samples surface a warning; the backup proceeds with whatever is available.

</domain>

<decisions>
## Implementation Decisions

### Missing sample warnings
- Parse the `.als` file before the file-copy phase begins; fire the notification before any writing occurs
- Warning is a macOS notification: count only — "3 samples missing from ProjectName" (consistent with existing backup result notifications)
- Backup proceeds automatically — no blocking or user confirmation required
- Tapping the notification opens the backup history entry for that project (not a separate sheet), where the user can see the full missing path list

### Sample discovery scope
- **External = anything whose path is outside the project folder.** If the sample path isn't under the `.als` project directory, it's collected.
- Samples already inside the project folder are not touched — Phase 1 already copies them
- If the `.als` cannot be parsed (corrupted, future format, gzip failure): proceed with plain folder backup (Phase 1 behavior) and fire a notification: "Could not parse .als — external samples not included"
- Offline/unmounted drives: treat missing samples the same as any missing file — add to warning count, skip, proceed
- Nested `.als` files (Live Sets referencing other Live Sets): not followed — top-level `.als` only

### Backup file layout
- Use Ableton's **"Collect All and Save" layout**: external samples copied into `Samples/Imported/` inside the backup project folder
- The backed-up `.als` is rewritten to use **relative paths** pointing to the new `Samples/Imported/` location, making the backup self-contained (open anywhere, Ableton finds the samples)
- Filename collisions resolved by **preserving the full original path as a subfolder structure** under `Samples/Imported/` (e.g. `Samples/Imported/Users/eric/Music/Drums/kick.wav`) — no renames, no collisions, paths always unique
- Internal samples (already inside project folder) are left as-is

### History & transparency
- Backup history entry records: **collected count + full list of paths** AND **missing count + full list of missing paths**
- History rows with missing samples show a **warning badge/icon** so incomplete backups are scannable at a glance
- Detail view (drill-down on a history row) shows both lists: collected samples and missing samples
- This is the same view the user lands on when tapping a "samples missing" notification

### Claude's Discretion
- XML parsing library choice (XMLDocument / XMLParser / third-party — no user preference)
- Exact notification copy beyond the pattern established above
- Warning badge visual design (color, icon style)
- Whether `.als` path rewriting happens in-memory before writing or as a post-process step

</decisions>

<specifics>
## Specific Ideas

- Behavior should mirror Ableton's own "Collect All and Save" feature — users familiar with that workflow will immediately understand what the backup did
- The self-contained backup is the core value: user should be able to move the backup to another machine, open it in Ableton, and have everything work

</specifics>

<deferred>
## Deferred Ideas

- None — discussion stayed within phase scope

</deferred>

---

*Phase: 05-als-parser*
*Context gathered: 2026-03-06*
