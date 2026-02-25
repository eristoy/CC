# Project Research Summary

**Project:** AbletonBackup
**Domain:** macOS menu bar background utility — DAW project backup
**Researched:** 2026-02-25
**Confidence:** HIGH

## Executive Summary

AbletonBackup is a native macOS menu bar utility that automatically backs up Ableton Live projects to multiple destinations (local disk, NAS, iCloud, Google Drive, Dropbox, GitHub). The product domain is well-understood: macOS backup utilities follow established patterns (LSUIElement agent app, FSEvents file watching, concurrent destination workers), and the technology choices — Swift 6, SwiftUI MenuBarExtra, FSEvents, GRDB.swift — are all high-confidence picks with strong official documentation. The architecture research identifies a clean 11-component design with a clear build order, meaning no major architectural unknowns remain before implementation begins.

The core differentiation from general-purpose backup tools (Time Machine, Arq, CCC) is the ALS file parser. Ableton Live's `.als` project file is gzip-compressed XML that references samples by absolute path — samples frequently stored outside the project folder in user libraries, on external drives, or in factory content folders. No existing backup tool resolves these external references and includes them in the backup. This insight, combined with multi-destination 3-2-1 backup in a single Ableton-aware tool, is the moat. Everything else is competent execution of well-documented macOS patterns.

The most critical risks are in the foundations, not the differentiators. Incorrect FSEvents event handling (missing the `kFSEventStreamCreateFlagFileEvents` flag, no event-ID persistence across sleep) will produce silent missed backups. Skipping per-file checksum verification will produce confident-but-corrupt backups — exactly the failure mode that destroys user trust in a backup tool. Both of these must be built correctly in Phase 1 before any user-facing features are added. The GitHub/Git LFS destination is a separate high-complexity concern that should ship last.

## Key Findings

### Recommended Stack

Swift 6 with Xcode 16+ is the unambiguous choice: native macOS API access, Swift Concurrency (actors, TaskGroup) for safe concurrent multi-destination writes, and SwiftUI MenuBarExtra for the menu bar popover. The pattern is ~70% SwiftUI for views, ~30% AppKit for system hooks (NSWorkspace for sleep/wake, NSStatusItem). Python, Electron, and Catalyst are explicitly ruled out — they lack the system API access required for FSEvents, NetFS, and Keychain integration.

Persistence uses GRDB.swift (SQLite) rather than Core Data: lighter weight, explicit schema, type-safe Swift API, and WAL mode for crash-safe atomic writes. Credentials go exclusively in the macOS Keychain. The GitHub destination requires bundling `git` and `git-lfs` binaries (not relying on system-installed tools) and official SDKs for Dropbox (SwiftyDropbox) and Google Drive (swift-google-drive-client).

**Core technologies:**
- **Swift 6 + Xcode 16**: Language and runtime — native macOS APIs, modern concurrency, no viable alternative
- **SwiftUI MenuBarExtra**: Menu bar UI — avoids AppKit boilerplate, targets macOS 13+ (Ventura)
- **FSEvents (`FSEventStreamCreate`)**: File watching — kernel-level, recursive, coalesced; correct tool for directory watching
- **GRDB.swift**: Persistence — type-safe SQLite, WAL mode, simple migrations, no ORM overhead
- **Swift Concurrency (actor + TaskGroup)**: Concurrency — safe concurrent destination writes, structured cancellation
- **NetFS.framework**: NAS/SMB mounts — Apple native API for authenticated SMB/NFS, survives sleep/wake
- **SwiftyDropbox + swift-google-drive-client**: Cloud SDKs — official OAuth and chunked upload handling
- **ASWebAuthenticationSession**: OAuth flow — native macOS web auth for Google Drive and Dropbox
- **Keychain (SecItem)**: Credential storage — required for all tokens and passwords; never UserDefaults
- **APFS cloning (`copyfile` with `COPYFILE_CLONE`)**: Local copies — near-instantaneous, copy-on-write

### Expected Features

