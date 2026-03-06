# Phase 5: ALS Parser - Research

**Researched:** 2026-03-06
**Domain:** Ableton Live Set (.als) file format parsing, XML path rewriting, gzip decompression, Swift Foundation XML APIs
**Confidence:** HIGH (core XML structure), MEDIUM (exact Collect All folder naming, Live 11+ path format details)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Missing sample warnings**
- Parse the `.als` file before the file-copy phase begins; fire the notification before any writing occurs
- Warning is a macOS notification: count only — "3 samples missing from ProjectName" (consistent with existing backup result notifications)
- Backup proceeds automatically — no blocking or user confirmation required
- Tapping the notification opens the backup history entry for that project (not a separate sheet), where the user can see the full missing path list

**Sample discovery scope**
- **External = anything whose path is outside the project folder.** If the sample path isn't under the `.als` project directory, it's collected.
- Samples already inside the project folder are not touched — Phase 1 already copies them
- If the `.als` cannot be parsed (corrupted, future format, gzip failure): proceed with plain folder backup (Phase 1 behavior) and fire a notification: "Could not parse .als — external samples not included"
- Offline/unmounted drives: treat missing samples the same as any missing file — add to warning count, skip, proceed
- Nested `.als` files (Live Sets referencing other Live Sets): not followed — top-level `.als` only

**Backup file layout**
- Use Ableton's **"Collect All and Save" layout**: external samples copied into `Samples/Imported/` inside the backup project folder
- The backed-up `.als` is rewritten to use **relative paths** pointing to the new `Samples/Imported/` location, making the backup self-contained (open anywhere, Ableton finds the samples)
- Filename collisions resolved by **preserving the full original path as a subfolder structure** under `Samples/Imported/` (e.g. `Samples/Imported/Users/eric/Music/Drums/kick.wav`) — no renames, no collisions, paths always unique
- Internal samples (already inside project folder) are left as-is

**History & transparency**
- Backup history entry records: **collected count + full list of paths** AND **missing count + full list of missing paths**
- History rows with missing samples show a **warning badge/icon** so incomplete backups are scannable at a glance
- Detail view (drill-down on a history row) shows both lists: collected samples and missing samples
- This is the same view the user lands on when tapping a "samples missing" notification

### Claude's Discretion
- XML parsing library choice (XMLDocument / XMLParser / third-party — no user preference)
- Exact notification copy beyond the pattern established above
- Warning badge visual design (color, icon style)
- Whether `.als` path rewriting happens in-memory before writing or as a post-process step

### Deferred Ideas (OUT OF SCOPE)
- None — discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| PRSR-01 | App parses `.als` files (gzipped XML) to extract all referenced sample paths | ALS format confirmed as gzip-compressed XML; XMLDocument + zlib decompress approach identified; FileRef/SampleRef element structure documented |
| PRSR-02 | App collects samples stored outside the project folder for inclusion in backup | External sample detection via `Path Value` attribute vs project folder prefix; copy to `Samples/Imported/` with full-path subfolder structure; `.als` path rewriting documented |
</phase_requirements>

---

## Summary

Ableton Live `.als` files are gzip-compressed XML documents. The format has been consistent in its core structure across versions 8 through 12. To find sample references, the parser walks the XML looking for `SampleRef/FileRef` element groups. Each `FileRef` contains a `Path` element with a `Value` attribute holding the absolute file path (Live 11+), and a `RelativePath` element with a `Value` attribute for the relative path. "External" means the absolute path does not start with the project directory — these samples are copied into `Samples/Imported/` in the backup.

After copying external samples into the backup, the `.als` file itself must be rewritten: the `Path Value` and `RelativePath Value` attributes for each collected sample are updated to point to the new `Samples/Imported/` location. The rewritten XML is then gzip-compressed and written to the backup destination alongside the copied samples. This mirrors Ableton's own "Collect All and Save" workflow, making the backup self-contained.

