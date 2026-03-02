---
phase: 03-settings-history
plan: 02
subsystem: ui
tags: [swiftui, settings, tabview, grdb, userdefaults, appstorage, macos]

# Dependency graph
requires:
  - phase: 03-settings-history
    plan: 01
    provides: WatchFolder GRDB model, BackupCoordinator.watchFolders, addWatchFolder/removeWatchFolder, database accessor

provides:
  - Settings SwiftUI scene in AbletonBackupApp.swift — opens native macOS Settings window
  - MenuBarView Settings... button with NSApp.sendAction showSettingsWindow: workaround
  - SettingsView.swift TabView with 5 tabs (General, Watch Folders, Destinations, History, About)
  - GeneralSettingsView.swift with auto-backup toggle (AppStorage), retention stepper (GRDB), Launch at Login toggle
  - AboutView.swift with app name, version, description
  - autoBackupEnabled guard in BackupCoordinator.handleALSChange (respects toggle)
  - Hashable conformance on WatchFolder for List selection binding

affects: [03-03-destinations-ui, 03-04-history-view]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Settings scene: Settings { SettingsView().environment(coordinator) } alongside MenuBarExtra"
    - "NSApp.sendAction Selector(showSettingsWindow:) pattern for LSUIElement apps — SettingsLink unreliable"
    - "AppStorage for user preference toggles; GRDB pool.read/write for model-backed settings (retention)"
    - "autoBackupEnabled guard: UserDefaults.standard.object(forKey:) == nil check preserves default-true behavior when key not yet written"

key-files:
  created:
    - AbletonBackup/Views/Settings/SettingsView.swift
    - AbletonBackup/Views/Settings/GeneralSettingsView.swift
    - AbletonBackup/Views/Settings/AboutView.swift
  modified:
    - AbletonBackup/AbletonBackupApp.swift
    - AbletonBackup/Views/MenuBarView.swift
    - AbletonBackup/BackupCoordinator.swift
    - Sources/BackupEngine/Persistence/Models/WatchFolder.swift

key-decisions:
  - "NSApp.sendAction Selector(showSettingsWindow:) used for Settings button — research confirmed SettingsLink silently fails in LSUIElement apps"
  - "AppStorage(autoBackupEnabled) default:true uses UserDefaults.standard.object(forKey:) == nil guard in BackupCoordinator to preserve default when key absent"
  - "WatchFolder conforms to Hashable — required for List(selection:) binding in WatchFoldersSettingsView"
  - "WatchFoldersSettingsView was pre-existing (outside plan scope) — used directly instead of Text stub"

patterns-established:
  - "Settings tab pattern: each tab is a standalone View struct accepting @Environment(BackupCoordinator.self)"
  - "Retention persistence: @State + .task { await load() } + .onChange { save() } with GRDB pool.read/write"

requirements-completed: [APP-04]

# Metrics
duration: 3min
completed: 2026-03-02
---

# Phase 3 Plan 02: Settings Scene and TabView Scaffold Summary

**SwiftUI Settings scene with 5-tab TabView: GeneralSettingsView (auto-backup toggle, retention stepper, login item), WatchFoldersSettingsView (pre-existing), Destinations/History stubs, and AboutView — wired via NSApp.sendAction from MenuBarView**

## Performance

- **Duration:** ~3 min
- **Started:** 2026-03-02T21:08:31Z
- **Completed:** 2026-03-02T21:11:30Z
- **Tasks:** 2
- **Files modified:** 7

## Accomplishments

- Added `Settings { SettingsView() }` scene to AbletonBackupApp.swift alongside MenuBarExtra
- Added "Settings..." button to MenuBarView.settingsSection using `NSApp.sendAction(Selector(("showSettingsWindow:")), ...)` with `NSApp.activate(ignoringOtherApps: true)` workaround
- Created SettingsView.swift with 5-tab TabView — General, Watch Folders, Destinations, History, About
- Created GeneralSettingsView.swift with auto-backup toggle (`@AppStorage`), retention stepper (GRDB-backed, range 1-50), Launch at Login toggle
- Created AboutView.swift with waveform icon, app name, version from Bundle, description text
- Added `autoBackupEnabled` guard in `BackupCoordinator.handleALSChange` to skip FSEvent-triggered backups when user disables auto-backup
- Auto-fixed `WatchFolder: Hashable` conformance required by `WatchFoldersSettingsView` List selection binding

## Task Commits

Each task was committed atomically:

1. **Task 1: Settings scene + MenuBarView Settings button** - `fa6b17e` (feat)
2. **Task 2: SettingsView TabView + GeneralSettingsView + AboutView + stubs** - `544178c` (feat)

