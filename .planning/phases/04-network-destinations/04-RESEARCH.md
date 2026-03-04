# Phase 4: Network Destinations - Research

**Researched:** 2026-03-04
**Domain:** macOS network filesystem mounting (SMB/NFS via NetFS), Keychain credential storage, iCloud Drive file access, sleep/wake reconnection, per-destination availability monitoring
**Confidence:** MEDIUM-HIGH (core APIs verified via official docs and community forums; NetFS Swift 6 integration has LOW confidence items flagged)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Destination types & picker**
- Three distinct destination types: "Mounted Volume", "SMB/NFS Network Drive", "iCloud Drive"
- Destination picker groups them: **Cloud** (iCloud Drive) and **Network** (Mounted Volume, SMB/NFS)
- User selects a type, then completes type-specific setup

**NAS — SMB/NFS setup**
- Structured fields: Host, Share name, Username, Password (not URL-style entry)
- Credentials stored in Keychain
- **Test connection required before saving** — destination not created until connection succeeds

**NAS — Mounted Volume setup**
- Picker from volumes currently mounted in /Volumes
- No credential entry (already authenticated by OS)
- Test connection required before saving (verifies write access)

**iCloud Drive setup**
- User chooses destination folder via macOS folder picker (not a fixed app container)
- Test connection/write-access check required before saving — same pattern as NAS
- No authentication step (uses system iCloud account)

**Destination status on main screen**
- **Colored dot** per destination (green = online, red = error/offline)
- **Last backup time + result** shown per destination: e.g., "NAS • Last backup: 2h ago • Success" or "NAS • Last backup: 5h ago • Failed"
- iCloud uses same three-state dot as NAS (no special syncing state)

**Error detail & recovery**
- Tapping a red dot navigates to destination settings
- Destination settings shows: error message + **Retry Now button** + last connected time
- No auto-retry when destination comes back online — user triggers retry manually

**Failure behavior during backup**
- If destination goes offline **mid-backup**: fire a system notification AND update in-app state to show failure
- If destination is offline **at backup start**: skip that destination, complete backup to remaining available destinations (partial success is valid)

### Claude's Discretion
- Exact dot size, color values, and animation (pulse on syncing?)
- How Keychain prompts are presented for credential updates
- SMB vs NFS protocol auto-detection or user selection
- Retry logic internals (timeout, error classification)

### Deferred Ideas (OUT OF SCOPE)
- None — discussion stayed within phase scope
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| DEST-02 | User can configure a NAS destination via already-mounted Mac volume | FileManager.mountedVolumeURLs API for picker; probe() uses directory-exists + isWritable check |
| DEST-03 | User can configure a NAS destination via direct SMB/NFS with stored credentials | NetFSMountURLAsync for mounting; Security framework kSecClassInternetPassword for Keychain storage |
| DEST-04 | User can configure iCloud Drive as a destination (no auth required) | NSOpenPanel folder picker in ~/Library/Mobile Documents/; standard FileManager write |
| DEST-06 | Each destination shows live availability status in settings | DestinationAdapter.probe() already defined; periodic timer polling pattern; colored dot UI in SwiftUI |
| DEST-07 | NAS connection auto-reconnects after system wakes from sleep | NSWorkspace.didWakeNotification observer pattern; re-call NetFSMountURLAsync on wake for SMB destinations |
</phase_requirements>

---

## Summary

Phase 4 adds three new destination types (Mounted Volume, SMB/NFS Network Drive, iCloud Drive) on top of the existing `DestinationAdapter` protocol and `DestinationConfig` GRDB model. The core architecture is already in place from Phase 1: the protocol, the enum cases, and the schema all anticipate these types. Phase 4's work is implementing the three new adapter classes, wiring a new destination-management UI (add/remove/configure), and adding per-destination live status to the main screen.

The biggest technical risk is SMB mounting. NetFS (`NetFSMountURLAsync`) is the standard macOS API for programmatic SMB mounting outside the sandbox, but it is poorly documented, finicky about asynchrony, and known to fail on unmount. This app distributes outside the Mac App Store (confirmed in STATE.md) so sandbox restrictions do not apply, which eliminates the most severe NetFS limitation. Keychain credential storage uses Security framework directly (`kSecClassInternetPassword`) — KeychainAccess library is available but has not been updated since 2020 and has uncertain Swift 6 concurrency status, so raw Security API is the safer choice.

