# Pitfalls — AbletonBackup (macOS Backup Utility)

*Research type: Project Research — Pitfalls dimension*
*Date: 2026-02-25*
*Milestone: Greenfield*

---

## Overview

This document captures critical mistakes that macOS backup utility projects commonly make, specifically for the technology stack and problem domain of AbletonBackup: FSEvents file watching, large audio file handling, SMB/NFS network connections, OAuth token management, Git LFS, version retention/cleanup, and backup integrity verification. Each pitfall includes warning signs, a prevention strategy, and which development phase must address it.

---

## Pitfall 1: FSEvents Event Coalescing Causes Silent Missed Backups

**Domain:** File watching (FSEvents)

### What Goes Wrong

FSEvents is a directory-level watcher, not a file-level watcher. When Ableton saves a project, it may write multiple files in rapid succession (the `.als` file, associated audio renders, temporary lock files). macOS coalesces FSEvents notifications when events arrive faster than the latency you configure. If your latency is set too high (e.g., 15 seconds) you may miss intermediate saves; if set too low the event stream floods and you get duplicate backup triggers. Projects also routinely write to nested subdirectories — `Samples/Processed/`, `Samples/Recorded/` — and FSEvents watches are recursive by default, but **the callback receives a directory path, not the specific file that changed**. Teams frequently assume they receive file paths and build logic on top of that incorrect assumption.

The second failure mode is the **event history gap after sleep/wake**: FSEvents provides a `since` token (`kFSEventStreamEventIdSinceNow` vs. a stored event ID). If the app crashes or the machine sleeps and you restart watching without replaying from the stored event ID, you silently miss all changes that happened while the watcher was down.

### Warning Signs

- Backup log shows the correct number of watch events but the backup timestamp does not match the most recent Ableton save timestamp
- Test: save a project rapidly five times in 2 seconds; only one backup triggers
- After sleep/wake test, files modified during sleep are not backed up on next wake
- Console shows FSEvents callback firing on the root watch directory rather than the changed subdirectory

### Prevention Strategy

1. Store the last-seen `FSEventStreamEventId` to persistent storage (UserDefaults or SQLite) after each callback. On startup, create the stream with `kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents` and pass the stored event ID so missed events are replayed.
2. Use `kFSEventStreamCreateFlagFileEvents` (available macOS 10.7+) to get per-file notifications instead of directory-level notifications. This is the single most important flag.
3. Use a **debounce window of 3–5 seconds** after the last event before triggering backup. Ableton's save is multi-file; the debounce absorbs the burst.
4. After wake from sleep (observe `NSWorkspace.didWakeNotification`), force a full scan of the watch folders comparing modification timestamps against the last backup timestamp — do not rely solely on the event replay catching everything.
5. Never derive "which file changed" from the directory path in the callback without `kFSEventStreamCreateFlagFileEvents`. With that flag set, the paths array contains actual file paths.

**Phase:** Core file watching infrastructure (Phase 1 / foundations). Must be correct before any other feature is built on top of it.

---

## Pitfall 2: Loading Entire Large Audio Files Into Memory

**Domain:** Large audio file handling

### What Goes Wrong

The most common mistake in backup tools handling multi-GB files is reading the entire source file into a `Data` buffer before writing it to the destination. On a project with a 4 GB sample library this exhausts available memory, triggers memory pressure kills on low-RAM Macs, and blocks the main thread if the copy is not properly backgrounded. A second mistake is using `FileManager.copyItem(at:to:)` for large files — it is a synchronous, blocking call that holds a file descriptor open for the entire duration and gives no progress feedback.

A subtler issue: **copying a file while Ableton still has it open for writing** produces a corrupt backup. Ableton does not use POSIX advisory locks; you cannot detect this via `flock`. The file appears fully readable but may contain an incomplete or inconsistent state mid-save.

### Warning Signs

- Memory footprint of the backup process spikes above 500 MB during a backup run
- UI becomes unresponsive or menu bar icon freezes during backup of large projects
- Progress indicator jumps from 0% to 100% with no intermediate updates
- Backups of very recent saves occasionally fail to open in Ableton

### Prevention Strategy

