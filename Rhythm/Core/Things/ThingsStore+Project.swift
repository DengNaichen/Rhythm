import Foundation
import SQLite3

extension ThingsStore {
  func listProjects(_ query: ThingsProjectQuery) throws -> ThingsPage<ThingsProject> {
    try databaseAccess.withReadableDatabaseURL { databaseURL in
      try withDatabase(at: databaseURL.path) { database in
        let (whereClause, bindings) = try makeProjectFilter(query)
        let today = Self.thingsDate(for: now(), calendar: calendar)
        let sql = """
          SELECT
              PROJECT.uuid,
              PROJECT.title,
              PROJECT.status,
              CASE
                  WHEN PROJECT.trashed != 0 THEN 'trash'
                  WHEN \(Self.projectLoggedExpression) THEN 'logbook'
                  WHEN PROJECT.status = 0 AND PROJECT.startDate IS NOT NULL AND PROJECT.startDate <= \(today) THEN 'today'
                  WHEN PROJECT.start = 0 THEN 'inbox'
                  WHEN PROJECT.start = 1 THEN 'anytime'
                  WHEN PROJECT.start = 2 AND PROJECT.startDate IS NULL THEN 'someday'
                  WHEN PROJECT.start = 2 THEN 'upcoming'
              END,
              date(\(Self.thingsDateToISODateExpression(column: Self.effectiveProjectStartDateExpression))),
              date(\(Self.thingsDateToISODateExpression(column: "PROJECT.deadline"))),
              datetime(PROJECT.stopDate, 'unixepoch', 'localtime'),
              PROJECT.notes,
              AREA.uuid,
              AREA.title,
              datetime(PROJECT.creationDate, 'unixepoch', 'localtime'),
              datetime(PROJECT.userModificationDate, 'unixepoch', 'localtime'),
              PROJECT.startBucket,
              \(Self.thingsTimeToISOTimeExpression(column: "PROJECT.reminderTime")),
              CASE WHEN \(Self.projectLoggedExpression) THEN 1 ELSE 0 END,
              REPEAT_TEMPLATE.uuid,
              REPEAT_TEMPLATE.title,
              CASE WHEN PROJECT.rt1_recurrenceRule IS NOT NULL THEN 1 ELSE 0 END,
              PROJECT.rt1_instanceCreationPaused,
              date(\(Self.thingsDateToISODateExpression(column: "PROJECT.rt1_instanceCreationStartDate"))),
              PROJECT.rt1_instanceCreationCount,
              datetime(PROJECT.rt1_afterCompletionReferenceDate, 'unixepoch', 'localtime'),
              date(\(Self.thingsDateToISODateExpression(column: "PROJECT.rt1_nextInstanceStartDate"))),
              PROJECT.t2_deadlineOffset,
              PROJECT.rt1_recurrenceRule
          FROM TMTask AS PROJECT
          LEFT OUTER JOIN TMTask AS REPEAT_TEMPLATE ON PROJECT.rt1_repeatingTemplate = REPEAT_TEMPLATE.uuid
          LEFT OUTER JOIN TMArea AS AREA ON PROJECT.area = AREA.uuid
          WHERE \(whereClause)
          ORDER BY \(projectOrderClause(query)), PROJECT.uuid ASC
          LIMIT ? OFFSET ?
          """
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

        var projects: [ThingsProject] = []
        while try step(statement, in: database) {
          projects.append(
            try makeProject(from: statement, includeTodos: query.includeTodos, in: database))
        }
        return Self.databasePage(projects, request: query.page)
      }
    }
  }

  func getProject(idOrTitle: String, includeTodos: Bool) throws -> ThingsProject {
    let parsed = ThingsEntityID.parse(idOrTitle)
    if let kind = parsed.kind, kind != .project {
      throw ThingsServiceError.entityTypeMismatch(expected: "project", actual: kind.rawValue)
    }

    return try databaseAccess.withReadableDatabaseURL { databaseURL in
      try withDatabase(at: databaseURL.path) { database in
        let byID = parsed.kind != nil || Self.looksLikeThingsID(parsed.rawID)
        let matchColumn = byID ? "PROJECT.uuid" : "PROJECT.title"
        let sql = projectSelectSQL(whereClause: "\(matchColumn) = ? COLLATE NOCASE")
        let statement = try prepareStatement(in: database, sql: sql)
        defer { sqlite3_finalize(statement) }
        try bind([.text(parsed.rawID)], to: statement, in: database)

        var matches: [ThingsProject] = []
        while try step(statement, in: database) {
          matches.append(try makeProject(from: statement, includeTodos: includeTodos, in: database))
        }
        guard !matches.isEmpty else {
          throw ThingsServiceError.entityNotFound(idOrTitle)
        }
        guard matches.count == 1 else {
          throw ThingsServiceError.ambiguousReference(idOrTitle)
        }
        return matches[0]
      }
    }
  }
}