The feature research surveyed Time Machine, Carbon Copy Cloner, ChronoSync, Arq, Backblaze, and Ableton-specific tools. No existing tool combines Ableton project awareness (ALS parsing, external sample collection) with multi-destination backup and a native macOS UI.

**Must have (table stakes):**
- FSEvents watch on Ableton Projects folder — core trigger mechanism
- Incremental backup (copy only changed files) — projects with large sample libraries are multi-GB
- Keep N versions per project with configurable retention — primary recovery scenario
- Version history browser and restore UI — a backup with no restore UI is useless
- Menu bar icon with idle/running/error states — macOS convention for background utilities
- macOS native notifications (complete + error) — never fail silently
- Settings window (destinations, schedule, retention) — required for configurability
- Launch at login — a tool requiring manual launch is not a backup tool
- Schedule-based backup (hourly/daily) and manual "Back Up Now" trigger

**Should have (competitive differentiators):**
- Parse `.als` XML to resolve all referenced sample paths (including external/scattered samples) — the core moat; no general tool does this
- Multiple simultaneous destinations with per-destination status — 3-2-1 in one Ableton-aware tool
- NAS via direct SMB/NFS with Keychain credentials (not just mounted volume) — survives sleep/wake
- Warn on missing/offline samples before backup completes — depends on ALS parsing
- Auto-detect Ableton Projects folder on first run — "just works" experience

**Defer (v2+):**
- GitHub/Git LFS destination — highest complexity, requires bundled git binaries, LFS quota management
- Cloud destinations (Google Drive, Dropbox) — ship after local + NAS are validated
- Bandwidth throttling, encryption, resume interrupted backups
- First-run setup wizard (start with settings window)
- Compare project versions (ALS diffing) — v3+ feature

**Anti-features (consciously excluded):**
- Real-time sync/mirroring — different product category
- Windows/Linux support — platform-specific APIs throughout
- DAW-agnostic mode — ALS parser is the moat; supporting other DAWs dilutes it
- Plugin/preset backup — requires installer management; out of scope

### Architecture Approach

The app runs as an LSUIElement (agent process — no Dock icon) with two UI surfaces: an NSStatusItem menu bar icon and a SwiftUI settings window. All background work (file watching, scheduling, backup transfers) runs off the main thread using Swift Concurrency. The BackupEngine is a Swift `actor` that serializes job management while individual destination transfers run concurrently via `TaskGroup`. A central `AppState` observable object bridges the engine to the UI without coupling them directly.

**Major components:**
1. **App Shell (AppDelegate + NSStatusItem)** — LSUIElement entry point, system event observation (sleep/wake, network), menu bar icon lifecycle
2. **File Watcher (FSEvents)** — watches configured project folders, debounces rapid saves, emits "project changed" events
3. **Backup Scheduler (Timer)** — interval-based triggers independent of file changes; coordinates with engine to avoid overlapping jobs
4. **Backup Engine (actor)** — orchestrates job: Project Resolver → Version Manager → Transfer Dispatcher → Result Aggregator
5. **Project Resolver / File Collector** — walks project folder, optionally parses ALS XML for external sample references
6. **Destination Workers (protocol-based)** — Local Disk, NAS/SMB, iCloud Drive, Google Drive, Dropbox, GitHub/Git LFS; each encapsulates its transport
7. **Version Manager** — assigns version IDs, enforces retention policy, provides version list for restore
8. **Persistence Layer (GRDB/SQLite)** — stores configuration and backup history; Keychain for credentials
9. **AppState (@Observable)** — observable state bridge between engine and UI
10. **Settings Window (SwiftUI)** — watch folders, destinations, schedule, retention, version history + restore
11. **Notification Center (UNUserNotification)** — surfaces backup complete, failure, destination unreachable

### Critical Pitfalls

1. **FSEvents without `kFSEventStreamCreateFlagFileEvents` + no event-ID persistence** — Use the file-events flag for per-file paths (not just directory paths); persist the last `FSEventStreamEventId` to SQLite so missed events are replayed after sleep/crash; implement 3-5 second debounce to absorb Ableton's multi-file save burst

