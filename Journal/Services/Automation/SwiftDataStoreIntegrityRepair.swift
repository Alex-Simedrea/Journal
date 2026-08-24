import Foundation
import SQLite3

/// Repairs relationship foreign keys that point at rows removed by an
/// interrupted or invalid SwiftData relationship replacement.
enum SwiftDataStoreIntegrityRepair {
    static func clearDanglingEntryDetailReferences(
        at storeURL: URL
    ) throws -> Int {
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            return 0
        }

        var database: OpaquePointer?
        guard sqlite3_open_v2(
            storeURL.path,
            &database,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let database else {
            throw error(database, fallback: "Could not open the journal data store.")
        }
        defer { sqlite3_close(database) }

        sqlite3_busy_timeout(database, 5_000)
        try execute("BEGIN IMMEDIATE TRANSACTION", in: database)
        do {
            var repairedCount = 0
            repairedCount += try clearDanglingReference(
                column: "ZPLACEVISITDETAILS",
                destinationTable: "ZPLACEVISITDETAILS",
                in: database
            )
            repairedCount += try clearDanglingReference(
                column: "ZTRANSITDETAILS",
                destinationTable: "ZTRANSITDETAILS",
                in: database
            )
            repairedCount += try clearDanglingReference(
                column: "ZWORKOUTDETAILS",
                destinationTable: "ZWORKOUTDETAILS",
                in: database
            )
            try execute("COMMIT TRANSACTION", in: database)
            return repairedCount
        } catch {
            try? execute("ROLLBACK TRANSACTION", in: database)
            throw error
        }
    }

    private static func clearDanglingReference(
        column: String,
        destinationTable: String,
        in database: OpaquePointer
    ) throws -> Int {
        guard try tableExists("ZLOGENTRY", in: database),
              try tableExists(destinationTable, in: database),
              try columnExists(column, in: "ZLOGENTRY", database: database) else {
            return 0
        }
        let statement = """
        UPDATE ZLOGENTRY
        SET \(column) = NULL,
            Z_OPT = Z_OPT + 1
        WHERE \(column) IS NOT NULL
          AND NOT EXISTS (
            SELECT 1
            FROM \(destinationTable)
            WHERE \(destinationTable).Z_PK = ZLOGENTRY.\(column)
          )
        """
        try execute(statement, in: database)
        return Int(sqlite3_changes(database))
    }

    private static func tableExists(
        _ table: String,
        in database: OpaquePointer
    ) throws -> Bool {
        var statement: OpaquePointer?
        let sql = "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = '\(table)' LIMIT 1"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil)
            == SQLITE_OK, let statement else {
            throw error(database, fallback: "Could not inspect the journal data store.")
        }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private static func columnExists(
        _ column: String,
        in table: String,
        database: OpaquePointer
    ) throws -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "PRAGMA table_info(\(table))",
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else {
            throw error(database, fallback: "Could not inspect the journal data store.")
        }
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let name = sqlite3_column_text(statement, 1) else { continue }
            if String(cString: name) == column { return true }
        }
        return false
    }

    private static func execute(
        _ statement: String,
        in database: OpaquePointer
    ) throws {
        guard sqlite3_exec(database, statement, nil, nil, nil) == SQLITE_OK else {
            throw error(database, fallback: "Could not repair the journal data store.")
        }
    }

    private static func error(
        _ database: OpaquePointer?,
        fallback: String
    ) -> NSError {
        let message = database.flatMap(sqlite3_errmsg).map(String.init(cString:))
            ?? fallback
        return NSError(
            domain: "Journal.SwiftDataStoreIntegrityRepair",
            code: Int(database.map(sqlite3_errcode) ?? SQLITE_ERROR),
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