1. Use `FileHandle` with chunked reads (4–8 MB chunks) or use `sendfile(2)` via `copyfile(3)` (the C function, not `FileManager`). On macOS, `copyfile` with `COPYFILE_ALL` uses the kernel's optimized copy path and supports progress callbacks via `copyfile_callback_t`.
2. Run all file I/O on a dedicated `DispatchQueue` with `.background` QoS and a `.serial` quality to avoid concurrent large file reads exhausting I/O bandwidth.
3. Use `URLResourceValues` to read `fileSizeKey` before copying; if the file is above a threshold (e.g., 100 MB) switch to the chunked/copyfile path automatically.
4. To avoid copying mid-save files: after the FSEvents debounce fires, check whether the `.als` file's modification date is still advancing by sampling it twice 500 ms apart. If the mtime is still changing, wait another debounce cycle. For sample files, check that no process has the file open using `lsof` programmatically (via `proc_pidinfo` syscall) — though this is complex; the debounce approach is usually sufficient since Ableton saves atomically to a temp file then renames.
5. Expose a `Progress` object for each backup operation and bind it to the UI so users see real progress.

**Phase:** File copy engine (Phase 1). Must be addressed before the first end-to-end backup test with real projects.

---

## Pitfall 3: SMB/NFS Connections Silently Stale After Sleep/Wake

**Domain:** NAS/network destinations

### What Goes Wrong

macOS mounts SMB shares under `/Volumes/`. After the Mac sleeps, the kernel marks the mounted volume as stale but does not unmount it. When the app wakes and tries to write to `/Volumes/MyNAS/Backups/`, the first `FileManager` call blocks for 20–90 seconds (the SMB timeout) before returning an error — or worse, succeeds silently by writing to a stale inode that is discarded on reconnect. Apps that cache the volume path string and assume it is always valid fall into this trap.

For direct SMB connections (not auto-mounted via Finder), the URLSession-based `SMBClient` or third-party libraries commonly fail to re-authenticate after token expiry or after a network interface change (WiFi → Ethernet), leaving the connection object in a permanently broken state that never surfaces an error until the next write attempt.

A third failure: using synchronous `FileManager` calls on the main thread to check network reachability — these block the menu bar app's UI thread.

### Warning Signs

- After sleep test: first backup after wake takes over 30 seconds or hangs indefinitely
- Log shows "backup succeeded" but files are absent on the NAS share
- App is unresponsive for 30+ seconds after wake before showing a backup error
- Network interface change (VPN connect/disconnect) causes backup to silently write to wrong destination

### Prevention Strategy

1. On `NSWorkspace.didWakeNotification`, proactively unmount and remount NAS volumes (or mark them as requiring re-validation) before the next backup attempt.
2. Before any write operation to a network destination, perform a **lightweight reachability probe**: attempt to stat a small sentinel file (`.ableton-backup-probe`) on the destination. Set a short timeout (3 seconds). If it fails, trigger reconnection before the backup starts, not during it.
3. All network I/O — including the reachability probe — must run on background threads. Use `async/await` with structured concurrency and actor isolation to enforce this.
4. For direct SMB connections, implement an exponential backoff reconnection loop triggered on wake or on connection error. Never assume a connection object is valid across a sleep cycle; always re-establish.
5. Distinguish between "destination unreachable" (NAS offline — skip and notify user) and "destination temporarily unavailable" (just woke up — retry with backoff). Surface both states clearly in the menu bar icon and notifications.
6. For NFS, use soft mounts with explicit `timeo` and `retrans` options when mounting programmatically; hard mounts with no timeout will hang the process indefinitely on network loss.

**Phase:** Network destination implementation (Phase 2). Reconnection logic must be built in from the start — retrofitting it after the fact is error-prone.

---

## Pitfall 4: OAuth Token Management Done Wrong for Cloud APIs

**Domain:** Google Drive and Dropbox OAuth

### What Goes Wrong

The most common mistake is storing OAuth access tokens and refresh tokens in `UserDefaults` or in a plist file on disk. Both are readable by any process with user-level access and are included in Time Machine backups and iCloud Drive sync — leaking credentials. The correct store is the macOS Keychain.

A second mistake: **not handling token refresh proactively**. Access tokens expire (Google Drive: 1 hour; Dropbox: depends on configuration, but short-lived tokens are common). Apps that only refresh on a 401 response cause the following failure mode: a backup starts, uploads 90% of a large file, receives a 401 on a subsequent chunk, fails the entire upload, and must restart from zero. Uploading a 2 GB file and failing at 90% with no resumable upload support causes user-visible backup failures on every hourly backup.

