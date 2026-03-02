# Phase 3: Settings + History - Research

**Researched:** 2026-03-02
**Domain:** SwiftUI Settings scene, macOS tabbed preferences, NSOpenPanel, GRDB observation, two-panel NavigationSplitView, watch folder lifecycle management
**Confidence:** HIGH (most findings cross-verified against official docs, existing project code, and Phase 2 research)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Settings window structure**
- Use SwiftUI `Settings` scene — renders as native macOS tabbed inspector window
- Five tabs: **General / Watch Folders / Destinations / History / About**
- General pane contains: auto-backup toggle (save-triggered, no timer), version retention setting, Launch at Login toggle
- Backup schedule is save-triggered only — no time-based scheduler in this phase

**Watch folder management**
- Watch Folders pane: list with **+/− buttons below** (macOS standard pattern)
- Each row shows: folder name + full path + last triggered time (e.g. "MyProject — ~/Music/Ableton — Last backup: 2 hours ago")
- Adding a folder: pressing + opens macOS NSOpenPanel (standard folder picker sheet)
- Version history is NOT accessible from this pane — it lives in the dedicated History tab

**Version history browser**
- History tab (5th tab in Settings)
- **Two-panel layout**: project list on the left, version list on the right
- Each version row shows: timestamp + destination icons + verification status (e.g. "Mar 2, 2:14 PM — 💾 Local ✓ — Verified")
- Version rows satisfy the roadmap requirement to show which destinations each version exists on
- **Read-only** — no restore, no delete actions in this phase

**Destructive action safety**
- **Remove watch folder**: confirmation sheet ("Stop watching 'X'? Existing backups are not affected.") → stops future monitoring, no backup data deleted
- **Reduce retention number**: silent change, pruning happens on next backup run (same as normal retention behavior, no immediate deletion dialog)
- **Remove destination**: confirmation sheet warns "X versions only exist on this destination and will become inaccessible" before proceeding

### Claude's Discretion
- Exact icon choices for destination indicators in history rows
- Spacing, typography, and visual polish within each pane
- Error state handling (e.g. watch folder path no longer accessible)
- About pane content and layout

### Deferred Ideas (OUT OF SCOPE)
- None — discussion stayed within phase scope
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| APP-04 | Settings window covers all configuration (destinations, schedule, retention, watch folders) | SwiftUI `Settings` scene with 5-tab `TabView` — confirmed pattern for macOS tabbed settings windows; `SettingsLink` in MenuBarView opens it |
| DISC-02 | User can add additional watch folders manually via settings | NSOpenPanel with `canChooseDirectories = true` called from Watch Folders pane + button; requires new `WatchFolder` DB table and new FSEventsWatcher per folder |
| DISC-03 | User can remove watch folders from settings | `-` button with `.confirmationDialog` sheet triggers DB delete and stops the corresponding FSEventsWatcher instance |
| HIST-01 | User can view version history per project in the settings window | History tab with `NavigationSplitView` — project list (left) drives version list (right); GRDB `ValueObservation` with async sequence keeps list live |
| HIST-02 | Version history shows timestamp and which destinations each version exists on | `BackupVersion` already has `destinationID`; group versions by timestamp prefix (same millisecond ID prefix = same logical backup) to show all destinations per backup event; `DestinationConfig` provides name/type for icon display |
</phase_requirements>

---

## Summary

Phase 3 builds the Settings window and version history browser. The core challenge is that this project is an LSUIElement app (no Dock icon), and macOS has a known limitation where SwiftUI's `openSettings()` environment action and `SettingsLink` do not reliably open the Settings scene from a `MenuBarExtra` `.menu`-style context. The working solution is to add a `SettingsLink` button in `MenuBarView` with the `NSApp.activate(ignoringOtherApps: true)` trick to bring the settings window forward. Alternatively, the `SettingsAccess` library (v2.1.0, MIT, no private API) provides a battle-tested solution.

The Watch Folders pane requires two new elements: a `WatchFolder` table in the GRDB schema (a new migration), and multi-watcher support in `BackupCoordinator` — replacing the single `watcher: FSEventsWatcher?` with a dictionary of `[String: FSEventsWatcher]` keyed by folder path. `NSOpenPanel` remains AppKit-only; calling it from SwiftUI requires a helper function that calls `runModal()` synchronously on the main thread or wraps it in `Task { @MainActor in }`.

The History tab uses a two-panel `NavigationSplitView` with GRDB `ValueObservation` providing live-updating lists. Since `BackupVersion` records have one row per project+destination pair per backup run, the history browser must group or join across destinations to show a unified timeline. The `destinationID` on each version allows displaying destination indicators per backup event.

