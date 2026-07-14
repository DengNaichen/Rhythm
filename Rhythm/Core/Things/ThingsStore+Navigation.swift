import Foundation
import SQLite3

extension ThingsStore {
  func resolveShowTarget(_ target: String) throws -> ThingsReference {
    let normalized = target.trimmingCharacters(in: .whitespacesAndNewlines)
    let builtins = Set(ThingsShowList.allCases.map(\.rawValue))
    if builtins.contains(normalized.lowercased()) {
      let id = normalized.lowercased()
      return ThingsReference(
        id: id,
        title: id.replacingOccurrences(of: "-", with: " ").capitalized
      )
    }

    let parsed = ThingsEntityID.parse(normalized)
    if parsed.kind != nil {
      return ThingsReference(id: normalized, title: normalized)
    }
    if Self.looksLikeThingsID(parsed.rawID) {
      return try databaseAccess.withReadableDatabaseURL { databaseURL in
        try withDatabase(at: databaseURL.path) { database in
          let statement = try prepareStatement(
            in: database,
            sql: """
              SELECT uuid, title, kind
              FROM (
                  SELECT
                      uuid,
                      title,
                      CASE type
                          WHEN 0 THEN 'todo'
                          WHEN 1 THEN 'project'
                          ELSE 'heading'
                      END AS kind
                  FROM TMTask
                  WHERE type IN (0, 1, 2)
                    AND trashed = 0
                  UNION ALL
                  SELECT uuid, title, 'area' AS kind
                  FROM TMArea
                  WHERE IFNULL(visible, 1) != 0
                  UNION ALL
                  SELECT uuid, title, 'tag' AS kind
                  FROM TMTag
              )
              WHERE uuid = ?
              """
          )
          defer { sqlite3_finalize(statement) }
          try bind([.text(parsed.rawID)], to: statement, in: database)
          var matches: [ThingsReference] = []
          while try step(statement, in: database) {
            let rawID = Self.stringValue(statement, column: 0) ?? parsed.rawID
            let kind = Self.stringValue(statement, column: 2)
              .flatMap(ThingsEntityKind.init(rawValue:))
            matches.append(
              ThingsReference(
                id: kind.map { ThingsEntityID.make($0, rawID: rawID) } ?? rawID,
                title: Self.stringValue(statement, column: 1) ?? normalized
              )
            )
          }
          guard !matches.isEmpty else { throw ThingsServiceError.entityNotFound(normalized) }
          guard matches.count == 1 else { throw ThingsServiceError.ambiguousReference(normalized) }
          return matches[0]
        }
      }
    }

    return try databaseAccess.withReadableDatabaseURL { databaseURL in
      try withDatabase(at: databaseURL.path) { database in
        let statement = try prepareStatement(
          in: database,
          sql: """
            SELECT uuid, title, kind
            FROM (
                SELECT
                    uuid,
                    title,
                    CASE type
                        WHEN 0 THEN 'todo'
                        WHEN 1 THEN 'project'
                        ELSE 'heading'
                    END AS kind
                FROM TMTask
                WHERE title = ? COLLATE NOCASE
                  AND type IN (0, 1, 2)
                  AND trashed = 0
                UNION ALL
                SELECT uuid, title, 'area' AS kind
                FROM TMArea
                WHERE title = ? COLLATE NOCASE
                  AND IFNULL(visible, 1) != 0
                UNION ALL
                SELECT uuid, title, 'tag' AS kind
                FROM TMTag
                WHERE title = ? COLLATE NOCASE
            )
            ORDER BY kind, uuid
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(
          [.text(normalized), .text(normalized), .text(normalized)],
          to: statement,
          in: database
        )
        var matches: [ThingsReference] = []
        while try step(statement, in: database) {
          let rawID = Self.stringValue(statement, column: 0) ?? ""
          let kind = Self.stringValue(statement, column: 2)
            .flatMap(ThingsEntityKind.init(rawValue:))
          matches.append(
            ThingsReference(
              id: kind.map { ThingsEntityID.make($0, rawID: rawID) } ?? rawID,
              title: Self.stringValue(statement, column: 1) ?? normalized
            )
          )
        }
        guard !matches.isEmpty else { throw ThingsServiceError.entityNotFound(normalized) }
        guard matches.count == 1 else { throw ThingsServiceError.ambiguousReference(normalized) }
        return matches[0]
      }
    }
  }

  func authToken() throws -> String? {
    try databaseAccess.withReadableDatabaseURL { databaseURL in
      try withDatabase(at: databaseURL.path) { database in
        let statement = try prepareStatement(
          in: database,
          sql: """
            SELECT uriSchemeAuthenticationToken
            FROM TMSettings
            WHERE uuid = 'RhAzEf6qDxCD5PmnZVtBZR'
            """
        )
        defer { sqlite3_finalize(statement) }
        return try step(statement, in: database) ? Self.stringValue(statement, column: 0) : nil
      }
    }
  }
}
