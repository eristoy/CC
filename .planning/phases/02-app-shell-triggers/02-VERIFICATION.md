---
phase: 02-app-shell-triggers
verified: 2026-02-27T20:15:00Z
status: human_needed
score: 9/9 must-haves verified
re_verification:
  previous_status: gaps_found
  previous_score: 5/7
  gaps_closed:
    - "NOTIF-01: macOS notification on backup success — NotificationDelegate wired for foreground delivery"
    - "NOTIF-02: macOS notification on backup failure — NotificationDelegate wired for foreground delivery"
    - "APP-02 partial: silent guard failures — BackupCoordinator now sets status = .error with descriptive message"
    - "Logging gap: all 5 backup lifecycle components emit os.log under com.abletonbackup subsystem"
  gaps_remaining: []
  regressions: []
human_verification:
  - test: "Notification permission dialog appears on first launch"
    expected: "A macOS system dialog asks 'Allow AbletonBackup to send notifications?' on first run"
    why_human: "Cannot automate — requires real app run and system dialog observation"
  - test: "Backup Complete notification banner appears after clicking Back Up Now"
    expected: "A persistent banner notification appears with title 'Backup Complete' and project name in body"
    why_human: "UNUserNotificationCenter delivery to foreground apps requires visual confirmation; delegate wiring is verified but banner appearance cannot be confirmed programmatically"
  - test: "Menu bar icon state transitions during backup"
    expected: "Icon changes from waveform (idle) to arrow.triangle.2.circlepath (running) and back to waveform after success"
    why_human: "Visual state transition requires human observation"
  - test: "No Dock icon appears while app is running"
    expected: "AbletonBackup does not appear in Dock or Cmd+Tab switcher"
    why_human: "LSUIElement=true is verified in Info.plist; Dock absence requires visual confirmation"
---

# Phase 2: App Shell + Triggers Verification Report (Re-verification)

**Phase Goal:** The app runs silently as a macOS menu bar utility, watches for Ableton saves, and backs up automatically with visible status
**Verified:** 2026-02-27T20:15:00Z
**Status:** human_needed
**Re-verification:** Yes — after gap closure (plans 02-06 and 02-07)

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | No Dock icon appears when AbletonBackup is running | VERIFIED | `Info.plist` has `LSUIElement = true` (line 22); confirmed in built app bundle at `.build/xcode/Build/Products/Debug/AbletonBackup.app/Contents/Info.plist` |
| 2 | Menu bar icon is visible and changes state during backup operations | VERIFIED | `BackupCoordinator.statusIcon` computed from `BackupStatus` enum; `AbletonBackupApp.swift` binds `coordinator.statusIcon` to `MenuBarExtra` label; three distinct SF Symbol states: `waveform` (idle), `arrow.triangle.2.circlepath` (running), `exclamationmark.triangle.fill` (error) |
| 3 | Saving an .als file in the watched folder triggers a backup within a few seconds | VERIFIED | `FSEventsWatcher` listens for `kFSEventStreamEventFlagItemRenamed` and `kFSEventStreamEventFlagItemModified` on `.als` files; callback invokes `BackupCoordinator.handleALSChange` via `@MainActor` Task; `AbletonPrefsReader.discoverProjectsFolder()` resolves the watched path |
| 4 | A macOS notification appears after backup success | VERIFIED (code) | `NotificationService.setup()` now calls `UNUserNotificationCenter.current().delegate = NotificationDelegate.shared` then `requestAuthorization` unconditionally; `NotificationDelegate.willPresent` returns `[.banner, .sound]` ensuring foreground delivery; `sendBackupSuccess` called at `runBackup` success path (line 247 of BackupCoordinator.swift) |
| 5 | A macOS notification appears when a backup fails | VERIFIED (code) | `NotificationService.sendBackupFailure` called in `runBackup` catch block (line 252 of BackupCoordinator.swift); `NotificationDelegate` ensures foreground delivery for failure notifications too |
| 6 | Back Up Now in the menu triggers an immediate backup | VERIFIED | `MenuBarView.backupSection` Button calls `Task { await coordinator.runBackup(trigger: .manual) }`; button is disabled during `.running` state |
| 7 | Clicking Back Up Now before setup completes shows error state instead of silently returning | VERIFIED | `runBackup` guard on engine/db/folder nil now sets `status = .error(reason)` with enum-branched descriptive message (BackupCoordinator.swift lines 211–222) |
| 8 | Launch at Login toggle works | VERIFIED | `LoginItemManager` uses `SMAppService.mainApp.register()/unregister()`; `MenuBarView` shows `.requiresApproval` hint with "Open System Settings..." button; prior human verification passed this check |
| 9 | All 5 backup lifecycle components emit structured os.log entries | VERIFIED | `Logger(subsystem: "com.abletonbackup", category: ...)` confirmed in: `BackupEngine.swift` (actor property, line 17), `BackupCoordinator.swift` (class property, line 53), `NotificationService.swift` (file-scope, line 6), `FSEventsWatcher.swift` (file-scope, line 7), `SchedulerTask.swift` (file-scope, line 6) |