**Primary recommendation:** Add the `Settings` scene to `AbletonBackupApp.swift` alongside `MenuBarExtra`, use `SettingsLink` in `MenuBarView` to open it, add a `watchFolder` GRDB migration, wire multi-watcher support in `BackupCoordinator`, and use `ValueObservation` with `.task` modifier to drive the History tab.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftUI `Settings` scene | Built-in (macOS 13+) | Renders native tabbed settings window with Cmd+, support | The only correct SwiftUI API for a macOS settings window; automatically adds Settings to the app menu |
| SwiftUI `TabView` | Built-in | Tab navigation inside the Settings scene | Standard macOS tabbed inspector; labels + SF Symbols produce platform-native appearance |
| SwiftUI `NavigationSplitView` | Built-in (macOS 13+) | Two-panel project/version history layout in History tab | Native macOS two-column layout; integrates translucent sidebar with detail pane automatically |
| AppKit `NSOpenPanel` | Built-in | macOS folder picker dialog for adding watch folders | No native SwiftUI folder picker; NSOpenPanel is the correct AppKit API |
| SwiftUI `.confirmationDialog` | Built-in (macOS 12+) | Confirmation sheets for destructive actions | Platform-native presentation; not a custom alert — proper macOS confirmation pattern |
| GRDB `ValueObservation` | 7.x (already in stack) | Live DB query observation for project and version lists | Already in the dependency graph; async sequence integration with `.task` modifier is idiomatic GRDB 7 |
| `BackupEngine` (local) | Phase 1 | Persistence models and schema | Already built; add WatchFolder model and migration here |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| SettingsAccess | 2.1.0 | Opens Settings scene from menu bar button reliably | Use if `SettingsLink` proves unreliable in this LSUIElement context (known issue documented in Phase 2 research) |
| SwiftUI `SettingsLink` | Built-in (macOS 14+) | Button that opens the Settings scene | Try first — works on macOS 14/15; fall back to NSApp.sendAction selector approach if needed |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| SwiftUI `Settings` scene + `TabView` | `NSPreferencePanesContainerView` (AppKit) | Full AppKit far more boilerplate; Settings scene + TabView is idiomatic SwiftUI |
| `SettingsLink` | `NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)` | Selector approach works on macOS 13/14/15 as a reliable fallback; no private API but brittle string-based selector |
| `NSOpenPanel.runModal()` | SwiftUI `.fileImporter` modifier | `.fileImporter` is file-oriented; `.canChooseDirectories = true` is also available on fileImporter but NSOpenPanel gives more control over prompt text |
| GRDB `ValueObservation` | Re-fetching on `.onAppear` | Polling on appear misses live changes (another backup runs while Settings is open); ValueObservation provides true reactivity |

**Installation:**

No new packages needed — all APIs are built-in or already in the dependency graph. If using SettingsAccess as fallback:

```bash
# In Xcode: File > Add Package Dependencies
# URL: https://github.com/orchetect/SettingsAccess
# Version: from: "2.1.0"
```

---

## Architecture Patterns

### Recommended Project Structure

Phase 3 adds to the existing `AbletonBackup/` app target folder:

```
AbletonBackup/
├── AbletonBackupApp.swift        # ADD: Settings scene alongside MenuBarExtra
├── BackupCoordinator.swift       # MODIFY: multi-watcher support, watchFolders from DB
├── Views/
│   ├── MenuBarView.swift         # MODIFY: add SettingsLink button
│   └── Settings/                 # NEW: settings view hierarchy
│       ├── SettingsView.swift    # TabView root: General/WatchFolders/Destinations/History/About
│       ├── GeneralSettingsView.swift
│       ├── WatchFoldersSettingsView.swift
│       ├── DestinationsSettingsView.swift
│       ├── HistoryView.swift     # NavigationSplitView with project + version lists
│       └── AboutView.swift
Sources/BackupEngine/
├── Persistence/
│   ├── Schema.swift              # ADD: v2_watch_folders migration
│   └── Models/
│       └── WatchFolder.swift     # NEW: WatchFolder GRDB model
```

### Pattern 1: Settings Scene Declaration in App Body

**What:** Add the `Settings` scene alongside `MenuBarExtra` in `AbletonBackupApp.swift`. SwiftUI automatically enables Cmd+, and the "Settings…" app menu item. The `Settings` scene is a separate scene; it does not interfere with `MenuBarExtra`.

**When to use:** Any macOS SwiftUI app needing a settings window.

```swift
// AbletonBackupApp.swift
// Source: serialcoder.dev macOS Settings tutorial (verified 2025)

@main
struct AbletonBackupApp: App {
    @State private var coordinator = BackupCoordinator()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(coordinator)
                .task {
                    NotificationService.setup()
                }
        } label: {
            Label("AbletonBackup", systemImage: coordinator.statusIcon)
        }
        .menuBarExtraStyle(.menu)

        // Settings scene — renders native tabbed settings window
        // Cmd+, opens it; app menu "Settings…" item is auto-added
        Settings {
            SettingsView()
                .environment(coordinator)
        }
    }
}
```