The sleep/wake reconnection requirement (DEST-07) is addressed by subscribing to `NSWorkspace.didWakeNotification` and re-invoking the mount + probe cycle on any SMB destination. iCloud Drive requires no mount step — it is a normal directory under `~/Library/Mobile Documents/` (or a user-chosen path) and writes via standard FileManager. The `DestinationConfig` table needs a GRDB migration (v3) to add SMB-specific columns (host, share, username) while keeping credentials in Keychain (not in the database).

**Primary recommendation:** Implement three new `DestinationAdapter` conformances (`MountedVolumeAdapter`, `SMBDestinationAdapter`, `iCloudDestinationAdapter`), a GRDB v3 migration for SMB columns, a `DestinationManager` actor for lifecycle management (add, remove, probe, reconnect), and update the main screen and settings UI for live status dots and destination CRUD.

---

## Standard Stack

### Core
| Library/API | Version/Availability | Purpose | Why Standard |
|-------------|---------------------|---------|--------------|
| NetFS.framework | macOS system (all versions) | Programmatic SMB/NFS mounting via `NetFSMountURLAsync` | The only Apple-supported public API for mounting network shares without shell invocation |
| Security.framework (SecItem APIs) | macOS system | Keychain CRUD: `SecItemAdd`, `SecItemCopyMatching`, `SecItemUpdate`, `SecItemDelete` with `kSecClassInternetPassword` | Native Apple API, Swift 6 safe (C functions, no Sendable concerns), no dependency |
| FileManager | Foundation | Enumerate /Volumes (`mountedVolumeURLs`), write to iCloud path, check write access | Already used throughout project |
| NSWorkspace | AppKit | `didWakeNotification` for sleep/wake detection, `unmountAndEjectDevice(at:)` for cleanup | Official Apple API for workspace events |
| NWPathMonitor | Network.framework (macOS 10.14+) | Detect general network availability changes | Modern replacement for Reachability; min target is macOS 13 so available |
| GRDB DatabaseMigrator | Already in project (GRDB 7.x) | v3 migration to add SMB columns to destination table | Established pattern in this project |

### Supporting
| Library/API | Version/Availability | Purpose | When to Use |
|-------------|---------------------|---------|-------------|
| NSOpenPanel | AppKit | Folder picker for iCloud Drive and Mounted Volume selection | Any time user selects a destination folder |
| URLComponents | Foundation | Build `smb://host/share` URLs safely (handles percent-encoding) | Constructing SMB URLs before mount |
| OSLog | Already in project | Per-adapter structured logging | All adapter lifecycle events |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Security.framework direct (kSecClassInternetPassword) | KeychainAccess library | KeychainAccess last released 2020 (v4.2.2), unclear Swift 6 Sendable status, not worth the dependency risk for ~20 lines of code |
| NetFSMountURLAsync | AMSMB2 library (amosavian/AMSMB2) | AMSMB2 is LGPL-linked, bypasses Finder/system integration, higher complexity — only use if NetFS proves unworkable |
| NSOpenPanel for iCloud | Fixed `~/Library/Mobile Documents/com~apple~CloudDocs/` | Fixed path doesn't let user choose subfolder; NSOpenPanel matches the locked decision |
| Polling timer for destination status | Push-based observation (e.g., NSWorkspace volume mount/unmount notifications) | Polling is simpler and sufficient for a backup app; push approach adds complexity for marginal gain |

**No new Swift Package dependencies are required for Phase 4.** All needed APIs are system frameworks already available.

---

## Architecture Patterns

### Recommended Project Structure