A third mistake: **performing the OAuth authorization flow inside the backup worker**, which blocks the backup queue waiting for user interaction.

A fourth mistake: not requesting the minimum required OAuth scopes. Requesting broad scopes (`https://www.googleapis.com/auth/drive` instead of `https://www.googleapis.com/auth/drive.file`) fails App Store review and makes users correctly suspicious.

### Warning Signs

- Credentials found in `~/Library/Preferences/*.plist` or UserDefaults database
- Backup fails consistently after the first hour of the app being open
- Large file uploads to Google Drive fail with 401 mid-upload and restart from zero
- OAuth popup appears unexpectedly in the middle of a scheduled backup
- App Store review rejection citing overly broad OAuth scopes

### Prevention Strategy

1. Store **all** OAuth tokens (access token, refresh token, expiry date) exclusively in the macOS Keychain using `SecItemAdd`/`SecItemUpdate` with `kSecAttrAccessible = kSecAttrAccessibleAfterFirstUnlock`. Never write tokens to UserDefaults, files, or NSUbiquitousKeyValueStore.
2. Implement **proactive token refresh**: before any API call, check if the access token expires within the next 5 minutes. If so, refresh it first. Use a dedicated serial actor to serialize token refresh so concurrent backup tasks do not trigger parallel refresh races.
3. For large file uploads, use the **resumable upload APIs** that both Google Drive and Dropbox provide. Google Drive's resumable upload session URL is valid for a week. Store the session URI in the Keychain or a local database so interrupted uploads can resume after a crash or token expiry without restarting.
4. Separate the OAuth authorization flow (user interaction, runs on main thread, can block) from the backup worker (background, never blocks on user input). Use a state machine: `unauthenticated → authorizing → authenticated → tokenExpired → refreshing`. Only the `unauthenticated` state requires user interaction.
5. Request minimum scopes: Google Drive — `drive.file` (access only to files created by this app); Dropbox — `files.content.write` + `files.content.read` scoped to the app folder.
6. Handle the case where a refresh token is revoked by the user (e.g., from the Google account security page): detect the `invalid_grant` error, clear stored tokens, and surface a clear "Re-authorize Google Drive" notification.

**Phase:** Cloud destination implementation (Phase 2). Token architecture must be established on day one of cloud integration — refactoring from UserDefaults to Keychain after the fact risks token loss for existing users.

---

## Pitfall 5: Git LFS Misuse for Large Audio Binaries

**Domain:** Git LFS for GitHub destination

### What Goes Wrong

The most common mistake is treating the GitHub destination as a normal git repository and attempting to `git add` multi-GB `.wav` and `.aif` files without LFS tracking configured. This hits GitHub's 100 MB file size limit immediately and produces push errors that are confusing to non-developer users ("this file is over 100.00 MB").

A second mistake is **configuring LFS after initial commit**. If even one commit lands in git history containing a large binary without LFS, that binary is permanently in the pack file and `git lfs migrate import` must be run to rewrite history — which invalidates all remote refs and requires a force-push to fix. On a shared repository this is catastrophic.

A third mistake: **assuming `git lfs` is installed on the user's machine**. Most Ableton producers are not developers. The app cannot shell out to `git lfs` as an external dependency — it must bundle its own implementation or use a library.

A fourth mistake: **not understanding LFS storage quotas**. GitHub's free tier includes 1 GB of LFS storage and 1 GB/month bandwidth. A single Ableton project with samples can exceed this. Users hit quota limits silently (LFS push succeeds but subsequent clones fail), and the app shows no warning.

A fifth mistake: storing the GitHub Personal Access Token or OAuth token in the git credential store (plaintext in `~/.git-credentials`) rather than the Keychain.

### Warning Signs

- First push attempt fails with "this file exceeds GitHub's file size limit"
- `git log --all --full-history -- '*.wav'` shows large binaries in non-LFS objects
- App shells out to `git` and `git-lfs` binaries and fails on clean macOS installs (no Xcode or Homebrew)
- User reports "can't clone the backup repo" despite pushes appearing to succeed
- GitHub Personal Access Token found in `~/.git-credentials`