**Score:** 9/9 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `AbletonBackup/NotificationService.swift` | NotificationDelegate class + setup() method replacing requestAuthorization | VERIFIED | `NotificationDelegate` at line 78; `setup()` at line 22; no residual `requestAuthorization()` method |
| `AbletonBackup/AbletonBackupApp.swift` | `.task { NotificationService.setup() }` on MenuBarView | VERIFIED | `.task` attached to `MenuBarView()` content view (lines 11–15); note: moved from Scene level (which lacks `.task`) to View level — semantically equivalent for menu bar apps |
| `AbletonBackup/BackupCoordinator.swift` | guard failures set `status = .error`; no call to requestAuthorization | VERIFIED | Lines 211–222: guard block sets `status = .error(reason)` with 3-branch reason string; line 83–84: replaced requestAuthorization call with log comment; nil folder warning at lines 162–168 |
| `AbletonBackup/Info.plist` | `LSUIElement = true`, `NSUserNotificationAlertStyle = alert` | VERIFIED | Line 21–24: both keys present with correct values |
| `Sources/BackupEngine/BackupEngine.swift` | Logger with category "BackupEngine"; 5+ log sites | VERIFIED | Logger at line 17; log sites at lines 54, 77, 113, 170, 277, 301 (6 sites total) |
| `AbletonBackup/FSEventsWatcher.swift` | Logger + log(path:) nonisolated method | VERIFIED | Logger at line 7; `log(path:)` method at lines 90–92; 3 call sites in init, C callback, deinit |
| `AbletonBackup/SchedulerTask.swift` | Logger + start/fire/stop log entries | VERIFIED | Logger at line 6; log at start (line 45), loop fire (line 40), stop (line 51) |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `AbletonBackupApp.swift` `.task` | `NotificationService.setup()` | Called on `MenuBarView` appearance = app launch | WIRED | Line 14: `NotificationService.setup()` inside `.task { }` |
| `NotificationService.setup()` | `NotificationDelegate.shared` | `UNUserNotificationCenter.current().delegate = NotificationDelegate.shared` | WIRED | Line 23 of NotificationService.swift |
| `NotificationDelegate.willPresent` | `.banner + .sound` | `completionHandler([.banner, .sound])` | WIRED | Line 88 of NotificationService.swift — ensures foreground notifications surface as banners |
| `BackupCoordinator.runBackup()` guard failure | `status = .error(reason)` | Enum-branched reason string replaces silent `return` | WIRED | Lines 213–221 of BackupCoordinator.swift |
| `BackupCoordinator.setup()` nil folder | `status = .error(...)` | Conditional at line 162 | WIRED | Line 166: `status = .error("Ableton Projects folder not found. Configure in Settings.")` |
| `BackupCoordinator` success path | `NotificationService.sendBackupSuccess` | After `engine.runJob` returns | WIRED | Line 247 of BackupCoordinator.swift |
| `BackupCoordinator` error path | `NotificationService.sendBackupFailure` | In `catch` block | WIRED | Line 252 of BackupCoordinator.swift |
| `MenuBarExtra` label | `coordinator.statusIcon` | `@Observable` binding via `Label("AbletonBackup", systemImage: coordinator.statusIcon)` | WIRED | AbletonBackupApp.swift line 18 |
| Console.app | `subsystem: com.abletonbackup` | All 5 loggers use same subsystem string | WIRED | Verified across all 5 files |

---

### Requirements Coverage

