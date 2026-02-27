# Phase 2: App Shell + Triggers - Research

**Researched:** 2026-02-27
**Domain:** macOS menu bar apps, FSEvents file watching, SMAppService login items, UNUserNotificationCenter, SwiftUI+Swift 6 concurrency
**Confidence:** HIGH (most findings verified against SDK headers, official docs, or direct inspection of Ableton files)

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| APP-01 | App runs as a menu bar utility (no Dock icon) | SwiftUI MenuBarExtra + LSUIElement = YES in Info.plist; requires Xcode app target (not SPM-only) |
| APP-02 | Menu bar icon reflects current status (idle / running / error) | MenuBarExtra label accepts dynamic SF Symbols via @Observable state; icon changes driven by BackupCoordinator actor state |
| APP-03 | App can be configured to launch at login | SMAppService.mainApp.register() / unregister() — macOS 13+, no entitlements needed for non-sandboxed app |
| DISC-01 | App auto-detects Ableton's configured Projects folder from Ableton preferences | Library.cfg is UTF-8 XML; parse `<ProjectPath Value="…"/>` inside `<UserLibrary>` — verified on real Ableton 12.2 install. Default: ~/Documents/Ableton/Ableton Projects |
| TRIG-01 | App detects when an Ableton project is saved and triggers backup automatically | FSEvents FileSystemEventStream with kFSEventStreamCreateFlagFileEvents; filter for .als suffix + kFSEventStreamEventFlagItemModified; debounce 2 s before triggering backup |
| TRIG-02 | App runs backups on a user-configured schedule (interval-based) | Swift Task loop with Task.sleep(for:) — no BGProcessingTask needed for non-App-Store app; store interval in UserDefaults or AppSettings table in GRDB |
| TRIG-03 | User can trigger a manual backup from the menu bar | SwiftUI Button in MenuBarExtra menu calls BackupCoordinator.triggerManualBackup() |
| NOTIF-01 | App sends macOS notification on backup completion | UNUserNotificationCenter with requestAuthorization + UNMutableNotificationContent; no sandbox entitlement required |
| NOTIF-02 | App sends macOS notification on backup failure with error detail | Same UNUserNotificationCenter flow; include error.localizedDescription in notification body |
</phase_requirements>

---

## Summary

Phase 2 builds the macOS app shell — a menu bar–only utility (no Dock icon) that runs silently, watches for Ableton saves via FSEvents, fires scheduled and manual backups through the Phase 1 BackupEngine actor, and reports results via macOS notifications.

The most important structural decision for this phase is the **app target type**: the project currently has only a Swift Package. Phase 2 requires adding a proper Xcode app target (`.xcodeproj`) that depends on the BackupEngine SPM package. SPM-only executables cannot carry a proper Info.plist, entitlements, or app bundle structure — all of which are required for LSUIElement, SMAppService, and UNUserNotificationCenter.

The **Ableton Projects folder discovery** is now definitively resolved via direct inspection of a real Ableton 12.2 installation on this machine: `Library.cfg` is a standard UTF-8 XML file at `~/Library/Preferences/Ableton/Live {version}/Library.cfg`. The Projects folder path is in the `<ProjectPath Value="…"/>` tag inside `<UserLibrary>`. `Preferences.cfg` is a proprietary binary format and must not be parsed. The default Projects folder when Ableton has never been reconfigured is `~/Documents/Ableton/Ableton Projects`.

**FSEvents** is the correct API for directory watching. Use `kFSEventStreamCreateFlagFileEvents` (file-level granularity, macOS 10.7+) with a 2-second debounce. Filter events to only those where the path ends in `.als` and `kFSEventStreamEventFlagItemModified` is set. Wrap FSEventStreamRef in a Swift `class` with a custom `deinit` for proper lifecycle management.

