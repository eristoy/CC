---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: unknown
last_updated: "2026-03-03T15:12:30.084Z"
progress:
  total_phases: 3
  completed_phases: 2
  total_plans: 18
  completed_plans: 17
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-25)

**Core value:** Ableton projects are always protected across multiple locations — set it up once and never lose work again.
**Current focus:** Phase 1 — Backup Engine

## Current Position

Phase: 3 of 6 (Settings + History) — COMPLETE (gap closure done)
Plan: 6 of 6 in current phase (03-06 complete — Phase 3 gap closure done)
Status: Phase 3 COMPLETE — all six plans complete (five main + one gap closure for APP-04)
Last activity: 2026-03-03 — Completed plan 03-06 (APP-04 gap closed: schedule interval Picker added to GeneralSettingsView, BackupCoordinator reads UserDefaults on startup and exposes updateScheduleInterval(_:); BUILD SUCCEEDED)

Progress: [██████████] 52% (13 of 25 total plans estimated)

## Performance Metrics

**Velocity:**
- Total plans completed: 4
- Average duration: 6 min
- Total execution time: 0.4 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-backup-engine | 5/5 complete | 119 min | 24 min |

**Recent Trend:**
- Last 5 plans: 01-01 (6 min), 01-02 (8 min), 01-03 (4 min), 01-04 (6 min), 01-05 (95 min)
- Trend: Plan 01-05 was significantly longer due to debugging GRDB date-precision bug in incremental skip logic

