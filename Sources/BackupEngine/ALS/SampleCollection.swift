import Foundation

/// Result type capturing the outcome of ALS sample discovery.
///
/// Carries both the successfully collected external samples and any that could
/// not be found on disk, along with a flag indicating whether parsing succeeded.
///
/// `SampleCollection.empty` — no external samples referenced (or project has none).
/// `SampleCollection.parseFailure` — .als could not be parsed; backup proceeds
/// with plain folder copy (Phase 1 behavior) and a warning notification is fired.
public struct SampleCollection: Sendable {
    /// External samples successfully found on disk (exist at the absolute path).
    public let collectedPaths: [URL]

    /// External samples that could not be found (missing or on unmounted drive).
    public let missingPaths: [URL]

    /// true if the .als file could not be parsed (gzip failure, XML failure, etc.).
    /// When true, collectedPaths and missingPaths are both empty — the parser fell
    /// back and did not attempt sample discovery.
    public let hasParseWarning: Bool

    /// Number of external samples successfully collected.
    public var collectedCount: Int { collectedPaths.count }

    /// Number of external samples that could not be found.
    public var missingCount: Int { missingPaths.count }

    public init(collectedPaths: [URL], missingPaths: [URL], hasParseWarning: Bool) {
        self.collectedPaths = collectedPaths
        self.missingPaths = missingPaths
        self.hasParseWarning = hasParseWarning
    }

    /// No external samples — project is self-contained.
    public static let empty = SampleCollection(
        collectedPaths: [],
        missingPaths: [],
        hasParseWarning: false
    )

    /// .als could not be parsed — backup proceeds without sample collection.
    public static let parseFailure = SampleCollection(
        collectedPaths: [],
        missingPaths: [],
        hasParseWarning: true
    )
}