**Primary recommendation:** Add an Xcode app target `AbletonBackup.app`, wire it to the BackupEngine local package, set `LSUIElement = YES` in Info.plist, implement a `BackupCoordinator` `@MainActor`-isolated `@Observable` class that owns the FSEvents watcher, scheduler Task, and BackupEngine actor reference.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftUI MenuBarExtra | Built-in (macOS 13+) | Menu bar icon + dropdown UI | Native SwiftUI API, no AppKit NSStatusItem needed for this use case |
| FSEvents (CoreServices) | Built-in | Directory watching for .als changes | Only correct API for recursive directory watching on macOS; per-file events via kFSEventStreamCreateFlagFileEvents |
| SMAppService (ServiceManagement) | Built-in (macOS 13+) | Login item registration | Replaces deprecated LSSharedFileList; no entitlements for non-sandboxed apps |
| UNUserNotificationCenter (UserNotifications) | Built-in (macOS 10.14+) | Local completion/failure notifications | Standard macOS notification API; works in non-sandboxed apps |
| BackupEngine (local SPM package) | Phase 1 | Backup execution | Already built; import as local package dependency from Xcode app target |
| GRDB.swift | 7.x (already in Package.swift) | Persist AppSettings (schedule interval, watch folders) | Already in the stack; add AppSettings table to existing schema |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| UserDefaults | Built-in | Simple preferences (loginAtStartup toggle, schedule interval) | Fast path for non-relational preferences before a full settings window in Phase 3 |
| AsyncAlgorithms (Apple) | 1.x | Debounce operator for FSEvents callback stream | Optional — alternatively hand-roll debounce with Task.sleep; use if already in dep graph |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| FSEvents FileSystemEventStream | NSFilePresenter | NSFilePresenter is designed for coordinated file access (conflict resolution), not monitoring; higher overhead, designed for a different use case |
| FSEvents FileSystemEventStream | DispatchSource.makeFileSystemObjectSource | DispatchSource watches a single file descriptor — requires opening a file handle per directory and cannot watch recursively; FSEvents watches entire directory trees with one stream |
| SwiftUI MenuBarExtra | NSStatusItem + NSPopover (AppKit) | Pure AppKit is more flexible but requires more boilerplate; SwiftUI MenuBarExtra is correct for macOS 13+ without complex AppKit interop |
| SMAppService.mainApp | LaunchAtLogin (third-party) or LSSharedFileList | LSSharedFileList deprecated; LaunchAtLogin wraps SMAppService anyway; use directly |

**Installation (Xcode app target):**
No additional SPM packages needed — all libraries are system frameworks. Add `BackupEngine` as a local package dependency via Xcode "Add Local Package."

---

## Architecture Patterns

### Recommended Project Structure

The current repo has a `Package.swift` (library + CLI). Phase 2 adds an Xcode project alongside it:

```
CC/                                    ← repo root
├── Package.swift                      ← existing (BackupEngine library + CLI)
├── Package.resolved
├── Sources/
│   ├── BackupEngine/                  ← Phase 1 library (unchanged)
│   └── AbletonBackupCLI/             ← existing CLI (may be unused after Phase 2)
├── Tests/
│   └── BackupEngineTests/
└── AbletonBackup.xcodeproj/          ← NEW: Xcode project for the app target
    └── AbletonBackup/                ← app target source folder
        ├── AbletonBackupApp.swift    ← @main App entry point
        ├── Info.plist                ← LSUIElement + NSUserNotificationAlertStyle
        ├── AbletonBackup.entitlements ← minimal (no sandbox)
        ├── BackupCoordinator.swift   ← @Observable @MainActor orchestrator
        ├── FSEventsWatcher.swift     ← wraps FSEventStreamRef
        ├── AbletonPrefsReader.swift  ← reads Library.cfg to find Projects folder
        ├── SchedulerTask.swift       ← Task loop for scheduled backups
        ├── NotificationService.swift ← UNUserNotificationCenter wrapper
        └── Views/
            ├── MenuBarView.swift     ← SwiftUI content for MenuBarExtra
            └── StatusMenuView.swift  ← status, last backup time, "Back Up Now" button
```

### Pattern 1: SwiftUI App Protocol with MenuBarExtra (no Dock icon)

**What:** The `@main` struct uses the SwiftUI `App` protocol with only a `MenuBarExtra` scene. Setting `LSUIElement = YES` in Info.plist suppresses the Dock icon and app switcher entry.

**When to use:** Any background-only macOS utility with no primary window.

```swift
// AbletonBackupApp.swift
// Source: Apple SwiftUI MenuBarExtra documentation + nilcoalescing.com guide

import SwiftUI

@main
struct AbletonBackupApp: App {
    @State private var coordinator = BackupCoordinator()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(coordinator)
        } label: {
            // Dynamic icon based on coordinator.status
            Label("AbletonBackup", systemImage: coordinator.statusIcon)
        }
        .menuBarExtraStyle(.menu)
    }
}
```

**Info.plist entries required:**
```xml
<key>LSUIElement</key>
<true/>
<key>NSUserNotificationAlertStyle</key>
<string>alert</string>
```

`NSUserNotificationAlertStyle = alert` ensures notifications show as persistent banners (not ephemeral — the user must dismiss them). This is the correct setting for backup success/failure events.

### Pattern 2: BackupCoordinator — Central @Observable @MainActor State

**What:** A single `@Observable @MainActor` class owns all mutable state that drives the menu bar icon and menu content. It holds references to the FSEventsWatcher, SchedulerTask, BackupEngine actor, and NotificationService. Swift 6 requires `@MainActor` on `@Observable` classes that update UI-observed properties.

**When to use:** Whenever you need SwiftUI views to observe changes from background actors.