The existing project uses `XMLDocument` (Foundation) with XPath queries already (`AbletonPrefsReader.swift` parses `Library.cfg` this way). The same approach applies here. Gzip decompression can be done with the system `zlib` library (available on macOS without extra packages) via `import zlib` and `inflateInit2_` with `MAX_WBITS + 32` to handle gzip format auto-detection. Re-compression uses `deflateInit2_` targeting gzip output. No new third-party packages are needed.

**Primary recommendation:** Implement `ALSParser` as a pure-Foundation struct in `BackupEngine` using system `zlib` for decompression/recompression and `XMLDocument` for XPath-based sample path extraction. The ALS mutation (path rewriting) happens in-memory on the parsed XMLDocument before writing the recompressed file to the backup destination.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Foundation `XMLDocument` | Built-in (macOS 10.4+) | Parse decompressed ALS XML, XPath queries, attribute mutation | Already used in project (`AbletonPrefsReader.swift`); full XPath + tree mutation support |
| System `zlib` | Built-in (macOS, Darwin) | Gzip decompress/recompress the `.als` file | No SPM dependency needed; `import zlib` works directly; `inflateInit2_` supports gzip auto-detect |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `Foundation.FileManager` | Built-in | Copy external samples, create `Samples/Imported/` directories | All file I/O in the copy step |
| `UserNotifications` | Built-in | Missing-sample warning notification | Already used in `NotificationService.swift` |
| GRDB | 7.x (existing) | Persist collected/missing sample lists in `backupVersion` metadata or new table | Schema migration for new columns |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| System `zlib` | GzipSwift (1024jp/GzipSwift) | GzipSwift is cleaner API but adds another SPM dependency; system zlib is ~30 lines of code, zero new dependency |
| System `zlib` | `(Data as NSData).decompressed(using: .zlib)` | Apple's `.zlib` algorithm is DEFLATE, not gzip — it strips the gzip header; cannot be used for `.als` which is true gzip (RFC 1952) |
| Foundation `XMLDocument` | `XMLParser` (SAX) | SAX is more memory-efficient for huge files but `.als` files are typically <1 MB uncompressed; XMLDocument + XPath is far simpler to implement correctly |
| Foundation `XMLDocument` | Fuzi / SwiftyXML | Adds SPM dependencies for no real gain; XMLDocument already handles full XPath |

**Installation:** No new packages required. The gzip decompressor uses `import zlib` (system library). The XML parser uses `import Foundation`.

---

## Architecture Patterns

### Recommended Project Structure

```
Sources/BackupEngine/
├── ALS/
│   ├── ALSParser.swift          # Decompress + parse XML, extract sample paths
│   ├── ALSRewriter.swift        # Mutate XMLDocument, recompress, write to destination
│   └── SampleCollection.swift   # Result type: collected + missing lists
├── BackupEngine.swift           # Calls ALSParser before file-copy phase
├── BackupJob.swift              # Extended: SampleCollection in BackupJobResult
└── Persistence/
    └── Schema.swift             # v3 migration: collected/missing columns on backupVersion
```

### Pattern 1: Gzip Decompress → XMLDocument Parse

**What:** Load the `.als` file as raw Data, decompress with zlib, parse with `XMLDocument`
**When to use:** At the start of every backup job that includes a `.als` file

```swift
// Source: Derived from atlantis DataCompression.swift + Apple Developer Documentation
import zlib
import Foundation

func decompressGzip(_ data: Data) throws -> Data {
    var stream = z_stream()
    // MAX_WBITS + 32 = 47: tells zlib to auto-detect gzip vs zlib header
    let initResult = inflateInit2_(&stream, MAX_WBITS + 32, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
    guard initResult == Z_OK else { throw ALSParserError.gzipInitFailed(initResult) }
    defer { inflateEnd(&stream) }

    var output = Data(count: data.count * 4)  // rough upper bound for ALS XML
    var status: Int32 = Z_OK

    data.withUnsafeBytes { inputPtr in
        stream.next_in = UnsafeMutablePointer(mutating: inputPtr.bindMemory(to: Bytef.self).baseAddress!)
        stream.avail_in = uInt(data.count)

        while status == Z_OK {
            output.withUnsafeMutableBytes { outputPtr in
                stream.next_out = outputPtr.bindMemory(to: Bytef.self).baseAddress!.advanced(by: Int(stream.total_out))
                stream.avail_out = uInt(output.count) - uInt(stream.total_out)
                status = inflate(&stream, Z_SYNC_FLUSH)
            }
            if stream.avail_out == 0 { output.count *= 2 }  // grow buffer if needed
        }
    }
    guard status == Z_STREAM_END else { throw ALSParserError.gzipDecompressFailed(status) }
    output.count = Int(stream.total_out)
    return output
}
```