extension ThingsStore {
  private func makeProjectFilter(_ query: ThingsProjectQuery) throws -> (String, [SQLiteBinding]) {
    var clauses = ["PROJECT.type = 1"]
    var bindings: [SQLiteBinding] = []
    let today = Self.thingsDate(for: now(), calendar: calendar)

    clauses.append(
      query.when == .repeating
        ? "PROJECT.rt1_recurrenceRule IS NOT NULL" : "PROJECT.rt1_recurrenceRule IS NULL")

    if query.when == .trash {
      clauses.append("PROJECT.trashed != 0")
    } else {
      clauses.append("PROJECT.trashed = 0")
    }

    switch query.status {
    case .incomplete: clauses.append("PROJECT.status = 0")
    case .completed: clauses.append("PROJECT.status = 3")
    case .canceled: clauses.append("PROJECT.status = 2")
    case .all: clauses.append("PROJECT.status IN (0, 2, 3)")
    }

    switch query.when {
    case .all: break
    case .today:
      clauses.append(
        "PROJECT.status = 0 AND PROJECT.startDate IS NOT NULL AND PROJECT.startDate <= \(today)")
    case .tomorrow:
      let tomorrow = calendar.date(byAdding: .day, value: 1, to: now()) ?? now()
      clauses.append("PROJECT.status = 0 AND PROJECT.startDate = ?")
      bindings.append(.integer(Int64(Self.thingsDate(for: tomorrow, calendar: calendar))))
    case .upcoming:
      clauses.append(
        "PROJECT.status = 0 AND PROJECT.start = 2 AND PROJECT.startDate IS NOT NULL AND PROJECT.startDate > \(today)"
      )
    case .anytime:
      clauses.append("PROJECT.status = 0 AND PROJECT.start = 1 AND PROJECT.startDate IS NULL")
    case .someday:
      clauses.append("PROJECT.status = 0 AND PROJECT.start = 2 AND PROJECT.startDate IS NULL")
    case .deadlines: clauses.append("PROJECT.status = 0 AND PROJECT.deadline IS NOT NULL")
    case .logbook: clauses.append(Self.projectLoggedExpression)
    case .repeating: break
    case .inbox: clauses.append("PROJECT.status = 0 AND PROJECT.start = 0")
    case .trash: break
    }

    if let value = query.query, !value.isEmpty {
      clauses.append(
        "(PROJECT.title LIKE ? ESCAPE '\\' COLLATE NOCASE OR PROJECT.notes LIKE ? ESCAPE '\\' COLLATE NOCASE)"
      )
      let pattern = Self.likePattern(value)
      bindings.append(contentsOf: [.text(pattern), .text(pattern)])
    }
    if let value = query.area, !value.isEmpty {
      let raw = ThingsEntityID.parse(value).rawID
      clauses.append("(AREA.uuid = ? OR AREA.title = ? COLLATE NOCASE)")
      bindings.append(contentsOf: [.text(raw), .text(value)])
    }
    if let value = query.tag, !value.isEmpty {
      let raw = ThingsEntityID.parse(value).rawID
      clauses.append(
        query.includeInheritedTags
          ? Self.projectAllMatchingTagExpression : Self.projectDirectTagExpression)
      bindings.append(contentsOf: [.text(raw), .text(value)])
    }
    if let evening = query.evening {
      clauses.append(evening ? "PROJECT.startBucket = 1" : "IFNULL(PROJECT.startBucket, 0) != 1")
    }
    if let hasReminder = query.hasReminder {
      clauses.append(
        hasReminder ? "PROJECT.reminderTime IS NOT NULL" : "PROJECT.reminderTime IS NULL")
    }
    if let isLogged = query.isLogged {
      clauses.append(
        isLogged ? Self.projectLoggedExpression : "NOT (\(Self.projectLoggedExpression))")
    }
    try appendReminderFilter(
      dateColumn: Self.effectiveProjectStartDateExpression,
      timeColumn: "PROJECT.reminderTime",
      from: query.reminderFrom,
      to: query.reminderTo,
      clauses: &clauses,
      bindings: &bindings
    )
    try appendTimestampFilter(
      column: "PROJECT.creationDate",
      from: query.createdFrom,
      to: query.createdTo,
      clauses: &clauses,
      bindings: &bindings
    )
    try appendTimestampFilter(
      column: "PROJECT.userModificationDate",
      from: query.updatedFrom,
      to: query.updatedTo,
      clauses: &clauses,
      bindings: &bindings
    )
    try appendTimestampFilter(
      column: "PROJECT.stopDate",
      from: query.completedFrom,
      to: query.completedTo,
      clauses: &clauses,
      bindings: &bindings
    )
    try appendDateFilter(
      column: "PROJECT.deadline",
      exact: nil,
      from: query.deadlineFrom,
      to: query.deadlineTo,
      clauses: &clauses,
      bindings: &bindings
    )
    return (clauses.map { "(\($0))" }.joined(separator: " AND "), bindings)
  }