### Pattern 2: Opening Settings from MenuBarView (LSUIElement Workaround)

**What:** LSUIElement apps cannot reliably use `@Environment(\.openSettings)` from within a `.menu`-style `MenuBarExtra`. The working approach is `SettingsLink` on macOS 14+, with an `NSApp.sendAction` fallback. The app must also call `NSApp.activate(ignoringOtherApps: true)` to bring the window to the front.

**When to use:** In `MenuBarView` wherever a "Settings…" button is shown.

**Priority approach — SettingsLink (macOS 14+):**

```swift
// MenuBarView.swift — settings section
// Source: rampatra.com + steipete.me 2025 investigation (MEDIUM confidence)

// macOS 14+ — SettingsLink is the documented approach
SettingsLink {
    Text("Settings…")
}
.keyboardShortcut(",")
```

**Fallback for macOS 13 (NSApp.sendAction with selector):**

```swift
// Fallback for macOS 13 or if SettingsLink fails in LSUIElement context
Button("Settings…") {
    NSApp.activate(ignoringOtherApps: true)
    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
}
.keyboardShortcut(",")
```

**If both fail (SettingsAccess library):**

```swift
// SettingsAccess v2.1.0 — use openSettingsLegacy()
// .openSettingsAccess() modifier added to a view in the hierarchy
@Environment(\.openSettingsLegacy) private var openSettings

Button("Settings…") {
    openSettings()
}
```

### Pattern 3: Settings TabView Structure

**What:** A `TabView` inside the `Settings` scene produces native macOS tabbed inspector tabs. Each tab uses a `Label` with an SF Symbol for the icon. The outer `frame` controls the minimum settings window size.

**When to use:** Any multi-section macOS settings window.

```swift
// SettingsView.swift
// Source: serialcoder.dev Settings tutorial (verified)

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(0)

            WatchFoldersSettingsView()
                .tabItem {
                    Label("Watch Folders", systemImage: "folder.badge.questionmark")
                }
                .tag(1)

            DestinationsSettingsView()
                .tabItem {
                    Label("Destinations", systemImage: "externaldrive")
                }
                .tag(2)

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .tag(3)

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(4)
        }
        .frame(minWidth: 500, minHeight: 360)
    }
}
```

### Pattern 4: Watch Folders Pane — List with +/− Buttons

**What:** A `List` showing watch folder rows, with `+` and `-` buttons below (macOS standard toolbar pattern). The `+` button calls `NSOpenPanel`, the `-` removes the selected row after a confirmation dialog.

**When to use:** Any list-with-add/remove in macOS settings panes.

```swift
// WatchFoldersSettingsView.swift
// Source: NSOpenPanel Apple docs + SwiftUI confirmationDialog docs

struct WatchFoldersSettingsView: View {
    @Environment(BackupCoordinator.self) private var coordinator
    @State private var selectedFolder: WatchFolder?
    @State private var showRemoveConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            List(coordinator.watchFolders, selection: $selectedFolder) { folder in
                WatchFolderRow(folder: folder)
            }

            Divider()

            // + / - toolbar below list (macOS standard)
            HStack(spacing: 0) {
                Button {
                    addWatchFolder()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)

                Button {
                    showRemoveConfirmation = true
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .disabled(selectedFolder == nil)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .confirmationDialog(
            "Stop watching '\(selectedFolder?.name ?? "")'?",
            isPresented: $showRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Stop Watching", role: .destructive) {
                if let folder = selectedFolder {
                    Task { await coordinator.removeWatchFolder(folder) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Existing backups are not affected.")
        }
    }

    private func addWatchFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Watch Folder"
        panel.message = "Select a folder to watch for Ableton project saves"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await coordinator.addWatchFolder(url: url) }
    }
}
```

**NSOpenPanel Swift 6 note:** `NSOpenPanel.runModal()` must be called on the main thread. Since `WatchFoldersSettingsView` is a `@MainActor`-isolated `View`, calling it from a button action (which runs on main actor) is safe. No `@MainActor` annotation is needed on the helper function when called from a button action in a SwiftUI view.

### Pattern 5: WatchFolder Model and GRDB Migration

**What:** A new `WatchFolder` struct conforming to GRDB persistence protocols, plus a `v2_watch_folders` migration in `Schema.swift`. The model stores the folder path, display name, and optional last-triggered timestamp.

**When to use:** Every time a user adds a watch folder; replaces the hardcoded `bootstrapProjectID`/`watchedProjectsFolder` in BackupCoordinator.

