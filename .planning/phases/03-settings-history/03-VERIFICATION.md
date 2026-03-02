---
phase: 03-settings-history
verified: 2026-03-02T22:00:00Z
status: gaps_found
score: 11/12 must-haves verified
gaps:
  - truth: "Settings window covers all configuration: destinations, schedule, version retention, and watch folders"
    status: partial
    reason: "The backup schedule interval is not configurable. SchedulerTask.defaultInterval is hardcoded at 3600s (1 hour). GeneralSettingsView exposes auto-backup on/off and retention count, but no schedule interval picker or stepper. APP-04 and ROADMAP Success Criterion 1 both list 'schedule' as a required configurable setting."
    artifacts:
      - path: "AbletonBackup/Views/Settings/GeneralSettingsView.swift"
        issue: "No schedule interval control. Only auto-backup toggle and retention stepper are present."
      - path: "AbletonBackup/SchedulerTask.swift"
        issue: "defaultInterval = .seconds(3600) hardcoded, never read from UserDefaults or DB"
    missing:
      - "Schedule interval control in GeneralSettingsView (e.g. Picker or Stepper for interval in hours)"
      - "SchedulerTask.start(interval:) must be called with the user-configured value from settings"
human_verification:
  - test: "Open Settings > History tab, trigger a backup, then select the project in the history browser"
    expected: "Left panel shows project name; right panel shows version with timestamp, destination icon, and green checkmark"
    why_human: "Requires a running backup to populate history — GRDB ValueObservation correctness is runtime behavior"
  - test: "Toggle Auto-backup off, make an Ableton save, confirm no backup fires; toggle back on and repeat"
    expected: "No backup triggers when toggle is off; backup fires immediately on save when toggle is on"
    why_human: "Depends on FSEvents firing in a real environment — cannot verify statically"
---

# Phase 3: Settings + History Verification Report

**Phase Goal:** All app behavior is configurable via a settings window and users can inspect past backup versions
**Verified:** 2026-03-02T22:00:00Z
**Status:** gaps_found — 1 gap
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Settings window covers all configuration: destinations, schedule, version retention, and watch folders | PARTIAL | Retention and auto-backup toggle present; schedule interval hardcoded in SchedulerTask — not configurable |
| 2 | User can add an additional watch folder and it is monitored for Ableton saves | VERIFIED | WatchFoldersSettingsView: NSOpenPanel -> coordinator.addWatchFolder(url:) -> startWatcher(for:) |
| 3 | User can remove a watch folder and it is no longer monitored | VERIFIED | confirmationDialog -> coordinator.removeWatchFolder(_:) -> watchers.removeValue + DB delete |
| 4 | User can view a list of past backup versions for any project, with timestamp for each version | VERIFIED | HistoryView: NavigationSplitView + BackupVersion.filter(projectID).order(createdAt.desc).fetchAll live via ValueObservation |
| 5 | Version history shows which destinations each version exists on | VERIFIED | BackupEventRow: ForEach(event.destinations) shows dest icon + name per destination |

**Score:** 4/5 truths fully verified; 1 partial (schedule not configurable)

---

## Required Artifacts

### Plan 01 Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Sources/BackupEngine/Persistence/Models/WatchFolder.swift` | WatchFolder GRDB model (id, path, name, addedAt, lastTriggeredAt) | VERIFIED | All fields present; TableRecord, FetchableRecord, PersistableRecord, Identifiable, Hashable conformances |
| `Sources/BackupEngine/Persistence/Schema.swift` | v2_watch_folders GRDB migration | VERIFIED | Migration "v2_watch_folders" present after "v1_initial"; creates watchFolder table with UNIQUE path |
| `AbletonBackup/BackupCoordinator.swift` | Multi-watcher coordinator with add/remove methods and DB-backed watch folder list | VERIFIED | watchFolders: [WatchFolder], database: AppDatabase?, addWatchFolder(url:), removeWatchFolder(_:), startWatcher(for:), watchers: [String: FSEventsWatcher] |

### Plan 02 Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `AbletonBackup/AbletonBackupApp.swift` | Settings scene alongside MenuBarExtra | VERIFIED | `Settings { SettingsView().environment(coordinator) }` present |
| `AbletonBackup/Views/MenuBarView.swift` | Settings button with NSApp.activate workaround | VERIFIED | NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) with NSApp.activate |
| `AbletonBackup/Views/Settings/SettingsView.swift` | TabView with 5 tabs | VERIFIED | All 5 tabs: General, Watch Folders, Destinations, History, About — no stubs remain |
| `AbletonBackup/Views/Settings/GeneralSettingsView.swift` | General settings pane with retentionCount | PARTIAL | retentionCount stepper and autoBackupEnabled toggle present; schedule interval control absent |
| `AbletonBackup/Views/Settings/AboutView.swift` | About pane with app name, version, description | VERIFIED | App name, CFBundleShortVersionString, description text all present |

### Plan 03 Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `AbletonBackup/Views/Settings/WatchFoldersSettingsView.swift` | Watch Folders pane with NSOpenPanel add/remove | VERIFIED | NSOpenPanel.runModal(), confirmationDialog, WatchFolderRow (name/path/lastTriggeredAt), empty state |
| `AbletonBackup/Views/Settings/DestinationsSettingsView.swift` | Destinations pane (read-only list) | VERIFIED | GRDB pool.read DestinationConfig list, DestinationRow with type icons, footer note |