  private func projectOrderClause(_ query: ThingsProjectQuery) -> String {
    let expression: String
    switch query.orderBy {
    case .things: expression = "PROJECT.\"index\""
    case .createdAt: expression = "PROJECT.creationDate"
    case .updatedAt: expression = "PROJECT.userModificationDate"
    case .scheduledDate: expression = Self.effectiveProjectStartDateExpression
    case .reminderAt:
      expression = Self.reminderSortExpression(
        dateColumn: Self.effectiveProjectStartDateExpression,
        timeColumn: "PROJECT.reminderTime"
      )
    case .deadline: expression = "PROJECT.deadline"
    case .completedAt: expression = "PROJECT.stopDate"
    case .title: expression = "PROJECT.title COLLATE NOCASE"
    }
    return "\(expression) \(query.orderDirection == .descending ? "DESC" : "ASC")"
  }

  private func projectSelectSQL(whereClause: String) -> String {
    let today = Self.thingsDate(for: now(), calendar: calendar)
    return """
      SELECT
          PROJECT.uuid, PROJECT.title, PROJECT.status,
          CASE
              WHEN PROJECT.trashed != 0 THEN 'trash'
              WHEN \(Self.projectLoggedExpression) THEN 'logbook'
              WHEN PROJECT.status = 0 AND PROJECT.startDate IS NOT NULL AND PROJECT.startDate <= \(today) THEN 'today'
              WHEN PROJECT.start = 0 THEN 'inbox'
              WHEN PROJECT.start = 1 THEN 'anytime'
              WHEN PROJECT.start = 2 AND PROJECT.startDate IS NULL THEN 'someday'
              WHEN PROJECT.start = 2 THEN 'upcoming'
          END,
          date(\(Self.thingsDateToISODateExpression(column: Self.effectiveProjectStartDateExpression))),
          date(\(Self.thingsDateToISODateExpression(column: "PROJECT.deadline"))),
          datetime(PROJECT.stopDate, 'unixepoch', 'localtime'),
          PROJECT.notes, AREA.uuid, AREA.title,
          datetime(PROJECT.creationDate, 'unixepoch', 'localtime'),
          datetime(PROJECT.userModificationDate, 'unixepoch', 'localtime'),
          PROJECT.startBucket,
          \(Self.thingsTimeToISOTimeExpression(column: "PROJECT.reminderTime")),
          CASE WHEN \(Self.projectLoggedExpression) THEN 1 ELSE 0 END,
          REPEAT_TEMPLATE.uuid, REPEAT_TEMPLATE.title,
          CASE WHEN PROJECT.rt1_recurrenceRule IS NOT NULL THEN 1 ELSE 0 END,
          PROJECT.rt1_instanceCreationPaused,
          date(\(Self.thingsDateToISODateExpression(column: "PROJECT.rt1_instanceCreationStartDate"))),
          PROJECT.rt1_instanceCreationCount,
          datetime(PROJECT.rt1_afterCompletionReferenceDate, 'unixepoch', 'localtime'),
          date(\(Self.thingsDateToISODateExpression(column: "PROJECT.rt1_nextInstanceStartDate"))),
          PROJECT.t2_deadlineOffset,
          PROJECT.rt1_recurrenceRule
      FROM TMTask AS PROJECT
      LEFT OUTER JOIN TMTask AS REPEAT_TEMPLATE ON PROJECT.rt1_repeatingTemplate = REPEAT_TEMPLATE.uuid
      LEFT OUTER JOIN TMArea AS AREA ON PROJECT.area = AREA.uuid
      WHERE PROJECT.type = 1 AND \(whereClause)
      ORDER BY PROJECT.uuid
      """
  }
}

