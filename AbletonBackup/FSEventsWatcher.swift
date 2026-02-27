// AbletonBackup/FSEventsWatcher.swift

import Foundation
import CoreServices

/// Wraps FSEventStreamRef to watch a directory tree for .als file changes.
///
/// Ableton saves .als files using an atomic rename pattern:
///   1. Writes to a temp file
///   2. Renames temp file → ProjectName.als
/// This fires kFSEventStreamEventFlagItemRenamed (not ItemModified) on the final path.
/// The filter checks for EITHER flag to cover both write patterns.
///
/// Thread safety: The FSEvents callback is delivered on the main run loop.
/// Callers that update @MainActor state must wrap in Task { @MainActor in ... }.
final class FSEventsWatcher {
    private var stream: FSEventStreamRef?
    private let callback: (String) -> Void

    /// Create and start watching the given directory URL.
    /// - Parameters:
    ///   - url: The directory to watch recursively.
    ///   - callback: Called with the full path of each .als file that changes.
    ///     Delivered on the main thread. Wrap in Task { @MainActor in ... } before
    ///     touching @MainActor-isolated state.
    init(url: URL, callback: @escaping (String) -> Void) {
        self.callback = callback

        let pathsToWatch = [url.path] as CFArray
        let latency: CFTimeInterval = 2.0  // coalesce events over 2 seconds

        // Pass self as unretained context pointer.
        // passRetained increments retain count by 1; deinit calls release to balance.
        var ctx = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passRetained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let createFlags = UInt32(
            kFSEventStreamCreateFlagFileEvents |  // per-file events (macOS 10.7+)
            kFSEventStreamCreateFlagUseCFTypes |  // required to cast eventPaths as NSArray
            kFSEventStreamCreateFlagNoDefer       // deliver ASAP after latency window
        )

        let eventCallback: FSEventStreamCallback = { _, info, numEvents, eventPaths, eventFlags, _ in
            guard let info else { return }
            let watcher = Unmanaged<FSEventsWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = unsafeBitCast(eventPaths, to: NSArray.self) as! [String]
            let flags = UnsafeBufferPointer(start: eventFlags, count: numEvents)

            for (path, flag) in zip(paths, flags) {
                let isModified = flag & UInt32(kFSEventStreamEventFlagItemModified) != 0
                let isRenamed  = flag & UInt32(kFSEventStreamEventFlagItemRenamed) != 0
                let isFile     = flag & UInt32(kFSEventStreamEventFlagItemIsFile) != 0

                // Ableton uses atomic rename: check BOTH flags.
                // Filter to .als only — ignores .asd, temp files, audio, logs.
                if (isModified || isRenamed) && isFile && path.hasSuffix(".als") {
                    watcher.callback(path)
                }
            }
        }

        stream = FSEventStreamCreate(
            nil,
            eventCallback,
            &ctx,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            FSEventStreamCreateFlags(createFlags)
        )

        if let stream {
            FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            FSEventStreamStart(stream)
        }
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        // Balance the passRetained in init
        Unmanaged.passUnretained(self).release()
    }
}
