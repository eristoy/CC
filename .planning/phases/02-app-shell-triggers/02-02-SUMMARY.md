---
phase: 02-app-shell-triggers
plan: "02"
subsystem: triggers
tags: [fsevents, coreservices, swift6, xml, preferences, directory-watching]

# Dependency graph
requires:
  - phase: 02-01
    provides: BackupCoordinator scaffold and Xcode project with AbletonBackup target

provides:
  - FSEventsWatcher: CoreServices FSEventStreamRef wrapper for atomic-rename .als detection
  - AbletonPrefsReader: Library.cfg XML parser and Projects folder auto-discovery

affects: [02-04-BackupCoordinator-wiring, 03-settings-ui, phase-3]

# Tech tracking
tech-stack:
  added: [CoreServices FSEventStreamRef, Foundation XMLDocument]
  patterns:
    - "FSEvents atomic-rename detection: filter (isModified || isRenamed) && isFile && .als"
    - "Retained self as FSEventStreamContext.info pointer; balanced in deinit"
    - "AbletonPrefsReader fallback chain: default path -> Library.cfg XPath -> nil"

key-files:
  created:
    - AbletonBackup/FSEventsWatcher.swift
    - AbletonBackup/AbletonPrefsReader.swift
  modified: []

key-decisions:
  - "Both kFSEventStreamEventFlagItemModified and kFSEventStreamEventFlagItemRenamed checked — Ableton uses atomic rename (write temp, rename to .als), so isModified alone would miss saves"
  - "kFSEventStreamCreateFlagFileEvents required — without it FSEvents delivers only directory-level events, making filename filtering impossible"
  - "CFRunLoopGetMain() used for stream scheduling — delivers on main thread; BackupCoordinator (02-04) will wrap in Task { @MainActor in ... }"
  - "discoverProjectsFolder() checks ~/Documents/Ableton/Ableton Projects first (confirmed Ableton 12.2 default on this machine), then falls back to Library.cfg parse"
  - "parseUserLibraryPath() uses XMLDocument on Library.cfg (UTF-8 XML) — Preferences.cfg is proprietary binary and must never be parsed"
  - "findLatestVersionFolder() sorts by lastPathComponent descending — handles multiple Ableton versions coexisting without hardcoding version strings"

patterns-established:
  - "FSEventStreamContext.info: passRetained in init, passUnretained.release() in deinit for correct ARC balance with C callbacks"
  - "Non-throwing discovery: all AbletonPrefsReader methods return Optional, never throw — callers fall back to nil/file picker"

requirements-completed: [TRIG-01, DISC-01]

# Metrics
duration: 1min
completed: 2026-02-27
---

# Phase 02, Plan 02: FSEventsWatcher + AbletonPrefsReader Summary

**CoreServices FSEventStreamRef wrapper with atomic-rename .als filter plus Library.cfg XML parser for Ableton Projects folder auto-discovery**

## Performance

- **Duration:** ~1 min
- **Started:** 2026-02-27T19:05:05Z
- **Completed:** 2026-02-27T19:06:21Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- FSEventsWatcher wraps FSEventStreamRef with correct flag filter for Ableton's atomic-rename save pattern: `(isModified || isRenamed) && isFile && path.hasSuffix(".als")`
- AbletonPrefsReader.discoverProjectsFolder() returned a non-nil URL on this machine (~/Documents/Ableton/Ableton Projects exists — Ableton 12.2 default confirmed)
- Both files compile cleanly under Swift 6 strict concurrency with zero errors, first attempt

## Task Commits

Each task was committed atomically:

1. **Task 1: Implement FSEventsWatcher** - `9694433` (feat)
2. **Task 2: Implement AbletonPrefsReader** - `4de0cc2` (feat)

## Files Created/Modified

- `AbletonBackup/FSEventsWatcher.swift` — CoreServices FSEventStreamRef wrapper; watches directory tree for .als changes via atomic-rename pattern; scheduled on main run loop with 2.0s latency
- `AbletonBackup/AbletonPrefsReader.swift` — Reads Library.cfg via XMLDocument XPath; discoverProjectsFolder() multi-step fallback strategy returning optional URL

## Decisions Made

- Both `isModified` and `isRenamed` flags checked — Ableton writes a temp file then renames it to `.als`; watching only `isModified` would miss every save. This was the critical correctness requirement.
- `kFSEventStreamCreateFlagFileEvents` is mandatory for per-file events (macOS 10.7+). Without it, FSEvents delivers directory-level notifications only, making `.als` filename filtering impossible.
- `CFRunLoopGetMain()` chosen for stream scheduling — the FSEventStreamCallback is a C function pointer with no Swift actor context; consumers (BackupCoordinator, Plan 02-04) wrap with `Task { @MainActor [weak self] in ... }`.
- `discoverProjectsFolder()` checks `~/Documents/Ableton/Ableton Projects` first — confirmed as Ableton 12.2's actual default on this machine during research. Library.cfg parse is a fallback for non-default configs.
- `Library.cfg` is UTF-8 XML; `Preferences.cfg` is proprietary binary. Only Library.cfg is parsed.
- Version folder discovery uses string sort descending on `lastPathComponent` — correctly picks "Live 12.2" over "Live 11.0" without hardcoding any version.

## Deviations from Plan

None — plan executed exactly as written. Both files compiled on the first build attempt with zero errors or warnings under Swift 6 strict concurrency.

## Issues Encountered

None. The FSEventStreamCallback C function pointer pattern compiled correctly in Swift 6 without concurrency warnings because the closure has no captures — the `watcher` reference is obtained from the `info` pointer inside the callback body.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- FSEventsWatcher is ready to be stored in BackupCoordinator (Plan 02-04) as `private var watcher: FSEventsWatcher?`
- AbletonPrefsReader.discoverProjectsFolder() is ready to be called at app launch in AbletonBackupApp.swift
- Both files are self-contained with no @MainActor dependencies — BackupCoordinator wiring (02-04) handles the actor boundary

---
*Phase: 02-app-shell-triggers*
*Completed: 2026-02-27*