```
Sources/BackupEngine/
├── Destinations/
│   ├── DestinationAdapter.swift       # existing protocol (unchanged)
│   ├── LocalDestinationAdapter.swift  # existing (unchanged)
│   ├── MountedVolumeAdapter.swift     # NEW: DEST-02
│   ├── SMBDestinationAdapter.swift    # NEW: DEST-03
│   └── iCloudDestinationAdapter.swift # NEW: DEST-04
├── Networking/
│   ├── DestinationManager.swift       # NEW: actor managing adapter lifecycle + wake reconnect
│   ├── NetFSMounter.swift             # NEW: wraps NetFSMountURLAsync in async/await
│   └── KeychainCredentialStore.swift  # NEW: wraps SecItem API for SMB credentials
├── Persistence/
│   ├── Models/
│   │   └── DestinationConfig.swift    # MODIFY: add smb-specific fields (host, share, username)
│   └── Schema.swift                   # MODIFY: add v3 migration
AbletonBackup/
├── Views/
│   └── Settings/
│       ├── DestinationsSettingsView.swift  # MODIFY: full CRUD UI with status dots
│       ├── AddDestinationView.swift        # NEW: destination type picker sheet
│       ├── SMBSetupView.swift              # NEW: host/share/user/pass form
│       ├── MountedVolumeSetupView.swift    # NEW: /Volumes picker
│       └── iCloudSetupView.swift           # NEW: NSOpenPanel folder picker
│   ├── MenuBarView.swift              # MODIFY: per-destination status dots
│   └── DestinationStatusDot.swift     # NEW: reusable colored dot + label component
├── BackupCoordinator.swift            # MODIFY: multi-destination job dispatch, wake observer
```

### Pattern 1: NetFS Async/Await Wrapping

**What:** `NetFSMountURLAsync` takes a completion block. Wrap it in `withCheckedThrowingContinuation` to produce a Swift async function.

**When to use:** Any time an SMB destination needs to be mounted before a backup.

```swift
// Source: Apple Developer Forums thread/94733 + Gist mosen/2ddf85824fbb5564aef527b60beb4669
import NetFS

func mountSMBShare(host: String, share: String, username: String, password: String) async throws -> URL {
    let smb = URLComponents(string: "smb://\(host)/\(share)")!
    guard let shareURL = smb.url else { throw SMBError.invalidURL }

    return try await withCheckedThrowingContinuation { continuation in
        var requestID: AsyncRequestID?
        let result = NetFSMountURLAsync(
            shareURL as CFURL,
            nil,                    // mountPath: nil — let NetFS choose (non-sandboxed only)
            username as CFString,
            password as CFString,
            nil,                    // openOptions
            nil,                    // mountOptions
            &requestID,
            .main,                  // DispatchQueue
            { status, mountpoints in
                if status == 0, let mounts = mountpoints as? [String], let first = mounts.first {
                    continuation.resume(returning: URL(fileURLWithPath: first))
                } else {
                    continuation.resume(throwing: SMBError.mountFailed(status: Int(status)))
                }
            }
        )
        if result != 0 {
            continuation.resume(throwing: SMBError.mountFailed(status: Int(result)))
        }
    }
}
```

**Critical notes:**
- Pass `nil` for mountPath — NetFS manages the mount point in `/Volumes` automatically for non-sandboxed apps.
- `NetFSMountURLAsync` requires Swift to see `NetFS` as an importable module. Add `NetFS.framework` to the Xcode target's "Linked Frameworks and Libraries" (not a Swift Package dependency — it is a system framework).
- In a Swift Package target, system frameworks are linked via `Package.swift` `linkerSettings`: `.linkedFramework("NetFS")`.

### Pattern 2: Keychain Internet Password (Security framework direct)

**What:** Use `kSecClassInternetPassword` to store SMB credentials keyed by (server, account).

**When to use:** Save credentials on "Test & Save", retrieve at mount time.

```swift
// Source: Apple Developer Documentation - Adding a password to the keychain
// https://developer.apple.com/documentation/security/adding-a-password-to-the-keychain
import Security

struct KeychainCredentialStore {
    static func save(server: String, account: String, password: String) throws {
        let passwordData = password.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String:       kSecClassInternetPassword,
            kSecAttrServer as String:  server,
            kSecAttrAccount as String: account,
            kSecValueData as String:   passwordData
        ]
        // Delete existing before adding (update pattern)
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    static func load(server: String, account: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String:            kSecClassInternetPassword,
            kSecAttrServer as String:       server,
            kSecAttrAccount as String:      account,
            kSecReturnData as String:       true,
            kSecMatchLimit as String:       kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            throw KeychainError.loadFailed(status)
        }
        return password
    }
}
```

**Security note:** Never store the password in `DestinationConfig` / GRDB. The `username` field in the DB is the Keychain lookup key (account). Password lives in Keychain only.

