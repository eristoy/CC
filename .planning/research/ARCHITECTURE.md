# Architecture Research — AbletonBackup

**Research type**: Project Research — Architecture dimension
**Date**: 2026-02-25
**Question**: How are macOS background utility apps (menu bar apps with settings windows) typically structured? What are the major architectural components for a backup tool that watches files, transfers to multiple destinations (local, NAS via SMB, cloud via APIs), manages version history, and supports restore?

---

## How macOS Menu Bar Backup Apps Are Typically Structured

### The macOS Menu Bar App Pattern

macOS background utilities that live in the menu bar follow a well-established pattern. The app runs as an `LSUIElement` (agent app) — it appears in the menu bar but not in the Dock or the App Switcher. The entry point is a standard `NSApplicationDelegate`, but `Info.plist` sets `LSUIElement = YES` (or `Application is agent` in Xcode). This keeps the app invisible to the user except for its status item.

The two primary UI surfaces are:

1. **NSStatusItem** — the menu bar icon and its dropdown menu (the primary interaction point)
2. **Settings window** — an `NSWindow` (or `SwiftUI WindowGroup`) surfaced via the menu, for configuration

The app process runs continuously. Background work (file watching, scheduled backups, transfers) runs on background queues/threads, never on the main thread. The main thread remains available for UI updates only.

### Process Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│  AbletonBackup.app process (LSUIElement — no Dock icon)              │
│                                                                       │
│  Main Thread                                                          │
│  ├── NSStatusItem (menu bar icon + menu)                             │
│  ├── Settings Window Controller                                       │
│  └── UI state observation (Combine / @Observable / NotificationCenter)│
│                                                                       │
│  Background                                                           │
│  ├── File Watcher (FSEvents stream on background queue)              │
│  ├── Backup Scheduler (Timer / BackgroundTasks framework)            │
│  ├── Backup Engine (OperationQueue, concurrent)                      │
│  │   ├── Transfer: Local Destination Worker                          │
│  │   ├── Transfer: NAS / SMB Destination Worker                      │
│  │   ├── Transfer: iCloud Drive Destination Worker                   │
│  │   ├── Transfer: Google Drive API Worker                           │
│  │   ├── Transfer: Dropbox API Worker                                │
│  │   └── Transfer: GitHub / Git LFS Worker                          │
│  └── Persistence Layer (SQLite via GRDB or Core Data)               │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Major Architectural Components

### 1. App Shell / Entry Point

**Responsibility**: Bootstrap the process, own top-level lifecycle, manage the status item.

- Sets `LSUIElement = YES` so the app has no Dock icon
- Creates `NSStatusItem` with an `NSMenu`
- Instantiates and wires up all subsystems at launch
- Listens for system events (sleep/wake, network change, login/logout) via `NSWorkspace.shared.notificationCenter` and `NSNotificationCenter`
- Owns the settings window controller; shows/hides it on demand

**Key API**: `NSStatusBar`, `NSStatusItem`, `NSMenu`, `NSWorkspace`, `NSApplicationDelegate`

---

### 2. File Watcher

**Responsibility**: Detect when Ableton project files change and notify the Backup Engine.

macOS provides two levels of file system event notification:

- **FSEvents** (`FSEventStreamCreate`) — kernel-level, very efficient, coalesced events, works recursively on directory trees. This is the right choice for watching a projects folder. Fires on file creation, modification, rename, deletion. Events are delivered to a callback on a designated dispatch queue.
- **DispatchSource / kqueue** — lower-level, used when you need per-file precision rather than directory-tree watching. Not needed here.

The File Watcher holds an `FSEventStream` for each configured watch folder. When an event fires, it:

1. Filters to Ableton-relevant changes (`.als` save, `Samples/` folder modification)
2. Debounces rapid successive events (Ableton writes multiple files during save; wait ~2s for the burst to settle)
3. Emits a "project changed" signal to the Backup Engine

**Key API**: `FSEvents` C API (`FSEventStreamCreate`, `FSEventStreamStart`, `FSEventStreamStop`), `DispatchQueue`

**Note on sandboxing**: FSEvents requires the watch path to be in a Security-Scoped Bookmark if the app is sandboxed. The user grants access once via an Open Panel; the app stores the bookmark in `UserDefaults` or `Keychain` and resolves it at launch.

---

### 3. Backup Scheduler