extension ThingsStore {
  private func makeProject(
    from statement: OpaquePointer,
    includeTodos: Bool,
    in database: OpaquePointer
  ) throws -> ThingsProject {
    let rawID = Self.stringValue(statement, column: 0) ?? ""
    return ThingsProject(
      id: ThingsEntityID.make(.project, rawID: rawID),
      type: .project,
      title: Self.stringValue(statement, column: 1) ?? "",
      status: Self.itemStatus(from: sqlite3_column_int(statement, 2)),
      list: Self.stringValue(statement, column: 3),
      when: Self.stringValue(statement, column: 4),
      deadline: Self.stringValue(statement, column: 5),
      completedAt: Self.stringValue(statement, column: 6),
      notes: Self.stringValue(statement, column: 7),
      area: Self.reference(
        kind: .area, id: Self.stringValue(statement, column: 8),
        title: Self.stringValue(statement, column: 9)),
      tags: try fetchTagTitles(for: rawID, in: database),
      createdAt: Self.stringValue(statement, column: 10),
      updatedAt: Self.stringValue(statement, column: 11),
      headings: try fetchHeadings(forProject: rawID, in: database),
      todos: includeTodos ? try fetchTodos(forProject: rawID, in: database) : nil,
      url: Self.showURL(rawID),
      evening: sqlite3_column_int(statement, 12) == 1,
      reminderTime: Self.stringValue(statement, column: 13),
      reminderAt: Self.reminderDateTime(
        date: Self.stringValue(statement, column: 4),
        time: Self.stringValue(statement, column: 13)
      ),
      isLogged: sqlite3_column_int(statement, 14) != 0,
      allMatchingTags: try fetchAllMatchingTagTitles(forTask: rawID, in: database),
      repeating: Self.repeatingMetadata(from: statement, startingAt: 15, kind: .project)
    )
  }

  private static let projectLoggedExpression = "PROJECT.status IN (2, 3)"

  private static let effectiveProjectStartDateExpression = """
    CASE
      WHEN PROJECT.rt1_recurrenceRule IS NOT NULL THEN PROJECT.rt1_nextInstanceStartDate
      ELSE PROJECT.startDate
    END
    """

  private static let projectDirectTagExpression = """
    EXISTS (
      WITH RECURSIVE MATCHING_TAGS(uuid) AS (
        SELECT uuid
        FROM TMTag
        WHERE uuid = ? OR title = ? COLLATE NOCASE
        UNION
        SELECT CHILD.uuid
        FROM TMTag AS CHILD
        JOIN MATCHING_TAGS AS PARENT ON CHILD.parent = PARENT.uuid
      )
      SELECT 1
      FROM TMTaskTag AS TAG_LINK
      JOIN MATCHING_TAGS AS MATCHING_TAG ON MATCHING_TAG.uuid = TAG_LINK.tags
      WHERE TAG_LINK.tasks = PROJECT.uuid
    )
    """

  private static let projectAllMatchingTagExpression = """
    EXISTS (
      WITH RECURSIVE MATCHING_TAGS(uuid) AS (
        SELECT uuid
        FROM TMTag
        WHERE uuid = ? OR title = ? COLLATE NOCASE
        UNION
        SELECT CHILD.uuid
        FROM TMTag AS CHILD
        JOIN MATCHING_TAGS AS PARENT ON CHILD.parent = PARENT.uuid
      )
      SELECT 1
      FROM MATCHING_TAGS AS MATCHING_TAG
      WHERE
        EXISTS (
          SELECT 1 FROM TMTaskTag AS TAG_LINK
          WHERE TAG_LINK.tags = MATCHING_TAG.uuid
            AND TAG_LINK.tasks = PROJECT.uuid
        )
        OR EXISTS (
          SELECT 1 FROM TMAreaTag AS AREA_TAG
          WHERE AREA_TAG.tags = MATCHING_TAG.uuid
            AND AREA_TAG.areas = AREA.uuid
        )
    )
    """
}