### Pattern 2: XPath Sample Path Extraction

**What:** Query `XMLDocument` for all `FileRef` elements and extract `Path Value` + `RelativePath Value`
**When to use:** Immediately after decompression

```swift
// Source: ALS XML structure verified via abletoolz + community parsers (MEDIUM confidence)
// ALS FileRef structure (Live 11+):
//   <SampleRef>
//     <FileRef>
//       <HasRelativePath Value="true" />
//       <RelativePathType Value="1" />      -- 1=relative-to-document, 3=relative-to-project
//       <RelativePath Value="../../../Drums/kick.wav" />   -- relative to .als file
//       <Path Value="/Users/eric/Drums/kick.wav" />        -- absolute path (AUTHORITATIVE)
//       <Type Value="1" />
//       <LivePackName Value="" />
//       <LivePackId Value="" />
//       ...
//     </FileRef>
//   </SampleRef>

func extractSamplePaths(from doc: XMLDocument) throws -> [String] {
    // XPath: all FileRef/Path elements
    let nodes = try doc.nodes(forXPath: "//SampleRef/FileRef/Path")
    return nodes.compactMap { node in
        (node as? XMLElement)?.attribute(forName: "Value")?.stringValue
    }
    .filter { !$0.isEmpty }
}
```

### Pattern 3: External Sample Classification

**What:** Determine if a sample path is inside or outside the project directory
**When to use:** After extracting all paths

```swift
// Source: CONTEXT.md decision — external = path not under project folder
func classifyPaths(
    _ paths: [String],
    projectDirectory: URL
) -> (external: [URL], internal: [URL]) {
    let resolvedProject = projectDirectory.resolvingSymlinksInPath().path
    var external: [URL] = []
    var internal_: [URL] = []

    for path in paths {
        let sampleURL = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        if sampleURL.path.hasPrefix(resolvedProject + "/") || sampleURL.path == resolvedProject {
            internal_.append(sampleURL)
        } else {
            external.append(sampleURL)
        }
    }
    return (external, internal_)
}
```

### Pattern 4: Path Rewriting (ALS Mutation)

**What:** Mutate the in-memory `XMLDocument` to update `Path Value` and `RelativePath Value` for each collected sample
**When to use:** After copying samples to `Samples/Imported/`, before re-gzipping

```swift
// Source: CONTEXT.md decision — rewrite to Samples/Imported/<full-original-path>
// Example: /Users/eric/Drums/kick.wav → Samples/Imported/Users/eric/Drums/kick.wav
// The relative path from the .als: ../Samples/Imported/Users/eric/Drums/kick.wav

func rewritePaths(in doc: XMLDocument, projectBackupURL: URL, collectedPaths: [URL: String]) throws {
    // collectedPaths: [originalAbsoluteURL: newRelativePathFromALS]
    let fileRefNodes = try doc.nodes(forXPath: "//SampleRef/FileRef")
    for node in fileRefNodes {
        guard let fileRef = node as? XMLElement else { continue }
        guard let pathEl = fileRef.elements(forName: "Path").first,
              let pathValue = pathEl.attribute(forName: "Value")?.stringValue,
              let mapping = collectedPaths[URL(fileURLWithPath: pathValue)] else { continue }

        // Update Path Value to new absolute path in backup
        pathEl.attribute(forName: "Value")?.stringValue = projectBackupURL
            .appendingPathComponent(mapping).path

        // Update RelativePath Value to new relative path
        if let relPathEl = fileRef.elements(forName: "RelativePath").first {
            relPathEl.attribute(forName: "Value")?.stringValue = mapping
        }
        // Update RelativePathType to 1 (relative-to-document)
        if let relTypeEl = fileRef.elements(forName: "RelativePathType").first {
            relTypeEl.attribute(forName: "Value")?.stringValue = "1"
        }
    }
}
```