2. **Backup integrity never verified** — Compute per-file checksums (xxHash) inline during copy (zero overhead); write a backup manifest per version; verify manifest against destination after backup; define a `pending → copying → copy_complete → verifying → verified | corrupt` lifecycle; only `verified` versions are eligible for restore or pruning

3. **Version cleanup race conditions** — Use write-then-cleanup pattern with SQLite commit log (write "pending deletion" before deleting; clear after confirmed); implement version locks for in-progress restores; serialize version metadata operations via a Swift actor; never prune until new version is `verified`

4. **SMB/NFS connections silently stale after sleep** — On `NSWorkspace.didWakeNotification`: proactively probe destination with a lightweight sentinel file stat (3s timeout); rebuild NAS connections before backup; distinguish "offline" (skip + notify) from "temporarily unavailable" (retry with backoff); all network I/O on background threads

5. **OAuth tokens in wrong storage / no proactive token refresh** — Store all tokens exclusively in Keychain; proactively refresh access tokens 5 minutes before expiry via a serial token-refresh actor; use resumable upload APIs (Google Drive session URIs valid for 1 week) so interrupted uploads resume without restart; separate OAuth auth flow (main thread) from backup worker (background)

6. **Git LFS misconfiguration** — Initialize `.gitattributes` with all audio format LFS tracking as the first commit before any files; bundle `git` + `git-lfs` binaries in the app (do not depend on system install); proactively check GitHub LFS quota before push; store tokens in Keychain only

## Implications for Roadmap

Based on the architecture research's explicit build order and the pitfalls' phase assignments, a five-phase structure is recommended. The architecture file identifies clear dependency relationships; this roadmap follows them.

### Phase 1: Foundation — Backup Core (No UI)

**Rationale:** The persistence schema, file copy engine, version management, and integrity verification have no external dependencies and must be correct before anything is built on top of them. Pitfalls 2, 6, and 7 all land here — building them wrong means retrofitting later with possible data loss.

**Delivers:** A working, tested backup system for local destinations. Triggerable via unit test or CLI target. No UI.

**Addresses:**
- Incremental backup (copy only changed files)
- Keep N versions per project
- Local attached drive as destination
- Backup integrity verification (manifest + checksum)

**Avoids:**
- Pitfall 2: Large file streaming with `copyfile` + chunked reads; APFS cloning for speed
- Pitfall 6: SQLite schema with version lifecycle states; write-then-cleanup pattern
- Pitfall 7: Per-file xxHash checksums inline during copy; backup manifest per version

**Research flag:** Standard patterns. SQLite + GRDB, FileManager, copyfile — all well-documented. No research phase needed.

---

### Phase 2: App Shell + File Watching + Basic Menu Bar

**Rationale:** The app shell, FSEvents watcher, and status item depend on the backup engine being functional. This phase produces the first runnable app — watching files and backing them up to local disk, with status visible in the menu bar.

**Delivers:** A functional v0. Runs as LSUIElement, watches Ableton Projects folder via FSEvents, backs up to local disk on save, shows status in menu bar, sends notifications. Launch at login.

**Addresses:**
- FSEvents watch (save-event trigger)
- Menu bar icon with idle/running/error states
- macOS notifications (complete + error)
- Schedule-based backup and manual trigger
- Launch at login

**Avoids:**
- Pitfall 1: `kFSEventStreamCreateFlagFileEvents` flag; event-ID persistence in SQLite; 3-5s debounce; post-wake forced scan

**Research flag:** Well-documented macOS patterns. LSUIElement, NSStatusItem, FSEvents, LaunchAgent — all standard. No research phase needed.

---

### Phase 3: Settings Window + Restore UI

**Rationale:** Until settings are configurable and restore works, the app is not user-ready. This phase makes the tool configurable and completes the backup/restore loop — the minimum viable product.

**Delivers:** Full settings window (watch folders, local destination, schedule, retention); version history browser; restore to original and alternate locations.

