# AbletonBackup

## What This Is

A macOS menu bar application that automatically backs up Ableton Live projects — including all referenced audio samples — to multiple destinations simultaneously. It implements a 3-2-1 backup strategy: at least one attached local drive, a NAS, and one or more cloud providers. The app runs silently in the background with a menu bar icon for status and a settings window for configuration.

## Core Value

Ableton projects are always protected across multiple locations — set it up once and never lose work again.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] Auto-detect Ableton's default Projects folder; user can add additional watch folders
- [ ] Watch for Ableton file saves and trigger backup automatically
- [ ] Schedule-based backups (configurable interval: hourly, daily, etc.)
- [ ] Manual backup trigger from menu bar
- [ ] Back up full project folder including all referenced samples
- [ ] Local attached storage as a backup destination (required, always at least one)
- [ ] NAS destination supporting both: mounted Mac volumes AND direct SMB/NFS connection with credentials
- [ ] Cloud destinations: iCloud Drive, Google Drive, Dropbox, GitHub (Git LFS for large audio)
- [ ] All backup destinations are configurable (add/remove/edit)
- [ ] Keep N versions per project (configurable, e.g. last 10 backups)
- [ ] Browse version history and restore any project version
- [ ] Menu bar icon showing backup status (idle, running, error)
- [ ] macOS native notifications for backup complete and errors
- [ ] Settings window for configuring destinations, schedules, and version retention

### Out of Scope

- Windows/Linux — macOS only for now
- Box — deferred to v2
- Real-time sync — this is backup, not mirroring
- Mobile companion app — not needed

## Context

- Built for personal use by an Ableton Live producer frustrated with manual backups and the risk of losing projects
- Ableton projects can be large (samples/audio files routinely GBs); the backup system must handle large files efficiently
- GitHub destination requires Git LFS for audio files to avoid repository size limits
- iCloud Drive is natively mounted on macOS — no extra auth needed; Google Drive and Dropbox require OAuth
- NAS connection may need to handle reconnection on wake from sleep

## Constraints

- **Platform**: macOS only — target macOS 13+ (Ventura) for modern APIs
- **File size**: Must handle projects with multi-GB sample libraries without blocking the UI
- **Reliability**: Backup failures must surface clearly — silent failures are worse than no backup

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Menu bar + settings window | Fits macOS conventions for background utilities; minimal friction | — Pending |
| Include samples in backup | A project without its samples is unrestorable | — Pending |
| Git LFS for GitHub destination | Audio files too large for standard git; LFS is the standard solution | — Pending |
| N-version retention per project | Protects against accidentally saving bad state; configurable so users control storage usage | — Pending |

---
*Last updated: 2026-02-25 after initialization*
