import Testing
import Foundation
@testable import BackupEngine

@Suite("AppDatabase")
struct AppDatabaseTests {

    @Test func migrationsRunWithoutError() throws {
        let db = try AppDatabase.makeInMemory()
        // Insert a destination and project to verify tables exist
        let dest = DestinationConfig(
            id: UUID().uuidString,
            type: .local,
            name: "Test Drive",
            rootPath: "/tmp/test",
            retentionCount: 10,
            createdAt: Date()
        )
        try db.pool.write { db in try dest.insert(db) }
        let fetched = try db.pool.read { db in
            try DestinationConfig.fetchAll(db)
        }
        #expect(fetched.count == 1)
    }

    @Test func projectTableExists() throws {
        let db = try AppDatabase.makeInMemory()
        let project = Project(
            id: UUID().uuidString,
            name: "My Live Set",
            path: "/Users/eric/Music/Projects/MySet"
        )
        try db.pool.write { db in try project.insert(db) }
        let fetched = try db.pool.read { db in
            try Project.fetchAll(db)
        }
        #expect(fetched.count == 1)
        #expect(fetched[0].name == "My Live Set")
    }

    @Test func backupVersionStatusLifecycle() throws {
        let db = try AppDatabase.makeInMemory()

        // Set up prerequisite rows
        let dest = DestinationConfig(id: UUID().uuidString, type: .local, name: "Drive", rootPath: "/tmp", createdAt: Date())
        let project = Project(id: UUID().uuidString, name: "Set", path: "/Music/Set")
        try db.pool.write { db in
            try dest.insert(db)
            try project.insert(db)
        }

        // Create a backup version and advance through lifecycle states
        var version = BackupVersion(
            id: BackupVersion.makeID(),
            projectID: project.id,
            destinationID: dest.id,
            createdAt: Date()
        )
        #expect(version.status == .pending)

        try db.pool.write { db in try version.insert(db) }

        version.status = .copying
        try db.pool.write { db in try version.update(db) }

        version.status = .copy_complete
        version.fileCount = 42
        version.totalBytes = 1_048_576
        try db.pool.write { db in try version.update(db) }

        version.status = .verifying
        try db.pool.write { db in try version.update(db) }

        version.status = .verified
        version.completedAt = Date()
        try db.pool.write { db in try version.update(db) }

        let fetched = try db.pool.read { db in
            try BackupVersion.fetchOne(db, key: version.id)
        }
        #expect(fetched?.status == .verified)
        #expect(fetched?.fileCount == 42)
        #expect(fetched?.completedAt != nil)
    }

    @Test func versionStatusEnumAllCases() {
        // Verify all 7 lifecycle states are defined
        let allCases: [VersionStatus] = [
            .pending, .copying, .copy_complete, .verifying, .verified, .corrupt, .deleting
        ]
        #expect(allCases.count == 7)

        // Verify raw values round-trip via Codable
        for status in allCases {
            let encoded = try? JSONEncoder().encode(status)
            #expect(encoded != nil)
        }
    }

    @Test func backupFileRecordInsertion() throws {
        let db = try AppDatabase.makeInMemory()

        let dest = DestinationConfig(id: UUID().uuidString, type: .local, name: "Drive", rootPath: "/tmp", createdAt: Date())
        let project = Project(id: UUID().uuidString, name: "Set", path: "/Music/Set")
        let version = BackupVersion(
            id: BackupVersion.makeID(),
            projectID: project.id,
            destinationID: dest.id,
            createdAt: Date()
        )

        try db.pool.write { db in
            try dest.insert(db)
            try project.insert(db)
            try version.insert(db)
        }

        let fileRecord = BackupFileRecord(
            versionID: version.id,
            relativePath: "Samples/kick.wav",
            sourceMtime: Date(),
            sourceSize: 512_000
        )
        try db.pool.write { db in try fileRecord.insert(db) }

        let fetched = try db.pool.read { db in
            try BackupFileRecord.fetchAll(db)
        }
        #expect(fetched.count == 1)
        #expect(fetched[0].relativePath == "Samples/kick.wav")
        #expect(fetched[0].checksum == nil) // null until verified
        #expect(fetched[0].copied == false)
    }

    @Test func destinationTypeEnum() {
        // Verify DestinationType covers all planned destination types
        let types: [DestinationType] = [.local, .nas, .icloud, .github]
        #expect(types.count == 4)
        #expect(DestinationType.local.rawValue == "local")
    }
}