**Responsibility**: Trigger backups on a time-based schedule independent of file changes.

- Maintains a configurable `Timer` (or `DispatchSourceTimer`) for interval-based triggers (hourly, daily, etc.)
- On macOS 13+, `BGTaskScheduler` can be used for true background refresh (waking the app when suspended), but for a menu bar app that stays running, a simple repeating timer on a background queue is sufficient and simpler
- Coordinates with the Backup Engine to avoid overlapping jobs: checks if a backup is already running before firing

**Key API**: `Timer`, `DispatchSourceTimer`, optionally `BGTaskScheduler`

---

### 4. Backup Engine

**Responsibility**: Orchestrate a backup job — enumerate files to back up, fan out transfers to destinations, track progress, persist results.

This is the core of the application. A backup job proceeds through these phases:

```
Trigger (file watch event or schedule or manual)
  │
  ▼
Project Resolver
  ├── Locate the .als file
  ├── Parse project folder structure
  └── Collect all referenced samples (scan /Samples subdirectory; optionally parse .als XML for external references)
  │
  ▼
Version Manager (pre-backup)
  ├── Assign version ID (timestamp-based, e.g. ISO8601)
  ├── Prune old versions beyond retention limit per destination
  └── Create backup manifest (list of files, sizes, checksums)
  │
  ▼
Transfer Dispatcher
  ├── Fan out to all configured destinations concurrently
  ├── Each destination runs its own transfer worker
  └── Workers report progress and completion back to engine
  │
  ▼
Result Aggregator
  ├── Collect success/failure from each destination
  ├── Persist backup record to database
  ├── Fire macOS notification (success or error)
  └── Update menu bar icon state
```

**Concurrency model**: Use `async/await` with Swift Concurrency (actors + structured concurrency) or `OperationQueue` with per-destination operations. Swift Concurrency is preferred for new code — the `BackupEngine` can be an `actor` to serialize job management, while individual transfers run concurrently via `async let` or `TaskGroup`.

**Key API**: Swift Concurrency (`Actor`, `TaskGroup`, `async/await`), `OperationQueue` (if pre-async)

---

### 5. Project Resolver / File Collector

**Responsibility**: Given a project path, determine the complete set of files to back up.

Ableton project structure:
```
MyProject/
├── MyProject.als          ← main project file (XML inside, zipped)
├── Backup/                ← Ableton's own auto-saves (back these up too)
├── Samples/
│   ├── Imported/          ← audio dragged into the project
│   ├── Recorded/          ← audio recorded in the session
│   └── Processed/         ← warped/frozen audio
└── Ableton Project Info/
```

External samples (from outside the project folder) are referenced by absolute path in the `.als` XML. To back up a project that's fully self-contained, the app should check if the user has used "Collect All and Save" in Ableton (which copies external samples into the project folder). If external references exist, the app can either warn the user or optionally copy-collect them.

For v1, back up the entire project folder. Parsing `.als` XML for external references is a v2 concern.

---

### 6. Destination Workers

**Responsibility**: Transfer files from the local project folder to a specific destination. Each destination type has its own worker that encapsulates its transport mechanism.

#### 6a. Local Disk Worker

- Uses `FileManager` to copy/hardlink files
- Can use file cloning on APFS (`copyfile()` with `COPYFILE_CLONE`) for near-instant, copy-on-write copies — major performance win
- Manages version directories: `<dest>/<project-name>/<timestamp>/`

**Key API**: `FileManager`, `copyfile()` with `COPYFILE_CLONE_FORCE`

#### 6b. NAS / SMB Worker

