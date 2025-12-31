//
//  WaveformCache.swift
//  HiFidelity
//
//  Manages waveform caching for fast loading
//

import Foundation
import SQLite3

class WaveformCache {
    static let shared = WaveformCache()

    private let dbPath: String
    private var db: OpaquePointer?

    private init() {
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            Logger.critical("Application Support directory not found - waveform cache unavailable")
            fatalError("Application Support directory not found")
        }
        let appFolder = appSupport.appendingPathComponent("HiFidelity", isDirectory: true)

        try? fileManager.createDirectory(at: appFolder, withIntermediateDirectories: true)

        dbPath = appFolder.appendingPathComponent("waveform_cache.db").path
        Logger.info("Waveform cache database path: \(dbPath)")
        openDatabase()
        createTable()
    }

    private func openDatabase() {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            Logger.error("Failed to open waveform cache database")
        }
    }

    private func createTable() {
        // Check if we need to migrate from old schema
        let checkSchemaSQL = "SELECT sql FROM sqlite_master WHERE type='table' AND name='waveform_cache'"
        var checkStatement: OpaquePointer?
        var needsMigration = false

        if sqlite3_prepare_v2(db, checkSchemaSQL, -1, &checkStatement, nil) == SQLITE_OK {
            if sqlite3_step(checkStatement) == SQLITE_ROW {
                if let schemaPtr = sqlite3_column_text(checkStatement, 0) {
                    let schema = String(cString: schemaPtr)
                    // If schema contains sample_count, we need to migrate
                    if schema.contains("sample_count") {
                        needsMigration = true
                        Logger.info("Detected old waveform cache schema, migrating...")
                    }
                }
            }
        }
        sqlite3_finalize(checkStatement)

        // Only drop table if migration is needed
        if needsMigration {
            let dropTableSQL = "DROP TABLE IF EXISTS waveform_cache"
            var dropStatement: OpaquePointer?
            if sqlite3_prepare_v2(db, dropTableSQL, -1, &dropStatement, nil) == SQLITE_OK {
                sqlite3_step(dropStatement)
            }
            sqlite3_finalize(dropStatement)
            Logger.info("Migrated waveform cache to new schema")
        }

        // Create new simplified schema (no sample_count)
        let createTableSQL = """
        CREATE TABLE IF NOT EXISTS waveform_cache (
            track_id TEXT PRIMARY KEY,
            samples BLOB NOT NULL,
            created_at REAL NOT NULL
        )
        """

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, createTableSQL, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_DONE {
                Logger.debug("Waveform cache table ready")
            }
        }
        sqlite3_finalize(statement)
    }

    // MARK: - Cache Operations

    func getCachedWaveform(trackId: String) -> [Float]? {
        let querySQL = "SELECT samples FROM waveform_cache WHERE track_id = ?"
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, querySQL, -1, &statement, nil) == SQLITE_OK else {
            Logger.error("Failed to prepare cache query for track \(trackId)")
            return nil
        }

        sqlite3_bind_text(statement, 1, (trackId as NSString).utf8String, -1, nil)

        var samples: [Float]?

        if sqlite3_step(statement) == SQLITE_ROW {
            if let blob = sqlite3_column_blob(statement, 0) {
                let blobSize = sqlite3_column_bytes(statement, 0)
                let count = Int(blobSize) / MemoryLayout<Float>.size
                let buffer = UnsafeRawPointer(blob).bindMemory(to: Float.self, capacity: count)
                samples = Array(UnsafeBufferPointer(start: buffer, count: count))
                Logger.debug("Cache HIT for track \(trackId) - \(count) samples")
            }
        } else {
            Logger.debug("Cache MISS for track \(trackId)")
        }

        sqlite3_finalize(statement)
        return samples
    }

    func cacheWaveform(trackId: String, samples: [Float]) {
        let insertSQL = """
        INSERT OR REPLACE INTO waveform_cache (track_id, samples, created_at)
        VALUES (?, ?, ?)
        """

        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK else {
            Logger.error("Failed to prepare waveform cache insert statement")
            return
        }

        sqlite3_bind_text(statement, 1, (trackId as NSString).utf8String, -1, nil)

        _ = samples.withUnsafeBytes { bufferPointer in
            sqlite3_bind_blob(statement, 2, bufferPointer.baseAddress, Int32(bufferPointer.count), nil)
        }

        sqlite3_bind_double(statement, 3, Date().timeIntervalSince1970)

        if sqlite3_step(statement) != SQLITE_DONE {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            Logger.error("Failed to cache waveform for track \(trackId): \(errorMessage)")
        } else {
            Logger.info("Successfully cached waveform for track \(trackId) - \(samples.count) samples")
        }

        sqlite3_finalize(statement)
    }

    func clearCache() {
        let deleteSQL = "DELETE FROM waveform_cache"
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, deleteSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_step(statement)
        }

        sqlite3_finalize(statement)
    }

    deinit {
        if let db = db {
            let result = sqlite3_close(db)
            if result != SQLITE_OK {
                Logger.error("Failed to close waveform cache database: \(result)")
            }
        }
    }
}
