# Features Research: macOS Backup Utilities & DAW Project Backup Tools

**Project**: AbletonBackup
**Research type**: Features — table stakes vs differentiators
**Date**: 2026-02-25
**Milestone**: Greenfield

---

## Research Summary

This document catalogs features across the macOS backup utility landscape (Time Machine, Carbon Copy Cloner, ChronoSync, Arq, Backblaze) and DAW/audio-specific backup tools (Ableton's built-in Collect All and Save, Live Grab, session archivers), then maps what is table stakes vs. differentiating for a focused Ableton Live project backup tool.

---

## Tools Surveyed

### macOS Backup Utilities

| Tool | Model | Backup Style |
|------|-------|-------------|
| Time Machine | Apple, free | Incremental, local/NAS |
| Carbon Copy Cloner (CCC) | Bombich, paid | Clone + incremental, local/NAS |
| ChronoSync | Econ Technologies, paid | Sync + backup, local/NAS/cloud |
| Arq Backup | Arq, paid | Versioned backup, local/cloud |
| Backblaze | Backblaze, subscription | Continuous cloud backup |
| Restic / Duplicati | Open source, free | Versioned, local/cloud |

### DAW/Audio-Specific Tools

| Tool | Notes |
|------|-------|
| Ableton Live — Collect All and Save | Built-in; copies all referenced samples into the project folder. Does not back up off-machine. |
| Live Grab (third-party script) | Scans Ableton project files and gathers samples. No versioning, no destination management. |
| Session archiver scripts | Various community tools; usually zip + timestamp. No multi-destination, no cloud. |
| Logic Pro — Project Alternatives | Apple's built-in "save alternate" system. Versioning within one folder, no off-machine backup. |
| Git + Git LFS (manual) | Used by technically advanced producers; no UI, requires CLI, steep learning curve. |
| Time Machine (general-purpose) | Backs up everything; no Ableton awareness; backs up samples only if they're in the TM-included path. |

---

## Feature Catalog

### A. File Detection & Triggering

| Feature | Who has it | Notes |
|---------|------------|-------|
| Watch folder for changes | CCC (SafetyNet triggers), ChronoSync (folder watch), Arq | Standard in paid tools |
| FSEvents / file-change triggering | CCC, ChronoSync, Arq | macOS-native; low-overhead |
| Ableton save-event detection | Nobody (gap) | Ableton writes `.als` on save; FSEvents catches this |
| Configurable watch delay (debounce) | ChronoSync | Prevents mid-save partial backups |
| Schedule-based trigger (hourly, daily) | All major tools | Cron-style or built-in scheduler |
| Manual trigger | All major tools | Always a "Back Up Now" button |
| Launch at login | All major tools | LaunchAgent / login item |

### B. Source Understanding (Ableton-Specific)

| Feature | Who has it | Notes |
|---------|------------|-------|
| Parse `.als` file to find referenced samples | Nobody in the backup space (gap) | ALS is gzip'd XML; parseable |
| Resolve absolute vs. relative sample paths | Nobody in backup space (gap) | Ableton uses both; must handle both |
| Include samples outside the project folder | Nobody automated (gap) | Huge pain point: samples scattered across system |
| "Collect All and Save" awareness | Only Ableton itself | Built-in; no backup destination |
| Handle missing/offline samples gracefully | Nobody | Need to warn, not silently fail |
| Detect project folder structure (`.als` + `Samples/` + `Presets/`) | Nobody outside Ableton | Known structure; straightforward |

### C. Destination Management

| Feature | Who has it | Notes |
|---------|------------|-------|
| Local attached drive | All tools | Absolute baseline |
| NAS via mounted volume | All tools | Treats as local path |
| NAS via SMB/NFS with credentials | CCC, ChronoSync, Arq | Direct protocol; survives volume unmount |
| iCloud Drive | Arq (partial), ChronoSync | Native mount = easy; iCloud throttles |
| Google Drive | Arq, Backblaze (not natively) | OAuth required |
| Dropbox | Arq | OAuth or local sync folder |
| GitHub / Git LFS | No backup tools; only developer tools | High complexity; requires LFS for audio |
| Multiple simultaneous destinations | Arq, ChronoSync | Differentiating for general tools; core here |
| Destination health check | Arq, CCC | Verify destination is reachable before backup |
| Destination capacity warning | CCC, Arq | Alert before disk fills |

### D. Versioning & Retention

| Feature | Who has it | Notes |
|---------|------------|-------|
| Keep N versions per source | Arq, CCC, ChronoSync | Configurable count |
| Keep versions by age (last 30 days) | Time Machine, Arq | Date-based pruning |
| Keep versions by storage cap | Arq | Size-based pruning |
| Grandfathering (daily/weekly/monthly) | Arq | Sophisticated retention policies |
| Per-project version count | Nobody — gap | General tools apply one policy globally |
| Version browsing UI | Time Machine (iconic), CCC, Arq | Time Machine UI is the gold standard |
| Restore single file from version | All major tools | Expected |
| Restore entire project version | All major tools | Expected |
| Diff/compare between versions | None in backup space | Git does this; gap for audio tools |

### E. Status & Observability

| Feature | Who has it | Notes |
|---------|------------|-------|
| Menu bar icon (idle/running/error) | CCC, Arq, Backblaze | Standard for background utilities |
| Menu bar dropdown with last-backup time | CCC, Arq, Backblaze | Expected |
| macOS native notifications | All modern tools | NSUserNotification / UNUserNotification |
| Detailed backup log | CCC, ChronoSync, Arq | File-level log of what was copied |
| Error surfacing (don't fail silently) | CCC (explicit errors), Arq | Critical; silent failure = false confidence |
| Email notifications on failure | Arq, ChronoSync | For power users / enterprise |
| Progress indicator during backup | CCC, Arq | Useful for large transfers |
| Estimated time remaining | CCC | Nice to have |
| Per-destination status | Arq | Which destinations succeeded/failed independently |

### F. Settings & Configuration

| Feature | Who has it | Notes |
|---------|------------|-------|
| Native settings window | All tools | macOS Settings/Preferences pattern |
| Add/remove/edit destinations | All tools | Expected |
| Schedule configuration | All tools | Expected |
| Retention policy configuration | Arq, CCC | Expected for versioned tools |
| Exclude patterns (file types, folders) | CCC, ChronoSync, Arq | Glob/regex excludes |
| Include additional folders beyond default | CCC, ChronoSync | Expected |
| First-run setup wizard | Arq, Backblaze | Reduces friction |
| Import/export settings | ChronoSync | Power-user feature |

### G. Performance & Efficiency

| Feature | Who has it | Notes |
|---------|------------|-------|
| Incremental backup (copy only changed files) | All serious tools | Critical for large projects |
| Deduplication (block-level) | Arq | Reduces storage; complex to implement |
| Compression | Arq, Restic | Good for text files; audio is already compressed |
| Encryption at rest | Arq, Backblaze | Required for cloud; optional for local |
| Bandwidth throttling for cloud | Arq, Backblaze | Prevents network saturation |
| Background priority (low CPU/IO) | CCC, Arq | Use QoS background priority on macOS |
| Large file chunking | Arq | Required for cloud APIs with size limits |
| Parallel destination writes | Arq | Speed up 3-2-1 multi-destination |
| Resume interrupted backups | Arq, Restic | Important for large files |

### H. Restore

| Feature | Who has it | Notes |
|---------|------------|-------|
| Browse version history in app | CCC, Arq, Time Machine | Expected |
| One-click restore to original location | All tools | Expected |
| Restore to alternate location | CCC, Arq | Useful for inspection without overwriting |
| Restore individual files | All tools | Expected |
| Restore entire project | All tools | Expected |
| Preview file before restoring | Time Machine (Finder QuickLook) | Nice to have |
| Restore across destination types | Arq | Restore from whichever destination is available |

---

## Feature Classification for AbletonBackup

### Table Stakes (Must Have — Users Leave Without These)

These are the baseline. Any backup tool that lacks these is not viable.

| Feature | Complexity | Rationale |
|---------|------------|-----------|
| Watch Ableton Projects folder for saves (FSEvents) | Low | Core trigger mechanism; without this it's manual-only |
| Incremental backup (copy only changed files) | Medium | Projects with large sample libraries are multi-GB; full copy every time is unusable |
| Local attached drive as destination | Low | Required anchor of 3-2-1 strategy |
| Keep N versions per project (configurable) | Medium | Protects against "saved bad state" — the most common Ableton disaster |
| Browse version history and restore | Medium-High | A backup with no restore UI is useless |
| Menu bar icon with status (idle/running/error) | Low | macOS convention for background utilities; users need at-a-glance confidence |
| macOS native notifications (complete + error) | Low | Expected on macOS |
| Error surfacing — never fail silently | Low | False confidence is worse than no backup |
| Settings window (destinations, schedule, retention) | Medium | Without this it's not configurable |
| Launch at login | Low | A backup tool that requires manual launch is not a backup tool |
| Schedule-based backup (hourly/daily) | Low | Safety net if FSEvents trigger is missed |
| Manual "Back Up Now" trigger | Low | Users always want an escape hatch |

### Differentiators (Competitive Advantage Over General Tools)

These are what make AbletonBackup worth using instead of Time Machine or Arq.

| Feature | Complexity | Rationale | Dependency |
|---------|------------|-----------|------------|
| Parse `.als` file to resolve all referenced sample paths | High | The core insight: backing up the project folder misses samples stored elsewhere. No general backup tool does this. | Requires gzip + XML parsing of ALS format |
| Collect referenced samples scattered outside the project folder | High | Samples on external drives, in user sample libraries, in factory content — all included automatically | Depends on ALS parsing |
| NAS via direct SMB/NFS with credentials (not just mounted volume) | Medium | Survives sleep/wake without volume unmount; general backup tools that need a mounted volume break here | Requires network credential storage in Keychain |
| Multiple simultaneous destinations (local + NAS + cloud) | Medium | 3-2-1 strategy in one tool; no general tool makes this easy and Ableton-aware | Parallel write architecture |
| Per-destination status (which destinations succeeded/failed independently) | Low-Medium | If iCloud is slow but local succeeded, user should know; don't report "backup failed" when local worked | Depends on multi-destination |
| Auto-detect Ableton Projects folder; add additional watch folders | Low | First-run "just works" experience; no configuration needed for the default case | LaunchAgent + FSEvents |
| GitHub destination with Git LFS for audio | Very High | Version control semantics (meaningful commits, diffs) for producers who want that; no tool offers this | Requires git + git-lfs CLI, LFS server setup |
| Warn on missing/offline samples before backup completes | Medium | Proactive: tells user a sample couldn't be found rather than silently backing up an incomplete project | Depends on ALS parsing |

### Nice-to-Have (Build Later, Not Now)

| Feature | Complexity | Rationale |
|---------|------------|-----------|
| Bandwidth throttling for cloud destinations | Medium | Useful but not day-1 critical |
| Backup encryption | Medium-High | Good for cloud; Arq and Backblaze do this; deferred until cloud destinations land |
| Resume interrupted backups | Medium | Important for very large projects; implement after basic cloud works |
| Detailed file-level backup log | Low | Power user feature; useful for debugging |
| Email/webhook notifications on failure | Medium | Useful for users with multiple machines; not day-1 |
| Import/export settings | Low | Nice for reinstall scenarios |
| First-run setup wizard | Medium | Reduces friction; can start with just settings window |
| Storage usage dashboard per destination | Medium | Useful but not critical |
| Compare project versions (what changed?) | Very High | Would require ALS diffing; v3+ feature |
| iCloud/Google Drive/Dropbox OAuth destinations | Medium-High | Cloud matters but start with local + NAS to validate core |

---

## Anti-Features (Deliberately NOT Build)

These are things to consciously avoid, either because they expand scope unsustainably, create user harm, or dilute the core value proposition.

| Anti-Feature | Reason to Avoid |
|-------------|----------------|
| Real-time sync / mirroring | This is backup, not sync. Real-time sync creates consistency problems (partial saves, in-progress files) and is a different product category. |
| Windows / Linux support | Platform-specific APIs (FSEvents, NSUserNotification, Keychain, SMB framework) are deep throughout the stack. Cross-platform means rewriting everything. macOS-first is the constraint. |
| DAW-agnostic "universal" mode | Tempting but wrong. The ALS parser is the core differentiator. Supporting Logic, Pro Tools, etc. means maintaining multiple project parsers with no validation from a single user. |
| Cloud storage service itself | Don't build S3-compatible storage. Use existing cloud destinations. |
| Mobile companion app | No restore scenario requires a phone. Adds an entire platform for marginal benefit. |
| Collaboration / sharing | Sharing projects is a different workflow (Splice, shared Dropbox). Don't conflate backup with collaboration. |
| Plugin / preset backup | Plugins require installers to restore; preset backup without plugin management is incomplete. Out of scope — back up the project, not the DAW installation. |
| Live performance set backup | `.als` sets vs. `.alp` projects have different restoration workflows. Sets reference Ableton's own library; projects are self-contained. Start with projects only. |
| Block-level deduplication | Extremely complex to implement correctly; audio files don't deduplicate well (binary, already compressed). File-level deduplication (don't copy unchanged files) is sufficient. |
| Backup of Ableton's own library / factory content | These are reinstallable. Backing them up wastes space and misrepresents the problem. Back up user-created content only. |

---

## Feature Dependencies Map

```
FSEvents watch
  └── Debounce/delay
        └── Trigger: ALS file parsing
              ├── Resolve sample paths (relative + absolute)
              │     └── Warn on missing samples
              └── Determine project folder contents
                    └── Incremental file copy engine
                          ├── Local destination write
                          ├── NAS destination write (SMB/NFS)
                          │     └── Keychain credential storage
                          │           └── Reconnect on wake
                          └── Cloud destination write
                                ├── iCloud (local path, no auth)
                                ├── Google Drive / Dropbox (OAuth)
                                └── GitHub + Git LFS (CLI subprocess)

Version retention
  └── Pruning engine (keep N per project)
        └── Version history browser UI
              └── Restore engine
                    ├── Restore to original location
                    └── Restore to alternate location

Menu bar icon
  ├── Status polling (idle / running / error)
  ├── Per-destination status
  └── macOS notifications (complete + error)

Settings window
  ├── Destination add/remove/edit
  ├── Watch folder configuration
  ├── Schedule configuration
  └── Retention policy configuration

LaunchAgent (login item)
  └── Requires all of the above to be stable
```

---

## Key Observations

1. **The ALS parser is the moat.** Every general-purpose backup tool treats the Ableton project folder as a folder. The insight — that samples are often scattered outside it — is what makes this tool different. Everything else is execution.

2. **Silent failure is the enemy.** Producers discover their backups failed when they need to restore, not before. Every failure path must surface clearly. This is a cultural constraint, not just a technical one.

3. **The 3-2-1 multi-destination model is genuinely uncommon in a single tool.** Time Machine is local only. Backblaze is cloud only. Arq does multi-destination but with no Ableton awareness. The combination is the differentiator.

4. **GitHub/Git LFS is the highest-complexity destination.** It requires git and git-lfs installed, LFS server configuration, and a mental model shift (commits, not just file copies). Ship last; validate everything else first.

5. **The restore experience is as important as the backup.** Users don't think about backups until they need to restore. A backup tool with a clunky restore UI fails the most important moment.

---

*Research based on: Time Machine (Apple), Carbon Copy Cloner 6/7 (Bombich Software), ChronoSync 5 (Econ Technologies), Arq 7 (Arq Software), Backblaze Personal Backup, Restic, Ableton Live 11/12 project format documentation, and community knowledge of DAW backup workflows.*
