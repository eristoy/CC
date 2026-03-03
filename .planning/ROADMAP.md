# Roadmap: AbletonBackup

## Overview

AbletonBackup is built foundation-first: a correct, verified backup engine ships before any UI, ensuring the tool never produces confident-but-corrupt backups. The app shell and file watching layer on top next, making the tool a real background utility. Settings and version history complete the MVP. Network destinations (NAS, iCloud) add the multi-location story. The ALS parser — the core differentiator — ships last among general features because it enhances a proven system rather than underpinning it. The GitHub/Git LFS destination closes out v1 as the highest-complexity, narrowest-audience feature.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Backup Engine** - Core file copy, checksum verification, versioning, and local destination — no UI (COMPLETE 2026-02-26)
- [ ] **Phase 2: App Shell + Triggers** - LSUIElement app, menu bar icon, FSEvents watch, schedule, manual trigger, notifications
- [x] **Phase 3: Settings + History** - Settings window, watch folder management, version history browser (completed 2026-03-02)
- [ ] **Phase 4: Network Destinations** - NAS (SMB/NFS), iCloud Drive, per-destination status, sleep/wake reconnection
- [ ] **Phase 5: ALS Parser** - Parse .als files to resolve external sample paths; warn on missing samples
- [ ] **Phase 6: GitHub Destination** - Git LFS destination with bundled binaries and quota management

## Phase Details

### Phase 1: Backup Engine
**Goal**: A correct, verified backup system for local destinations exists and is testable without any UI
**Depends on**: Nothing (first phase)
**Requirements**: BACK-01, BACK-02, BACK-03, BACK-04, BACK-05, DEST-01
**Success Criteria** (what must be TRUE):
  1. A backup job copies a project folder and all specified files to a local destination, creating a versioned snapshot directory
  2. A second backup of the same project skips unchanged files (incremental — only changed files are copied)
  3. After copy, each file's checksum is verified against the source; a corrupted file causes the version to be marked corrupt, not verified
  4. After N+1 backups, the oldest version is automatically pruned; N is configurable
  5. A local attached drive can be configured as a destination and receives backup output
**Plans**: 5 plans

Plans:
- [x] 01-01-PLAN.md — Xcode/SPM project setup, GRDB 7 schema, and all persistence model types
- [x] 01-02-PLAN.md — TDD: ProjectResolver (folder walker) and BackupJob contract types
- [x] 01-03-PLAN.md — FileCopyPipeline (inline checksum + APFS clone) and LocalDestinationAdapter
- [x] 01-04-PLAN.md — TDD: VersionManager (ID generation, retention enforcement, safe pruning)
- [x] 01-05-PLAN.md — BackupEngine actor orchestration and end-to-end integration tests

### Phase 2: App Shell + Triggers
**Goal**: The app runs silently as a macOS menu bar utility, watches for Ableton saves, and backs up automatically with visible status
**Depends on**: Phase 1
**Requirements**: APP-01, APP-02, APP-03, DISC-01, TRIG-01, TRIG-02, TRIG-03, NOTIF-01, NOTIF-02
**Success Criteria** (what must be TRUE):
  1. App launches with no Dock icon; a menu bar icon is the only visible entry point
  2. Menu bar icon changes between idle, running, and error states reflecting current backup status
  3. Saving an Ableton project triggers a backup automatically within a few seconds
  4. A scheduled backup runs at the configured interval without any user action
  5. User can click "Back Up Now" in the menu to trigger an immediate backup
  6. A macOS notification appears on backup completion and on backup failure with error detail
  7. App can be configured to launch at login and does so reliably
**Plans**: 7 plans

Plans:
- [ ] 02-01-PLAN.md — Xcode project scaffold via xcodegen: app target, Info.plist (LSUIElement), BackupCoordinator skeleton
- [ ] 02-02-PLAN.md — FSEventsWatcher (atomic-rename filter) and AbletonPrefsReader (Library.cfg discovery)
- [ ] 02-03-PLAN.md — NotificationService, SchedulerTask (Task loop), and LoginItemManager (SMAppService)
- [ ] 02-04-PLAN.md — Wire all components: complete BackupCoordinator + MenuBarView with status, triggers, and login item toggle
- [ ] 02-05-PLAN.md — Human verification checkpoint: all Phase 2 success criteria confirmed end-to-end
- [ ] 02-06-PLAN.md — GAP: Add os.log structured logging to BackupEngine and all app-layer components
- [ ] 02-07-PLAN.md — GAP: Fix notification authorization + foreground delivery delegate; surface guard failures as error states