**Addresses:**
- Settings window (destinations, schedule, retention)
- Browse version history and restore
- Error surfacing throughout

**Research flag:** Standard SwiftUI patterns. No research phase needed.

---

### Phase 4: Network Destinations (NAS + iCloud)

**Rationale:** Local backup is validated first. NAS and iCloud are the next most common backup targets for home studio producers. They share file-copy semantics with local disk (FileManager), making them lower complexity than OAuth cloud APIs. SMB reconnection logic is isolated here.

**Delivers:** NAS via SMB/NFS with Keychain credentials; iCloud Drive as local-path destination; per-destination status in menu bar.

**Addresses:**
- NAS via direct SMB/NFS with credentials
- Multiple simultaneous destinations with per-destination status
- iCloud Drive destination (no auth, treat as local path)

**Avoids:**
- Pitfall 3: Sleep/wake reconnection; sentinel probe before backup; exponential backoff; background-only I/O

**Research flag:** NetFS.framework is moderately complex. May benefit from a targeted research spike on macOS 15 NetFS API and SMB reconnection behavior during planning.

---

### Phase 5: Cloud Destinations (Dropbox, Google Drive)

**Rationale:** OAuth cloud destinations share authentication patterns (ASWebAuthenticationSession, Keychain token storage, chunked uploads) but are independent of NAS. They ship after NAS/iCloud to allow validating the multi-destination architecture with simpler destinations first.

**Delivers:** Dropbox and Google Drive destinations with OAuth, chunked/resumable uploads, bandwidth awareness.

**Addresses:**
- Google Drive and Dropbox as backup destinations
- Cloud destination health checking and capacity warnings

**Avoids:**
- Pitfall 4: Keychain-only token storage; proactive refresh actor; resumable upload sessions; minimum OAuth scopes; revoked-token detection

**Research flag:** Resumable upload APIs and OAuth scope requirements are cloud-provider-specific. A targeted research spike is recommended during planning for each provider's current chunked upload API.

---

### Phase 6: ALS Parser + External Sample Collection

**Rationale:** This is the core differentiator — but it requires the backup engine, destination workers, and version manager to be stable first. It is a self-contained enhancement to the Project Resolver component. Building it early would block on having a working backup system to test against.

**Delivers:** Parsing of `.als` (gzip+XML) to resolve all referenced sample paths, including samples stored outside the project folder. Warnings for missing/offline samples.

**Addresses:**
- Parse `.als` to resolve external sample paths — the core moat
- Warn on missing/offline samples before backup

**Research flag:** ALS format is undocumented officially but well-understood in the community. A targeted research spike into the ALS XML schema (gzip decompression + `SampleRef` element structure) is strongly recommended during planning.

---

### Phase 7: GitHub / Git LFS Destination

**Rationale:** Highest complexity destination. Requires bundled git binaries, LFS quota management, and a distinct mental model (commits, not file copies). Ships last after all other destinations are stable.

**Delivers:** GitHub as a backup destination using Git LFS for audio files; LFS quota monitoring; bundled git + git-lfs binaries.

**Avoids:**
- Pitfall 5: `.gitattributes` as initial commit before any audio files; bundled binaries; proactive LFS quota check; Keychain-only token storage

**Research flag:** Research phase strongly recommended. LFS storage quota API, bundled binary approach for macOS, and GitHub OAuth app vs. PAT tradeoffs all need validation.

---

### Phase Ordering Rationale

- **Foundations before UI** (Phases 1-2): The backup engine must be correct before building UI on top. A corrupt engine with a beautiful UI is a liability for a backup tool.
- **Local before network** (Phase 2-3 before Phase 4): File-copy semantics are identical; validates multi-destination architecture before adding network complexity.
- **NAS before cloud** (Phase 4 before Phase 5): NAS uses FileManager (familiar); cloud adds OAuth and chunked APIs (new complexity tier).
- **Core before differentiator** (Phases 1-5 before Phase 6): The ALS parser enhances a working backup system rather than being a dependency of it.
- **GitHub last** (Phase 7): Independent, highest complexity, lowest percentage of target users. Failure here doesn't affect other destinations.

