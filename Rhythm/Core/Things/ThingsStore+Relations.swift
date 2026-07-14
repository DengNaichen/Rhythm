import SQLite3

extension ThingsStore {
  func fetchTagTitles(for rawID: String, in database: OpaquePointer) throws -> [String] {
    let statement = try prepareStatement(
      in: database,
      sql: """
        SELECT TAG.title
        FROM TMTaskTag AS TASK_TAG
        JOIN TMTag AS TAG ON TAG.uuid = TASK_TAG.tags
        WHERE TASK_TAG.tasks = ?
        ORDER BY TAG."index", TAG.uuid
        """
    )
    defer { sqlite3_finalize(statement) }
    try bind([.text(rawID)], to: statement, in: database)
    return try fetchSingleStringColumn(from: statement, in: database)
  }

  func fetchAllMatchingTagTitles(forTask rawID: String, in database: OpaquePointer) throws
    -> [String]
  {
    let statement = try prepareStatement(
      in: database,
      sql: """
        WITH RECURSIVE
        EFFECTIVE_TAGS(uuid) AS (
            SELECT TASK_TAG.tags
            FROM TMTaskTag AS TASK_TAG
            WHERE TASK_TAG.tasks = ?
            UNION
            SELECT PROJECT_TAG.tags
            FROM TMTask AS TASK
            LEFT JOIN TMTask AS DIRECT_PROJECT ON TASK.project = DIRECT_PROJECT.uuid
            LEFT JOIN TMTask AS HEADING ON TASK.heading = HEADING.uuid
            LEFT JOIN TMTask AS HEADING_PROJECT ON HEADING.project = HEADING_PROJECT.uuid
            JOIN TMTaskTag AS PROJECT_TAG
              ON PROJECT_TAG.tasks = COALESCE(DIRECT_PROJECT.uuid, HEADING_PROJECT.uuid)
            WHERE TASK.uuid = ?
            UNION
            SELECT AREA_TAG.tags
            FROM TMTask AS TASK
            LEFT JOIN TMTask AS DIRECT_PROJECT ON TASK.project = DIRECT_PROJECT.uuid
            LEFT JOIN TMTask AS HEADING ON TASK.heading = HEADING.uuid
            LEFT JOIN TMTask AS HEADING_PROJECT ON HEADING.project = HEADING_PROJECT.uuid
            JOIN TMAreaTag AS AREA_TAG
              ON AREA_TAG.areas = COALESCE(TASK.area, DIRECT_PROJECT.area, HEADING_PROJECT.area)
            WHERE TASK.uuid = ?
        ),
        ALL_MATCHING_TAGS(uuid) AS (
            SELECT uuid
            FROM EFFECTIVE_TAGS
            UNION
            SELECT TAG.parent
            FROM TMTag AS TAG
            JOIN ALL_MATCHING_TAGS AS MATCHING_TAG ON MATCHING_TAG.uuid = TAG.uuid
            WHERE TAG.parent IS NOT NULL
        )
        SELECT TAG.title
        FROM ALL_MATCHING_TAGS AS MATCHING_TAG
        JOIN TMTag AS TAG ON TAG.uuid = MATCHING_TAG.uuid
        ORDER BY TAG."index", TAG.uuid
        """
    )
    defer { sqlite3_finalize(statement) }
    try bind([.text(rawID), .text(rawID), .text(rawID)], to: statement, in: database)
    return try fetchSingleStringColumn(from: statement, in: database)
  }

  func fetchAreaTagTitles(for rawID: String, in database: OpaquePointer) throws
    -> [String]
  {
    let statement = try prepareStatement(
      in: database,
      sql: """
        SELECT TAG.title
        FROM TMAreaTag AS AREA_TAG
        JOIN TMTag AS TAG ON TAG.uuid = AREA_TAG.tags
        WHERE AREA_TAG.areas = ?
        ORDER BY TAG."index", TAG.uuid
        """
    )
    defer { sqlite3_finalize(statement) }
    try bind([.text(rawID)], to: statement, in: database)
    return try fetchSingleStringColumn(from: statement, in: database)
  }
}

extension ThingsStore {
  func fetchHeadings(forProject rawID: String, in database: OpaquePointer) throws
    -> [ThingsReference]
  {
    try fetchReferences(
      sql:
        "SELECT uuid, title FROM TMTask WHERE type = 2 AND trashed = 0 AND project = ? ORDER BY \"index\"",
      bindings: [.text(rawID)],
      kind: .heading,
      in: database
    )
  }

