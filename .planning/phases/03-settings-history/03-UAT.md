---
status: complete
phase: 03-settings-history
source: 03-01-SUMMARY.md, 03-02-SUMMARY.md, 03-03-SUMMARY.md, 03-04-SUMMARY.md, 03-05-SUMMARY.md, 03-06-SUMMARY.md
started: 2026-03-03T00:00:00Z
updated: 2026-03-03T00:00:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Settings opens from menu bar and Cmd+,
expected: Click "Settings…" in menu bar menu → window opens. Cmd+, → same window.
result: pass

### 2. General tab — all four controls present
expected: General tab shows: "Auto-backup on save" toggle, retention stepper ("Keep N versions"), "Backup schedule" picker, and "Launch at Login" toggle. All four visible in the Backup and Login sections.
result: pass

### 3. Backup schedule picker — options and persistence
expected: "Backup schedule" picker shows four options: Every 30 minutes, Every hour, Every 2 hours, Every 4 hours. Selecting a different option persists after reopening Settings (selection is remembered).
result: pass

### 4. Watch Folders tab — add a folder
expected: Click the + button at the bottom of the Watch Folders list → macOS folder picker (NSOpenPanel) sheet opens. Select any folder → it appears as a new row in the list showing its name, path, and "Never" or a timestamp for last triggered.
result: pass

### 5. Watch Folders tab — remove a folder with confirmation
expected: Select a folder row in the list → click the − button → a confirmation sheet appears: "Stop watching '[name]'?" with message "Existing backups are not affected." Clicking the confirm button removes the row. Clicking Cancel keeps it.
result: pass

### 6. Destinations tab — read-only list
expected: Destinations tab shows the configured destination (e.g. "App Support Backup") with a drive icon. No add or remove controls are present — the list is read-only.
result: pass

### 7. History tab — two-panel layout and version display
expected: History tab shows a two-panel layout: project list on the left, version list on the right. If at least one backup has run: selecting a project shows version rows on the right with timestamp, destination icon, and a green checkmark (verified) or red triangle (corrupt). If no backups yet: both panels show an empty/placeholder state.
result: pass

### 8. About tab
expected: About tab shows the app name "AbletonBackup" and the version number.
result: pass

## Summary

total: 8
passed: 8
issues: 0
pending: 0
skipped: 0

## Gaps

[none yet]