### Pattern 3: FileManager.mountedVolumeURLs for /Volumes Picker

**What:** Enumerate currently mounted volumes for the "Mounted Volume" destination type.

**When to use:** When building the volume picker in `MountedVolumeSetupView`.

```swift
// Source: Apple Developer Documentation - FileManager.mountedVolumeURLs
let volumes = FileManager.default.mountedVolumeURLs(
    includingResourceValuesForKeys: [.volumeNameKey, .volumeIsNetworkKey, .volumeIsLocalKey],
    options: [.skipHiddenVolumes]
) ?? []

// Filter to likely NAS candidates (network volumes or external drives)
// Note: local system volumes (Macintosh HD) will appear too — show all, user picks
```

### Pattern 4: Sleep/Wake Reconnection

**What:** Subscribe to `NSWorkspace.didWakeNotification` and trigger re-mount + probe for SMB destinations.

**When to use:** During `BackupCoordinator.setup()`.

```swift
// Source: Apple Developer Documentation - NSWorkspace.didWakeNotification
NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didWakeNotification,
    object: nil,
    queue: .main
) { [weak self] _ in
    Task { @MainActor [weak self] in
        await self?.destinationManager.reconnectNetworkDestinations()
    }
}
```

**What `reconnectNetworkDestinations()` does:**
1. For each `DestinationConfig` where `type == .nas`:
   - If the mount point no longer exists in `/Volumes`: re-invoke `NetFSMountURLAsync`
   - Re-run `probe()` to update status
2. For `type == .icloud` and `type == .local`: just re-run `probe()` (no mount needed)
3. Emit updated status to `@Observable` state so UI updates automatically

### Pattern 5: DestinationConfig GRDB Migration (v3)

**What:** Add SMB-specific columns without breaking existing destinations.

```swift
// Source: GRDB DatabaseMigrator docs - Schema.swift pattern established in this project
migrator.registerMigration("v3_nas_destinations") { db in
    try db.alter(table: "destination") { t in
        t.add(column: "host", .text)          // nullable — SMB only
        t.add(column: "share", .text)         // nullable — SMB only
        t.add(column: "username", .text)      // nullable — SMB key for Keychain lookup
        t.add(column: "lastConnectedAt", .datetime)  // nullable — for "last connected" display
        t.add(column: "lastErrorMessage", .text)     // nullable — for error detail view
    }
}
```

Update `DestinationConfig` struct to add optional fields with `var host: String? = nil`, etc. Since GRDB uses `Codable`, adding optional properties with defaults is backward compatible.

### Pattern 6: iCloud Drive Path

**What:** iCloud Drive is a normal directory — no special API needed for writing. The path `~/Library/Mobile Documents/com~apple~CloudDocs/` is the iCloud Drive root. User-chosen subfolders (via NSOpenPanel) work identically to any local path.

**When to use:** `iCloudDestinationAdapter` stores the user-chosen path as `rootPath` in `DestinationConfig`. The `transfer()` and `probe()` methods are identical to `LocalDestinationAdapter` — just use `FileManager`.

**Critical note:** The user-chosen path must be stored as a security-scoped bookmark if the app later sandboxes. Since this app is non-sandboxed (confirmed in STATE.md), plain path storage in `rootPath` is sufficient for Phase 4.

### Pattern 7: NSOpenPanel in SwiftUI (non-sandboxed)

```swift
// Source: Apple Developer Documentation - NSOpenPanel
func pickFolder() -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.message = "Choose a folder in iCloud Drive"
    panel.prompt = "Choose"
    return panel.runModal() == .OK ? panel.url : nil
}
```

Call from `.onAppear` or button action in SwiftUI by calling this synchronously (NSOpenPanel.runModal() is synchronous AppKit, safe from @MainActor).

### Pattern 8: Destination Status Polling

**What:** Periodic `probe()` calls update per-destination status observable. No push mechanism needed.

**Recommended interval:** 30 seconds when idle. The `DestinationManager` actor runs a repeating async timer.

```swift
// Source: established SchedulerTask pattern in this project
actor DestinationManager {
    var statuses: [String: DestinationStatus] = [:]  // keyed by destinationID

    func startPolling() {
        Task {
            while !Task.isCancelled {
                await probeAll()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }
}
```