### Pattern 5: Re-gzip and Write

**What:** Serialize the mutated XMLDocument back to Data, gzip-compress, write to backup destination
**When to use:** After path rewriting, before the ALS is written to the backup folder

```swift
// Source: ALS files are gzip-compressed XML; must re-compress before saving
func compressGzip(_ data: Data) throws -> Data {
    var stream = z_stream()
    // deflateInit2: level=6, method=Z_DEFLATED, windowBits=15+16 (gzip), memLevel=8
    let initResult = deflateInit2_(&stream, 6, Z_DEFLATED, MAX_WBITS + 16, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
    guard initResult == Z_OK else { throw ALSParserError.gzipCompressFailed(initResult) }
    defer { deflateEnd(&stream) }

    var output = Data(count: data.count)  // compressed will be <= original size
    data.withUnsafeBytes { inputPtr in
        stream.next_in = UnsafeMutablePointer(mutating: inputPtr.bindMemory(to: Bytef.self).baseAddress!)
        stream.avail_in = uInt(data.count)
        output.withUnsafeMutableBytes { outputPtr in
            stream.next_out = outputPtr.bindMemory(to: Bytef.self).baseAddress!
            stream.avail_out = uInt(output.count)
            _ = deflate(&stream, Z_FINISH)
        }
    }
    output.count = Int(stream.total_out)
    return output
}
```

### Anti-Patterns to Avoid

- **Using `(Data as NSData).decompressed(using: .zlib)` for ALS files:** Apple's built-in compression API uses the DEFLATE algorithm (zlib format, RFC 1950), not gzip format (RFC 1952). `.als` files are true gzip (starts with `0x1f 0x8b`). This API will fail silently or produce incorrect output.
- **Using XMLParser (SAX) for path rewriting:** SAX parsers produce events, not a mutable tree. To rewrite paths you need a DOM — use `XMLDocument`.
- **Assuming `RelativePath` alone is authoritative:** The `RelativePath Value` attribute is relative and may use `..` segments. The `Path Value` attribute is the canonical absolute path (Live 11+). Always use `Path Value` as ground truth for identifying external samples.
- **Parsing the hex `Data` element for paths:** Pre-Live 11 projects store absolute paths in a binary hex-encoded `Data` element. Ableton 11 and 12 store them in `Path Value` (plain string). Since the project targets users on modern Ableton (11+), use `Path Value`. If `Path Value` is absent or empty, fall back to the hex decoding path or treat as unresolvable.
- **Attempting to parse nested `.als` references:** The decision is top-level `.als` only — do not follow any nested references.
- **Writing XML with XMLDocument then manually gzipping the wrong format:** `MAX_WBITS + 16` (not `MAX_WBITS` alone) in `deflateInit2_` produces the gzip header/trailer. Using `MAX_WBITS` alone produces raw zlib format, which Ableton will not open.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Gzip decompress | Custom bit-level gzip parser | System `zlib` via `import zlib` + `inflateInit2_` | zlib handles all the RFC 1952 header/footer/CRC edge cases |
| XML tree mutation | String-replace approach on raw XML bytes | `XMLDocument` DOM mutation | String replace breaks on attribute ordering, whitespace, encoding differences |
| XPath queries | Manual recursive XML traversal | `doc.nodes(forXPath:)` | `SampleRef` appears in dozens of different parent contexts in `.als` (clips, racks, instruments) — XPath handles all paths correctly |
| Path uniqueness in `Samples/Imported/` | Hash-based renaming | Full original path as subfolder structure (CONTEXT.md decision) | No collisions possible; paths remain human-readable; matches the decision |

**Key insight:** The gzip + XML tooling is already present on macOS — system zlib + Foundation XMLDocument requires zero new package dependencies.

---

## Common Pitfalls