### Phase 3: Settings + History
**Goal**: All app behavior is configurable via a settings window and users can inspect past backup versions
**Depends on**: Phase 2
**Requirements**: APP-04, DISC-02, DISC-03, HIST-01, HIST-02
**Success Criteria** (what must be TRUE):
  1. Settings window covers all configuration: destinations, schedule, version retention, and watch folders
  2. User can add an additional watch folder and it is monitored for Ableton saves going forward
  3. User can remove a watch folder and it is no longer monitored
  4. User can view a list of past backup versions for any project, with timestamp for each version
  5. Version history shows which destinations each version exists on
**Plans**: 5 plans

Plans:
- [ ] 03-01-PLAN.md — WatchFolder GRDB model + v2 migration; BackupCoordinator multi-watcher refactor with DB-backed watch folder list
- [ ] 03-02-PLAN.md — Settings scene, MenuBarView settings button, SettingsView TabView, GeneralSettingsView, AboutView
- [ ] 03-03-PLAN.md — WatchFoldersSettingsView (NSOpenPanel + confirmationDialog) and DestinationsSettingsView (read-only)
- [ ] 03-04-PLAN.md — HistoryView (NavigationSplitView, BackupEvent grouping, ValueObservation, corrupt warnings)
- [x] 03-05-PLAN.md — Human verification checkpoint: all Phase 3 success criteria confirmed end-to-end (completed 2026-03-03)

### Phase 4: Network Destinations
**Goal**: Users can back up to a NAS (with Keychain credentials) and iCloud Drive, with live destination status and reliable sleep/wake behavior
**Depends on**: Phase 3
**Requirements**: DEST-02, DEST-03, DEST-04, DEST-06, DEST-07
**Success Criteria** (what must be TRUE):
  1. User can configure a NAS destination via an already-mounted Mac volume and backups write to it
  2. User can configure a NAS destination via direct SMB/NFS with credentials stored in Keychain; app mounts and connects without user action
  3. User can configure iCloud Drive as a destination; backups appear in iCloud Drive without any authentication step
  4. Each configured destination shows a live availability status (online / offline / error) in settings
  5. After system wakes from sleep, NAS destinations reconnect and a backup proceeds without manual intervention
**Plans**: TBD

### Phase 5: ALS Parser
**Goal**: Backups include all externally referenced samples, making every backup fully restorable regardless of where samples are stored on disk
**Depends on**: Phase 4
**Requirements**: PRSR-01, PRSR-02
**Success Criteria** (what must be TRUE):
  1. When backing up a project, the app parses the .als file and identifies all sample paths referenced in the project, including samples stored outside the project folder
  2. All identified external samples are included in the backup alongside the project folder contents
  3. If a referenced sample is missing or on an offline drive, the user sees a warning before the backup completes (backup still proceeds with available files)
**Plans**: TBD

### Phase 6: GitHub Destination
**Goal**: Users can back up projects to a GitHub repository using Git LFS for audio files, with quota monitoring and no dependency on system-installed git tools
**Depends on**: Phase 5
**Requirements**: DEST-05
**Success Criteria** (what must be TRUE):
  1. User can configure a GitHub repository as a backup destination; the app initializes it with correct .gitattributes LFS tracking before any audio files are pushed
  2. Backup commits land in the GitHub repository with audio files stored via Git LFS; the repository is cloneable and restorable
  3. App uses bundled git and git-lfs binaries — no dependency on system-installed git
  4. App checks GitHub LFS quota before push and warns the user if quota is insufficient to complete the backup
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Backup Engine | 5/5 | Complete | 2026-02-26 |
| 2. App Shell + Triggers | 6/7 | In Progress|  |
| 3. Settings + History | 6/6 | Complete   | 2026-03-03 |
| 4. Network Destinations | 0/TBD | Not started | - |
| 5. ALS Parser | 0/TBD | Not started | - |
| 6. GitHub Destination | 0/TBD | Not started | - |