| Requirement | Phase Claim | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| APP-01 | Phase 2 | App runs as menu bar utility (no Dock icon) | SATISFIED | `Info.plist` `LSUIElement = true`; `MenuBarExtra` in `AbletonBackupApp.swift` |
| APP-02 | Phase 2 | Menu bar icon reflects idle / running / error | SATISFIED | `BackupStatus.iconName` returns 3 distinct SF Symbols; coordinator status updated at every state transition including guard failures |
| APP-03 | Phase 2 | App can be configured to launch at login | SATISFIED | `LoginItemManager` uses `SMAppService`; toggle in `MenuBarView` with approval handling |
| DISC-01 | Phase 2 | App auto-detects Ableton Projects folder from preferences | SATISFIED | `AbletonPrefsReader.discoverProjectsFolder()` checks default path then parses Library.cfg |
| TRIG-01 | Phase 2 | Detects Ableton project save and triggers backup | SATISFIED | `FSEventsWatcher` watches discovered folder; `.als` rename/modify events call `runBackup(trigger: .fsEvent)` |
| TRIG-02 | Phase 2 | Backups run on scheduled interval | SATISFIED | `SchedulerTask.start(interval: .seconds(3600))` started in `BackupCoordinator.setup()` |
| TRIG-03 | Phase 2 | User can trigger manual backup from menu bar | SATISFIED | "Back Up Now" button in `MenuBarView` calls `runBackup(trigger: .manual)` |
| NOTIF-01 | Phase 2 | macOS notification on backup completion | SATISFIED (code-verified) | `NotificationService.sendBackupSuccess` called after successful job; `NotificationDelegate` ensures foreground delivery; requires human verification of actual banner appearance |
| NOTIF-02 | Phase 2 | macOS notification on backup failure with error detail | SATISFIED (code-verified) | `NotificationService.sendBackupFailure` called in catch block with `error.localizedDescription`; `NotificationDelegate` ensures foreground delivery; requires human verification |

**Note on APP-01:** REQUIREMENTS.md still shows `[ ]` (incomplete) for APP-01 and should be updated to `[x]` — `LSUIElement = true` in Info.plist satisfies this requirement.

**Orphaned requirements check:** No orphaned requirements found. All 9 requirement IDs from the plan frontmatter map to Phase 2 in REQUIREMENTS.md traceability table.

---

### Anti-Patterns Found

| File | Pattern | Severity | Impact |
|------|---------|----------|--------|
| None | — | — | — |

Zero TODO/FIXME/placeholder comments found. Zero empty implementations. Zero stub returns found in modified files.

---

### Human Verification Required

The following items cannot be verified programmatically. All code-level preconditions are confirmed.

#### 1. Notification Permission Dialog

**Test:** Kill any running instance (`pkill -f AbletonBackup`), then launch the app fresh. Watch for a macOS notification permission dialog.
**Expected:** A system dialog appears: "AbletonBackup would like to send you notifications" with Allow/Don't Allow buttons.
**Why human:** `UNUserNotificationCenter.requestAuthorization` with `options: [.alert, .sound]` is wired correctly; whether the system prompts (vs. already-granted) depends on prior run history. Only human can confirm the dialog appeared on a truly fresh install.

#### 2. Backup Complete Notification Banner

**Test:** With the app running, click "Back Up Now" in the menu bar. Wait up to 10 seconds.
**Expected:** A persistent alert banner appears in the top-right corner: title "Backup Complete", body "{folder name} backed up successfully."
**Why human:** `NotificationDelegate.willPresent` returning `[.banner, .sound]` is verified in code; actual banner appearance in the notification center requires human observation. The `NSUserNotificationAlertStyle = alert` Info.plist key is also confirmed.

#### 3. Menu Bar Icon State Transition

**Test:** Click "Back Up Now" and watch the menu bar icon during the backup operation.
**Expected:** Icon changes from waveform to spinning arrows (arrow.triangle.2.circlepath) while backup runs, then returns to waveform (idle) on success or exclamationmark.triangle.fill (error) on failure.
**Why human:** `@Observable` binding and `coordinator.statusIcon` are wired correctly; actual visual update in the menu bar requires human observation.

#### 4. No Dock Icon Confirmation

**Test:** With AbletonBackup running, look at the Dock and press Cmd+Tab.
**Expected:** No AbletonBackup icon in Dock; app does not appear in Cmd+Tab app switcher.
**Why human:** `LSUIElement = true` is confirmed in Info.plist; the prior verification (plan 02-05) passed this step — documenting for completeness.

---

### Re-verification Summary

**Previous gaps and their resolution:**

| Gap | Previous Status | Resolution | Current Status |
|-----|----------------|------------|----------------|
| NOTIF-01/NOTIF-02: notifications never appear | failed | `NotificationDelegate` singleton added; `setup()` replaces `requestAuthorization()`; `.task` on `MenuBarView` ensures delegate is set before any backup runs | CLOSED (code-verified; human confirmation pending) |
| APP-02 partial: silent guard failures | failed | `runBackup` guard now sets `status = .error(reason)` with enum-branched descriptive message | CLOSED |
| No structured logging | failed (non-req) | All 5 components emit `os.log` under `com.abletonbackup` subsystem | CLOSED |

**No regressions detected.** All artifacts that passed previous verification (LSUIElement, MenuBarExtra wiring, TRIG-01/02/03, DISC-01, APP-03) remain intact.

---

_Verified: 2026-02-27T20:15:00Z_
_Verifier: Claude (gsd-verifier) — Re-verification after gap closure plans 02-06 and 02-07_