### Pitfall 1: Apple Compression API Does Not Handle Gzip

**What goes wrong:** Developer uses `(data as NSData).decompressed(using: .zlib)` — returns nil or garbage because `.als` files use gzip (RFC 1952) which has a specific 10-byte header starting with `0x1f 0x8b`, not the raw DEFLATE or zlib (RFC 1950) format the Apple API expects.
**Why it happens:** The term "zlib" is overloaded — Apple's API uses the zlib *compression library* but applies DEFLATE format, not gzip format.
**How to avoid:** Always use `inflateInit2_` with `MAX_WBITS + 32` (auto-detect gzip) or `MAX_WBITS + 16` (force gzip).
**Warning signs:** Decompression returns nil or corrupted data on valid `.als` files.

### Pitfall 2: Pre-Live 11 Path Format

**What goes wrong:** Parser looks for `Path Value` attribute but finds an empty string or missing element — the sample path was stored in a hex-encoded binary `Data` element (pre-Live 11 format).
**Why it happens:** Ableton changed the file format in Live 11 to use plain-text `Path Value` instead of binary hex encoding.
**How to avoid:** Check if `Path Value` is non-empty before using it. If empty, the file is from pre-Live 11 — proceed as if path is unresolvable (treat like a corrupted reference; do not attempt to decode hex binary).
**Warning signs:** All samples show as "unresolvable" on a Ableton 10 project.

### Pitfall 3: ALS File Not at Project Root

**What goes wrong:** Developer assumes the `.als` file is at the top of the project folder. In practice, a project folder can contain multiple `.als` files (versions, different arrangements).
**Why it happens:** Ableton projects contain the `.als` beside the `Samples/` folder, but a project folder CAN have multiple `.als` files.
**How to avoid:** Find the `.als` file that corresponds to the watched project. In Phase 2, the FSEventsWatcher already tracks the specific `.als` file path from the triggering event — use that path directly, not a directory scan.
**Warning signs:** Wrong `.als` being parsed for a project.

### Pitfall 4: Symlinks in Sample Paths

**What goes wrong:** `path.hasPrefix(projectDirectory.path)` returns false even though the sample IS inside the project, because one uses a symlink path and the other uses the resolved path.
**Why it happens:** macOS has symlink-heavy paths (`/var` → `/private/var`). The existing codebase already has this pattern and uses `resolvingSymlinksInPath()`.
**How to avoid:** Resolve symlinks on both the project path AND the sample path before comparison. Consistent with existing `ProjectResolver.swift` pattern.
**Warning signs:** Internal samples being treated as external.

### Pitfall 5: XMLDocument XMLString Encoding Mismatch

**What goes wrong:** `XMLDocument.xmlString` produces UTF-16 or adds an XML declaration header that changes the byte count, causing the gzip re-compression of the wrong bytes.
**Why it happens:** `XMLDocument.xmlString(options:)` defaults may include BOM or different encoding.
**How to avoid:** Use `XMLDocument.xmlData(options:)` directly (returns UTF-8 by default on macOS) or `xmlString(options: .nodePreserveAll)` and encode explicitly to UTF-8 Data before compressing.
**Warning signs:** Ableton fails to open the backed-up `.als` with an XML parse error.

### Pitfall 6: SampleRef Appears in Multiple Context Paths

**What goes wrong:** Parser only looks at `AudioClip/SampleRef/FileRef` and misses samples in instruments (Simpler, Sampler, Drum Rack, etc.).
**Why it happens:** Ableton embeds `SampleRef` in dozens of different XML parent paths.
**How to avoid:** Use the XPath `//SampleRef/FileRef/Path` (descendant axis, `//`) which matches ALL `SampleRef` elements regardless of their parent context — do not hardcode a specific parent path.
**Warning signs:** Instruments' samples not being backed up while audio clip samples are.

### Pitfall 7: Schema Migration Required for New History Data

