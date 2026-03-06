import Foundation

// MARK: - BackupJob input and output contract types

/// Input to BackupEngine.runJob() — identifies which project to back up and to which destinations.
public struct BackupJob: Sendable {
    /// The project whose folder will be resolved and copied.
    public let project: Project
    /// IDs of the configured destinations to target for this job.
    public let destinationIDs: [String]

    public init(project: Project, destinationIDs: [String]) {
        self.project = project
        self.destinationIDs = destinationIDs
    }
}

/// Per-destination outcome reported by a single transfer attempt.
public struct DestinationResult: Sendable {
    public let destinationID: String
    public let status: VersionStatus
    public let errorMessage: String?

    public init(destinationID: String, status: VersionStatus, errorMessage: String? = nil) {
        self.destinationID = destinationID
        self.status = status
        self.errorMessage = errorMessage
    }
}

/// Output of BackupEngine.runJob() — aggregate result across all targeted destinations.
public struct BackupJobResult: Sendable {
    public let versionID: String
    public let projectID: String
    public let filesCopied: Int
    public let filesSkipped: Int
    public let totalBytes: Int64
    public let status: VersionStatus
    public let destinationResults: [DestinationResult]
    /// Sample collection outcome for this job. Used by the caller (BackupCoordinator)
    /// to send missing-sample or parse-warning notifications (PRSR-01, PRSR-02).
    public let sampleCollection: SampleCollection

    public init(
        versionID: String,
        projectID: String,
        filesCopied: Int,
        filesSkipped: Int,
        totalBytes: Int64,
        status: VersionStatus,
        destinationResults: [DestinationResult],
        sampleCollection: SampleCollection = .empty
    ) {
        self.versionID = versionID
        self.projectID = projectID
        self.filesCopied = filesCopied
        self.filesSkipped = filesSkipped
        self.totalBytes = totalBytes
        self.status = status
        self.destinationResults = destinationResults
        self.sampleCollection = sampleCollection
    }
}