```swift
// Sources/BackupEngine/Persistence/Models/WatchFolder.swift

import GRDB
import Foundation

public struct WatchFolder: Codable, Sendable, Identifiable {
    public var id: String           // UUID string
    public var path: String         // UNIQUE — absolute path
    public var name: String         // Display name (folder.lastPathComponent)
    public var addedAt: Date
    public var lastTriggeredAt: Date?

    public init(id: String = UUID().uuidString, path: String, name: String,
                addedAt: Date = Date(), lastTriggeredAt: Date? = nil) {
        self.id = id
        self.path = path
        self.name = name
        self.addedAt = addedAt
        self.lastTriggeredAt = lastTriggeredAt
    }
}

extension WatchFolder: TableRecord {
    public static let databaseTableName = "watchFolder"
}
extension WatchFolder: FetchableRecord {}
extension WatchFolder: PersistableRecord {}
```

**Migration to add to Schema.swift:**

```swift
// Sources/BackupEngine/Persistence/Schema.swift
// Source: GRDB DatabaseMigrator docs

migrator.registerMigration("v2_watch_folders") { db in
    try db.create(table: "watchFolder") { t in
        t.primaryKey("id", .text)
        t.column("path", .text).notNull().unique()     // UNIQUE — one record per folder path
        t.column("name", .text).notNull()
        t.column("addedAt", .datetime).notNull()
        t.column("lastTriggeredAt", .datetime)          // nullable — updated on each trigger
    }
}
```

**Bootstrap migration note:** Phase 2's `BackupCoordinator` hardcodes `watchedProjectsFolder` from `AbletonPrefsReader`. Phase 3's first setup task must migrate the discovered folder into the `watchFolder` table if none exist.

### Pattern 6: Multi-Watcher BackupCoordinator

**What:** Replace the single `watcher: FSEventsWatcher?` with a dictionary `[String: FSEventsWatcher]` keyed by folder path. Each watch folder gets its own `FSEventsWatcher` instance. Adding a folder creates a new watcher; removing a folder stops and removes the entry.

**When to use:** Multi-folder watch support required by DISC-02/DISC-03.

```swift
// BackupCoordinator.swift — modified watcher management

// BEFORE (Phase 2):
private var watcher: FSEventsWatcher?

// AFTER (Phase 3):
private var watchers: [String: FSEventsWatcher] = [:]  // keyed by folder path

func addWatchFolder(url: URL) async {
    // 1. Insert WatchFolder into DB
    let folder = WatchFolder(path: url.path, name: url.lastPathComponent)
    try? await db?.pool.write { db in try folder.save(db) }

    // 2. Start FSEventsWatcher for this folder
    let w = FSEventsWatcher(url: url) { [weak self] path in
        Task { @MainActor [weak self] in
            await self?.handleALSChange(at: path)
        }
    }
    watchers[url.path] = w
    watchFolders.append(folder)  // drives UI
}

func removeWatchFolder(_ folder: WatchFolder) async {
    // 1. Stop and remove the watcher
    watchers.removeValue(forKey: folder.path)

    // 2. Delete from DB
    try? await db?.pool.write { db in
        try WatchFolder.deleteOne(db, key: folder.id)
    }

    // 3. Update observable state
    watchFolders.removeAll { $0.id == folder.id }
}
```

### Pattern 7: History Tab — NavigationSplitView with GRDB Observation

**What:** Two-panel layout: left side shows all backed-up projects, right side shows version history for the selected project. Both lists are live-updated via GRDB `ValueObservation` started in `.task` modifiers.

**Version grouping for HIST-02:** Since `BackupVersion` has one row per project+destination per backup run, and the version ID format is `"yyyy-MM-dd'T'HHmmss.SSS-xxxxxxxx"` (millisecond timestamp + UUID suffix), versions from the same backup run share the same timestamp prefix. Group them by truncating the ID to the timestamp portion to produce "backup events" that show all destinations.

**When to use:** History tab view.

```swift
// HistoryView.swift
// Source: GRDB ValueObservation docs + NavigationSplitView Apple docs

struct HistoryView: View {
    @Environment(BackupCoordinator.self) private var coordinator
    @State private var projects: [Project] = []
    @State private var selectedProject: Project?
    @State private var versions: [BackupVersion] = []

    var body: some View {
        NavigationSplitView {
            List(projects, id: \.id, selection: $selectedProject) { project in
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name).fontWeight(.medium)
                    if let lastAt = project.lastBackupAt {
                        Text(lastAt.formatted(.relative(presentation: .named)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Projects")
        } detail: {
            if let project = selectedProject {
                VersionListView(project: project)
            } else {
                Text("Select a project to view its backup history")
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            // Observe all projects with at least one completed backup
            guard let db = coordinator.database else { return }
            let observation = ValueObservation.tracking { db in
                try Project
                    .filter(Column("lastBackupAt") != nil)
                    .order(Column("name").asc)
                    .fetchAll(db)
            }
            for try await fresh in observation.values(in: db.pool) {
                projects = fresh
            }
        }
    }
}
```

**ValueObservation async sequence pattern (GRDB 7):**