```swift
// BackupCoordinator.swift
// Source: Swift 6 @Observable + @MainActor pattern

import Foundation
import BackupEngine

enum BackupStatus {
    case idle
    case running
    case error(String)

    var iconName: String {
        switch self {
        case .idle:    return "clock.arrow.circlepath"
        case .running: return "arrow.triangle.2.circlepath"
        case .error:   return "exclamationmark.triangle.fill"
        }
    }
}

@Observable
@MainActor
final class BackupCoordinator {
    var status: BackupStatus = .idle
    var lastBackupAt: Date? = nil
    var statusIcon: String { status.iconName }

    private let engine: BackupEngine
    private var watcher: FSEventsWatcher?
    private var schedulerTask: Task<Void, Never>?

    init() {
        // Initialize BackupEngine with configured destinations from GRDB
        // AppDatabase.makeShared() is called here
        self.engine = BackupEngine(db: AppDatabase.makeShared(), adapters: [])
    }

    func startWatching(folder: URL) {
        watcher = FSEventsWatcher(url: folder) { [weak self] changedPath in
            Task { @MainActor [weak self] in
                await self?.handleFileChange(at: changedPath)
            }
        }
    }

    private func handleFileChange(at path: String) async {
        guard path.hasSuffix(".als") else { return }
        await runBackup(trigger: .fsEvent)
    }

    func runBackup(trigger: BackupTrigger) async {
        guard case .idle = status else { return } // deduplicate
        status = .running
        do {
            // Build job from watched projects + configured destinations
            // ...
            status = .idle
        } catch {
            status = .error(error.localizedDescription)
        }
    }
}
```

### Pattern 3: FSEventsWatcher — Wrapping FSEventStreamRef in Swift

**What:** A Swift class that owns the `FSEventStreamRef` lifecycle. Uses `kFSEventStreamCreateFlagFileEvents` for per-file granularity and a 2-second latency for debouncing. The callback is a C function passed as a closure bridge.

**When to use:** Watching an Ableton Projects folder for `.als` file saves.

```swift
// FSEventsWatcher.swift
// Source: Apple FSEvents Programming Guide + FSEvents.h SDK header

import Foundation
import CoreServices

final class FSEventsWatcher {
    private var stream: FSEventStreamRef?
    private let callback: (String) -> Void

    init(url: URL, callback: @escaping (String) -> Void) {
        self.callback = callback
        let pathsToWatch = [url.path] as CFArray
        let latency: CFTimeInterval = 2.0   // 2-second debounce

        // Create callback context with self pointer
        var ctx = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passRetained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )

        let flags = UInt32(
            kFSEventStreamCreateFlagFileEvents |   // per-file granularity (macOS 10.7+)
            kFSEventStreamCreateFlagUseCFTypes |   // required for path access
            kFSEventStreamCreateFlagNoDefer        // deliver ASAP after latency
        )

        stream = FSEventStreamCreate(
            nil,
            { _, info, numEvents, eventPaths, eventFlags, _ in
                let watcher = Unmanaged<FSEventsWatcher>.fromOpaque(info!).takeUnretainedValue()
                let paths = unsafeBitCast(eventPaths, to: NSArray.self) as! [String]
                let flags = UnsafeBufferPointer(start: eventFlags, count: numEvents)

                for (path, flag) in zip(paths, flags) {
                    // Only trigger on actual file modifications to .als files
                    let isModified = flag & UInt32(kFSEventStreamEventFlagItemModified) != 0
                    let isFile     = flag & UInt32(kFSEventStreamEventFlagItemIsFile) != 0
                    let isRenamed  = flag & UInt32(kFSEventStreamEventFlagItemRenamed) != 0

                    if (isModified || isRenamed) && isFile && path.hasSuffix(".als") {
                        watcher.callback(path)
                    }
                }
            },
            &ctx,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            FSEventStreamCreateFlags(flags)
        )

        FSEventStreamScheduleWithRunLoop(stream!, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        FSEventStreamStart(stream!)
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        Unmanaged.passUnretained(self).release()
    }
}
```

**Ableton-specific notes for the FSEvents filter:**
- Ableton writes `.als` files using an atomic rename pattern: it writes to a temp file, then renames it to `ProjectName.als`. The rename fires `kFSEventStreamEventFlagItemRenamed` on the final path, not `kFSEventStreamEventFlagItemModified`. Filter for EITHER flag on `.als` suffix to cover both behaviors.
- Ableton also writes `.asd` (analysis), temp audio, and log files. The `.als` suffix filter eliminates most noise.
- The 2-second debounce (latency parameter) handles cases where Ableton fires multiple events for the same save operation.

### Pattern 4: Ableton Projects Folder Discovery (Library.cfg parsing)

**What:** Read `Library.cfg` from `~/Library/Preferences/Ableton/Live {version}/Library.cfg`. This is **standard UTF-8 XML** (verified by direct inspection of Ableton 12.2 files). Extract `<ProjectPath Value="…"/>` inside `<UserLibrary>`. This is the **User Library parent folder**, not a "Projects folder" — but the convention is that Ableton projects are saved inside a sibling `Ableton Projects` folder at the same level.