*Updated after each plan completion*
| Phase 02 P02 | 1 | 2 tasks | 2 files |
| Phase 02-app-shell-triggers P02-03 | 2 | 2 tasks | 4 files |
| Phase 02-app-shell-triggers P02-04 | 2 | 2 tasks | 3 files |
| Phase 02-app-shell-triggers P06 | 8 | 2 tasks | 5 files |
| Phase 02-app-shell-triggers P07 | 2 | 2 tasks | 3 files |
| Phase 03-settings-history P01 | 3 | 2 tasks | 3 files |
| Phase 03-settings-history P02 | 3 | 2 tasks | 7 files |
| Phase 03-settings-history P03 | 7 | 2 tasks | 4 files |
| Phase 03-settings-history P04 | 2 | 2 tasks | 2 files |
| Phase 03-settings-history P05 | 5 | 2 tasks | 0 files |
| Phase 03-settings-history P06 | 50 | 2 tasks | 2 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Swift 6 + SwiftUI MenuBarExtra + GRDB.swift confirmed as stack (research phase)
- Distribute outside Mac App Store initially — sandbox restrictions conflict with FSEvents bookmarks and NetFS
- GitHub/Git LFS destination ships last (Phase 6) — highest complexity, narrowest audience
- **[01-01]** xxHash-Swift 1.1.1 resolved successfully — included (no CryptoKit fallback needed)
- **[01-01]** makeInMemory() uses temp-file DatabasePool (not :memory:) — WAL mode requires real file path
- **[01-01]** VersionStatus defined in separate file for clean imports across modules
- **[01-01]** ProjectResolver.swift stub created — satisfies compilation of plan 01-02 TDD RED test file
- [Phase 01-02]: Plan 01-01 models were already built — BackupJob.swift uses real Project and VersionStatus from Persistence/Models (no stubs needed)
- [Phase 01-02]: resolvingSymlinksInPath() required on macOS: FileManager.temporaryDirectory uses /var/... but filesystem resolves to /private/var/... — both root and file URLs must be resolved before relative path computation
- [Phase 01-02]: FileEntry conforms to Equatable per plan interface spec
- **[01-03]** xxHash64 used for checksums (not SHA-256) — faster for audio files, sufficient for non-cryptographic integrity verification
- **[01-03]** APFS clone path reads destination once post-clone for checksum; chunked path hashes inline — zero extra I/O in both dominant cases
- **[01-03]** LocalDestinationAdapter.pruneVersions is documented no-op stub — VersionManager (01-04) orchestrates deletion lifecycle
- **[01-03]** VersionManager stub created to allow VersionManagerTests.swift (TDD RED for 01-04) to compile
- [Phase 01-04]: Corrupt versions kept in DB (status=corrupt), excluded from retention count, never pruned — surface in Phase 3 history UI with warning
- [Phase 01-04]: Walk-and-collect pruning: iterate all verified versions oldest-first, collect up to excessCount non-locked candidates — prefix+filter approach was incorrect when locked versions are in pruning window
- [Phase 01-04]: Write-then-cleanup pattern: status=deleting set in single DB write transaction before disk deletion — crash-safe, BackupEngine re-processes deleting rows at startup
- **[01-05]** FileEntry cache over BackupFileRecord cache: GRDB truncates Date to milliseconds; filesystem mtime has nanosecond precision — comparing DB-fetched mtime to current filesystem mtime causes all files to appear "changed" on second backup. Fix: actor-local FileEntry cache bypasses DB round-trip.
- **[01-05]** WAL write-barrier: pool.write (not pool.read) for step 7 allRecords fetch ensures just-inserted records are visible — WAL snapshot isolation on pool.read can miss writes from same async context.
- **[01-05]** Full checksum verification (re-read all destination files) chosen over spot-check — correctness over speed for Phase 1; Phase 3 can add deep-verify toggle if needed.
- [Phase 02-02]: Both kFSEventStreamEventFlagItemModified and kFSEventStreamEventFlagItemRenamed checked — Ableton uses atomic rename so isModified alone would miss saves
- [Phase 02-02]: discoverProjectsFolder() checks ~/Documents/Ableton/Ableton Projects first (confirmed Ableton 12.2 default), then falls back to Library.cfg XMLDocument XPath parse
- [Phase 02-02]: FSEventsWatcher schedules on CFRunLoopGetMain() with no @MainActor dependency — BackupCoordinator (02-04) wraps callback in Task { @MainActor in ... }
- [Phase 02-03]: NotificationService.requestAuthorization() checks .notDetermined before requesting — avoids re-requesting if already granted or denied
- [Phase 02-03]: SchedulerTask is @MainActor-isolated to store Task<Void, Never> without Sendable constraint; BackgroundTasks framework rejected (requires sandbox/App Store)
- [Phase 02-03]: LoginItemManager.isEnabled reads SMAppService.mainApp.status live on every access — UserDefaults caching would desync with System Settings independent changes
- [Phase 02-04]: BackupEngine.adapters is private — LocalDestinationAdapter initialized at BackupEngine init time, not added later (addAdapter extension not viable)
- [Phase 02-04]: Project uses path: String, DestinationConfig uses name, rootPath, type: DestinationType enum, createdAt: Date — actual Phase 1 schema differs from plan interface spec
- [Phase 02-04]: BackupStatus/BackupTrigger/BackupCoordinator made internal (not public) — app target, LoginItemManager is internal
- [Phase 02-06]: Logger declared as actor property for BackupEngine and class property for BackupCoordinator; file-scope private let for static-method struct (NotificationService) and top-level classes — Logger is Sendable so any isolation domain works
- [Phase 02-06]: FSEventsWatcher.log(path:) nonisolated method bridges C callback context to fsLogger, avoiding actor-isolation issues from C callback
- **[02-07]** NotificationDelegate uses @unchecked Sendable — singleton with no mutable state, safe from any isolation domain under Swift 6
- **[02-07]** .task modifier attached to MenuBarView (not MenuBarExtra Scene) — Scene does not expose .task; view-level .task fires on first appearance which is equivalent to app launch for menu bar apps
- **[02-07]** nil watchedProjectsFolder sets error state but does NOT return from setup() — scheduler and manual trigger still start so user can resolve in Phase 3 settings
- **[03-01]** WatchFolder GRDB model uses TEXT primary key (UUID string), UNIQUE path constraint — consistent with existing Phase 1 model pattern
- **[03-01]** Bootstrap seeding non-fatal: if AbletonPrefsReader returns nil on first launch, setup() continues with error state — scheduler still starts, user configures in Settings
- **[03-01]** startWatcher(for:) has idempotency guard (watchers[url.path] == nil) — safe to call from both bootstrap and addWatchFolder without duplicate watchers
- **[03-01]** removeWatchFolder stops FSEventsWatcher BEFORE DB delete — prevents stray events during removal window
- **[03-01]** bootstrapProjectID/bootstrapDestID retained — multi-destination job dispatch is Phase 4+, Phase 3 adds multi-watcher infrastructure only
- [Phase 03-02]: NSApp.sendAction Selector(showSettingsWindow:) used for Settings button — SettingsLink silently fails in LSUIElement apps
- [Phase 03-02]: AppStorage(autoBackupEnabled) + UserDefaults.standard.object(forKey:)==nil guard in BackupCoordinator preserves default-true when key absent
- [Phase 03-02]: WatchFolder conforms to Hashable — required for List(selection:) binding in WatchFoldersSettingsView
- **[03-03]** selectedFolderID: String? used instead of WatchFolder? for List selection — avoids Hashable assumption, works with any model type
- **[03-03]** DestinationsSettingsView is read-only in Phase 3 — loads DestinationConfig rows from GRDB on appear, no add/remove controls (Phase 4+)
- **[03-03]** xcodegen regeneration required after each new Swift file — project.yml sources glob does not auto-update xcodeproj
- [Phase 03-04]: selectedProjectID: String? used for List selection instead of Project? to avoid Hashable requirement — consistent with 03-03 selectedFolderID pattern
- [Phase 03-05]: Human verification checkpoint passed — all Phase 3 features confirmed working by user without issues
- [Phase 03-06]: scheduleIntervalSeconds stored as Int (seconds) in UserDefaults — @AppStorage in view, UserDefaults.standard.integer in coordinator, consistent with autoBackupEnabled pattern
- [Phase 03-06]: updateScheduleInterval calls scheduler.start() directly — SchedulerTask.start() cancels existing task before starting new one, no explicit stop() needed

### Pending Todos

None yet.

### Blockers/Concerns

- **Phase 2**: Sandboxing decision must be finalized before implementation (affects FSEvents bookmark handling)
- **Phase 2**: Concurrent job limit policy needed when multiple watch folders change simultaneously
- **Phase 4**: iCloud large file throttling behavior at scale needs validation (5-20 GB projects)
- **Phase 4**: macOS 15 NetFS reconnection behavior needs validation during planning
- **Phase 5**: ALS XML schema should be validated against real Ableton 11 and 12 projects before implementation
- **Phase 6**: GitHub LFS quota UX (1 GB free tier vs. multi-GB audio) needs design before implementation

## Session Continuity

Last session: 2026-03-03
Stopped at: Completed 03-06-PLAN.md — APP-04 gap closed: schedule interval configurable (30 min/1 hr/2 hr/4 hr) via Picker in GeneralSettingsView; BackupCoordinator reads interval from UserDefaults on startup and restarts scheduler immediately on change; Phase 3 gap closure fully complete
Resume file: None
