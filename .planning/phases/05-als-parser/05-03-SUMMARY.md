---
phase: 05-als-parser
plan: 03
subsystem: ui
tags: [swiftui, navigation, notifications, history, samples, als, deep-link]

# Dependency graph
requires:
  - phase: 05-01
    provides: BackupVersion ALS schema fields (collectedSampleCount, collectedSamplePaths, missingSampleCount, missingSamplePaths, hasParseWarning), BackupVersion.decodePaths
  - phase: 05-02
    provides: Notification.Name.navigateToVersion, NotificationDelegate.didReceive posting navigateToVersion, BackupJobResult.sampleCollection

provides:
  - BackupEvent computed properties totalMissingSamples, hasParseWarning, hasSampleWarning
  - BackupEvent conformance to Hashable for NavigationLink(value:) programmatic navigation
  - BackupEventRow warning badge: orange doc.badge.exclamationmark for parse failures, yellow triangle for missing samples
  - VersionDetailView showing aggregated missing and collected sample path lists
  - VersionListView wrapped in NavigationStack using value-based NavigationLink + navigationDestination
  - HistoryView.onReceive(.navigateToVersion): finds owning project from DB, sets selectedProjectID
  - NSApp.sendAction(showSettingsWindow:) on notification tap to surface Settings window
  - navigateToVersionID binding wired from HistoryView to VersionListView for programmatic deep-link navigation

affects: [history-ui, end-to-end-als-flow]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "NavigationLink(value:) + navigationDestination(for:) for programmatic SwiftUI navigation with Hashable models"
    - "Binding<String?> passed from parent view to child list view for deep-link navigation coordination"
    - "ValueObservation handler used to both update state and consume pending navigation intent in a single pass"

key-files:
  created: []
  modified:
    - AbletonBackup/Views/Settings/HistoryView.swift

key-decisions:
  - "Both Task 1 (warning badges + VersionDetailView) and Task 2 (navigateToVersion observer) implemented together in a single file edit and commit — same file, no conflicts, BUILD SUCCEEDED on first attempt"
  - "NavigationLink(value:) + Hashable BackupEvent chosen over NavigationLink(destination:) — enables programmatic programmatic navigation via selectedEventForNavigation state binding"
  - "navigateToVersionID binding wired into VersionListView.onChange(of: events) to auto-navigate when events first load after project selection from notification tap"

patterns-established:
  - "Deep-link navigation pattern: parent holds navigateToVersionID binding, child list view consumes it in onChange(of: events) once data loads"

requirements-completed: [PRSR-01, PRSR-02]

# Metrics
duration: 2min
completed: 2026-03-06
---

# Phase 05 Plan 03: HistoryView ALS Sample UI Summary

**Warning badges on history rows (yellow triangle for missing samples, orange icon for parse failures), VersionDetailView drill-down with collected/missing path lists, and notification-tap deep-link navigation to the relevant project and backup event**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-03-06T20:05:50Z
- **Completed:** 2026-03-06T20:07:52Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments

- BackupEventRow now shows a yellow `exclamationmark.triangle.fill` badge when missingSampleCount > 0 and an orange `doc.badge.exclamationmark` badge when hasParseWarning is true; rows with no sample data (pre-Phase-5 backups) show no badge
- VersionDetailView (new private struct) aggregates unique collected and missing sample paths across all destination versions in an event, showing a parse warning banner, missing samples section, and collected samples section with SF Symbol labels
- HistoryView observes `.navigateToVersion` notification, calls `NSApp.sendAction(showSettingsWindow:)` to open Settings, fetches the owning project from GRDB, sets `selectedProjectID`, and passes `navigateToVersionID` binding to VersionListView for programmatic list navigation
- VersionListView now wraps in NavigationStack and uses value-based NavigationLink + `navigationDestination(for: BackupEvent.self)` — BackupEvent conforms to Hashable; `onChange(of: events)` auto-navigates to target event when events first load

## Task Commits

Each task was committed atomically:

1. **Task 1: BackupEventRow warning badge + VersionDetailView** and **Task 2: Notification tap → history navigation** - `0efc39e` (feat) — both tasks in same file, committed together

## Files Created/Modified

- `AbletonBackup/Views/Settings/HistoryView.swift` — BackupEvent Hashable conformance + sample summary computed properties; BackupEventRow warning badges; VersionDetailView; VersionListView NavigationStack + value-based NavigationLink; HistoryView .onReceive(.navigateToVersion) observer + navigateToVersionID binding

## Decisions Made

- **Tasks 1 and 2 committed together**: Both tasks modify only `HistoryView.swift`. The entire implementation was written in one pass, BUILD SUCCEEDED on the first attempt, so a single atomic commit covers both tasks cleanly.
- **NavigationLink(value:) + navigationDestination(for:)**: Value-based navigation was required for programmatic deep-link navigation (setting `selectedEventForNavigation` state from the `.onChange` handler). The destination-based `NavigationLink(destination:)` approach from the original Task 1 draft does not support programmatic trigger.
- **navigateToVersionID consumed in ValueObservation handler**: Rather than a separate `.onChange(of: navigateToVersionID)`, the deep-link intent is also consumed inside the ValueObservation result handler. This ensures navigation fires even when the events list was already loaded before the notification arrived.

## Deviations from Plan

None - plan executed exactly as written. The value-based NavigationLink approach was already described in Task 2 of the plan; the implementation followed it throughout rather than doing destination-based first and value-based second.

## Issues Encountered

None — BUILD SUCCEEDED on first attempt with no compiler errors.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 05 (ALS Parser) is now complete — all three plans done
- History rows surface ALS sample data: yellow/orange warning badges, drill-down VersionDetailView, notification deep-link navigation
- Ready for Phase 06 (GitHub LFS destination) or any remaining phases

---
*Phase: 05-als-parser*
*Completed: 2026-03-06*