### Anti-Patterns to Avoid

- **Storing passwords in GRDB:** `DestinationConfig.rootPath` and new `username` column are safe to store; passwords MUST stay in Keychain only.
- **Calling NetFSMountURLSync:** Documented as "do not call" — blocks the thread indefinitely on network timeout. Use `NetFSMountURLAsync` always.
- **Assuming unmount succeeds:** `NSWorkspace.unmountAndEjectDevice(at:)` fails silently or with errors. Always check error; log and continue — don't throw.
- **Calling probe() on every backup:** Check probe status from the in-memory `DestinationManager.statuses` dict first; only re-probe if status is unknown or stale.
- **Importing NetFS via Swift Package:** NetFS is a system framework, not a Swift package. Link it via Xcode target or `Package.swift` `linkerSettings`.
- **Using iCloud container API (FileManager.url(forUbiquityContainerIdentifier:)):** This requires an iCloud entitlement and App Store provisioning. The user-chosen folder picker via NSOpenPanel avoids this entirely — use plain file paths.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| SMB URL construction | String concatenation | `URLComponents` with `.scheme = "smb"` | Percent-encoding of special chars in host/share/username is mandatory and subtle |
| Credential storage | UserDefaults or GRDB | `Security.framework` `SecItemAdd`/`kSecClassInternetPassword` | Keychain encrypts at rest, survives app deletion (by design), integrates with system Lock Screen |
| Volume listing | Scanning /Volumes manually | `FileManager.default.mountedVolumeURLs(...)` | Handles edge cases (APFS snapshots, hidden volumes, boot volume) |
| Network-layer reachability | TCP ping / custom probe | `NWPathMonitor` for general network; `DestinationAdapter.probe()` for destination-specific | NWPathMonitor handles interface transitions correctly |
| Sleep/wake detection | kqueue, IOKit power management | `NSWorkspace.didWakeNotification` | Official documented API, fires after network interfaces have been re-established |

**Key insight:** All needed capabilities are in Apple system frameworks. No new SPM dependencies are required for Phase 4.

---

## Common Pitfalls

### Pitfall 1: NetFS Mount Point Collision
**What goes wrong:** If an SMB share is already mounted (from a previous session or user action), NetFSMountURLAsync returns status 0 but with the existing mount path, not a new one.
**Why it happens:** macOS silently reuses existing mounts for the same URL.
**How to avoid:** Before mounting, check `FileManager.default.mountedVolumeURLs(...)` for an existing mount matching the host/share. If found, use it directly — skip the mount call.
**Warning signs:** Mount callback receives a path already in `/Volumes` — handle both "newly mounted" and "already mounted" paths the same way.

### Pitfall 2: NetFS Callback Never Fires (Timeout)
**What goes wrong:** If the host is unreachable, `NetFSMountURLAsync` callback may not fire within a useful timeout. The default system timeout is 30-75 seconds.
**Why it happens:** NetFS has no configurable timeout parameter.
**How to avoid:** Wrap the `withCheckedThrowingContinuation` in a `Task` with `.timeoutAfter` or use `withTaskCancellationHandler`. For the "Test connection" flow, set a 10-second outer timeout.

```swift
// Apply a 10s timeout around the mount call
let mountURL = try await withTimeout(seconds: 10) {
    try await mountSMBShare(host: host, share: share, username: user, password: pass)
}
```

**Warning signs:** UI appears frozen waiting for "Test Connection" to respond.

### Pitfall 3: Password Roundtrip Through GRDB
**What goes wrong:** Developer adds `password: String?` to `DestinationConfig` to make it easy to pass around. Password ends up in SQLite on disk.
**Why it happens:** GRDB's Codable conformance serializes all struct properties automatically.
**How to avoid:** Keep `DestinationConfig.password` absent. Load credentials from Keychain at the point of use (mount time, test time). Only `username` (the Keychain account key) lives in the struct.

