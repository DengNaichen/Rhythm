import Foundation
import SQLite3

extension ThingsStore {
  func listHeadings(_ query: ThingsHeadingQuery) throws -> ThingsPage<ThingsHeading> {
    try databaseAccess.withReadableDatabaseURL { databaseURL in
      try withDatabase(at: databaseURL.path) { database in
        let (whereClause, bindings) = makeHeadingFilter(query)
        let sql =
          headingSelectSQL(whereClause: whereClause)
          + " ORDER BY \(headingOrderClause(query)), HEADING.uuid ASC LIMIT ? OFFSET ?"
        let statement = try prepareStatement(in: database, sql: sql)
        defer { sqlite3_finalize(statement) }
        try bind(
          bindings + [
            .integer(Int64(query.page.limit + 1)),
            .integer(Int64(query.page.offset)),
          ],
          to: statement,
          in: database
        )

        var headings: [ThingsHeading] = []
        while try step(statement, in: database) {
          headings.append(
            try makeHeading(from: statement, includeTodos: query.includeTodos, in: database))
        }
        return Self.databasePage(headings, request: query.page)
      }
    }
  }

  func getHeading(idOrTitle: String, includeTodos: Bool) throws -> ThingsHeading {
    let parsed = ThingsEntityID.parse(idOrTitle)
    if let kind = parsed.kind, kind != .heading {
      throw ThingsServiceError.entityTypeMismatch(expected: "heading", actual: kind.rawValue)
    }

    return try databaseAccess.withReadableDatabaseURL { databaseURL in
      try withDatabase(at: databaseURL.path) { database in
        let byID = parsed.kind != nil || Self.looksLikeThingsID(parsed.rawID)
        let column = byID ? "HEADING.uuid" : "HEADING.title"
        let statement = try prepareStatement(
          in: database,
          sql: headingSelectSQL(whereClause: "\(column) = ? COLLATE NOCASE")
        )
        defer { sqlite3_finalize(statement) }
        try bind([.text(parsed.rawID)], to: statement, in: database)
        var matches: [ThingsHeading] = []
        while try step(statement, in: database) {
          matches.append(try makeHeading(from: statement, includeTodos: includeTodos, in: database))
        }
        guard !matches.isEmpty else { throw ThingsServiceError.entityNotFound(idOrTitle) }
        guard matches.count == 1 else { throw ThingsServiceError.ambiguousReference(idOrTitle) }
        return matches[0]
      }
    }
  }

  private func makeHeadingFilter(_ query: ThingsHeadingQuery) -> (String, [SQLiteBinding]) {
    var clauses = ["HEADING.type = 2"]
    if !query.includeTrashed {
      clauses.append("HEADING.trashed = 0")
      clauses.append("IFNULL(PROJECT.trashed, 0) = 0")
    }
    var bindings: [SQLiteBinding] = []
    switch query.status {
    case .incomplete: clauses.append("HEADING.status = 0")
    case .completed: clauses.append("HEADING.status = 3")
    case .canceled: clauses.append("HEADING.status = 2")
    case .all: clauses.append("HEADING.status IN (0, 2, 3)")
    }
    if let value = query.query, !value.isEmpty {
      clauses.append("HEADING.title LIKE ? ESCAPE '\\' COLLATE NOCASE")
      bindings.append(.text(Self.likePattern(value)))
    }
    if let value = query.project, !value.isEmpty {
      let raw = ThingsEntityID.parse(value).rawID
      clauses.append("(PROJECT.uuid = ? OR PROJECT.title = ? COLLATE NOCASE)")
      bindings.append(contentsOf: [.text(raw), .text(value)])
    }
    if let isLogged = query.isLogged {
      clauses.append(
        isLogged ? Self.headingLoggedExpression : "NOT (\(Self.headingLoggedExpression))")
    }
    return (clauses.map { "(\($0))" }.joined(separator: " AND "), bindings)
  }

  private func headingOrderClause(_ query: ThingsHeadingQuery) -> String {
    let expression: String
    switch query.orderBy {
    case .things: expression = "HEADING.\"index\""
    case .createdAt: expression = "HEADING.creationDate"
    case .updatedAt: expression = "HEADING.userModificationDate"
    case .completedAt: expression = "HEADING.stopDate"
    case .title: expression = "HEADING.title COLLATE NOCASE"
    case .scheduledDate, .reminderAt, .deadline: expression = "HEADING.\"index\""
    }
    return "\(expression) \(query.orderDirection == .descending ? "DESC" : "ASC")"
  }

  private func headingSelectSQL(whereClause: String) -> String {
    return """
      SELECT
          HEADING.uuid,
          HEADING.title,
          HEADING.status,
          CASE WHEN \(Self.headingLoggedExpression) THEN 1 ELSE 0 END,
          datetime(HEADING.stopDate, 'unixepoch', 'localtime'),
          datetime(HEADING.creationDate, 'unixepoch', 'localtime'),
          datetime(HEADING.userModificationDate, 'unixepoch', 'localtime'),
          PROJECT.uuid,
          PROJECT.title
      FROM TMTask AS HEADING
      JOIN TMTask AS PROJECT ON HEADING.project = PROJECT.uuid
      WHERE HEADING.type = 2 AND \(whereClause)
      """
  }

  private func makeHeading(
    from statement: OpaquePointer,
    includeTodos: Bool,
    in database: OpaquePointer
  ) throws -> ThingsHeading {
    let rawID = Self.stringValue(statement, column: 0) ?? ""
    guard
      let project = Self.reference(
        kind: .project,
        id: Self.stringValue(statement, column: 7),
        title: Self.stringValue(statement, column: 8)
      )
    else {
      throw ThingsServiceError.entityNotFound(rawID)
    }
    return ThingsHeading(
      id: ThingsEntityID.make(.heading, rawID: rawID),
      type: .heading,
      title: Self.stringValue(statement, column: 1) ?? "",
      status: Self.itemStatus(from: sqlite3_column_int(statement, 2)),
      isLogged: sqlite3_column_int(statement, 3) != 0,
      completedAt: Self.stringValue(statement, column: 4),
      createdAt: Self.stringValue(statement, column: 5),
      updatedAt: Self.stringValue(statement, column: 6),
      project: project,
      todos: includeTodos ? try fetchTodos(forHeading: rawID, in: database) : nil,
      url: Self.showURL(rawID)
    )
  }

  private static let headingLoggedExpression = """
    (HEADING.status IN (2, 3) OR IFNULL(PROJECT.status, 0) IN (2, 3))
    """
}