## Files Created/Modified

- `AbletonBackup/AbletonBackupApp.swift` - Added Settings scene with SettingsView and coordinator environment
- `AbletonBackup/Views/MenuBarView.swift` - Added Settings... button with NSApp.sendAction + import AppKit
- `AbletonBackup/Views/Settings/SettingsView.swift` - 5-tab TabView (General, Watch Folders, Destinations, History, About)
- `AbletonBackup/Views/Settings/GeneralSettingsView.swift` - Auto-backup toggle, retention stepper, login item toggle
- `AbletonBackup/Views/Settings/AboutView.swift` - App icon, name, version, description
- `AbletonBackup/BackupCoordinator.swift` - autoBackupEnabled guard in handleALSChange
- `Sources/BackupEngine/Persistence/Models/WatchFolder.swift` - Added Hashable conformance

## Decisions Made

- **NSApp.sendAction approach**: Research confirmed `SettingsLink` silently fails in LSUIElement (menu-bar-only) apps. The `NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)` pattern is the reliable cross-version approach.
- **AppStorage + UserDefaults guard**: `autoBackupEnabled` stored via `@AppStorage` in the view and checked via `UserDefaults.standard.object(forKey:) == nil` guard in BackupCoordinator. The `object(forKey:)` nil-check preserves default-true behavior when the key has never been written (avoids `bool(forKey:)` returning false for missing keys).
- **WatchFolder Hashable**: Added conformance to `WatchFolder` in BackupEngine module so `WatchFoldersSettingsView`'s `List(selection:)` compiles without error.
- **WatchFoldersSettingsView pre-existing**: File was already created outside the plan scope. Used it directly in the Watch Folders tab instead of a `Text` stub, which is more correct than a stub.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Added Hashable conformance to WatchFolder**
- **Found during:** Task 2 (SettingsView files created; build attempted)
- **Issue:** `WatchFoldersSettingsView.swift` (pre-existing file in project) uses `List(coordinator.watchFolders, id: \.id, selection: $selectedFolder)` — this `List` initializer requires `WatchFolder: Hashable` for the selection binding. Build error: "referencing initializer on List requires WatchFolder conform to Hashable"
- **Fix:** Added `Hashable` to WatchFolder's conformance list in `Sources/BackupEngine/Persistence/Models/WatchFolder.swift`
- **Files modified:** `Sources/BackupEngine/Persistence/Models/WatchFolder.swift`
- **Verification:** BUILD SUCCEEDED after adding conformance
- **Committed in:** 544178c (Task 2 commit)

**2. [Pre-existing discovery] WatchFoldersSettingsView.swift already existed**
- **Found during:** Task 1 (checking Settings directory after creating it)
- **Issue:** `AbletonBackup/Views/Settings/WatchFoldersSettingsView.swift` was already created and registered in the Xcode project prior to plan execution. The plan expected a `Text("Watch Folders")` stub.
- **Fix:** Used pre-existing `WatchFoldersSettingsView()` in the Watch Folders tab instead of a stub — correct behavior that improves on the plan spec.
- **Files modified:** `AbletonBackup/Views/Settings/SettingsView.swift`
- **Committed in:** 544178c (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (1 missing conformance, 1 pre-existing file discovery)
**Impact on plan:** Both deviations required for correct compilation and better UX. No scope creep.

## Issues Encountered

None beyond the auto-fixed deviations above.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Settings window is fully functional and accessible via Cmd+, or "Settings..." button
- GeneralSettingsView implements APP-04: auto-backup toggle + retention stepper + launch at login
- Watch Folders tab is functional (WatchFoldersSettingsView pre-existed with full implementation)
- Destinations and History tabs remain as Text stubs — to be replaced in Plans 03/04
- BUILD SUCCEEDED with no Swift 6 strict concurrency errors

## Self-Check: PASSED

- FOUND: AbletonBackupApp.swift (Settings scene present)
- FOUND: MenuBarView.swift (NSApp.sendAction showSettingsWindow: present)
- FOUND: SettingsView.swift (TabView with 5 tabs)
- FOUND: GeneralSettingsView.swift (retentionCount, autoBackupEnabled)
- FOUND: AboutView.swift
- FOUND: 03-02-SUMMARY.md
- FOUND commit fa6b17e (Task 1: Settings scene + MenuBarView)
- FOUND commit 544178c (Task 2: TabView + Views + Guards)
- BUILD SUCCEEDED

---
*Phase: 03-settings-history*
*Completed: 2026-03-02*