### Pitfall 4: iCloud Drive "Optimize Storage" Eviction
**What goes wrong:** Files written to iCloud Drive may be evicted to the cloud when local disk is low. A backup that verified successfully may later have its verification fail because the file is now a stub (`.icloud` placeholder).
**Why it happens:** macOS "Optimize Mac Storage" replaces local files with cloud stubs.
**How to avoid:** After writing to iCloud, do NOT read back for checksum verification in the same session — the file is guaranteed present immediately after write. Only re-verify in a future probe if the file is evicted, this is expected behavior. The `probe()` for iCloud should check directory existence and write access, NOT checksum re-reads.
**Warning signs:** Checksum verification fails on iCloud destination despite successful copy.

### Pitfall 5: Wake Notification Fires Before Network Is Ready
**What goes wrong:** `NSWorkspace.didWakeNotification` fires immediately on wake, but SMB servers may be unreachable for several seconds while Wi-Fi/Ethernet re-establishes.
**Why it happens:** The notification fires before network interfaces are fully up.
**How to avoid:** After receiving the wake notification, wait 3-5 seconds before attempting to remount. Use `NWPathMonitor` to detect when the network path becomes `.satisfied` before attempting mount.

```swift
// After wake notification, wait for network before remounting
let monitor = NWPathMonitor()
let stream = AsyncStream<NWPath> { cont in
    monitor.pathUpdateHandler = { cont.yield($0) }
    monitor.start(queue: .global())
}
for await path in stream {
    if path.status == .satisfied {
        monitor.cancel()
        await destinationManager.reconnectNetworkDestinations()
        break
    }
}
```

### Pitfall 6: NetFS Framework Not Found in Swift Package Target
**What goes wrong:** `import NetFS` compiles in the Xcode app target but not in the `BackupEngine` Swift package target.
**Why it happens:** Swift package targets require explicit framework linkage.
**How to avoid:** If placing `NetFSMounter.swift` in `BackupEngine` target, add to `Package.swift`:

```swift
.target(
    name: "BackupEngine",
    dependencies: [...],
    path: "Sources/BackupEngine",
    linkerSettings: [.linkedFramework("NetFS")]
)
```

Alternatively, place `NetFSMounter.swift` in the Xcode app target (not the package) and inject the mounter via protocol into `SMBDestinationAdapter`.

### Pitfall 7: BackupCoordinator Multi-Destination Job Dispatch
**What goes wrong:** Current `runBackup()` hardcodes `destinationIDs: [bootstrapDestID]`. With multiple destinations, the engine needs all active destination IDs.
**Why it happens:** Phase 2/3 bootstrap left this as a stub comment: "Phase 4+ multi-destination work will replace this".
**How to avoid:** Phase 4 must replace the bootstrap destination logic. `BackupCoordinator.runBackup()` fetches all `DestinationConfig` rows from GRDB, filters to those that are currently available (per `DestinationManager.statuses`), and passes their IDs to `BackupEngine.runJob()`.

---

## Code Examples

### Enumerating /Volumes for Mounted Volume picker

```swift
// Source: Apple Developer Documentation - FileManager.mountedVolumeURLs
// https://developer.apple.com/documentation/foundation/filemanager/1409626-mountedvolumeurls
let volumeURLs = FileManager.default.mountedVolumeURLs(
    includingResourceValuesForKeys: [
        .volumeNameKey,
        .volumeIsNetworkKey,
        .volumeIsRemovableKey,
        .volumeAvailableCapacityKey
    ],
    options: [.skipHiddenVolumes]
) ?? []

for url in volumeURLs {
    let values = try? url.resourceValues(forKeys: [.volumeNameKey, .volumeIsNetworkKey])
    let name = values?.volumeName ?? url.lastPathComponent
    let isNetwork = values?.volumeIsNetwork ?? false
    // Populate picker row
}
```

### Write-access test (probe for Mounted Volume and iCloud)

```swift
// Source: Apple Developer Documentation - FileManager.isWritableFile(atPath:)
func probeWriteAccess(at rootPath: String) -> DestinationStatus {
    var isDir: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: rootPath, isDirectory: &isDir)
    guard exists && isDir.boolValue else {
        return .unavailable(reason: "Directory not found: \(rootPath)")
    }
    guard FileManager.default.isWritableFile(atPath: rootPath) else {
        return .unavailable(reason: "No write access to: \(rootPath)")
    }
    // Attempt a sentinel write for definitive confirmation
    let probe = URL(fileURLWithPath: rootPath).appendingPathComponent(".abletonbackup_probe")
    do {
        try Data().write(to: probe)
        try FileManager.default.removeItem(at: probe)
        return .available
    } catch {
        return .unavailable(reason: "Write test failed: \(error.localizedDescription)")
    }
}
```