**What goes wrong:** Storing collected/missing sample lists in BackupVersion requires new DB columns, but the Schema migrator is not updated — GRDB fails to read new columns.
**Why it happens:** GRDB schema is strictly typed via migrations. New columns must be added via a new migration.
**How to avoid:** Add migration `v3_als_sample_tracking` in `Schema.swift` adding columns to `backupVersion`: `collectedSampleCount INTEGER`, `collectedSamplePaths TEXT` (JSON array), `missingSampleCount INTEGER`, `missingSamplePaths TEXT` (JSON array), `hasParseWarning BOOLEAN`.
**Warning signs:** GRDB throws a database error on startup after the update.

---

## Code Examples

### Full ALS Parse + Classify Flow (Structural Reference)

```swift
// Source: Synthesized from verified ALS XML structure + existing project patterns
// File: Sources/BackupEngine/ALS/ALSParser.swift

public struct ALSParser {

    public enum ParseResult {
        case success(external: [URL], internal_: [URL])
        case parseFailure(reason: String)  // triggers fallback to plain folder backup
    }

    /// Parse an .als file and classify sample references as external or internal.
    /// - Parameters:
    ///   - alsURL: The .als file to parse (must exist on disk)
    ///   - projectDirectory: The project folder root (used to classify paths as internal/external)
    public static func parse(alsURL: URL, projectDirectory: URL) -> ParseResult {
        // 1. Load raw bytes
        guard let compressedData = try? Data(contentsOf: alsURL) else {
            return .parseFailure(reason: "Could not read .als file")
        }

        // 2. Gzip decompress
        guard let xmlData = try? decompressGzip(compressedData) else {
            return .parseFailure(reason: "gzip decompression failed")
        }

        // 3. Parse XML
        guard let doc = try? XMLDocument(data: xmlData, options: []) else {
            return .parseFailure(reason: "XML parse failed")
        }

        // 4. Extract all Path Value attributes under SampleRef/FileRef
        guard let pathNodes = try? doc.nodes(forXPath: "//SampleRef/FileRef/Path") else {
            return .parseFailure(reason: "XPath query failed")
        }

        let allPaths: [URL] = pathNodes.compactMap { node in
            guard let el = node as? XMLElement,
                  let value = el.attribute(forName: "Value")?.stringValue,
                  !value.isEmpty else { return nil }
            return URL(fileURLWithPath: value).resolvingSymlinksInPath()
        }

        // 5. Classify
        let resolvedProject = projectDirectory.resolvingSymlinksInPath().path
        var external: [URL] = []
        var internal_: [URL] = []
        for url in allPaths {
            if url.path.hasPrefix(resolvedProject + "/") {
                internal_.append(url)
            } else {
                external.append(url)
            }
        }

        return .success(external: external, internal_: internal_)
    }
}
```

### Destination Path Construction (Collision-Free)

```swift
// Source: CONTEXT.md — preserve full original path as subfolder under Samples/Imported/
// Input:  /Users/eric/Music/Drums/kick.wav
// Output: Samples/Imported/Users/eric/Music/Drums/kick.wav

func importedRelativePath(for sampleURL: URL) -> String {
    // Drop the leading "/" to make it a relative path
    let absolutePath = sampleURL.path  // e.g. "/Users/eric/Music/Drums/kick.wav"
    let withoutLeadingSlash = absolutePath.hasPrefix("/")
        ? String(absolutePath.dropFirst())
        : absolutePath
    return "Samples/Imported/" + withoutLeadingSlash
}
```

### Notification Pattern (Missing Samples)

```swift
// Source: Existing NotificationService.swift pattern — extend to add missing-samples notification
// File: AbletonBackup/NotificationService.swift

static func sendMissingSamplesWarning(projectName: String, count: Int, versionID: String) {
    let content = UNMutableNotificationContent()
    content.title = "\(count) sample\(count == 1 ? "" : "s") missing from \(projectName)"
    content.body = "Backup completed with missing samples. Tap to view details."
    content.sound = .default
    // userInfo carries the versionID so tapping navigates to the history entry
    content.userInfo = ["versionID": versionID]
    post(content: content, identifier: "missing-samples-\(projectName)-\(Date().timeIntervalSince1970)")
}
```

### Schema Migration v3

