import Foundation
import GRDB

/// Database schema migrations
public enum Migrations {
    /// Apply all migrations to the database
    public static func migrate(_ db: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()

        // Migration v1: Initial schema
        migrator.registerMigration("v1_initial_schema") { db in
            // Canonical tracks table
            try db.create(table: "canonical_tracks") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("artist", .text).notNull()
                t.column("album", .text)
                t.column("duration_seconds", .integer)
                t.column("is_explicit", .boolean)
                t.column("isrc", .text)
                t.column("spotify_id", .text)
                t.column("apple_id", .text)
                t.column("availability", .integer).notNull()
                t.column("created_at", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
                t.column("updated_at", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
            }

            // Indexes for canonical_tracks
            try db.create(index: "idx_tracks_spotify_id", on: "canonical_tracks", columns: ["spotify_id"])
            try db.create(index: "idx_tracks_apple_id", on: "canonical_tracks", columns: ["apple_id"])
            try db.create(index: "idx_tracks_isrc", on: "canonical_tracks", columns: ["isrc"])

            // Canonical playlists table
            try db.create(table: "canonical_playlists") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("owner", .text)
                t.column("description", .text)
                t.column("source_spotify_id", .text)
                t.column("source_apple_id", .text)
                t.column("created_at", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
                t.column("updated_at", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
            }

            // Playlist tracks (ordered membership)
            try db.create(table: "playlist_tracks") { t in
                t.column("playlist_id", .text).notNull()
                t.column("track_id", .text).notNull()
                t.column("position", .integer).notNull()
                t.foreignKey(["playlist_id"], references: "canonical_playlists", columns: ["id"], onDelete: .cascade)
                t.foreignKey(["track_id"], references: "canonical_tracks", columns: ["id"], onDelete: .cascade)
                t.primaryKey(["playlist_id", "position"])
            }

            try db.create(index: "idx_playlist_tracks_playlist", on: "playlist_tracks", columns: ["playlist_id"])
            try db.create(index: "idx_playlist_tracks_track", on: "playlist_tracks", columns: ["track_id"])

            // Manual mappings (user overrides)
            try db.create(table: "manual_mappings") { t in
                t.column("id", .text).primaryKey()
                t.column("canonical_track_id", .text).notNull()
                t.column("source_service", .text).notNull()
                t.column("source_track_id", .text).notNull()
                t.column("target_service", .text).notNull()
                t.column("target_track_id", .text).notNull()
                t.column("confidence_score", .double)
                t.column("created_at", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
                t.foreignKey(["canonical_track_id"], references: "canonical_tracks", columns: ["id"], onDelete: .cascade)
                t.uniqueKey(["source_service", "source_track_id"])
            }

            try db.create(index: "idx_manual_mappings_canonical", on: "manual_mappings", columns: ["canonical_track_id"])

            // Sync runs (history)
            try db.create(table: "sync_runs") { t in
                t.column("id", .text).primaryKey()
                t.column("started_at", .datetime).notNull()
                t.column("completed_at", .datetime)
                t.column("direction", .text).notNull()
                t.column("operations_count", .integer)
                t.column("success_count", .integer)
                t.column("failure_count", .integer)
                t.column("status", .text).notNull()  // 'running', 'completed', 'failed'
                t.column("duration_seconds", .double)
            }

            try db.create(index: "idx_sync_runs_status", on: "sync_runs", columns: ["status"])
            try db.create(index: "idx_sync_runs_started", on: "sync_runs", columns: ["started_at"])
        }

        // Migration v2: partial unique indexes so service IDs cannot duplicate (#13).
        migrator.registerMigration("v2_unique_service_ids") { db in
            try db.execute(sql: """
                CREATE UNIQUE INDEX IF NOT EXISTS idx_tracks_spotify_id_unique
                ON canonical_tracks(spotify_id) WHERE spotify_id IS NOT NULL
                """)
            try db.execute(sql: """
                CREATE UNIQUE INDEX IF NOT EXISTS idx_tracks_apple_id_unique
                ON canonical_tracks(apple_id) WHERE apple_id IS NOT NULL
                """)
        }

        // Migration v3: case-insensitive ISRC index for matching lookups (#14).
        migrator.registerMigration("v3_isrc_nocase_index") { db in
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_tracks_isrc_nocase
                ON canonical_tracks(isrc COLLATE NOCASE)
                """)
        }

        // Migration v4: persisted match decisions for metrics export (#9).
        migrator.registerMigration("v4_match_outcomes") { db in
            try db.create(table: "match_outcomes") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("run_id", .text)
                t.column("recorded_at", .datetime).notNull()
                t.column("source_service", .text).notNull()
                t.column("target_service", .text).notNull()
                t.column("source_track_id", .text).notNull()
                t.column("decision", .text).notNull()
                t.column("method", .text)
                t.column("top_score", .double)
                t.column("candidate_count", .integer).notNull()
            }
            try db.create(index: "idx_match_outcomes_run", on: "match_outcomes", columns: ["run_id"])
        }

        try migrator.migrate(db)
    }
}