### NSWorkspace sleep/wake observer registration

```swift
// Source: Apple Developer Documentation - NSWorkspace.didWakeNotification
// https://developer.apple.com/documentation/appkit/nsworkspace/didwakenotification
// Register in BackupCoordinator.setup()
NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didWakeNotification,
    object: nil,
    queue: .main
) { [weak self] _ in
    Task { @MainActor [weak self] in
        guard let self else { return }
        self.logger.info("System woke from sleep — scheduling NAS reconnect")
        // Brief delay: wait for network to re-establish
        try? await Task.sleep(for: .seconds(4))
        await self.destinationManager.reconnectNetworkDestinations()
    }
}
```

### DestinationConfig struct extension for SMB fields

```swift
// Extend DestinationConfig with v3 migration optional columns
// These map to the new DB columns added in v3_nas_destinations migration
public struct DestinationConfig: Codable, Sendable {
    // ... existing fields ...
    public var host: String?                // SMB: e.g. "192.168.1.10" or "nas.local"
    public var share: String?               // SMB: e.g. "Backups"
    public var username: String?            // SMB: Keychain account key
    public var lastConnectedAt: Date?       // All types: last successful probe
    public var lastErrorMessage: String?    // All types: last probe error message
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `SMAppService` (sandboxed) restrictions on NetFS | Non-sandboxed distribution — NetFS works fully | Decided in Phase 1/2 research | Unlocks NetFS without sandbox workarounds |
| Reachability (SCNetworkReachability) | NWPathMonitor (Network.framework) | macOS 10.14 (2018) | NWPathMonitor is the modern standard; Reachability is deprecated |
| `SecKeychainAddInternetPassword` (legacy) | `SecItemAdd` with `kSecClassInternetPassword` | macOS 10.15+ (Keychain Services v2) | The legacy `SecKeychain*` functions still work but `SecItem*` is the current API |

**Deprecated/outdated:**
- `NetFSMountURLSync`: documented as "do not call" — use `NetFSMountURLAsync`
- `SecKeychainAddInternetPassword` / `SecKeychainFindInternetPassword`: legacy, use `SecItemAdd` / `SecItemCopyMatching`
- Reachability (SCNetworkReachability): use NWPathMonitor
- `NSWorkspace.getFileSystemInfo(forPath:...)`: use `URL.resourceValues(forKeys:)` instead

---

## Open Questions

1. **NetFS Swift 6 Sendable / concurrency**
   - What we know: `NetFSMountURLAsync` takes a C block callback (`NetFSMountURLBlock`). The Swift bridging accepts a Swift closure. This should be usable with `withCheckedThrowingContinuation`.
   - What's unclear: Whether the closure bridging compiles cleanly under Swift 6 strict concurrency without `@Sendable` annotation errors. The NetFS Swift interface was documented as of macOS 10.12, not updated since.
   - Recommendation: Isolate all NetFS calls in a dedicated `NetFSMounter` struct. If Swift 6 strict concurrency rejects the closure, mark it `@Sendable` or wrap in `nonisolated` function. Test compilation early in Wave 0.

2. **NFS protocol support**
   - What we know: NetFS supports both SMB and NFS; URL scheme is `nfs://` for NFS.
   - What's unclear: The locked decision says "SMB/NFS Network Drive" but the CONTEXT.md marks "SMB vs NFS protocol auto-detection or user selection" as Claude's Discretion.
   - Recommendation: Default to SMB (scheme `smb://`). Add an optional protocol selector (SMB / NFS / AFP) in the setup UI — this is a single-field change. Auto-detect based on server response is complex and not worth it for v1.

3. **iCloud Drive large file behavior at scale**
   - What we know: Chunk size is ~15MB, throttle events are brief (sub-second). Upload for very large projects (5-20 GB) can take a long time. Optimize Mac Storage can evict files.
   - What's unclear: Whether iCloud Drive write operations block the calling thread or are always asynchronous via daemon handoff.
   - Recommendation: Write via `FileManager.copyItem` (same as LocalDestinationAdapter). This returns after the file is handed to `bird` (the iCloud daemon) — it does not block until uploaded. For Phase 4 this is sufficient. Document in backup success notification that "iCloud sync may take time."