  func fetchTodos(forProject rawID: String, in database: OpaquePointer) throws
    -> [ThingsReference]
  {
    try fetchReferences(
      sql: """
        SELECT DISTINCT TASK.uuid, TASK.title
        FROM TMTask AS TASK
        LEFT JOIN TMTask AS HEADING ON TASK.heading = HEADING.uuid
        WHERE TASK.type = 0 AND TASK.trashed = 0
          AND (TASK.project = ? OR HEADING.project = ?)
        ORDER BY TASK."index", TASK.uuid
        """,
      bindings: [.text(rawID), .text(rawID)],
      kind: .todo,
      in: database
    )
  }

  func fetchTodos(forHeading rawID: String, in database: OpaquePointer) throws
    -> [ThingsReference]
  {
    try fetchReferences(
      sql: """
        SELECT uuid, title
        FROM TMTask
        WHERE type = 0 AND trashed = 0 AND heading = ?
        ORDER BY "index", uuid
        """,
      bindings: [.text(rawID)],
      kind: .todo,
      in: database
    )
  }

  func fetchProjects(forArea rawID: String, in database: OpaquePointer) throws
    -> [ThingsReference]
  {
    try fetchReferences(
      sql:
        "SELECT uuid, title FROM TMTask WHERE type = 1 AND trashed = 0 AND area = ? ORDER BY \"index\"",
      bindings: [.text(rawID)],
      kind: .project,
      in: database
    )
  }

  func fetchTodos(forArea rawID: String, in database: OpaquePointer) throws
    -> [ThingsReference]
  {
    try fetchReferences(
      sql: """
        SELECT DISTINCT TASK.uuid, TASK.title
        FROM TMTask AS TASK
        LEFT JOIN TMTask AS PROJECT ON TASK.project = PROJECT.uuid
        LEFT JOIN TMTask AS HEADING ON TASK.heading = HEADING.uuid
        LEFT JOIN TMTask AS HEADING_PROJECT ON HEADING.project = HEADING_PROJECT.uuid
        WHERE TASK.type = 0 AND TASK.trashed = 0
          AND (TASK.area = ? OR PROJECT.area = ? OR HEADING_PROJECT.area = ?)
        ORDER BY TASK."index", TASK.uuid
        """,
      bindings: [.text(rawID), .text(rawID), .text(rawID)],
      kind: .todo,
      in: database
    )
  }