**Direct findings from inspecting this machine's Ableton 12.2 install:**
- `Library.cfg` location: `~/Library/Preferences/Ableton/Live 12.2/Library.cfg`
- XML structure: `<Ableton><ContentLibrary><UserLibrary><LibraryProject><ProjectPath Value="/Users/eric/Music/Ableton"/></LibraryProject></UserLibrary></ContentLibrary></Ableton>`
- The actual Projects folder on this machine is: `/Users/eric/Documents/Ableton/Ableton Projects/` (a separate user choice)
- `Preferences.cfg` is a proprietary binary format — do NOT attempt to parse it

**IMPORTANT:** The `ProjectPath` in Library.cfg is the **User Library location**, not the Projects save folder. The default projects location is `~/Documents/Ableton/Ableton Projects` and is not stored in either config file in a machine-readable way. The strategy is:

1. Find the newest Ableton version folder under `~/Library/Preferences/Ableton/`
2. Parse `Library.cfg` as XML to extract `ProjectPath` (the User Library path, e.g., `~/Music/Ableton`)
3. The Projects folder is typically a sibling: check if `~/Documents/Ableton/Ableton Projects` exists (hardcoded Ableton default), then fall back to showing a file picker

```swift
// AbletonPrefsReader.swift
// Source: Direct inspection of Ableton 12.2 Library.cfg on this machine

import Foundation

struct AbletonPrefsReader {
    /// Find the most recent Ableton version folder under ~/Library/Preferences/Ableton/
    static func findLatestVersionFolder() -> URL? {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/Ableton")
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: base, includingPropertiesForKeys: [.isDirectoryKey]) else { return nil }
        // Sort by version string descending — Ableton uses "Live 12.2" format
        return items
            .filter { $0.lastPathComponent.hasPrefix("Live ") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .first
    }

    /// Parse Library.cfg and return the ProjectPath value from <UserLibrary>
    static func parseUserLibraryPath(from versionFolder: URL) -> URL? {
        let cfg = versionFolder.appendingPathComponent("Library.cfg")
        guard let data = try? Data(contentsOf: cfg) else { return nil }

        // Library.cfg is UTF-8 XML — parse with XMLDocument
        guard let doc = try? XMLDocument(data: data, options: []) else { return nil }
        let nodes = try? doc.nodes(forXPath: "//UserLibrary/LibraryProject/ProjectPath/@Value")
        guard let path = (nodes?.first as? XMLNode)?.stringValue, !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Return the best guess at the Ableton Projects folder.
    /// Falls back to ~/Documents/Ableton/Ableton Projects (Ableton's default).
    static func discoverProjectsFolder() -> URL? {
        // Ableton default: ~/Documents/Ableton/Ableton Projects
        let defaultPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Ableton/Ableton Projects")
        if FileManager.default.fileExists(atPath: defaultPath.path) {
            return defaultPath
        }
        return nil
    }
}
```

### Pattern 5: Scheduled Backup via Task Loop

**What:** A repeating Swift Concurrency task that wakes at the configured interval and triggers a backup. Uses `Task.sleep(for:)` from Swift 5.7+. Store the interval in UserDefaults (Phase 3 will move it to a proper Settings UI). Cancel and restart the task when the interval changes.

**Why not BackgroundTasks framework:** `BGProcessingTask` requires App Store distribution and sandbox entitlement. Non-sandboxed, non-App-Store apps use simple Task loops.

```swift
// SchedulerTask.swift
// Source: wadetregaskis.com "Performing a delayed and/or repeating operation in a Swift actor" + Swift Concurrency docs

import Foundation

@MainActor
final class SchedulerTask {
    private var task: Task<Void, Never>?

    func start(interval: Duration, action: @escaping @MainActor () async -> Void) {
        task?.cancel()
        task = Task(priority: .utility) {
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                if !Task.isCancelled {
                    await action()
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
```

**Default schedule:** Start with 1-hour interval hardcoded for Phase 2. Phase 3's settings window exposes this to users.

### Pattern 6: Login Item Registration with SMAppService

**What:** `SMAppService.mainApp.register()` registers the app as a login item. Works without any entitlements for non-sandboxed macOS apps. The user can also remove the item from System Settings > General > Login Items, so the app must read `SMAppService.mainApp.status` to check current state rather than relying on local storage.

```swift
// Source: Apple ServiceManagement docs + nilcoalescing.com/blog/LaunchAtLoginSetting/

import ServiceManagement

struct LoginItemManager {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
```

**SMAppService.Status values:** `.enabled`, `.notRegistered`, `.notFound`, `.requiresApproval`

The `.requiresApproval` case appears if the user has already manually blocked this app from System Settings. Show an error and deep-link to System Settings with `SMAppService.openSystemSettingsLoginItems()`.

### Pattern 7: UNUserNotificationCenter Notifications

**What:** Request authorization at first launch, then post notifications for backup success and failure. On macOS, `UNUserNotificationCenter` works for non-sandboxed apps with no special entitlements. The `NSUserNotificationAlertStyle = alert` Info.plist key ensures banners appear as dismissible alerts (not just in Notification Center).