4. **DestinationManager placement in module**
   - What we know: `BackupEngine` package currently has no AppKit dependency. `DestinationManager` needs `NSWorkspace` (AppKit) for wake notifications.
   - What's unclear: Whether to put `DestinationManager` in the app target or in a new `DestinationServices` module.
   - Recommendation: Put `DestinationManager` (including NSWorkspace subscription) in the app target (`AbletonBackup/`), not in `BackupEngine`. This keeps `BackupEngine` platform-agnostic. The adapters themselves (`SMBDestinationAdapter` etc.) can live in `BackupEngine` if NetFS is linked there, or in the app target if the linker settings are complex.

---

## Sources

### Primary (HIGH confidence)
- Apple Developer Documentation — `FileManager.mountedVolumeURLs(includingResourceValuesForKeys:options:)`: https://developer.apple.com/documentation/foundation/filemanager/1409626-mountedvolumeurls
- Apple Developer Documentation — `NSWorkspace.didWakeNotification`: https://developer.apple.com/documentation/appkit/nsworkspace/didwakenotification
- Apple Developer Documentation — `NSWorkspace.unmountAndEjectDevice(at:)`: https://developer.apple.com/documentation/appkit/nsworkspace/1530469-unmountandejectdevice
- Apple Developer Documentation — `SecItemAdd`, `SecItemCopyMatching`, `kSecClassInternetPassword`: https://developer.apple.com/documentation/security/adding-a-password-to-the-keychain
- Apple Developer Documentation — `NWPathMonitor`: https://developer.apple.com/documentation/network/nwpathmonitor
- Apple Developer Documentation — `NSOpenPanel`: https://developer.apple.com/documentation/appkit/nsopenpanel
- NetFS Changes for Swift (macOS 10.12 API diffs): https://developer.apple.com/library/archive/releasenotes/General/APIDiffsMacOS10_12/Swift/NetFS.html
- Existing project code: `DestinationAdapter.swift`, `DestinationConfig.swift`, `Schema.swift`, `LocalDestinationAdapter.swift` — establishes patterns for Phase 4 adapters

### Secondary (MEDIUM confidence)
- Apple Developer Forums — "how to mount a network share in Swift": https://developer.apple.com/forums/thread/94733 — confirms `NetFSMountURLAsync` as the recommended approach, `nil` mount point for non-sandboxed
- Gist mosen/2ddf85824fbb5564aef527b60beb4669 — Swift NetFS wrapper (delegate pattern): verified the `NetFSMountURLAsync` callback signature and MountOption enum pattern
- The Eclectic Light Company — "iCloud Drive in Sonoma: Mechanisms, throttling and system limits" (March 2024): https://eclecticlight.co/2024/03/05/icloud-drive-in-sonoma-mechanisms-throttling-and-system-limits/ — chunk sizes, throttling behavior

### Tertiary (LOW confidence)
- KeychainAccess (kishikawakatsumi) — assessed as LOW confidence for Swift 6 compatibility (last release 2020): https://github.com/kishikawakatsumi/KeychainAccess — reason to use Security.framework directly
- AMSMB2 library — noted as fallback if NetFS proves unworkable; LGPL licensing concern: https://github.com/amosavian/AMSMB2

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all APIs are Apple system frameworks available on macOS 13+; no new SPM dependencies
- Architecture: HIGH — patterns follow established project conventions (DestinationAdapter protocol, GRDB migrations, actor isolation, @Observable + @MainActor)
- NetFS Swift 6 integration: LOW-MEDIUM — NetFS works outside sandbox, but Swift 6 strict concurrency closure bridging needs early compilation test
- iCloud Drive behavior at scale: LOW — write mechanics are solid; large-file timing and eviction behavior flagged as open question
- Sleep/wake reconnection: MEDIUM — NSWorkspace.didWakeNotification is well-documented; the "delay before remount" timing (3-5 seconds) is from community patterns, not official docs
- Pitfalls: MEDIUM — derived from Apple Developer Forum discussions and established project patterns

**Research date:** 2026-03-04
**Valid until:** 2026-04-04 (30 days — macOS system framework APIs are stable)
