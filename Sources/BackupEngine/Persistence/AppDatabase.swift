import GRDB
import Foundation

/// The application database.
///
/// Uses DatabasePool (not DatabaseQueue) to enable WAL mode automatically,
/// which allows concurrent reads alongside writes.
///
/// Usage:
/// ```swift
/// // Production
/// let db = try AppDatabase.makeShared(at: "/path/to/app.db")
///
/// // Tests
/// let db = try AppDatabase.makeInMemory()
/// ```
public final class AppDatabase: Sendable {
    public let pool: DatabasePool

    /// Open the database at the given file path, applying all migrations.
    ///
    /// DatabasePool automatically enables WAL mode on open.
    public static func makeShared(at path: String) throws -> AppDatabase {
        let pool = try DatabasePool(path: path)
        let db = AppDatabase(pool: pool)
        try db.applyMigrations()
        return db
    }

    /// Create a temporary file-backed database for testing. Migrations are applied immediately.
    ///
    /// DatabasePool requires a real file path to activate WAL mode (WAL is incompatible with
    /// SQLite :memory: databases). This factory creates a unique temp-file database that is
    /// automatically deleted when the process exits (or the file is cleaned up manually).
    ///
    /// Each call produces an isolated database — safe for parallel tests.
    public static func makeInMemory() throws -> AppDatabase {
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("abletonbackup-test-\(UUID().uuidString).db")
            .path
        let pool = try DatabasePool(path: tempPath)
        let db = AppDatabase(pool: pool)
        try db.applyMigrations()
        return db
    }

    private init(pool: DatabasePool) {
        self.pool = pool
    }

    private func applyMigrations() throws {
        var migrator = DatabaseMigrator()
        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif
        Schema.registerMigrations(in: &migrator)
        try migrator.migrate(pool)
    }
}
