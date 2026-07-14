import Foundation
import SQLite3

extension ThingsStore {
  func listTodos(_ query: ThingsTodoQuery) throws -> ThingsPage<ThingsTodo> {
    try databaseAccess.withReadableDatabaseURL { databaseURL in
      try withDatabase(at: databaseURL.path) { database in
        let (whereClause, bindings) = try makeTodoFilter(query)
        let orderClause = todoOrderClause(query)
        let today = Self.thingsDate(for: now(), calendar: calendar)
        let sql = """
          SELECT
              TASK.uuid,
              TASK.title,
              TASK.status,
              CASE
                  WHEN \(Self.todoEffectiveTrashedExpression) THEN 'trash'
                  WHEN \(Self.todoLoggedExpression) THEN 'logbook'
                  WHEN TASK.status = 0
                    AND IFNULL(PROJECT.start, -1) != 2
                    AND IFNULL(HEADING_PROJECT.start, -1) != 2
                    AND (
                      (TASK.start = 1 AND TASK.startDate IS NOT NULL)
                      OR (TASK.start = 2 AND TASK.startDate IS NOT NULL AND TASK.startDate <= \(today))
                      OR (
                          TASK.startDate IS NULL
                          AND TASK.deadline IS NOT NULL
                          AND TASK.deadline <= \(today)
                          AND TASK.deadlineSuppressionDate IS NULL
                      )
                  ) THEN 'today'
                  WHEN TASK.start = 0 THEN 'inbox'
                  WHEN TASK.start = 1 THEN 'anytime'
                  WHEN TASK.start = 2 AND TASK.startDate IS NULL THEN 'someday'
                  WHEN TASK.start = 2 THEN 'upcoming'
              END AS list_name,
              date(\(Self.thingsDateToISODateExpression(column: Self.effectiveStartDateExpression))) AS scheduled_date,
              date(\(Self.thingsDateToISODateExpression(column: "TASK.deadline"))) AS deadline,
              datetime(TASK.stopDate, 'unixepoch', 'localtime') AS completed_at,
              datetime(TASK.creationDate, 'unixepoch', 'localtime') AS created_at,
              datetime(TASK.userModificationDate, 'unixepoch', 'localtime') AS updated_at,
              TASK.notes,
              COALESCE(DIRECT_AREA.uuid, PROJECT_AREA.uuid, HEADING_PROJECT_AREA.uuid) AS area_uuid,
              COALESCE(DIRECT_AREA.title, PROJECT_AREA.title, HEADING_PROJECT_AREA.title) AS area_title,
              COALESCE(PROJECT.uuid, HEADING_PROJECT.uuid) AS project_uuid,
              COALESCE(PROJECT.title, HEADING_PROJECT.title) AS project_title,
              HEADING.uuid AS heading_uuid,
              HEADING.title AS heading_title,
              TASK.startBucket,
              \(Self.thingsTimeToISOTimeExpression(column: "TASK.reminderTime")) AS reminder_time,
              CASE WHEN \(Self.todoLoggedExpression) THEN 1 ELSE 0 END AS is_logged,
              REPEAT_TEMPLATE.uuid,
              REPEAT_TEMPLATE.title,
              CASE WHEN TASK.rt1_recurrenceRule IS NOT NULL THEN 1 ELSE 0 END AS is_template,
              TASK.rt1_instanceCreationPaused,
              date(\(Self.thingsDateToISODateExpression(column: "TASK.rt1_instanceCreationStartDate"))),
              TASK.rt1_instanceCreationCount,
              datetime(TASK.rt1_afterCompletionReferenceDate, 'unixepoch', 'localtime'),
              date(\(Self.thingsDateToISODateExpression(column: "TASK.rt1_nextInstanceStartDate"))),
              TASK.t2_deadlineOffset,
              TASK.rt1_recurrenceRule
          FROM TMTask AS TASK
          LEFT OUTER JOIN TMTask AS PROJECT ON TASK.project = PROJECT.uuid
          LEFT OUTER JOIN TMTask AS HEADING ON TASK.heading = HEADING.uuid
          LEFT OUTER JOIN TMTask AS HEADING_PROJECT ON HEADING.project = HEADING_PROJECT.uuid
          LEFT OUTER JOIN TMTask AS REPEAT_TEMPLATE ON TASK.rt1_repeatingTemplate = REPEAT_TEMPLATE.uuid
          LEFT OUTER JOIN TMArea AS DIRECT_AREA ON TASK.area = DIRECT_AREA.uuid
          LEFT OUTER JOIN TMArea AS PROJECT_AREA ON PROJECT.area = PROJECT_AREA.uuid
          LEFT OUTER JOIN TMArea AS HEADING_PROJECT_AREA ON HEADING_PROJECT.area = HEADING_PROJECT_AREA.uuid
          WHERE \(whereClause)
          ORDER BY \(orderClause), TASK.uuid ASC
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

        var todos: [ThingsTodo] = []
        while try step(statement, in: database) {
          todos.append(try makeTodo(from: statement, in: database))
        }

        return Self.databasePage(todos, request: query.page)
      }
    }
  }

  func getTodo(id: String) throws -> ThingsTodo {
    let rawID = try ThingsEntityID.rawID(id, expectedKind: .todo)
    return try databaseAccess.withReadableDatabaseURL { databaseURL in
      try withDatabase(at: databaseURL.path) { database in
        let today = Self.thingsDate(for: now(), calendar: calendar)
        let sql = """
          SELECT
              TASK.uuid, TASK.title, TASK.status,
              CASE
                  WHEN \(Self.todoEffectiveTrashedExpression) THEN 'trash'
                  WHEN \(Self.todoLoggedExpression) THEN 'logbook'
                  WHEN TASK.status = 0
                    AND IFNULL(PROJECT.start, -1) != 2
                    AND IFNULL(HEADING_PROJECT.start, -1) != 2
                    AND (
                      (TASK.start = 1 AND TASK.startDate IS NOT NULL)
                      OR (TASK.start = 2 AND TASK.startDate IS NOT NULL AND TASK.startDate <= \(today))
                      OR (
                          TASK.startDate IS NULL
                          AND TASK.deadline IS NOT NULL
                          AND TASK.deadline <= \(today)
                          AND TASK.deadlineSuppressionDate IS NULL
                      )
                  ) THEN 'today'
                  WHEN TASK.start = 0 THEN 'inbox'
                  WHEN TASK.start = 1 THEN 'anytime'
                  WHEN TASK.start = 2 AND TASK.startDate IS NULL THEN 'someday'
                  WHEN TASK.start = 2 THEN 'upcoming'
              END,
              date(\(Self.thingsDateToISODateExpression(column: Self.effectiveStartDateExpression))),
              date(\(Self.thingsDateToISODateExpression(column: "TASK.deadline"))),
              datetime(TASK.stopDate, 'unixepoch', 'localtime'),
              datetime(TASK.creationDate, 'unixepoch', 'localtime'),
              datetime(TASK.userModificationDate, 'unixepoch', 'localtime'),
              TASK.notes,
              COALESCE(DIRECT_AREA.uuid, PROJECT_AREA.uuid, HEADING_PROJECT_AREA.uuid),
              COALESCE(DIRECT_AREA.title, PROJECT_AREA.title, HEADING_PROJECT_AREA.title),
              COALESCE(PROJECT.uuid, HEADING_PROJECT.uuid),
              COALESCE(PROJECT.title, HEADING_PROJECT.title),
              HEADING.uuid, HEADING.title,
              TASK.startBucket,
              \(Self.thingsTimeToISOTimeExpression(column: "TASK.reminderTime")),
              CASE WHEN \(Self.todoLoggedExpression) THEN 1 ELSE 0 END,
              REPEAT_TEMPLATE.uuid, REPEAT_TEMPLATE.title,
              CASE WHEN TASK.rt1_recurrenceRule IS NOT NULL THEN 1 ELSE 0 END,
              TASK.rt1_instanceCreationPaused,
              date(\(Self.thingsDateToISODateExpression(column: "TASK.rt1_instanceCreationStartDate"))),
              TASK.rt1_instanceCreationCount,
              datetime(TASK.rt1_afterCompletionReferenceDate, 'unixepoch', 'localtime'),
              date(\(Self.thingsDateToISODateExpression(column: "TASK.rt1_nextInstanceStartDate"))),
              TASK.t2_deadlineOffset,
              TASK.rt1_recurrenceRule
          FROM TMTask AS TASK
          LEFT OUTER JOIN TMTask AS PROJECT ON TASK.project = PROJECT.uuid
          LEFT OUTER JOIN TMTask AS HEADING ON TASK.heading = HEADING.uuid
          LEFT OUTER JOIN TMTask AS HEADING_PROJECT ON HEADING.project = HEADING_PROJECT.uuid
          LEFT OUTER JOIN TMTask AS REPEAT_TEMPLATE ON TASK.rt1_repeatingTemplate = REPEAT_TEMPLATE.uuid
          LEFT OUTER JOIN TMArea AS DIRECT_AREA ON TASK.area = DIRECT_AREA.uuid
          LEFT OUTER JOIN TMArea AS PROJECT_AREA ON PROJECT.area = PROJECT_AREA.uuid
          LEFT OUTER JOIN TMArea AS HEADING_PROJECT_AREA ON HEADING_PROJECT.area = HEADING_PROJECT_AREA.uuid
          WHERE TASK.uuid = ? AND TASK.type = 0
          LIMIT 1
          """
        let statement = try prepareStatement(in: database, sql: sql)
        defer { sqlite3_finalize(statement) }
        try bind([.text(rawID)], to: statement, in: database)
        guard try step(statement, in: database) else {
          throw ThingsServiceError.entityNotFound(id)
        }
        return try makeTodo(from: statement, in: database)
      }
    }
  }
}

extension ThingsStore {
  private func makeTodoFilter(_ query: ThingsTodoQuery) throws -> (String, [SQLiteBinding]) {
    var clauses = ["TASK.type = 0"]
    var bindings: [SQLiteBinding] = []
    let today = Self.thingsDate(for: now(), calendar: calendar)

    clauses.append(
      query.list == .repeating
        ? "TASK.rt1_recurrenceRule IS NOT NULL" : "TASK.rt1_recurrenceRule IS NULL")

    if query.list == .trash {
      clauses.append(Self.todoEffectiveTrashedExpression)
    } else {
      clauses.append("NOT (\(Self.todoEffectiveTrashedExpression))")
    }

    switch query.status {
    case .incomplete:
      clauses.append("TASK.status = 0")
    case .completed:
      clauses.append("TASK.status = 3")
    case .canceled:
      clauses.append("TASK.status = 2")
    case .all:
      clauses.append("TASK.status IN (0, 2, 3)")
    }

    switch query.list {
    case .all:
      break
    case .inbox:
      clauses.append("TASK.status = 0 AND TASK.start = 0")
    case .today:
      clauses.append(
        """
        TASK.status = 0 AND (
            (TASK.start = 1 AND TASK.startDate IS NOT NULL)
            OR (TASK.start = 2 AND TASK.startDate IS NOT NULL AND TASK.startDate <= \(today))
            OR (
                TASK.startDate IS NULL
                AND TASK.deadline IS NOT NULL
                AND TASK.deadline <= \(today)
                AND TASK.deadlineSuppressionDate IS NULL
            )
        )
        """
      )
      clauses.append("IFNULL(PROJECT.start, -1) != 2")
      clauses.append("IFNULL(HEADING_PROJECT.start, -1) != 2")
    case .tomorrow:
      let tomorrow = calendar.date(byAdding: .day, value: 1, to: now()) ?? now()
      clauses.append("TASK.status = 0 AND TASK.startDate = ?")
      bindings.append(.integer(Int64(Self.thingsDate(for: tomorrow, calendar: calendar))))
    case .upcoming:
      clauses.append(
        "TASK.status = 0 AND TASK.start = 2 AND TASK.startDate IS NOT NULL AND TASK.startDate > \(today)"
      )
    case .anytime:
      clauses.append("TASK.status = 0 AND TASK.start = 1 AND TASK.startDate IS NULL")
    case .someday:
      clauses.append("TASK.status = 0 AND TASK.start = 2 AND TASK.startDate IS NULL")
    case .deadlines:
      clauses.append("TASK.status = 0 AND TASK.deadline IS NOT NULL")
    case .logbook:
      clauses.append(Self.todoLoggedExpression)
    case .repeating:
      break
    case .trash:
      break
    }

    if ![.all, .logbook, .repeating, .trash].contains(query.list) {
      clauses.append("NOT (\(Self.todoLoggedExpression))")
    }

    if let value = query.query, !value.isEmpty {
      clauses.append(
        """
        (
          TASK.title LIKE ? ESCAPE '\\' COLLATE NOCASE
          OR TASK.notes LIKE ? ESCAPE '\\' COLLATE NOCASE
          OR EXISTS (
            SELECT 1
            FROM TMChecklistItem AS SEARCH_CHECKLIST
            WHERE SEARCH_CHECKLIST.task = TASK.uuid
              AND IFNULL(SEARCH_CHECKLIST.leavesTombstone, 0) = 0
              AND SEARCH_CHECKLIST.title LIKE ? ESCAPE '\\' COLLATE NOCASE
          )
        )
        """
      )
      let pattern = Self.likePattern(value)
      bindings.append(contentsOf: [.text(pattern), .text(pattern), .text(pattern)])
    }
    if let value = query.project, !value.isEmpty {
      let raw = ThingsEntityID.parse(value).rawID
      clauses.append(
        "(PROJECT.uuid = ? OR PROJECT.title = ? COLLATE NOCASE OR HEADING_PROJECT.uuid = ? OR HEADING_PROJECT.title = ? COLLATE NOCASE)"
      )
      bindings.append(contentsOf: [.text(raw), .text(value), .text(raw), .text(value)])
    }
    if let value = query.area, !value.isEmpty {
      let raw = ThingsEntityID.parse(value).rawID
      clauses.append(
        "(DIRECT_AREA.uuid = ? OR DIRECT_AREA.title = ? COLLATE NOCASE OR PROJECT_AREA.uuid = ? OR PROJECT_AREA.title = ? COLLATE NOCASE OR HEADING_PROJECT_AREA.uuid = ? OR HEADING_PROJECT_AREA.title = ? COLLATE NOCASE)"
      )
      bindings.append(contentsOf: [
        .text(raw), .text(value), .text(raw), .text(value), .text(raw), .text(value),
      ])
    }
    if let value = query.heading, !value.isEmpty {
      let raw = ThingsEntityID.parse(value).rawID
      clauses.append("(HEADING.uuid = ? OR HEADING.title = ? COLLATE NOCASE)")
      bindings.append(contentsOf: [.text(raw), .text(value)])
    }
    if let value = query.tag, !value.isEmpty {
      let raw = ThingsEntityID.parse(value).rawID
      clauses.append(
        query.includeInheritedTags
          ? Self.todoAllMatchingTagExpression : Self.todoDirectTagExpression)
      bindings.append(contentsOf: [.text(raw), .text(value)])
    }

    if let evening = query.evening {
      clauses.append(evening ? "TASK.startBucket = 1" : "IFNULL(TASK.startBucket, 0) != 1")
    }
    if let hasReminder = query.hasReminder {
      clauses.append(hasReminder ? "TASK.reminderTime IS NOT NULL" : "TASK.reminderTime IS NULL")
    }
    if let isLogged = query.isLogged {
      clauses.append(isLogged ? Self.todoLoggedExpression : "NOT (\(Self.todoLoggedExpression))")
    }
    try appendReminderFilter(
      dateColumn: Self.effectiveStartDateExpression,
      timeColumn: "TASK.reminderTime",
      from: query.reminderFrom,
      to: query.reminderTo,
      clauses: &clauses,
      bindings: &bindings
    )
    try appendTimestampFilter(
      column: "TASK.creationDate",
      from: query.createdFrom,
      to: query.createdTo,
      clauses: &clauses,
      bindings: &bindings
    )
    try appendTimestampFilter(
      column: "TASK.userModificationDate",
      from: query.updatedFrom,
      to: query.updatedTo,
      clauses: &clauses,
      bindings: &bindings
    )
    try appendTimestampFilter(
      column: "TASK.stopDate",
      from: query.completedFrom,
      to: query.completedTo,
      clauses: &clauses,
      bindings: &bindings
    )

    try appendDateFilter(
      column: Self.effectiveStartDateExpression,
      exact: query.scheduledOn,
      from: query.scheduledFrom,
      to: query.scheduledTo,
      clauses: &clauses,
      bindings: &bindings
    )
    try appendDateFilter(
      column: "TASK.deadline",
      exact: query.deadlineOn,
      from: query.deadlineFrom,
      to: query.deadlineTo,
      clauses: &clauses,
      bindings: &bindings
    )

    return (clauses.map { "(\($0))" }.joined(separator: " AND "), bindings)
  }

  private func todoOrderClause(_ query: ThingsTodoQuery) -> String {
    let expression: String
    switch query.orderBy {
    case .things:
      expression = query.list == .today ? "IFNULL(TASK.todayIndex, 0)" : "TASK.\"index\""
    case .createdAt: expression = "TASK.creationDate"
    case .updatedAt: expression = "TASK.userModificationDate"
    case .scheduledDate: expression = Self.effectiveStartDateExpression
    case .reminderAt:
      expression = Self.reminderSortExpression(
        dateColumn: Self.effectiveStartDateExpression,
        timeColumn: "TASK.reminderTime"
      )
    case .deadline: expression = "TASK.deadline"
    case .completedAt: expression = "TASK.stopDate"
    case .title: expression = "TASK.title COLLATE NOCASE"
    }
    return "\(expression) \(query.orderDirection == .descending ? "DESC" : "ASC")"
  }
}

extension ThingsStore {
  private func makeTodo(from statement: OpaquePointer, in database: OpaquePointer) throws
    -> ThingsTodo
  {
    let rawID = Self.stringValue(statement, column: 0) ?? ""
    return ThingsTodo(
      id: ThingsEntityID.make(.todo, rawID: rawID),
      type: .todo,
      title: Self.stringValue(statement, column: 1) ?? "",
      status: Self.itemStatus(from: sqlite3_column_int(statement, 2)),
      list: Self.stringValue(statement, column: 3),
      when: Self.stringValue(statement, column: 4),
      deadline: Self.stringValue(statement, column: 5),
      completedAt: Self.stringValue(statement, column: 6),
      createdAt: Self.stringValue(statement, column: 7),
      updatedAt: Self.stringValue(statement, column: 8),
      notes: Self.stringValue(statement, column: 9),
      area: Self.reference(
        kind: .area, id: Self.stringValue(statement, column: 10),
        title: Self.stringValue(statement, column: 11)),
      project: Self.reference(
        kind: .project, id: Self.stringValue(statement, column: 12),
        title: Self.stringValue(statement, column: 13)),
      heading: Self.reference(
        kind: .heading, id: Self.stringValue(statement, column: 14),
        title: Self.stringValue(statement, column: 15)),
      tags: try fetchTagTitles(for: rawID, in: database),
      checklistItems: try fetchChecklistItems(for: rawID, in: database),
      url: Self.showURL(rawID),
      evening: sqlite3_column_int(statement, 16) == 1,
      reminderTime: Self.stringValue(statement, column: 17),
      reminderAt: Self.reminderDateTime(
        date: Self.stringValue(statement, column: 4),
        time: Self.stringValue(statement, column: 17)
      ),
      isLogged: sqlite3_column_int(statement, 18) != 0,
      allMatchingTags: try fetchAllMatchingTagTitles(forTask: rawID, in: database),
      repeating: Self.repeatingMetadata(from: statement, startingAt: 19, kind: .todo)
    )
  }

  private func fetchChecklistItems(for rawID: String, in database: OpaquePointer) throws
    -> [ThingsChecklistItem]
  {
    let statement = try prepareStatement(
      in: database,
      sql: """
        SELECT
            uuid,
            title,
            status,
            "index",
            datetime(stopDate, 'unixepoch', 'localtime'),
            datetime(creationDate, 'unixepoch', 'localtime'),
            datetime(userModificationDate, 'unixepoch', 'localtime')
        FROM TMChecklistItem
        WHERE task = ? AND IFNULL(leavesTombstone, 0) = 0
        ORDER BY "index"
        """
    )
    defer { sqlite3_finalize(statement) }
    try bind([.text(rawID)], to: statement, in: database)
    var items: [ThingsChecklistItem] = []
    while try step(statement, in: database) {
      items.append(
        ThingsChecklistItem(
          title: Self.stringValue(statement, column: 1) ?? "",
          status: Self.itemStatus(from: sqlite3_column_int(statement, 2)),
          id: Self.stringValue(statement, column: 0),
          index: Int(sqlite3_column_int64(statement, 3)),
          completedAt: Self.stringValue(statement, column: 4),
          createdAt: Self.stringValue(statement, column: 5),
          updatedAt: Self.stringValue(statement, column: 6)
        )
      )
    }
    return items
  }

  private static let todoLoggedExpression = """
    (
      TASK.status IN (2, 3)
      OR IFNULL(PROJECT.status, 0) IN (2, 3)
      OR IFNULL(HEADING.status, 0) IN (2, 3)
      OR IFNULL(HEADING_PROJECT.status, 0) IN (2, 3)
    )
    """

  private static let effectiveStartDateExpression = """
    CASE
      WHEN TASK.rt1_recurrenceRule IS NOT NULL THEN TASK.rt1_nextInstanceStartDate
      ELSE TASK.startDate
    END
    """

  private static let todoDirectTagExpression = """
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
      WHERE TAG_LINK.tasks = TASK.uuid
    )
    """

  private static let todoAllMatchingTagExpression = """
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
            AND TAG_LINK.tasks IN (TASK.uuid, PROJECT.uuid, HEADING_PROJECT.uuid)
        )
        OR EXISTS (
          SELECT 1 FROM TMAreaTag AS AREA_TAG
          WHERE AREA_TAG.tags = MATCHING_TAG.uuid
            AND AREA_TAG.areas IN (
              DIRECT_AREA.uuid,
              PROJECT_AREA.uuid,
              HEADING_PROJECT_AREA.uuid
            )
        )
    )
    """
}