```swift
// Source: GRDB 7 README + migration guide (verified February 2026 release)

// In a .task modifier — automatically cancelled when view disappears
.task {
    let observation = ValueObservation.tracking { db in
        try BackupVersion
            .filter(Column("projectID") == projectID)
            .order(Column("createdAt").desc)
            .fetchAll(db)
    }
    // GRDB 7: values(in:) iterates on cooperative thread pool by default
    // Start on main actor for direct state assignment
    for try await fresh in observation.values(in: db.pool, scheduling: .mainActor) {
        self.versions = fresh
    }
}
```

### Anti-Patterns to Avoid

- **Calling NSOpenPanel from a non-main-thread context:** `runModal()` must be on the main thread. Do not call from a background Task.
- **Grouping versions by createdAt Date equality:** Dates from separate backup runs are never identical — group by the timestamp prefix of the version ID string (first 23 chars: `yyyy-MM-dd'T'HHmmss.SSS`). Two versions with matching ID prefixes came from the same BackupEngine job run.
- **Replacing the entire `watchers` dictionary on each settings change:** When adding a folder, only add the new entry; when removing, only remove the matching entry. Never re-create all watchers on every change — FSEvents streams start from `kFSEventStreamEventIdSinceNow` on creation, so rebuilding would drop events.
- **Caching watch folder paths in UserDefaults:** The source of truth is the GRDB `watchFolder` table. UserDefaults would desync if DB is modified outside the app. Always read from GRDB on startup.
- **Not bootstrapping the auto-discovered Ableton folder into the DB:** Phase 3 must migrate `AbletonPrefsReader.discoverProjectsFolder()` result into the `watchFolder` table on first launch, or Settings will show an empty list.
- **Using `openSettings()` environment action from inside the `.menu` MenuBarExtra:** This silently fails in LSUIElement apps. Use `SettingsLink` or the `NSApp.sendAction` fallback.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Folder picker dialog | Custom window or drag-and-drop target | `NSOpenPanel` with `canChooseDirectories = true` | NSOpenPanel handles permissions, bookmarks, and platform-standard UX; custom picker misses security-scoped bookmarks |
| Settings window | Custom `NSWindow` or `WindowGroup` | SwiftUI `Settings` scene | Settings scene auto-adds "Settings…" to app menu, handles Cmd+,, correct macOS window behavior |
| Confirmation dialog for destructive actions | Custom `Alert` with buttons | SwiftUI `.confirmationDialog` | macOS-native presentation; correct for macOS destructive action pattern |
| Live-updating lists | Manual `.onAppear` re-fetch | GRDB `ValueObservation` with async sequence | ValueObservation tracks exact table columns accessed; only re-fires when relevant data changes |
| Version grouping across destinations | Complex ID-based join | Query all BackupVersions for project ordered by createdAt DESC, then group in Swift by ID timestamp prefix | The ID format (`"yyyy-MM-dd'T'HHmmss.SSS-..."`) makes same-run versions trivially groupable in O(n) |

**Key insight:** `NSOpenPanel`, `Settings` scene, and `.confirmationDialog` are standard AppKit/SwiftUI primitives that handle a large surface area of platform behavior (sandboxing, focus management, animation, accessibility). Hand-rolling any of these would regress platform conformance.

---

## Common Pitfalls

### Pitfall 1: SettingsLink Does Not Open the Window in LSUIElement Apps

**What goes wrong:** Adding `SettingsLink { Text("Settings…") }` to `MenuBarView` — the user clicks it, nothing happens (or the window appears behind other windows).

**Why it happens:** `MenuBarExtra(.menu)` apps with `LSUIElement = YES` have activation policy `.accessory`. macOS won't bring new windows to the front without activation policy `.regular`. `SettingsLink` calls `openSettings()` environment action internally, which requires a functioning SwiftUI render tree with window context.

**How to avoid:** After `SettingsLink`, call `NSApp.activate(ignoringOtherApps: true)` or use the `NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)` approach. The steipete.me 2025 investigation confirmed that temporarily switching activation policy + calling `NSApp.activate` is the reliable solution. If simpler: add `SettingsAccess` library.

**Warning signs:** Clicking "Settings…" in the menu does nothing, or the window appears but is behind Finder.

### Pitfall 2: Watch Folder Bootstrap — Empty Folder List on First Launch

**What goes wrong:** Phase 3 opens the Settings window and the Watch Folders pane is empty, even though `AbletonPrefsReader` found the Ableton Projects folder in Phase 2.

**Why it happens:** Phase 2's `BackupCoordinator.setup()` stores the discovered folder in `watchedProjectsFolder: URL?` (in-memory only) and never writes it to the `watchFolder` table (which doesn't exist until Phase 3 adds it). Phase 3 reads from the new table, finds nothing, and shows an empty list.