```swift
// NotificationService.swift
// Source: Apple UserNotifications documentation

import UserNotifications

struct NotificationService {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        ) { granted, error in
            // Store granted status; don't re-request if denied
        }
    }

    static func sendBackupSuccess(projectName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Backup Complete"
        content.body = "\(projectName) backed up successfully."
        content.sound = .default
        post(content: content, identifier: "backup-success-\(projectName)")
    }

    static func sendBackupFailure(projectName: String, error: String) {
        let content = UNMutableNotificationContent()
        content.title = "Backup Failed"
        content.body = "\(projectName): \(error)"
        content.sound = .defaultCritical
        post(content: content, identifier: "backup-failure-\(projectName)")
    }

    private static func post(content: UNMutableNotificationContent, identifier: String) {
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil  // nil = deliver immediately
        )
        UNUserNotificationCenter.current().add(request)
    }
}
```

### Anti-Patterns to Avoid

- **Parsing Preferences.cfg:** This file is a proprietary binary format — it appears to use UTF-16 LE encoding for keys but has undocumented binary framing. Use Library.cfg instead (UTF-8 XML).
- **DispatchSource for recursive directory watching:** DispatchSource requires an open file descriptor per watched item and cannot watch recursively. FSEvents handles entire directory trees with one stream.
- **NSFilePresenter for save detection:** NSFilePresenter participates in NSFileCoordinator for conflict resolution, not for triggering backups. Overhead is high and the API is designed for a different problem.
- **BackgroundTasks framework for scheduled backups:** BGProcessingTask is App Store + sandboxed only. Use a Task loop with Task.sleep.
- **Storing `isLoginItemEnabled` in UserDefaults:** Users can toggle login items in System Settings independently. Always read from `SMAppService.mainApp.status`.
- **SPM-only executable for the app target:** SPM cannot produce a proper .app bundle with Info.plist, entitlements, and code signature. An Xcode project with a macOS App target is required.
- **MenuBarExtra .window style:** Use `.menu` style for a standard dropdown menu. The `.window` style requires an explicit frame and behaves like a floating panel — correct for control surfaces, wrong for a simple backup status menu. Phase 2 uses `.menu`.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Directory watching | Custom kqueue or poll loop | FSEvents FileSystemEventStream | FSEvents is kernel-level, coalesces events, handles volume mounts/unmounts, no polling overhead |
| Debouncing FSEvents | Custom timer restart logic | FSEvents `latency` parameter | The latency value coalesces events before delivery — use 2.0 seconds for Ableton save patterns |
| Login item persistence | Custom LaunchAgent plist | SMAppService.mainApp | SMAppService manages the launchd plist automatically, survives system updates |
| Notification permission tracking | Custom "did we ask?" flag | UNAuthorizationStatus from getNotificationSettings | System tracks permission state; always query before deciding to re-request |
| XML parsing for Library.cfg | Custom byte scanner | XMLDocument (Foundation) | Library.cfg is proper UTF-8 XML; Foundation's XMLDocument handles namespaces and encoding |
| Version folder discovery | Hardcode "Live 12.2" | Sort ~/Library/Preferences/Ableton/ by lastPathComponent descending | Multiple Ableton versions can coexist; always pick the newest |

**Key insight:** FSEvents, SMAppService, and UNUserNotificationCenter each abstract significant OS-level complexity (kernel event coalescing, launchd integration, and user consent UX). Reimplementing any of these would miss edge cases that took Apple years to solve.

---

## Common Pitfalls

### Pitfall 1: Ableton Uses Atomic Rename for .als Saves

**What goes wrong:** Watching for `kFSEventStreamEventFlagItemModified` on `.als` files misses saves. The backup never triggers even though Ableton is saving correctly.

**Why it happens:** Ableton (and many professional apps) write saves atomically: write to a temp file, then rename it to the final filename. The rename operation fires `kFSEventStreamEventFlagItemRenamed` on the destination path, not `kFSEventStreamEventFlagItemModified`. Without `kFSEventStreamCreateFlagFileEvents`, you don't even get per-file events — only directory-level notifications.

**How to avoid:** Filter for `(isModified || isRenamed) && isFile && path.hasSuffix(".als")`. The rename approach means you always get the complete final file, never a partial write.

**Warning signs:** FSEvents watcher starts, but manual test (save an .als in the watched folder, add a log) shows no callback firing.

### Pitfall 2: Settings Window Focus Failure in LSUIElement Apps

**What goes wrong:** Phase 3 will add a Settings window. The `openSettings()` SwiftUI environment action silently fails in LSUIElement apps because there is no regular app activation policy.

**Why it happens:** macOS does not bring windows to the front for apps without a Dock presence unless activation policy is temporarily switched to `.regular`. The `openSettings()` environment action has this limitation as of macOS Sonoma.