### Plan 04 Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `AbletonBackup/Views/Settings/HistoryView.swift` | NavigationSplitView history browser with BackupEvent grouping | VERIFIED | NavigationSplitView, BackupEvent struct, groupVersions(), VersionListView, BackupEventRow, corrupt warning indicator |

---

## Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| BackupCoordinator.swift | WatchFolder.swift | WatchFolder.save(db) | VERIFIED | Lines 177, 221, 271: folder.save(database) in pool.write |
| BackupCoordinator.swift | FSEventsWatcher.swift | watchers[url.path] = FSEventsWatcher(...) | VERIFIED | Line 248: exact pattern present |
| AbletonBackupApp.swift | SettingsView.swift | Settings { SettingsView() } | VERIFIED | Lines 22-25: Settings { SettingsView().environment(coordinator) } |
| MenuBarView.swift | Settings window | NSApp.sendAction(showSettingsWindow:) | VERIFIED | Lines 81-82: NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) |
| WatchFoldersSettingsView.swift | BackupCoordinator.swift | coordinator.addWatchFolder / removeWatchFolder | VERIFIED | Lines 76, 95: both coordinator calls present |
| WatchFoldersSettingsView.swift | WatchFolder.swift | coordinator.watchFolders: [WatchFolder] | VERIFIED | Lines 13, 18, 33: watchFolders used for list rendering and selection |
| HistoryView.swift | AppDatabase.swift | coordinator.database?.pool + ValueObservation | VERIFIED | Lines 96-110: ValueObservation.tracking with pool, for try await |
| HistoryView.swift | BackupVersion.swift | BackupVersion.filter(Column("projectID") == id).fetchAll | VERIFIED | Lines 152-155: filter + order + fetchAll pattern present |

---

## Requirements Coverage

| Requirement | Source Plan(s) | Description | Status | Evidence |
|-------------|---------------|-------------|--------|----------|
| APP-04 | 03-02, 03-03 | Settings window covers all configuration (destinations, schedule, retention, watch folders) | PARTIAL | Destinations tab shows configured destinations; retention stepper present; watch folders configurable; schedule interval NOT configurable (hardcoded 1hr) |
| DISC-02 | 03-01, 03-03 | User can add additional watch folders manually via settings | VERIFIED | NSOpenPanel in WatchFoldersSettingsView -> coordinator.addWatchFolder -> DB + watcher |
| DISC-03 | 03-01, 03-03 | User can remove watch folders from settings | VERIFIED | confirmationDialog -> coordinator.removeWatchFolder -> watcher stop + DB delete |
| HIST-01 | 03-04 | User can view version history per project in settings window | VERIFIED | HistoryView NavigationSplitView: project list left, version history right, live via ValueObservation |
| HIST-02 | 03-04 | Version history shows timestamp and which destinations each version exists on | VERIFIED | BackupEventRow: timestamp formatted, ForEach destinations with icon and name per BackupVersion |

No orphaned requirements — all 5 Phase 3 requirements (APP-04, DISC-02, DISC-03, HIST-01, HIST-02) are claimed in plans and verified in code.

---

## Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| None found | — | — | — | — |

No TODO/FIXME/placeholder comments found. No empty implementations. No Text("...") stubs remaining in SettingsView.

---

## Human Verification Required

### 1. History tab live data

**Test:** Trigger a backup (click "Back Up Now"), then open Settings > History tab
**Expected:** Left panel shows the project name; selecting it shows a version row on the right with timestamp, destination icon (externaldrive.fill), and green checkmark
**Why human:** Requires a live backup run to populate GRDB tables — ValueObservation correctness is runtime behavior that cannot be verified statically

### 2. Auto-backup toggle

**Test:** Toggle "Auto-backup on save" off in General settings, make an Ableton .als save, confirm no backup fires; re-enable and save again
**Expected:** No backup when toggle is off; backup triggers when toggle is on
**Why human:** Requires FSEvents to fire in a real environment with Ableton; UserDefaults guard logic cannot be run headlessly

---

## Gaps Summary

**1 gap identified: Schedule interval not configurable (APP-04 partial)**

ROADMAP Success Criterion 1 and APP-04 both require the Settings window to cover "schedule" configuration. The backup schedule interval is hardcoded at 3600 seconds in `AbletonBackup/SchedulerTask.swift` (`static let defaultInterval: Duration = .seconds(3600)`). `BackupCoordinator.setup()` calls `scheduler.start(interval: SchedulerTask.defaultInterval, ...)` — the interval never comes from user settings.

`GeneralSettingsView.swift` has only two controls: auto-backup toggle (AppStorage) and retention stepper (GRDB). A schedule interval picker/stepper is absent.

To close this gap, GeneralSettingsView needs a schedule interval control (e.g. a Picker with common intervals: 30 min, 1 hr, 2 hr, 4 hr, or a custom Stepper), the selected value stored in UserDefaults or GRDB, and BackupCoordinator must read that value when starting the scheduler.

All other Phase 3 must-haves are fully implemented and verified. The human verification checkpoint (Plan 05) was completed and user-approved — however that approval occurred before this automated gap analysis detected the schedule omission.

---

_Verified: 2026-03-02T22:00:00Z_
_Verifier: Claude (gsd-verifier)_