```swift
// Source: Existing Schema.swift migration pattern — add v3 for ALS tracking columns
migrator.registerMigration("v3_als_sample_tracking") { db in
    try db.alter(table: "backupVersion") { t in
        t.add(column: "collectedSampleCount", .integer).defaults(to: 0)
        t.add(column: "collectedSamplePaths", .text)   // JSON array of strings, nullable
        t.add(column: "missingSampleCount", .integer).defaults(to: 0)
        t.add(column: "missingSamplePaths", .text)     // JSON array of strings, nullable
        t.add(column: "hasParseWarning", .boolean).notNull().defaults(to: false)
    }
}
```

### Notification Action Tap → History Navigation

```swift
// Source: Apple UNUserNotificationCenter delegate pattern
// File: AbletonBackup/NotificationService.swift or AbletonBackupApp.swift

// In NotificationDelegate (already exists):
func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
) {
    if let versionID = response.notification.request.content.userInfo["versionID"] as? String {
        // Post to coordinator to navigate to history entry
        NotificationCenter.default.post(
            name: .navigateToVersion,
            object: nil,
            userInfo: ["versionID": versionID]
        )
    }
    completionHandler()
}
```

---

## ALS File Format Summary

### FileRef XML Structure (Live 11+)

```xml
<SampleRef>
  <FileRef>
    <HasRelativePath Value="true" />
    <RelativePathType Value="1" />    <!-- 1=relative-to-document, 3=relative-to-project -->
    <RelativePath Value="../../Drums/kick.wav" />   <!-- relative from .als location -->
    <Path Value="/Users/eric/Music/Drums/kick.wav" /> <!-- AUTHORITATIVE absolute path -->
    <Type Value="1" />
    <LivePackName Value="" />
    <LivePackId Value="" />
    <OriginalFileSize Value="2345678" />
    <OriginalCrc Value="abcd1234" />
  </FileRef>
  <LastModDate Value="1708967412" />
  <SourceContext />
  <SampleUsageHint Value="0" />
</SampleRef>
```

### RelativePathType Values (Confirmed)

| Value | Meaning | Treatment |
|-------|---------|-----------|
| 1 | RelativeToDocument | Normal user sample — use Path Value |
| 3 | RelativeToProject | Inside project folder — skip (internal) |
| 5 | RelativeToFactoryPack | Ableton factory content — skip |
| 6 | RelativeToUserLibrary | Ableton User Library — external, collect |
| 7 | RelativeToBuiltinContent | Ableton builtin — skip |

**Note:** Only types 1 and 6 are candidates for external sample collection. Types 3, 5, 7 reference content that should be available on any machine with Ableton installed.

### ALS Gzip Signature

ALS files start with bytes `0x1F 0x8B` (gzip magic number). Verify this before attempting decompression to give a useful error for non-ALS inputs.

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Hex-encoded binary `Data` element for paths | Plain-text `Path Value` attribute | Live 11 (2021) | Dramatically simpler parsing; no binary decoding needed for modern files |
| `SearchHint/PathHint/RelativePathElement` for paths | `RelativePath Value` attribute | Live 11 (2021) | Single attribute vs. reconstructing a path from Dir elements |

**Deprecated/outdated:**
- Pre-Live 11 hex binary `Data` element path encoding: Still present in older `.als` files. Do not attempt to decode — treat as unresolvable and proceed with folder-only backup (matching the CONTEXT.md fallback decision).

---

## Open Questions

1. **`Samples/Imported/` vs `Samples/Collected/` — exact Ableton naming**
   - What we know: CONTEXT.md specifies `Samples/Imported/` (user decision, locked). Ableton's own "Collect All and Save" uses `Samples/Collected/` per community forum sources.
   - What's unclear: Whether Ableton uses `Collected` or `Imported` as the subfolder name internally. This doesn't matter for correctness — the locked decision is `Samples/Imported/` — but it means Ableton's own app and our backup will use different subfolder names.
   - Recommendation: Implement as `Samples/Imported/` per the locked decision. Ableton resolves files by absolute path first, then relative path — the rewritten `.als` will point directly to `Samples/Imported/` so Ableton will find files regardless of naming convention.