### Research Flags

Phases needing deeper research during planning:
- **Phase 4 (NAS):** NetFS.framework reconnection behavior on macOS 15; soft NFS mount options via programmatic mount
- **Phase 5 (Cloud):** Google Drive and Dropbox current resumable upload APIs and chunked upload size limits; minimum OAuth scope validation
- **Phase 6 (ALS Parser):** ALS XML schema (SampleRef elements, absolute vs. relative path encoding); Ableton 11 vs. 12 format differences
- **Phase 7 (GitHub/LFS):** Bundled git binary approach; LFS quota API; GitHub OAuth app vs. PAT for desktop apps

Phases with standard patterns (skip research phase):
- **Phase 1 (Foundation):** GRDB, FileManager, copyfile, xxHash — all well-documented
- **Phase 2 (App Shell):** LSUIElement, FSEvents, NSStatusItem, LaunchAgent — established macOS patterns
- **Phase 3 (Settings + Restore):** SwiftUI WindowGroup, GRDB queries — standard patterns

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All choices verified against official Apple documentation and established Swift community practice; no experimental APIs |
| Features | HIGH | Feature survey is comprehensive across 6+ competing tools; table stakes and differentiators are well-supported by competitive analysis |
| Architecture | HIGH | Component design follows well-established macOS menu bar utility patterns; build order has clear dependency rationale |
| Pitfalls | HIGH | Each pitfall is documented with specific warning signs and prevention strategies drawn from known macOS API behavior |

**Overall confidence:** HIGH

### Gaps to Address

- **ALS format validation:** The ALS XML schema is based on community documentation and reverse engineering, not Ableton's official documentation (which doesn't exist publicly). The parser implementation should be validated against real Ableton 11 and 12 projects across different configurations before shipping Phase 6.
- **Sandboxing decision:** The architecture research recommends distributing outside the Mac App Store initially to avoid sandbox restrictions on arbitrary file system access, NetFS, and shell commands. This is a distribution decision that affects FSEvents bookmark handling and should be confirmed before Phase 2.
- **Concurrent job limit:** If the user has many watch folders and projects change simultaneously, a concurrent job limit policy needs to be defined. The architecture raises this as an open question. Define during Phase 2 planning.
- **iCloud throttling behavior:** The features research notes iCloud throttles large file uploads. The practical impact on large sample libraries (5-20 GB projects) needs validation during Phase 4.
- **GitHub LFS quota UX:** The LFS quota problem (1 GB free tier vs. multi-GB audio projects) has no clean solution. The UX for communicating quota limits and upgrade paths needs design work before Phase 7.

## Sources

### Primary (HIGH confidence)
- Apple Developer Documentation — FSEvents API, NSStatusItem, NSWorkspace, NetFS.framework, UserNotifications, Security.framework (Keychain), SwiftUI MenuBarExtra, LSUIElement
- Swift Concurrency documentation — actor, TaskGroup, async/await patterns
- GRDB.swift official documentation — SQLite WAL mode, Swift API
- Ableton Live project format (gzip+XML) — community documentation and format analysis
- macOS backup utility survey — Time Machine (Apple), Carbon Copy Cloner 6/7, ChronoSync 5, Arq 7, Backblaze Personal Backup, Restic

### Secondary (MEDIUM confidence)
- SwiftyDropbox (official Dropbox Swift SDK) — OAuth, chunked uploads
- swift-google-drive-client (darrarski) — lightweight Google Drive REST client, no Google SDK dependency
- Community documentation on Ableton `.als` format XML structure and SampleRef elements
- FSWatcher (okooo5km) — Swift-native FSEvents wrapper with filtering

### Tertiary (LOW confidence)
- GitHub LFS storage quota API behavior — needs validation during Phase 7 planning
- iCloud large file throttling behavior at scale — needs validation during Phase 4
- macOS 15-specific NetFS reconnection behavior — needs validation during Phase 4

---
*Research completed: 2026-02-25*
*Ready for roadmap: yes*