### Prevention Strategy

1. Initialize **every** GitHub backup repository with a `.gitattributes` file that tracks all audio formats via LFS **before the first commit**:
   ```
   *.wav filter=lfs diff=lfs merge=lfs -text
   *.aif filter=lfs diff=lfs merge=lfs -text
   *.aiff filter=lfs diff=lfs merge=lfs -text
   *.mp3 filter=lfs diff=lfs merge=lfs -text
   *.flac filter=lfs diff=lfs merge=lfs -text
   *.ogg filter=lfs diff=lfs merge=lfs -text
   *.m4a filter=lfs diff=lfs merge=lfs -text
   *.alc filter=lfs diff=lfs merge=lfs -text
   *.adg filter=lfs diff=lfs merge=lfs -text
   ```
   Commit this file as the **initial commit** before any audio files are added.
2. Bundle `git` and `git-lfs` as embedded binaries within the app bundle (or use `libgit2` + a pure-Swift LFS implementation). Do not depend on system-installed git tooling.
3. Before each push, query the GitHub API for LFS storage usage (`GET /repos/{owner}/{repo}` and check LFS quota via the billing API or storage quota headers). Warn the user proactively when they are above 80% of their quota.
4. Store GitHub tokens in the macOS Keychain, never in git credential helpers or plaintext files.
5. Enforce a maximum file size check before staging to git: files above 50 MB must go through LFS. Files above 2 GB should be flagged as potentially exceeding LFS limits and warned to the user before upload.
6. For the initial repository setup wizard, display the LFS storage pricing prominently so users understand the cost model before committing to this destination.

**Phase:** GitHub destination implementation (Phase 2). The `.gitattributes` bootstrap is a one-time setup action that must be done correctly; it cannot be fixed without rewriting git history.

---

## Pitfall 6: Version Retention Cleanup Race Conditions and Data Loss

**Domain:** Version retention / cleanup

### What Goes Wrong

The most common mistake is implementing cleanup (pruning old versions beyond the configured N) as a post-backup step that runs immediately after a successful backup. The race condition: if the app crashes during cleanup after deleting version N+1 but before confirming version N was written correctly, the user ends up with fewer versions than configured and potentially a corrupted newest version as the only remaining copy.

A second mistake: **cleaning up versions across all destinations simultaneously**. If Google Drive cleanup fails halfway through (network error) and local cleanup succeeded, the local destination has fewer versions than the remote. The user's apparent redundancy is false.

A second common mistake is implementing version numbering as a simple counter in a plist or UserDefaults without atomic updates. Concurrent backup triggers (e.g., user triggers manual backup while scheduled backup is running) corrupt the counter and produce duplicate or missing version numbers.

A third mistake: **purging versions that are currently being restored**. If the user opens the version browser and starts a restore, a background cleanup job running concurrently can delete the version they are restoring mid-copy.

### Warning Signs

- After a crash during backup, version count on disk is fewer than the configured minimum
- Manual backup triggered while scheduled backup runs produces version numbering gaps
- User reports "the file I was restoring disappeared"
- Version listing shows gaps in sequence numbers (e.g., v1, v2, v5 — v3 and v4 missing)
- Cloud destination has different number of versions than local destination for the same project

### Prevention Strategy

1. Use a **write-then-cleanup** pattern with a commit log: before deleting any old version, write a "pending deletion" record to a local SQLite database. Only delete when the new version is fully verified (see Pitfall 7). After deletion succeeds, mark the record complete. On startup, check for incomplete deletions and resolve them.
2. Implement a **version lock mechanism**: before cleanup, check if any version is currently being read (restore in progress). Use a lightweight SQLite table `version_locks(version_id, locked_since)` that the restore operation writes to and cleanup respects.
3. Perform cleanup on each destination **independently** with independent error handling. A cleanup failure on cloud does not roll back local cleanup — but both are logged and surfaced. Never treat cleanup as atomic across destinations.
4. Use a serial actor (Swift concurrency) or serial `DispatchQueue` for all version metadata operations. Manual and scheduled backups contend for the same version counter; serialize them with a queue rather than a lock to avoid deadlocks.
5. Never delete a version until the backup integrity check (Pitfall 7) passes for the new version. The lifecycle is: `backing-up → verifying → verified → (cleanup old versions)`.
6. Store version metadata (timestamps, checksums, file counts) in SQLite, not in plist files. SQLite's WAL mode provides atomic writes even on crash.