**How to avoid:** In Phase 3's new `BackupCoordinator.setup()` flow, after running migrations (which creates the `watchFolder` table), check if the table is empty. If empty, call `AbletonPrefsReader.discoverProjectsFolder()` and insert the result as the first `WatchFolder` row.

**Warning signs:** Settings → Watch Folders pane shows empty list despite the app having been backing up successfully.

### Pitfall 3: Version History HIST-02 Requires Per-Destination Grouping

**What goes wrong:** The History tab shows duplicate entries for the same backup event — one row per destination instead of one row showing all destinations.

**Why it happens:** `BackupVersion` has one DB row per (projectID, destinationID) pair per backup run. Displaying raw rows gives N rows for N destinations. HIST-02 requires showing "which destinations each version exists on" — meaning one logical version row with destination indicators, not N separate rows.

**How to avoid:** Query all `BackupVersion` rows for the selected project, ordered by `createdAt DESC`. In Swift, group them by the first 23 characters of their `id` (the timestamp portion: `"2026-03-02T143022.456"`). All versions with the same timestamp prefix belong to the same backup run. Display one row per group, with destination icons from all versions in the group.

```swift
// Group BackupVersion rows by backup run
struct BackupEvent: Identifiable {
    var id: String           // timestamp prefix from version ID
    var timestamp: Date      // createdAt of first version in group
    var destinations: [BackupVersion]  // one entry per destination
    var overallStatus: VersionStatus   // worst status across destinations
}

func groupVersions(_ versions: [BackupVersion]) -> [BackupEvent] {
    let grouped = Dictionary(grouping: versions) { v in
        String(v.id.prefix(23))  // "yyyy-MM-dd'T'HHmmss.SSS"
    }
    return grouped.map { (prefix, group) in
        BackupEvent(
            id: prefix,
            timestamp: group.first!.createdAt,
            destinations: group,
            overallStatus: group.contains { $0.status == .corrupt } ? .corrupt : .verified
        )
    }.sorted { $0.timestamp > $1.timestamp }
}
```

**Warning signs:** History shows 2x as many rows as expected when two destinations are configured.

### Pitfall 4: NSOpenPanel.runModal() Blocks the Main Thread

**What goes wrong:** The `+` button for adding a watch folder triggers `NSOpenPanel.runModal()`, which blocks the main thread. While this is correct behavior for a synchronous modal, calling it inside an async `Task` on the wrong actor causes Swift 6 concurrency warnings or deadlocks.

**Why it happens:** `NSOpenPanel.runModal()` is a synchronous blocking call. It must run on the main thread (AppKit requirement) but cannot be called from a background Task.

**How to avoid:** Call `NSOpenPanel.runModal()` directly in the `Button` action — SwiftUI button actions run on the main thread. Do NOT wrap it in `Task { ... }`. Only the subsequent GRDB write and coordinator update should be wrapped in `Task { @MainActor in ... }`.

```swift
// CORRECT: runModal() called synchronously on main thread
Button("+") {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    // Only the async part goes in a Task
    Task { await coordinator.addWatchFolder(url: url) }
}
```

**Warning signs:** Swift 6 error "Expression is 'async' but is not marked with 'await'" or runtime hang when opening the panel.

### Pitfall 5: Multiple FSEventsWatcher Instances Each Hold Retained Self Reference

**What goes wrong:** `FSEventsWatcher.init` calls `Unmanaged.passRetained(self)` to hold a reference through the C callback. If multiple `FSEventsWatcher` instances are created and none are properly released, memory leaks accumulate — one leak per added watch folder.

