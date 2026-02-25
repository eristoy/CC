# Stack Research: AbletonBackup

**Domain:** macOS menu bar backup utility for Ableton Live projects
**Research date:** 2026-02-25

---

## Recommended Stack

### Language & Runtime

| Choice | Rationale | Confidence |
|--------|-----------|------------|
| **Swift 6** | Native macOS, best system API access, modern concurrency (async/await, actors) ideal for concurrent backup transfers | High |
| Xcode 16+ | Required for Swift 6, macOS 15 SDK | High |

**Not:** Python/Electron — no native macOS feel, sandboxing friction, poor menu bar integration.

---

### UI Framework

| Layer | Choice | Rationale |
|-------|--------|-----------|
| Menu bar | **SwiftUI `MenuBarExtra`** (macOS 13+) | Native API, avoids AppKit boilerplate, targets Ventura+ |
| Settings window | **SwiftUI + `Settings` scene** | Declarative, matches macOS conventions |
| System integration | **AppKit where needed** | `NSWorkspace` (sleep/wake), `NSStatusItem`, `NSOpenPanel` |

**Pattern:** ~70% SwiftUI for views, ~30% AppKit for system hooks. Use `NSMenu` + `NSHostingView` for the menu bar popover to get native dismiss behavior.

**Not:** Electron, Catalyst, or pure AppKit — too much boilerplate or wrong platform.

---

### File Watching

| Choice | Rationale | Confidence |
|--------|-----------|------------|
| **FSEvents** (`FSEventStream`) via `CoreServices` | Native macOS API, no known scale limits, works well for directory hierarchies | High |
| Wrapper: **FSWatcher** (okooo5km/FSWatcher) | Swift-native, DispatchSource-based, supports file type/size filtering | Medium |

**Key behavior:** FSEvents coalesces rapid saves — you'll get one event for multiple quick saves. This is fine for backup use cases. For individual file events, use `kFSEventStreamCreateFlagFileEvents`.

---

### Backup Destinations

#### Local / Mounted Volumes (attached drives, iCloud Drive, mounted NAS)
- **Foundation `FileManager`** — direct file copy with `copyItem(at:to:)`
- **`URLSession` background transfers** for large files (non-blocking)
- iCloud Drive path: `~/Library/Mobile Documents/com~apple~CloudDocs/` — no auth needed, treat as local

#### NAS via SMB/NFS

| Choice | Rationale | Confidence |
|--------|-----------|------------|
| **NetFS.framework** | Apple's native API for mounting SMB/NFS shares programmatically | High |
| Shell: `mount_smbfs` / `open smb://...` | Fallback; simpler but less control | Medium |

**Note:** SMB shares reliably disconnect on sleep. Use `NSWorkspace.shared.notificationCenter` to observe `NSWorkspace.didWakeNotification` and auto-remount.

#### Dropbox

| Choice | Rationale | Confidence |
|--------|-----------|------------|
| **SwiftyDropbox** (official SDK) | Official Dropbox Swift SDK for API v2, handles OAuth, chunked uploads | High |
| Dropbox REST API directly | More control, fewer dependencies | Medium |

SwiftyDropbox supports macOS OAuth via external browser redirect — the standard pattern for desktop apps.

#### Google Drive

| Choice | Rationale | Confidence |
|--------|-----------|------------|
| **Google APIs Swift Client** or direct REST | Google's SDK is heavyweight; lightweight REST client preferred | Medium |
| **swift-google-drive-client** (darrarski) | Lightweight, no Google SDK dependency, uses URLSession | High |

Use `ASWebAuthenticationSession` for OAuth on macOS.

#### GitHub (Git LFS)

| Choice | Rationale | Confidence |
|--------|-----------|------------|
| **Shell out to `git` + `git-lfs`** | Most reliable; libgit2 has limited LFS support | High |
| `Process` / `AsyncStream` for git output | Swift's `Process` class wraps shell commands cleanly | High |

Require `git` and `git-lfs` to be installed (Homebrew). Detect on startup and guide user to install if missing.

---

### Credentials & Auth

| Choice | Rationale |
|--------|-----------|
| **Keychain (`SecItem`)** | Store OAuth tokens, NAS passwords — macOS standard, encrypted at rest |
| `ASWebAuthenticationSession` | OAuth web flow for Google Drive, Dropbox — macOS native |

---

### Persistence (Backup History & Metadata)

| Choice | Rationale | Confidence |
|--------|-----------|------------|
| **Core Data** | Native macOS, good for structured backup history, version tracking | High |
| **SQLite via GRDB.swift** | Lighter weight, excellent Swift API, easier migrations | Medium |

GRDB.swift recommended for simplicity. Core Data for deeper Apple ecosystem integration.

---

### Concurrency

| Choice | Rationale |
|--------|-----------|
| **Swift Concurrency** (`async/await`, `actor`, `TaskGroup`) | Native, safe for concurrent destination writes |
| `OperationQueue` | Backup job queue with concurrency limits |

Use `actor` for destination adapters to prevent concurrent write conflicts.

---

### Sandboxing

**Decision:** Distribute outside Mac App Store initially to avoid sandbox restrictions on:
- Arbitrary file system access (user's Ableton project folders)
- Network mounts (SMB)
- Shell commands (git, git-lfs)

If App Store distribution is later desired: use **Security-Scoped Bookmarks** for folder access.

---

## What NOT to Use

| Option | Why Not |
|--------|---------|
| Electron | No native macOS feel, poor menu bar integration |
| Python/Node.js | No macOS system API access without bridging |
| libgit2 | Poor LFS support; shell is more reliable |
| AFP | Removed from macOS (2025); use SMB only |
| Google Drive for Desktop SDK | Too heavyweight; direct REST API preferred |

---

## Dependencies Summary

```
SwiftyDropbox         — Dropbox SDK (official)
swift-google-drive-client — Google Drive REST client
GRDB.swift            — SQLite persistence
FSWatcher (optional)  — FSEvents wrapper
```

System tools required (check on startup):
```
git (Homebrew)
git-lfs (Homebrew)
```