**Phase:** Version management (Phase 1 for data model; Phase 2 for cleanup logic). The SQLite schema must be designed before the first backup is written.

---

## Pitfall 7: Backup Integrity Verification Is an Afterthought

**Domain:** Backup integrity verification

### What Goes Wrong

The most common — and most dangerous — mistake is treating a successful file copy as a verified backup. File copy operations can silently produce corrupt output due to: storage media errors (bit rot on cheap drives), network interruption on SMB/cloud upload that is not properly detected, filesystem bugs (APFS transaction aborts), and macOS Spotlight/antivirus intercepting file writes mid-copy.

A second mistake: using file size comparison as the only integrity check. A truncated copy (network drop mid-upload) has a different size — but a storage corruption replacing bytes with zeros produces a file with the **same size** and a different checksum that size-only checks miss.

A third mistake: **never verifying integrity on read** (restore). Projects are backed up but the restore path is never tested. Users discover their backups are corrupt only when they need them most.

A fourth mistake: computing checksums synchronously in the backup worker, blocking the next backup from starting. On a project with 10 GB of samples, SHA-256 computation at disk I/O speeds (~500 MB/s on modern SSDs) takes 20 seconds — long enough to delay the next scheduled backup.

### Warning Signs

- Backup log shows "success" but restored project fails to open in Ableton
- No checksum or hash is stored in the backup manifest
- Restore operation copies files without re-verifying checksums
- Integrity check is only run when the user explicitly requests it (not automatically)
- Large backup jobs delay subsequent scheduled backups by minutes

### Prevention Strategy

1. Compute a **per-file checksum** (xxHash for speed, or SHA-256 for strong guarantees) during the copy operation itself — read each chunk, write it, and feed the same bytes to the hasher. This adds near-zero overhead versus a separate post-copy read pass.
2. Store a **backup manifest** for each version: a JSON or SQLite record containing `{relative_path, size_bytes, checksum, mtime_source, mtime_backup}` for every file in the backup. The manifest is written atomically after all files are copied.
3. After completing a backup, verify the manifest against the destination by re-reading each file and comparing checksums. Run this verification on a low-priority background queue so it does not block subsequent backups. If verification fails, mark the backup version as `corrupt` in the database and notify the user.
4. On **restore**, always re-verify checksums against the manifest before declaring success. Never restore a version marked `corrupt`.
5. Implement a **periodic background integrity scan** (e.g., weekly) that re-verifies all stored backup manifests against current destination contents. This catches bit rot and silent corruption that occurred after the initial backup.
6. For network destinations (SMB, cloud), verify the file size after upload as a minimum check. For cloud destinations, use the API's returned ETag or content hash (Google Drive provides `md5Checksum` in the file metadata; Dropbox provides `content_hash`) and compare against the locally computed hash.
7. Define a clear backup lifecycle state machine: `pending → copying → copy_complete → verifying → verified | corrupt`. Only `verified` backups are eligible for restore or version count enforcement.

**Phase:** Phase 1 (local backup integrity) and Phase 2 (cloud/network integrity). Integrity checking must be designed into the data model from the first backup operation — retrofitting it means re-verifying all existing backups or discarding their trustworthiness.

---

## Summary Table

| # | Pitfall | Domain | Phase to Address |
|---|---------|--------|-----------------|
| 1 | FSEvents coalescing / missed events after sleep | File watching | Phase 1 — Foundations |
| 2 | Loading large audio files into memory | File copy engine | Phase 1 — Foundations |
| 3 | SMB/NFS stale connections after sleep/wake | Network destinations | Phase 2 — Network |
| 4 | OAuth tokens in wrong storage / no proactive refresh | Cloud auth | Phase 2 — Cloud |
| 5 | Git LFS misconfiguration / external dependency | GitHub destination | Phase 2 — Cloud |
| 6 | Version cleanup race conditions and data loss | Version management | Phase 1 (schema) / Phase 2 (cleanup) |
| 7 | Backup integrity never verified | Core backup | Phase 1 — Foundations |

---

*Generated: 2026-02-25*
