# Phase 4: Network Destinations - Context

**Gathered:** 2026-03-04
**Status:** Ready for planning

<domain>
## Phase Boundary

Users can configure NAS (via mounted volume or direct SMB/NFS) and iCloud Drive as backup destinations, with live per-destination status on the main screen and reliable sleep/wake reconnection. Backup engine integration and scheduling are handled by prior phases.

</domain>

<decisions>
## Implementation Decisions

### Destination types & picker
- Three distinct destination types: "Mounted Volume", "SMB/NFS Network Drive", "iCloud Drive"
- Destination picker groups them: **Cloud** (iCloud Drive) and **Network** (Mounted Volume, SMB/NFS)
- User selects a type, then completes type-specific setup

### NAS — SMB/NFS setup
- Structured fields: Host, Share name, Username, Password (not URL-style entry)
- Credentials stored in Keychain
- **Test connection required before saving** — destination not created until connection succeeds

### NAS — Mounted Volume setup
- Picker from volumes currently mounted in /Volumes
- No credential entry (already authenticated by OS)
- Test connection required before saving (verifies write access)

### iCloud Drive setup
- User chooses destination folder via macOS folder picker (not a fixed app container)
- Test connection/write-access check required before saving — same pattern as NAS
- No authentication step (uses system iCloud account)

### Destination status on main screen
- **Colored dot** per destination (green = online, red = error/offline)
- **Last backup time + result** shown per destination: e.g., "NAS • Last backup: 2h ago • Success" or "NAS • Last backup: 5h ago • Failed"
- iCloud uses same three-state dot as NAS (no special syncing state)

### Error detail & recovery
- Tapping a red dot navigates to destination settings
- Destination settings shows: error message + **Retry Now button** + last connected time
- No auto-retry when destination comes back online — user triggers retry manually

### Failure behavior during backup
- If destination goes offline **mid-backup**: fire a system notification AND update in-app state to show failure
- If destination is offline **at backup start**: skip that destination, complete backup to remaining available destinations (partial success is valid)

### Claude's Discretion
- Exact dot size, color values, and animation (pulse on syncing?)
- How Keychain prompts are presented for credential updates
- SMB vs NFS protocol auto-detection or user selection
- Retry logic internals (timeout, error classification)

</decisions>

<specifics>
## Specific Ideas

- Destination setup follows a consistent pattern across all types: configure → test → save
- Main screen is the primary place to see health at a glance — not buried in Settings

</specifics>

<deferred>
## Deferred Ideas

- None — discussion stayed within phase scope

</deferred>

---

*Phase: 04-network-destinations*
*Context gathered: 2026-03-04*