  func fetchTaggedItems(
    forTag tagID: String,
    type: Int,
    kind: ThingsEntityKind,
    in database: OpaquePointer
  ) throws -> [ThingsReference] {
    let sql: String
    switch kind {
    case .todo:
      sql = """
        WITH RECURSIVE MATCHING_TAGS(uuid) AS (
            SELECT uuid
            FROM TMTag
            WHERE uuid = ?
            UNION
            SELECT CHILD.uuid
            FROM TMTag AS CHILD
            JOIN MATCHING_TAGS AS PARENT ON CHILD.parent = PARENT.uuid
        )
        SELECT DISTINCT TASK.uuid, TASK.title
        FROM TMTask AS TASK
        LEFT JOIN TMTask AS PROJECT ON TASK.project = PROJECT.uuid
        LEFT JOIN TMTask AS HEADING ON TASK.heading = HEADING.uuid
        LEFT JOIN TMTask AS HEADING_PROJECT ON HEADING.project = HEADING_PROJECT.uuid
        LEFT JOIN TMArea AS DIRECT_AREA ON TASK.area = DIRECT_AREA.uuid
        LEFT JOIN TMArea AS PROJECT_AREA ON PROJECT.area = PROJECT_AREA.uuid
        LEFT JOIN TMArea AS HEADING_PROJECT_AREA ON HEADING_PROJECT.area = HEADING_PROJECT_AREA.uuid
        WHERE TASK.type = ?
          AND NOT (\(Self.todoEffectiveTrashedExpression))
          AND (
            EXISTS (
              SELECT 1
              FROM TMTaskTag AS TAG_LINK
              JOIN MATCHING_TAGS AS MATCHING_TAG ON MATCHING_TAG.uuid = TAG_LINK.tags
              WHERE TAG_LINK.tasks IN (TASK.uuid, PROJECT.uuid, HEADING_PROJECT.uuid)
            )
            OR EXISTS (
              SELECT 1
              FROM TMAreaTag AS AREA_TAG
              JOIN MATCHING_TAGS AS MATCHING_TAG ON MATCHING_TAG.uuid = AREA_TAG.tags
              WHERE AREA_TAG.areas IN (
                DIRECT_AREA.uuid,
                PROJECT_AREA.uuid,
                HEADING_PROJECT_AREA.uuid
              )
            )
          )
        ORDER BY TASK."index", TASK.uuid
        """
    case .project:
      sql = """
        WITH RECURSIVE MATCHING_TAGS(uuid) AS (
            SELECT uuid
            FROM TMTag
            WHERE uuid = ?
            UNION
            SELECT CHILD.uuid
            FROM TMTag AS CHILD
            JOIN MATCHING_TAGS AS PARENT ON CHILD.parent = PARENT.uuid
        )
        SELECT DISTINCT PROJECT.uuid, PROJECT.title
        FROM TMTask AS PROJECT
        LEFT JOIN TMArea AS AREA ON PROJECT.area = AREA.uuid
        WHERE PROJECT.type = ?
          AND PROJECT.trashed = 0
          AND (
            EXISTS (
              SELECT 1
              FROM TMTaskTag AS TAG_LINK
              JOIN MATCHING_TAGS AS MATCHING_TAG ON MATCHING_TAG.uuid = TAG_LINK.tags
              WHERE TAG_LINK.tasks = PROJECT.uuid
            )
            OR EXISTS (
              SELECT 1
              FROM TMAreaTag AS AREA_TAG
              JOIN MATCHING_TAGS AS MATCHING_TAG ON MATCHING_TAG.uuid = AREA_TAG.tags
              WHERE AREA_TAG.areas = AREA.uuid
            )
          )
        ORDER BY PROJECT."index", PROJECT.uuid
        """
    case .heading, .area, .tag, .all:
      return []
    }
    return try fetchReferences(
      sql: sql,
      bindings: [.text(tagID), .integer(Int64(type))],
      kind: kind,
      in: database
    )
  }

  func fetchReferences(
    sql: String,
    bindings: [SQLiteBinding],
    kind: ThingsEntityKind,
    in database: OpaquePointer
  ) throws -> [ThingsReference] {
    try fetchReferences(sql: sql, bindings: bindings, prefixKind: kind, in: database)
  }

  func countProjects(forArea rawID: String, in database: OpaquePointer) throws -> Int {
    try count(
      sql: "SELECT COUNT(*) FROM TMTask WHERE type = 1 AND trashed = 0 AND area = ?",
      bindings: [.text(rawID)],
      in: database
    )
  }

  func countTodos(forArea rawID: String, in database: OpaquePointer) throws -> Int {
    try fetchTodos(forArea: rawID, in: database).count
  }

  private func fetchReferences(
    sql: String,
    bindings: [SQLiteBinding],
    prefixKind: ThingsEntityKind?,
    in database: OpaquePointer
  ) throws -> [ThingsReference] {
    let statement = try prepareStatement(in: database, sql: sql)
    defer { sqlite3_finalize(statement) }
    try bind(bindings, to: statement, in: database)
    var values: [ThingsReference] = []
    while try step(statement, in: database) {
      let rawID = Self.stringValue(statement, column: 0) ?? ""
      values.append(
        ThingsReference(
          id: prefixKind.map { ThingsEntityID.make($0, rawID: rawID) } ?? rawID,
          title: Self.stringValue(statement, column: 1) ?? ""
        )
      )
    }
    return values
  }

  private func count(sql: String, bindings: [SQLiteBinding], in database: OpaquePointer) throws
    -> Int
  {
    let statement = try prepareStatement(in: database, sql: sql)
    defer { sqlite3_finalize(statement) }
    try bind(bindings, to: statement, in: database)
    guard try step(statement, in: database) else { return 0 }
    return Int(sqlite3_column_int64(statement, 0))
  }

  private func fetchSingleStringColumn(
    from statement: OpaquePointer,
    in database: OpaquePointer
  ) throws -> [String] {
    var values: [String] = []
    while try step(statement, in: database) {
      if let value = Self.stringValue(statement, column: 0) { values.append(value) }
    }
    return values
  }
}