**Why it happens:** The existing `FSEventsWatcher` uses `passRetained` in `init` and `passUnretained(self).release()` in `deinit` to balance the retain. If the watcher is removed from the `watchers` dictionary but the `FSEventStreamRef` is not stopped and invalidated first (or if deinit doesn't run), the memory is not released.

**How to avoid:** The existing `FSEventsWatcher.deinit` correctly calls `FSEventStreamStop`, `FSEventStreamInvalidate`, `FSEventStreamRelease`, and `Unmanaged.passUnretained(self).release()`. As long as the `watchers[path] = nil` assignment triggers `deinit` (i.e., no other strong references exist), cleanup is correct. Verify by checking that the `watchers` dictionary is the only owner.

**Warning signs:** Memory usage grows with each watch folder add/remove cycle; Console shows no "FSEventsWatcher: stopped" log entries after removal.

### Pitfall 6: Retention Count Changes Require No Immediate DB Action

**What goes wrong:** Implementer adds immediate pruning when the user reduces the retention count in General settings — calling `VersionManager.pruneOldVersions()` synchronously on the save.

**Why it happens:** Intuition says "fewer retained versions → prune now."

**How to avoid:** Per the locked decision: "Reduce retention number: silent change, pruning happens on next backup run." Simply save the new `retentionCount` to the `DestinationConfig` in GRDB. The next `BackupEngine.runJob()` call will read the updated count and prune accordingly. No immediate pruning call needed.

**Warning signs:** Pruning is triggered in the settings save path rather than in `BackupEngine.runJob()`.

---

## Code Examples

Verified patterns from official sources and existing project code:

### GRDB Migration Pattern (existing codebase pattern)

```swift
// Sources/BackupEngine/Persistence/Schema.swift
// Source: existing Schema.swift in project (Phase 1)

public static func registerMigrations(in migrator: inout DatabaseMigrator) {
    migrator.registerMigration("v1_initial") { db in
        // ... existing tables ...
    }

    // Phase 3: add watch folder tracking
    migrator.registerMigration("v2_watch_folders") { db in
        try db.create(table: "watchFolder") { t in
            t.primaryKey("id", .text)
            t.column("path", .text).notNull().unique()
            t.column("name", .text).notNull()
            t.column("addedAt", .datetime).notNull()
            t.column("lastTriggeredAt", .datetime)
        }
    }
}
```

### GRDB ValueObservation with Async Sequence in .task Modifier

```swift
// Source: GRDB 7 README (verified — version 7.10.0, released 2026-02-15)

.task {
    let observation = ValueObservation.tracking { db in
        try WatchFolder.order(Column("addedAt").asc).fetchAll(db)
    }
    // scheduling: .mainActor ensures state assignment is on main actor (GRDB 7)
    do {
        for try await folders in observation.values(in: db.pool, scheduling: .mainActor) {
            self.watchFolders = folders
        }
    } catch {
        // observation ended — view disappeared, task cancelled, or DB error
    }
}
```

### NSOpenPanel Folder Picker (AppKit, main thread)

```swift
// Source: Apple NSOpenPanel documentation + serialcoder.dev macOS tutorial

// Must be called on main thread — safe in SwiftUI Button action
private func selectFolder() -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = false
    panel.prompt = "Watch Folder"
    panel.message = "Select a folder to watch for Ableton project saves"
    return panel.runModal() == .OK ? panel.url : nil
}
```

### Confirmation Dialog for Destructive Remove

```swift
// Source: Apple SwiftUI .confirmationDialog documentation

.confirmationDialog(
    "Stop watching '\(selectedFolder?.name ?? "")'?",
    isPresented: $showConfirmation,
    titleVisibility: .visible
) {
    Button("Stop Watching", role: .destructive) {
        Task { await coordinator.removeWatchFolder(folder) }
    }
    Button("Cancel", role: .cancel) {}
} message: {
    Text("Existing backups are not affected.")
}
```

### BackupVersion ID Timestamp Prefix for Grouping

```swift
// Source: BackupVersion.makeID() in existing codebase (Phase 1)
// ID format: "2026-02-25T143022.456-a3f8b12c"
// Timestamp prefix = first 23 chars: "2026-02-25T143022.456"

let timestampPrefix = String(version.id.prefix(23))
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| NSPreferencePane (AppKit) | SwiftUI `Settings` scene with `TabView` | macOS 13 / WWDC21 | Native SwiftUI, no AppKit subclassing needed |
| Manual UserDefaults for settings | GRDB-backed settings models | Phase 1 established GRDB as stack | Consistent persistence layer; observable via ValueObservation |
| NSFilePresenter + NSFileSecurity for sandboxed file access | NSOpenPanel (non-sandboxed) | N/A | This project distributes outside App Store (non-sandboxed); NSOpenPanel works without security-scoped bookmark dance |
| Fetching on `.onAppear` | GRDB `ValueObservation` with async sequence | GRDB 7 + Swift 6 | True reactivity; no stale data when Settings is open during an active backup |
| `@ObservableObject` + `@Published` | `@Observable` + `@MainActor` | macOS 14 / WWDC23 | Project already uses this pattern (BackupCoordinator); Settings views inherit same approach |

**Deprecated/outdated:**
- `NSPreferencePane` + preference pane bundles: obsolete; SwiftUI `Settings` scene is the replacement
- `NSUserDefaults` for structured settings: functional, but GRDB is already the persistence layer — prefer GRDB for anything with relational structure (watch folders, destinations)

---

## Open Questions

1. **Does SettingsLink work reliably in this app's LSUIElement + MenuBarExtra(.menu) context?**
   - What we know: `SettingsLink` works on macOS 14/15 in most contexts; steipete.me 2025 confirms it does NOT work reliably in `.menu` style MenuBarExtra for all users; `NSApp.sendAction` with the `showSettingsWindow:` selector is the reliable fallback
   - What's unclear: Whether this specific app (already built with existing Phase 2 code) will see the failure
   - Recommendation: Implement `SettingsLink` first, test it during the human verification checkpoint (Phase 3 wave), and fall back to `NSApp.sendAction` selector approach if unreliable. Do not add SettingsAccess library dependency unless both fail.

2. **How should the auto-discovered Ableton folder bootstrap into the WatchFolder table?**
   - What we know: Phase 2's `BackupCoordinator.setup()` calls `AbletonPrefsReader.discoverProjectsFolder()` and stores the result in `watchedProjectsFolder: URL?` (in-memory). Phase 3 needs this in the DB.
   - What's unclear: Whether to run the bootstrap in the new `v2_watch_folders` migration (schema layer) or in `BackupCoordinator.setup()` (app layer)
   - Recommendation: Do it in `BackupCoordinator.setup()` after running migrations. Check if `watchFolder` table is empty → if yes, call `AbletonPrefsReader.discoverProjectsFolder()` → insert result. This keeps the schema migration free of app logic.

3. **Should the WatchFolders pane update BackupCoordinator.watchedProjectsFolder or fully replace the Phase 2 single-folder model?**
   - What we know: Phase 2 hardcoded `watchedProjectsFolder: URL?` and `bootstrapProjectID`/`bootstrapDestID` constants. Phase 3 must support multiple folders.
   - What's unclear: Whether to keep the single-folder fast path or fully replace it.
   - Recommendation: Fully replace with the `[String: FSEventsWatcher]` dictionary model. Remove `watchedProjectsFolder` and bootstrap constants. Load all `WatchFolder` rows from DB at startup and start a watcher per row. This is cleaner and avoids two parallel models.

4. **History tab: should corrupt versions be shown with a warning indicator?**
   - What we know: `VersionStatus.corrupt` rows are kept in DB with an `errorMessage`. Per STATE.md: "Corrupt versions kept in DB (status=corrupt), excluded from retention count, never pruned — surface in Phase 3 history UI with warning."
   - What's unclear: Exact UI treatment (color, icon, tooltip).
   - Recommendation: Show corrupt versions with a `⚠` icon and `.red` foreground color. Tooltip/hover shows the `errorMessage`. This was explicitly called out in STATE.md decisions as Phase 3 work.

---

## Sources

### Primary (HIGH confidence)
- Existing project codebase (`/Users/eric/dev/CC`) — `BackupCoordinator.swift`, `FSEventsWatcher.swift`, `Schema.swift`, `BackupVersion.swift`, `VersionStatus.swift` — direct read, authoritative
- Phase 2 RESEARCH.md (`02-RESEARCH.md`) — FSEvents, SMAppService, LSUIElement patterns verified in prior research
- STATE.md decisions — "Corrupt versions surface in Phase 3 history UI with warning" is a documented decision
- Apple NSOpenPanel documentation — NSOpenPanel API, `canChooseDirectories`, `runModal()` behavior
- Apple SwiftUI Settings documentation (via SerialCoder.dev tutorial, verified against Apple docs pattern) — Settings scene declaration, TabView inside Settings

### Secondary (MEDIUM confidence)
- [serialcoder.dev: Presenting the Preferences Window on macOS with SwiftUI](https://serialcoder.dev/text-tutorials/macos-tutorials/presenting-the-preferences-window-on-macos-using-swiftui/) — Settings scene + TabView code pattern verified
- [steipete.me: Showing Settings from macOS Menu Bar Items (2025)](https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items) — LSUIElement activation policy workaround, SettingsLink failure modes
- [rampatra.com: How to open the Settings view in SwiftUI on Sonoma](https://blog.rampatra.com/how-to-open-settings-view-in-swiftui-on-sonoma) — SettingsLink vs NSApp.sendAction selector progression
- GRDB 7 README + migration guide — ValueObservation async sequence, `scheduling: .mainActor` parameter, task cancellation behavior
- [orchetect/SettingsAccess v2.1.0](https://github.com/orchetect/SettingsAccess) — fallback library for opening settings, no private API, MIT license
- [hackingwithswift.com: NavigationSplitView](https://www.hackingwithswift.com/quick-start/swiftui/how-to-create-a-two-column-or-three-column-layout-with-navigationsplitview) — two-column selection binding pattern

### Tertiary (LOW confidence)
- General GRDB observation + SwiftUI integration posts — consistent across 3+ sources; elevated to MEDIUM for core pattern, LOW for specific API variants

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — All libraries are either already in the project or built-in macOS frameworks
- Architecture patterns: HIGH — Settings scene, NSOpenPanel, NavigationSplitView, and GRDB observation patterns all verified against official docs or project codebase
- LSUIElement/SettingsLink pitfall: MEDIUM — documented by one highly credible source (steipete.me 2025) plus corroboration from orchetect/SettingsAccess readme; not personally verified on this machine
- WatchFolder DB migration: HIGH — follows existing project migration pattern exactly
- Version grouping (HIST-02): HIGH — derived from the version ID format already in production (BackupVersion.makeID())

**Research date:** 2026-03-02
**Valid until:** 2026-09-02 (stable APIs; re-verify if macOS 16 changes Settings scene or MenuBarExtra behavior)