**How to avoid:** This is a Phase 3 problem. Document here so it's planned for: switching activation policy temporarily (`NSApp.setActivationPolicy(.regular)` + `NSApp.activate()`) before showing any window is the working solution (per Peter Steinberger's 2025 investigation). Phase 2 has no settings window, so this is not a blocker.

**Warning signs:** Phase 3 attempts to add Settings and the window appears behind other windows or doesn't appear at all.

### Pitfall 3: SMAppService Registration Fails Silently on First Launch

**What goes wrong:** The "Launch at Login" toggle is flipped on, `SMAppService.mainApp.register()` is called, no error is thrown, but the app doesn't actually launch at login.

**Why it happens:** On first registration, macOS may require the user to approve in System Settings > General > Login Items. The status becomes `.requiresApproval`. The register() call succeeds (no throw) but the item isn't active until approved.

**How to avoid:** After calling `register()`, check `SMAppService.mainApp.status`. If `.requiresApproval`, show a message directing users to System Settings and offer to open it with `SMAppService.openSystemSettingsLoginItems()`.

**Warning signs:** Toggle shows "on" in the app but app doesn't launch at login after reboot.

### Pitfall 4: FSEvents Callback Is Called on an Arbitrary Thread

**What goes wrong:** Swift 6 strict concurrency: mutating `@Observable @MainActor` state from the FSEvents callback triggers a concurrency violation, or worse, silently races on UI state.

**Why it happens:** `FSEventStreamScheduleWithRunLoop` delivers events on the run loop it's scheduled on. Scheduling on `CFRunLoopGetMain()` delivers on the main thread, but the callback itself is a raw C function that has no Swift actor context. In Swift 6, calling `@MainActor`-isolated code from a non-isolated context is a compile error.

**How to avoid:** Use `Task { @MainActor in ... }` inside the FSEvents callback to safely hop to the main actor. This is shown in Pattern 3 above. The callback closure in `FSEventsWatcher.init` captures `watcher.callback(path)` where `callback` is a plain closure; the `BackupCoordinator` wraps it with `Task { @MainActor [weak self] in ... }`.

**Warning signs:** Swift 6 compiler emits "Call to main actor–isolated method in a synchronous nonisolated context."

### Pitfall 5: Library.cfg ProjectPath Is the User Library, Not the Projects Folder

**What goes wrong:** Discovery logic reads `<ProjectPath Value="/Users/eric/Music/Ableton"/>` from Library.cfg, treats it as the watched Projects folder, and finds no `.als` files because that's the User Library (presets, packs).

**Why it happens:** The XML key name is `ProjectPath` but semantically it holds the User Library location — the folder where Ableton stores its User Library content. The Projects save folder is a separate user-chosen location not stored in either Library.cfg or Preferences.cfg in a parseable form.