2. **RelativePathType 6 (RelativeToUserLibrary) — should these be collected?**
   - What we know: User Library samples are in `~/Music/Ableton/User Library/` by default — outside any project folder — so they ARE external by the CONTEXT.md definition.
   - What's unclear: Whether collecting User Library samples could cause very large backups (User Library can be many GB).
   - Recommendation: Per CONTEXT.md, external = "path is outside the project folder." User Library samples qualify. Collect them. Users can see the list in history. This is consistent with the locked decision.

3. **Live 10 and earlier projects: hex binary path format**
   - What we know: abletoolz source shows pre-Live 11 uses binary-encoded `Data` element. The decode logic involves reading OS-specific binary structures.
   - What's unclear: How common are pre-Live 11 projects among the target user base?
   - Recommendation: Per the fallback decision in CONTEXT.md — if `Path Value` is absent or empty (pre-Live 11 signature), treat all samples as unresolvable and fire "Could not parse .als — external samples not included." Do not implement the binary hex decoder. Ableton 11 launched in 2021 — support for pre-11 is low priority.

4. **ALS XML declaration and re-gzip byte fidelity**
   - What we know: `XMLDocument.xmlData(options:)` may add or remove the XML declaration. Ableton's parser may be tolerant.
   - What's unclear: Whether Ableton is strict about the XML declaration presence/format.
   - Recommendation: Use `XMLDocument.xmlData(options: .nodePreserveAll)` to preserve the original document structure as much as possible. Verify the backed-up `.als` opens in Ableton as a manual test step.

---

## Sources

### Primary (HIGH confidence)

- kiddikai/ableton-parser GitHub: actual `.als.xml` file showing `SampleRef/FileRef/Path` and `RelativePath` element structure
- AbletonPrefsReader.swift (existing project): confirms `XMLDocument` + XPath (`nodes(forXPath:)`) pattern works for Ableton XML files; already used in this codebase
- atlantis DataCompression.swift (Proxyman): verified `inflateInit2_` with `MAX_WBITS + 32` for gzip decompression and `deflateInit2_` with `MAX_WBITS + 16` for gzip compression
- abletoolz (elixirbeats/abletoolz): confirmed Live 11+ uses `Path` and `RelativePath` elements as plain-text `Value` attributes; pre-11 uses hex-encoded `Data` element

### Secondary (MEDIUM confidence)

- Ableton Live 12 Reference Manual (ableton.com): confirms "Collect All and Save" copies files to project `Samples` folder; exact subfolder name not specified in docs
- Ableton forum thread (t=27750): RelativePathType numeric values confirmed (1=relative-to-document, 3=relative-to-project, etc.)
- WebSearch cross-verification: `Path Value` attribute as absolute path confirmed by multiple community sources
- Hackingwithswift.com: confirms Apple's NSData.decompress(using:) uses DEFLATE/libcompression, not gzip RFC 1952

### Tertiary (LOW confidence)

- WebSearch: `Samples/Imported` vs `Samples/Collected` subfolder naming — not definitively confirmed from official source. CONTEXT.md decision locks us to `Samples/Imported/`.
- WebSearch: abletoolz live-11 path format change — confirmed by parser source code but no official Ableton documentation

---

## Metadata

**Confidence breakdown:**
- Standard stack (zlib + XMLDocument): HIGH — existing codebase already uses XMLDocument; zlib approach verified via multiple open-source implementations
- ALS XML structure (FileRef/Path): HIGH — confirmed from actual .als XML file on GitHub + abletoolz source
- Architecture (ALSParser struct, schema migration): HIGH — consistent with existing BackupEngine patterns
- Pitfalls (gzip API, pre-11 format): HIGH — verified Apple API limitation; confirmed via abletoolz version branching code
- Samples/Imported subfolder naming: MEDIUM — locked by CONTEXT.md decision; Ableton's own name unclear from docs but irrelevant

**Research date:** 2026-03-06
**Valid until:** 2026-09-06 (ALS format is stable; unlikely to change without a major Ableton version)
