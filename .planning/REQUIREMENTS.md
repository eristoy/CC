# Requirements: AbletonBackup

**Defined:** 2026-02-25
**Core Value:** Ableton projects are always protected across multiple locations — set it up once and never lose work again.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Project Discovery

- [ ] **DISC-01**: App auto-detects Ableton's configured Projects folder from Ableton preferences file
- [ ] **DISC-02**: User can add additional watch folders manually via settings
- [ ] **DISC-03**: User can remove watch folders from settings

### Triggers

- [ ] **TRIG-01**: App detects when an Ableton project is saved and triggers backup automatically
- [ ] **TRIG-02**: App runs backups on a user-configured schedule (interval-based)
- [ ] **TRIG-03**: User can trigger a manual backup from the menu bar

### ALS Parser

- [ ] **PRSR-01**: App parses `.als` files (gzipped XML) to extract all referenced sample paths
- [ ] **PRSR-02**: App collects samples stored outside the project folder for inclusion in backup

### Backup Engine

- [ ] **BACK-01**: App copies project folder + all collected samples to each configured destination
- [ ] **BACK-02**: Backup is incremental — unchanged files are skipped
- [ ] **BACK-03**: Each file is checksum-verified after copy to detect silent corruption
- [ ] **BACK-04**: App retains N versions per project (configurable, default: 10)
- [ ] **BACK-05**: App automatically prunes oldest versions when over limit

### Destinations

- [ ] **DEST-01**: User can configure a local attached drive destination
- [ ] **DEST-02**: User can configure a NAS destination via already-mounted Mac volume
- [ ] **DEST-03**: User can configure a NAS destination via direct SMB/NFS with stored credentials
- [ ] **DEST-04**: User can configure iCloud Drive as a destination (no auth required)
- [ ] **DEST-05**: User can configure a GitHub repository with Git LFS as a destination
- [ ] **DEST-06**: Each destination shows live availability status in settings
- [ ] **DEST-07**: NAS connection auto-reconnects after system wakes from sleep

### App & Menu Bar

- [ ] **APP-01**: App runs as a menu bar utility (no Dock icon)
- [ ] **APP-02**: Menu bar icon reflects current status (idle / running / error)
- [ ] **APP-03**: App can be configured to launch at login
- [ ] **APP-04**: Settings window covers all configuration (destinations, schedule, retention, watch folders)

### Notifications

- [ ] **NOTIF-01**: App sends macOS notification on backup completion
- [ ] **NOTIF-02**: App sends macOS notification on backup failure with error detail

### Version History

- [ ] **HIST-01**: User can view version history per project in the settings window
- [ ] **HIST-02**: Version history shows timestamp and which destinations each version exists on

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Cloud Destinations

- **DEST-v2-01**: Google Drive destination (OAuth + chunked uploads)
- **DEST-v2-02**: Dropbox destination (OAuth + SwiftyDropbox SDK)

### Restore

- **REST-v2-01**: User can restore any version to its original location
- **REST-v2-02**: User can restore any version to a user-selected folder

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Windows / Linux support | macOS-only design; system APIs (FSEvents, NSWorkspace, Keychain) are macOS-specific |
| Real-time sync | This is a backup tool, not a sync tool — different reliability model |
| Box destination | Low user priority; deferred to v3+ |
| Plugin / preset backup | Out of Ableton project scope; different problem |
| Mobile companion app | No mobile use case for project backup management |
| Full disk backup | Use Time Machine; out of scope for a project-specific tool |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| APP-01 | — | Pending |
| APP-02 | — | Pending |
| APP-03 | — | Pending |
| APP-04 | — | Pending |
| DISC-01 | — | Pending |
| DISC-02 | — | Pending |
| DISC-03 | — | Pending |
| TRIG-01 | — | Pending |
| TRIG-02 | — | Pending |
| TRIG-03 | — | Pending |
| PRSR-01 | — | Pending |
| PRSR-02 | — | Pending |
| BACK-01 | — | Pending |
| BACK-02 | — | Pending |
| BACK-03 | — | Pending |
| BACK-04 | — | Pending |
| BACK-05 | — | Pending |
| DEST-01 | — | Pending |
| DEST-02 | — | Pending |
| DEST-03 | — | Pending |
| DEST-04 | — | Pending |
| DEST-05 | — | Pending |
| DEST-06 | — | Pending |
| DEST-07 | — | Pending |
| NOTIF-01 | — | Pending |
| NOTIF-02 | — | Pending |
| HIST-01 | — | Pending |
| HIST-02 | — | Pending |

**Coverage:**
- v1 requirements: 28 total
- Mapped to phases: 0 (roadmap pending)
- Unmapped: 28 ⚠️

---
*Requirements defined: 2026-02-25*
*Last updated: 2026-02-25 after initial definition*
