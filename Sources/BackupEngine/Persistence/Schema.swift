import GRDB
import Foundation

/// Database schema migrations for AbletonBackup.
///
/// All schema evolution goes through DatabaseMigrator to ensure
/// reproducible database creation for both production and in-memory test databases.
public enum Schema {

    /// Register all migrations into the provided migrator.
    /// Called by AppDatabase.applyMigrations().
    public static func registerMigrations(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v1_initial") { db in
            // destination — backup destination configuration
            try db.create(table: "destination") { t in
                t.primaryKey("id", .text)                        // UUID string
                t.column("type", .text).notNull()                // "local" | "nas" | "icloud" | "github"
                t.column("name", .text).notNull()
                t.column("rootPath", .text).notNull()
                t.column("retentionCount", .integer).notNull().defaults(to: 10)
                t.column("createdAt", .datetime).notNull()
            }

            // project — Ableton projects under watch
            try db.create(table: "project") { t in
                t.primaryKey("id", .text)                        // UUID string
                t.column("name", .text).notNull()
                t.column("path", .text).notNull().unique()       // UNIQUE — one record per project path
                t.column("lastBackupAt", .datetime)              // nullable
            }

            // backupVersion — one record per backup snapshot
            try db.create(table: "backupVersion") { t in
                t.primaryKey("id", .text)                        // "2026-02-25T143022.456-a3f8b12c"
                t.column("projectID", .text).notNull()
                    .references("project", onDelete: .cascade)
                t.column("destinationID", .text).notNull()
                    .references("destination", onDelete: .cascade)
                t.column("status", .text).notNull().defaults(to: "pending")
                    // valid: pending | copying | copy_complete | verifying | verified | corrupt | deleting
                t.column("fileCount", .integer)                  // nullable — set when copy_complete
                t.column("totalBytes", .integer)                 // nullable — set when copy_complete
                t.column("createdAt", .datetime).notNull()
                t.column("completedAt", .datetime)               // nullable — set when verified or corrupt
                t.column("errorMessage", .text)                  // nullable
            }

            // Index for common retention/pruning query: find verified versions for a project
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_backupVersion_project_status_created
                ON backupVersion (projectID, status, createdAt)
                """)

            // backupFileRecord — per-file manifest for each backup version
            try db.create(table: "backupFileRecord") { t in
                t.autoIncrementedPrimaryKey("rowid")
                t.column("versionID", .text).notNull()
                    .references("backupVersion", onDelete: .cascade)
                t.column("relativePath", .text).notNull()
                t.column("sourceMtime", .datetime).notNull()
                t.column("sourceSize", .integer).notNull()
                t.column("checksum", .text)                      // nullable — null until verified
                t.column("copied", .boolean).notNull().defaults(to: false)
                t.uniqueKey(["versionID", "relativePath"])
            }

            // versionLock — prevents pruning while a restore is in progress (future phases)
            try db.create(table: "versionLock") { t in
                t.primaryKey("versionID", .text)
                    .references("backupVersion", onDelete: .cascade)
                t.column("lockedSince", .datetime).notNull()
            }
        }
    }
}