**How to avoid:** Use Library.cfg `ProjectPath` only as a hint for the parent path. The primary strategy is: check `~/Documents/Ableton/Ableton Projects` (Ableton's hardcoded default, confirmed on this machine). Phase 3's settings UI lets users add additional watch folders (DISC-02/DISC-03).

**Warning signs:** Watcher is set up successfully but no projects appear in backup history after weeks of use.

### Pitfall 6: Concurrent Backups When Multiple .als Files Change Simultaneously

**What goes wrong:** User saves a project while a scheduled backup is already running for the same project. Two BackupEngine.runJob() calls fire for the same project. If not handled, results in duplicate version rows and DB constraint violations.

**Why it happens:** FSEvents and the scheduler can fire within milliseconds of each other. BackupEngine already has deduplication (Phase 1: `runningJobs[project.id]` task-join pattern), but only within a single project. If the scheduler backs up all projects and FSEvents fires for the same project simultaneously, the BackupEngine deduplication handles it correctly — the second caller joins the existing task.

**How to avoid:** Trust BackupEngine's existing deduplication (verified in Phase 1 tests). No additional locking needed. Document the guarantee in the BackupCoordinator.

**Warning signs:** Integration tests show duplicate version IDs in the database after simulated simultaneous trigger.

### Pitfall 7: Xcode App Target Cannot Directly Import SPM Package from Package.swift

**What goes wrong:** Adding the Xcode app target and trying to `import BackupEngine` fails with "no such module."

**Why it happens:** Xcode app targets don't automatically discover SPM packages in the same repo. You must explicitly add the local package via Xcode's "Add Packages" dialog or by dragging `Package.swift` into the Xcode project navigator, then adding `BackupEngine` to the app target's "Frameworks and Libraries" in the target settings.

**How to avoid:** In Xcode: File > Add Package Dependencies > select the local path to the repo root. The BackupEngine library target appears and can be added to the app target.

**Warning signs:** `import BackupEngine` produces "no such module" error at compile time.

---

## Code Examples

Verified patterns from official sources and direct inspection:

### FSEvents Flag Constants (from FSEvents.h SDK header, verified)
```swift
// kFSEventStreamCreateFlagFileEvents — per-file granularity (macOS 10.7+)
// kFSEventStreamEventFlagItemModified — file content changed
// kFSEventStreamEventFlagItemRenamed  — file renamed (catches atomic save writes)
// kFSEventStreamEventFlagItemIsFile   — event path is a file (not a directory)
let createFlags = UInt32(
    kFSEventStreamCreateFlagFileEvents |  // 0x00000010
    kFSEventStreamCreateFlagUseCFTypes |  // 0x00000001
    kFSEventStreamCreateFlagNoDefer       // 0x00000002
)
```

### Library.cfg XML Path (verified on Ableton 12.2 on this machine)
```
File: ~/Library/Preferences/Ableton/Live 12.2/Library.cfg
Format: UTF-8 XML
XPath: //UserLibrary/LibraryProject/ProjectPath/@Value
Example value: "/Users/eric/Music/Ableton"  ← User Library, not Projects folder
```

### Ableton Default Projects Folder (confirmed on this machine)
```
~/Documents/Ableton/Ableton Projects/   ← confirmed as default
Each project is a directory: "My Project.als" + "Samples/" + "Backup/" etc.
```

### MenuBarExtra Dynamic Icon
```swift
// Source: Apple SwiftUI MenuBarExtra docs + nilcoalescing.com guide
// The label closure re-renders when coordinator.status changes via @Observable
MenuBarExtra {
    MenuBarView().environment(coordinator)
} label: {
    switch coordinator.status {
    case .idle:
        Label("AbletonBackup", systemImage: "waveform")
    case .running:
        Label("AbletonBackup", systemImage: "arrow.triangle.2.circlepath")
    case .error:
        Label("AbletonBackup", systemImage: "exclamationmark.triangle.fill")
    }
}
```

### SMAppService Login Item (verified API)
```swift
// Source: Apple ServiceManagement documentation + nilcoalescing.com
import ServiceManagement

// Register (call when user enables toggle)
try SMAppService.mainApp.register()

// Unregister (call when user disables toggle)
try SMAppService.mainApp.unregister()

// Read current status (do NOT cache — user can change in System Settings)
let isEnabled = SMAppService.mainApp.status == .enabled

// Deep link to System Settings when requiresApproval
SMAppService.openSystemSettingsLoginItems()
```

### UNUserNotificationCenter Request Auth (at launch, once)
```swift
// Source: Apple UserNotifications documentation
UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
```

### Task Loop for Scheduled Backup
```swift
// Source: wadetregaskis.com "Performing a delayed/repeating operation in a Swift actor"
var schedulerTask: Task<Void, Never>? = Task(priority: .utility) {
    while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(3600)) // 1 hour default
        guard !Task.isCancelled else { break }
        await coordinator.runBackup(trigger: .scheduled)
    }
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| NSStatusItem + NSPopover (AppKit) | SwiftUI MenuBarExtra | macOS 13 / WWDC22 | Native SwiftUI, no AppKit interop needed for simple menus |
| LSSharedFileList (deprecated) | SMAppService.mainApp | macOS 13 / WWDC22 | Modern launchd integration, system-managed lifecycle |
| NSFilePresenter for save detection | FSEvents with kFSEventStreamCreateFlagFileEvents | macOS 10.7 | Per-file events, recursive watching, no fd-per-file overhead |
| @ObservableObject + @Published | @Observable (Observation framework) | macOS 14 / WWDC23 | Less boilerplate, more granular tracking — but @MainActor isolation must be explicit |
| NSUserNotification (deprecated) | UNUserNotificationCenter | macOS 10.14 | Unified API across Apple platforms |
| BackgroundTasks framework | Task loop with Task.sleep | Not applicable | BackgroundTasks requires App Store; Task loop works for non-sandboxed apps |

**Deprecated/outdated:**
- `LSSharedFileList` / `SMLoginItemSetEnabled`: Deprecated in macOS 13. Use `SMAppService`.
- `NSUserNotification`: Deprecated in macOS 11. Use `UNUserNotificationCenter`.
- `NSFilePresenter` for backup triggering: Wrong tool; use FSEvents.
- `@ObservableObject` + `@Published`: Functional, but `@Observable` is preferred for new code targeting macOS 14+. Since this project targets macOS 13+, use `@Observable` with careful note that it requires macOS 14+. Fallback: use `@ObservableObject` if macOS 13 is a hard requirement. **Decision: use `@Observable` with `#available(macOS 14, *)` or target macOS 14+ minimum for the app target while keeping the library at macOS 13+.**

---

## Open Questions

1. **App target minimum deployment target: macOS 13 or 14?**
   - What we know: Package.swift declares `.macOS(.v13)` for the library. `@Observable` is macOS 14+. `MenuBarExtra` and `SMAppService` are macOS 13+.
   - What's unclear: Whether to raise the app target to macOS 14 to get `@Observable`, or use `@ObservableObject` to maintain macOS 13 compatibility.
   - Recommendation: Set the app target to macOS 14 minimum. The library remains macOS 13+. The user of this app is a macOS audio producer — macOS 14 Sonoma (Sep 2023) has high adoption. Document the decision in the plan.

2. **Xcode project creation: manual or script?**
   - What we know: An Xcode project requires a `.xcodeproj` bundle with PBX format. This cannot be created by SPM or committed cleanly without binary files.
   - What's unclear: The plan needs to specify whether to commit the `.xcodeproj` or generate it.
   - Recommendation: Create the Xcode project manually as the first plan step. Commit the `.xcodeproj` to git — it is text-based (PBX format) and appropriate to commit.

3. **Concurrent job limit when multiple watched folders change simultaneously**
   - What we know: BackupEngine deduplicates per `project.id`. If two projects both save in the same second, two parallel runJob() calls happen.
   - What's unclear: Is there a risk of exhausting resources with many simultaneous backups?
   - Recommendation: For Phase 2 (single watch folder), this is low risk. Document as a known limitation; Phase 3's settings UI will constrain the number of destinations.

4. **Code signing for distribution outside App Store**
   - What we know: Non-App-Store macOS apps require Developer ID signing + notarization for Gatekeeper acceptance. This affects build settings, not Phase 2 code.
   - What's unclear: Whether to set up code signing in Phase 2 or defer to a "distribution" phase.
   - Recommendation: Set up code signing identity in the Xcode project during Phase 2 (build setting: Developer ID Application certificate). Actual notarization can be deferred. Unsigned builds work fine for development on the dev machine.

---

## Sources

### Primary (HIGH confidence)
- Direct inspection of `/Users/eric/Library/Preferences/Ableton/Live 12.2/Library.cfg` — confirmed UTF-8 XML format, `<ProjectPath Value="…"/>` structure, User Library path value
- Direct inspection of `/Users/eric/Library/Preferences/Ableton/Live 12.2/Preferences.cfg` — confirmed proprietary binary format (UTF-16 LE strings with binary framing); do NOT parse
- Direct inspection of `/Users/eric/Documents/Ableton/Ableton Projects/` — confirmed Ableton's actual default projects folder on this machine
- FSEvents.h SDK header at `/Applications/Xcode.app/.../FSEvents.framework/Headers/FSEvents.h` — verified all flag constants and their hex values
- [Apple FSEvents Programming Guide](https://developer.apple.com/library/archive/documentation/Darwin/Conceptual/FSEvents_ProgGuide/UsingtheFSEventsFramework/UsingtheFSEventsFramework.html) — stream lifecycle, latency parameter, flag semantics
- [nilcoalescing.com: Build a macOS menu bar utility in SwiftUI](https://nilcoalescing.com/blog/BuildAMacOSMenuBarUtilityInSwiftUI/) — MenuBarExtra setup, LSUIElement, .menu vs .window styles
- [nilcoalescing.com: Launch at Login Setting](https://nilcoalescing.com/blog/LaunchAtLoginSetting/) — SMAppService.mainApp.register/unregister pattern, `.requiresApproval` handling
- [wadetregaskis.com: Repeating operations in Swift actors](https://wadetregaskis.com/performing-a-delayed-and-or-repeating-operation-in-a-swift-actor/) — Task loop vs DispatchQueue timer in actor context

### Secondary (MEDIUM confidence)
- [Peter Steinberger: Showing Settings from macOS Menu Bar Items (2025)](https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items) — activation policy workaround for settings windows in LSUIElement apps; relevant for Phase 3
- [Apple SMAppService documentation](https://developer.apple.com/documentation/servicemanagement/smappservice) — confirmed API exists and targets macOS 13+; entitlement requirements for non-sandboxed not explicitly documented but community confirms no entitlement needed
- [Apple Developer Forums: SMAppService](https://developer.apple.com/forums/thread/719862) — confirms works for non-App-Store apps

### Tertiary (LOW confidence)
- Ableton Forum discussions on temp files — general confirmation that Ableton writes temp/analysis files alongside saves; exact atomic-rename behavior inferred from FSEvents flags rather than documented
- Multiple blog posts confirming LSUIElement + MenuBarExtra pattern — consistent across 5+ sources; confidence elevated

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — All framework choices verified against macOS SDK headers and official docs
- Architecture patterns: HIGH — MenuBarExtra, SMAppService, UNUserNotificationCenter patterns verified against official or well-documented sources; FSEventsWatcher pattern derived from SDK headers and Apple programming guide
- Ableton discovery: HIGH — Directly verified on a real Ableton 12.2 installation on this machine; no speculation
- Pitfalls: HIGH — Atomic rename pitfall derived from FSEvents flag semantics (verified in SDK header); other pitfalls derived from documented Swift 6 concurrency rules and community-verified SMAppService behavior
- Settings window pitfall (Phase 3 preview): MEDIUM — documented by one reputable source (Steinberger 2025), not cross-verified

**Research date:** 2026-02-27
**Valid until:** 2026-08-27 (stable APIs; Ableton format could change with major version update; re-verify if Ableton 13 ships)