Two sub-modes:
1. **Mounted volume**: The NAS is mounted at `/Volumes/MyNAS` — treat it like local disk (same `FileManager` API, but APFS cloning won't apply)
2. **Direct SMB with credentials**: Use `NetFS.framework` to mount the share programmatically, then transfer via `FileManager`, then optionally unmount. Or keep the mount persistent. Credentials stored in Keychain.

macOS auto-mounts SMB shares when you connect, and `NetFS` (`SMBOpenServerEx`, `NetFSMountURLSync`) handles authenticated mounts. Connection should be retried after wake from sleep.

**Key API**: `NetFS.framework`, `FileManager`, `Keychain` (via `Security.framework`)

#### 6c. iCloud Drive Worker

iCloud Drive is mounted at `~/Library/Mobile Documents/` and exposed via `NSUbiquitousItemDownloadingStatus`. Files can be copied there with `FileManager` like any local path — iCloud syncs automatically. No OAuth needed; the user must be signed into iCloud.

Considerations:
- Large audio files will count against the user's iCloud storage quota
- The worker should check available iCloud space before transfer (`URLResourceKey.volumeAvailableCapacityForImportantUsageKey`)

**Key API**: `FileManager`, `FileManager.default.url(forUbiquityContainerIdentifier:)`, `NSMetadataQuery` (for sync status)

#### 6d. Google Drive / Dropbox Workers

Both require OAuth 2.0. Flow:
1. Open auth URL in browser (`NSWorkspace.shared.open(authURL)`)
2. Receive callback via custom URL scheme (`myapp://oauth-callback`) registered in `Info.plist`
3. Exchange code for access/refresh tokens; store tokens in Keychain
4. Use REST API for file uploads

For large files (multi-GB audio), use resumable/chunked uploads — both Google Drive and Dropbox support this. Track upload progress for UI feedback. Retry on transient network errors with exponential backoff.

**Key API**: `URLSession` (with `URLSessionUploadTask`), `ASWebAuthenticationSession` (cleaner OAuth than raw URL scheme), Keychain

**Library consideration**: Use the official SDKs (Google Drive SDK for Swift, Dropbox Swift SDK) to reduce implementation burden for OAuth and chunked uploads.

#### 6e. GitHub / Git LFS Worker

Git LFS is required for audio files. Two implementation approaches:

1. **Shell out to `git` + `git-lfs`**: Reliable, but requires `git` and `git-lfs` to be installed on the user's machine (via Homebrew or Xcode CLT). Use `Process` (formerly `NSTask`) to run commands.
2. **Libgit2 / SwiftGit2**: Embed a git library. Does not natively support LFS — would need custom LFS pointer/upload logic. More work.

Approach 1 is simpler for v1. The worker:
1. Checks out / clones the destination repo on first run
2. Copies new project files in
3. Commits with a timestamp message
4. Pushes (LFS objects transfer automatically)

GitHub requires a Personal Access Token or OAuth app. Token stored in Keychain.

**Key API**: `Process`, `Keychain`, optionally `SwiftGit2`

---

### 7. Version Manager

**Responsibility**: Enforce retention policy (keep last N versions per project per destination), provide version history for restore.

- Each backup creates a timestamped version record
- After each successful backup, prune versions beyond retention limit
- Store version metadata in the local database (not per-destination — one source of truth)
- For restore: present version list from database; copy files back from destination to original project location

**Version directory structure** (for file-copy destinations):
```
<destination-root>/
└── <project-name>/
    ├── 2026-02-25T143022/
    │   ├── MyProject.als
    │   └── Samples/
    │       └── Imported/
    │           └── kick.wav
    └── 2026-02-24T091500/
        └── ...
```

For Git destinations, each commit is a version; pruning means deleting old commits (rewriting history) or leaving old commits and just tracking which ones to surface in the UI.

---

### 8. Persistence Layer (Database)

**Responsibility**: Store configuration (destinations, schedules, retention settings) and backup history (versions, timestamps, file counts, errors).

**Two data categories**:

1. **Configuration** — small, structured, changes infrequently
   - Could use `UserDefaults` for simple settings
   - Better: a lightweight SQLite database (via GRDB.swift) or a plist for settings, keeping it separate from history

2. **Backup history** — grows over time, needs queries (list versions for project X)
   - SQLite via GRDB.swift is the right choice: type-safe Swift API, no ORM overhead, fast, zero server
   - Schema: `Projects`, `BackupJobs`, `BackupVersions`, `Destinations`

**Sensitive data** (passwords, OAuth tokens, API keys) must go in the Keychain, never in UserDefaults or SQLite.

**Key API**: GRDB.swift (recommended), or Core Data (heavier), `Security.framework` (Keychain)

---

### 9. Status / State Bus

**Responsibility**: Propagate real-time backup state to the UI (menu bar icon, settings window progress views).

The Backup Engine emits state updates that the UI observes. Options:

- **Combine** — `PassthroughSubject` / `CurrentValueSubject` published from the engine; UI subscribes. Works well with SwiftUI.
- **NotificationCenter** — looser coupling; fine for cross-module events
- **@Observable (Swift 5.9+)** — if the engine is a class/actor annotated with `@Observable`, SwiftUI views automatically re-render on state changes

Recommended: a central `AppState` observable object that holds `backupStatus: BackupStatus`, `lastBackupDate`, `activeTransfers: [TransferProgress]`. The engine writes to it; the menu bar and settings window read from it.

---

### 10. Settings Window

**Responsibility**: UI for configuring all aspects of the app.

- Built in SwiftUI (`WindowGroup` or a single `NSWindow` with a SwiftUI root view)
- Sections: Watch Folders, Destinations (add/remove/configure each), Schedule, Retention, Version History + Restore
- Opened from the menu bar menu
- Must handle the case where settings change while a backup is running (defer reloading config until current job completes)

---

### 11. Notification Center Integration

**Responsibility**: Surface backup completion and errors to the user even when they're not looking at the menu.

- Use `UserNotifications` framework (`UNUserNotificationCenter`)
- Request authorization at first launch
- Post notifications for: backup complete, backup failed, destination unreachable, storage nearly full

**Key API**: `UserNotifications` framework, `UNUserNotificationCenter`, `UNNotificationRequest`

---

## Component Interaction Diagram

```
                          ┌─────────────────────┐
                          │   App Shell / Entry  │
                          │   (AppDelegate)       │
                          └──────┬──────┬────────┘
                                 │      │
                    ┌────────────┘      └──────────────┐
                    ▼                                   ▼
         ┌──────────────────┐               ┌──────────────────────┐
         │  Status Item /   │               │   Settings Window    │
         │  Menu Bar UI     │               │   (SwiftUI)          │
         └────────┬─────────┘               └───────────┬──────────┘
                  │  reads                              │ reads/writes
                  │                                     │
                  └──────────────┬──────────────────────┘
                                 ▼
                    ┌────────────────────────┐
                    │      AppState          │  ← @Observable / Combine
                    │  (status, progress,    │
                    │   history summary)     │
                    └────────────┬───────────┘
                                 │ written by
                    ┌────────────┴───────────────────────────┐
                    │           Backup Engine                 │
                    │   (actor — serializes job management)   │
                    └──┬──────────┬──────────────────────────┘
                       │          │
          ┌────────────┘          └────────────────────┐
          ▼                                            ▼
┌──────────────────┐                       ┌──────────────────────┐
│  File Watcher    │   triggers            │  Backup Scheduler    │
│  (FSEvents)      │──────────────────────▶│  (Timer)             │
└──────────────────┘                       └──────────────────────┘
          │ trigger                                    │ trigger
          └───────────────────┬────────────────────────┘
                              ▼
                   ┌──────────────────────┐
                   │  Project Resolver /  │
                   │  File Collector      │
                   └──────────┬───────────┘
                              │ file list
                              ▼
                   ┌──────────────────────┐
                   │  Transfer Dispatcher │
                   │  (TaskGroup / async) │
                   └──┬────┬─────┬────┬──┘
          ┌───────────┘    │     │    └─────────────┐
          ▼                ▼     ▼                   ▼
  ┌──────────┐  ┌───────┐ ┌──────────┐  ┌──────────────────┐
  │  Local   │  │  NAS  │ │  Cloud   │  │  GitHub/Git LFS  │
  │  Worker  │  │ Worker│ │ Workers  │  │  Worker          │
  └──────────┘  └───────┘ └──────────┘  └──────────────────┘
          │                │     │                   │
          └────────────────┴──┬──┴───────────────────┘
                              ▼
                   ┌──────────────────────┐
                   │  Version Manager     │
                   │  + Persistence Layer │
                   │  (GRDB / SQLite)     │
                   └──────────┬───────────┘
                              │ result
                              ▼
                   ┌──────────────────────┐
                   │  Notification Center │
                   │  (UNUserNotification)│
                   └──────────────────────┘
```

---

## Data Flow: A Backup Job End-to-End

```
1. TRIGGER
   File Watcher detects .als file write
   → debounce 2 seconds
   → emit "project X changed" event to Backup Engine

2. JOB CREATION
   Backup Engine (actor) receives event
   → checks: is a job already running for project X? → skip/queue
   → creates BackupJob(projectPath, timestamp, destinations)
   → updates AppState.backupStatus = .running(project: X)

3. FILE COLLECTION
   Project Resolver walks project folder
   → returns [FileEntry(path, size, modifiedDate)]
   → Backup Engine logs: N files, ~X GB total

4. VERSION ASSIGNMENT
   Version Manager generates versionID = ISO8601 timestamp
   → checks retention: will pruning be needed after this backup?
   → creates pending BackupVersion record in database (status: .inProgress)

5. PARALLEL TRANSFER
   Transfer Dispatcher opens TaskGroup
   → spawns one child Task per configured destination
   → each destination worker:
      a. Creates destination version directory (or git branch/commit for GitHub)
      b. Copies/uploads files (streams large files; reports bytes-transferred)
      c. Returns .success or .failure(error)
   → progress updates flow back to AppState (per-destination progress)

6. RESULT AGGREGATION
   All tasks complete (success or failure)
   → Version Manager finalizes BackupVersion record (status, per-destination results)
   → Prunes old versions beyond retention limit
   → AppState.backupStatus = .idle (or .error if all destinations failed)
   → lastBackupDate = now

7. NOTIFICATION
   Notification Center posts:
   → Success: "Project X backed up to 3 destinations"
   → Partial failure: "Project X backed up to 2/3 destinations — NAS unreachable"
   → Full failure: "Backup failed — check destinations"
```

---

## Handling Background Operation

### Staying Alive

Menu bar apps (`LSUIElement`) are long-running processes — they don't get suspended like sandboxed apps in the background. The app stays resident as long as the user is logged in. No special lifecycle management is needed beyond handling system sleep/wake.

### Sleep/Wake

Register for `NSWorkspace.didWakeNotification`:
- On wake, reconnect NAS mounts that dropped during sleep
- Re-validate OAuth tokens (cloud providers may invalidate them)
- Run any missed scheduled backups (check "last backup time" against schedule)

### Network Connectivity

Register for `NWPathMonitor` (Network framework) to detect when network is available/unavailable:
- Pause NAS and cloud transfers when network is offline
- Resume/retry when connectivity returns
- Surface "NAS unreachable" in menu without crashing

### File Watching Across Sleep

FSEvent streams survive sleep automatically. No special handling needed for the watcher itself.

---

## Handling Concurrent Transfers

Swift Concurrency with `TaskGroup` is the right model:

```swift
actor BackupEngine {
    func runJob(_ job: BackupJob) async {
        await withTaskGroup(of: DestinationResult.self) { group in
            for destination in job.destinations {
                group.addTask {
                    await destination.worker.transfer(job.files, version: job.version)
                }
            }
            for await result in group {
                // update AppState with per-destination progress
            }
        }
    }
}
```

Key properties:
- Transfers to all destinations run concurrently
- Each worker owns its concurrency internally (e.g., chunked upload with URLSession)
- Cancellation propagates: if the user quits or requests cancel, `Task.cancel()` propagates to all workers
- No destination's failure blocks others
- The engine actor serializes job management; it won't start a new job for the same project until the current one finishes (or implement a job queue)

---

## Suggested Build Order

The components have clear dependency relationships. Build in this order:

### Phase 1 — Foundation (no UI, testable in isolation)
1. **Persistence Layer** (GRDB schema: Projects, BackupVersions, Destinations)
2. **Project Resolver / File Collector** (walk a folder, return file list)
3. **Version Manager** (assign version IDs, prune logic)

These have no external dependencies; they can be built and tested with unit tests immediately.

### Phase 2 — First Transfer
4. **Local Disk Worker** (copy files to a local destination path)
5. **Backup Engine** (orchestrate: resolve → version → transfer → persist)

At this point you have a working backup system for local destinations. No UI, trigger via unit test or a simple command-line target.

### Phase 3 — App Shell + Basic UI
6. **App Shell** (LSUIElement, NSStatusItem, basic menu: Backup Now, Quit)
7. **AppState** observable object
8. **File Watcher** (FSEvents, debounce, trigger engine)
9. **Backup Scheduler** (timer-based triggers)
10. **Notification Center integration**

Now the app runs, watches files, backs up to local disk, shows status in the menu bar. This is a functional v0.

### Phase 4 — Settings Window
11. **Settings Window** (SwiftUI: watch folders, local destination configuration)
12. **Version History + Restore UI**

### Phase 5 — Network Destinations
13. **NAS / SMB Worker** (NetFS mount + FileManager copy)
14. **iCloud Drive Worker** (FileManager to ubiquity container)
15. **Google Drive Worker** (OAuth + REST chunked uploads)
16. **Dropbox Worker** (OAuth + REST chunked uploads)
17. **GitHub / Git LFS Worker** (Process → git commands)

Each network destination is independently addable; they share the Transfer Worker protocol.

### Dependency Graph

```
Persistence ──────────────────────────────────┐
Project Resolver ─────────────────────────────┤
Version Manager (depends on Persistence) ─────┤
                                              ▼
Local Disk Worker ──────────────────────▶ Backup Engine ──▶ App Shell
                                              ▲               │
NAS Worker ───────────────────────────────────┤           File Watcher
Cloud Workers (Google, Dropbox, iCloud) ──────┤           Scheduler
GitHub Worker ────────────────────────────────┘           Notifications
                                                              │
                                                         Settings Window
                                                         Version History UI
```

---

## Key Architectural Decisions and Rationale

| Decision | Rationale |
|----------|-----------|
| LSUIElement (agent app) | Standard macOS pattern for background utilities; no Dock icon; matches user expectation for a backup tool |
| Swift Concurrency (actors + TaskGroup) | Native to modern Swift; structured cancellation; avoids callback hell for multi-destination fan-out |
| FSEvents for file watching | Kernel-level, coalesced, efficient for directory trees; correct tool for Ableton project folder monitoring |
| GRDB.swift for persistence | Type-safe SQLite; no ORM overhead; simple schema; easy to query version history |
| Per-destination worker protocol | Clean extension point — adding a new destination (Box, OneDrive) requires only a new conforming type |
| Credentials in Keychain | Security requirement; never store tokens/passwords in UserDefaults or SQLite |
| APFS cloning for local copies | `copyfile()` with `COPYFILE_CLONE` makes local copies near-instantaneous and space-efficient on APFS |
| TaskGroup for concurrent transfers | All destinations transfer in parallel; one slow destination doesn't block others |
| Actor for BackupEngine | Serializes job management without manual locking; safe to call from any async context |

---

## What Talks to What (Component Boundaries)

| Component | Inputs | Outputs | Must Not |
|-----------|--------|---------|----------|
| File Watcher | FSEvent callbacks | "Project changed" events to Backup Engine | Trigger transfers directly |
| Backup Scheduler | System timer | "Run scheduled backup" signal to Backup Engine | Know about destinations |
| Backup Engine | Trigger events | Coordinates all sub-components; writes AppState | Block the main thread |
| Project Resolver | Project folder path | List of files to back up | Make network calls |
| Version Manager | Backup results | Version records in DB; prune old versions | Know about UI |
| Destination Workers | File list + destination config | Transfer result (success/failure/progress) | Know about other destinations |
| Persistence Layer | CRUD requests | Stored config + history | Hold in-memory state |
| AppState | Updates from Backup Engine | Observable state for UI | Initiate backups |
| Settings Window | User input | Configuration changes to Persistence | Talk to Backup Engine directly |
| Notification Center | Backup results | macOS notifications | Know about file system details |

---

## Open Questions / Build-Time Decisions

1. **Sandboxing**: Will the app be sandboxed (Mac App Store distribution) or not? Sandbox complicates FSEvents (needs security-scoped bookmarks), file access, and NetFS. If distributing outside the App Store, avoiding the sandbox significantly simplifies file watcher and NAS integration.

2. **Git LFS dependency**: The GitHub destination requires `git` and `git-lfs` installed on the user's machine. Should the app bundle its own `git` binary, or document this as a prerequisite? Bundling is more reliable but increases app size; detecting and prompting for install is simpler.

3. **External sample collection**: Should the app warn users about externally-referenced samples (those not in the project folder)? Parsing `.als` (zlib-compressed XML) is not complex, but adds scope.

4. **Concurrent job limit**: If the user has many watch folders, multiple projects could change near-simultaneously. Define: run all concurrently, or serialize to a job queue?

5. **SQLite vs. Core Data**: GRDB is lighter and more explicit; Core Data has better macOS integration for sync and migrations. GRDB is recommended for this use case.

---

*Research synthesized from macOS development documentation, Swift Concurrency patterns, FSEvents API, and standard macOS utility app architecture as of 2026-02.*
