import Foundation

/// Lifecycle states for a backup version.
///
/// State machine:
///   pending -> copying -> copy_complete -> verifying -> verified
///                                                    -> corrupt
///   (also: deleting — used by pruning write-then-cleanup pattern)
///
/// Rules:
///   - Only `verified` versions count toward retention limit.
///   - Only `verified` versions are eligible for pruning.
///   - Only `verified` versions are eligible for restore.
public enum VersionStatus: String, Codable, Sendable {
    case pending
    case copying
    case copy_complete = "copy_complete"
    case verifying
    case verified
    case corrupt
    case deleting
}
