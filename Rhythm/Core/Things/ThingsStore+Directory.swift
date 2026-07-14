import Foundation
import SQLite3

extension ThingsStore {
  func listAreas(_ query: ThingsDirectoryQuery) throws -> ThingsPage<ThingsArea> {
    try databaseAccess.withReadableDatabaseURL { databaseURL in
      try withDatabase(at: databaseURL.path) { database in
        var clauses = ["IFNULL(AREA.visible, 1) != 0"]
        var bindings: [SQLiteBinding] = []
        if let search = query.query, !search.isEmpty {
          clauses.append("AREA.title LIKE ? ESCAPE '\\' COLLATE NOCASE")
          bindings.append(.text(Self.likePattern(search)))
        }
        let sql = """
          SELECT AREA.uuid, AREA.title
          FROM TMArea AS AREA
          WHERE \(clauses.joined(separator: " AND "))
          ORDER BY AREA."index", AREA.uuid
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

        var areas: [ThingsArea] = []
        while try step(statement, in: database) {
          let rawID = Self.stringValue(statement, column: 0) ?? ""
          areas.append(
            ThingsArea(
              id: ThingsEntityID.make(.area, rawID: rawID),
              type: .area,
              title: Self.stringValue(statement, column: 1) ?? "",
              projectCount: try countProjects(forArea: rawID, in: database),
              todoCount: try countTodos(forArea: rawID, in: database),
              projects: query.includeItems ? try fetchProjects(forArea: rawID, in: database) : nil,
              todos: query.includeItems ? try fetchTodos(forArea: rawID, in: database) : nil,
              url: Self.showURL(rawID),
              tags: try fetchAreaTagTitles(for: rawID, in: database),
              allMatchingTags: try fetchAreaTagTitles(for: rawID, in: database)
            )
          )
        }
        return Self.databasePage(areas, request: query.page)
      }
    }
  }

  func listTags(_ query: ThingsDirectoryQuery) throws -> ThingsPage<ThingsTag> {
    try databaseAccess.withReadableDatabaseURL { databaseURL in
      try withDatabase(at: databaseURL.path) { database in
        var clauses: [String] = []
        var bindings: [SQLiteBinding] = []
        if let search = query.query, !search.isEmpty {
          clauses.append("TAG.title LIKE ? ESCAPE '\\' COLLATE NOCASE")
          bindings.append(.text(Self.likePattern(search)))
        }
        let sql = """
          SELECT TAG.uuid, TAG.title, TAG.shortcut
          FROM TMTag AS TAG
          WHERE \(clauses.isEmpty ? "1 = 1" : clauses.joined(separator: " AND "))
          ORDER BY TAG."index", TAG.uuid
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

        var tags: [ThingsTag] = []
        while try step(statement, in: database) {
          let rawID = Self.stringValue(statement, column: 0) ?? ""
          let todos = try fetchTaggedItems(forTag: rawID, type: 0, kind: .todo, in: database)
          let projects = try fetchTaggedItems(forTag: rawID, type: 1, kind: .project, in: database)
          tags.append(
            ThingsTag(
              id: ThingsEntityID.make(.tag, rawID: rawID),
              type: .tag,
              title: Self.stringValue(statement, column: 1) ?? "",
              shortcut: Self.stringValue(statement, column: 2),
              todoCount: todos.count,
              projectCount: projects.count,
              todos: query.includeItems ? todos : nil,
              projects: query.includeItems ? projects : nil,
              url: Self.showURL(rawID),
              parent: try fetchTagParent(for: rawID, in: database),
              children: try fetchTagChildren(for: rawID, in: database),
              path: try fetchTagPath(for: rawID, in: database)
            )
          )
        }
        return Self.databasePage(tags, request: query.page)
      }
    }
  }

  func getArea(idOrTitle: String, includeItems: Bool) throws -> ThingsArea {
    let parsed = ThingsEntityID.parse(idOrTitle)
    let byID = parsed.kind != nil || Self.looksLikeThingsID(parsed.rawID)
    return try databaseAccess.withReadableDatabaseURL { databaseURL in
      try withDatabase(at: databaseURL.path) { database in
        let statement = try prepareStatement(
          in: database,
          sql: "SELECT uuid, title FROM TMArea WHERE \(byID ? "uuid" : "title") = ? COLLATE NOCASE"
        )
        defer { sqlite3_finalize(statement) }
        try bind([.text(parsed.rawID)], to: statement, in: database)
        var matches: [ThingsArea] = []
        while try step(statement, in: database) {
          let rawID = Self.stringValue(statement, column: 0) ?? ""
          matches.append(
            ThingsArea(
              id: ThingsEntityID.make(.area, rawID: rawID),
              type: .area,
              title: Self.stringValue(statement, column: 1) ?? "",
              projectCount: try countProjects(forArea: rawID, in: database),
              todoCount: try countTodos(forArea: rawID, in: database),
              projects: includeItems ? try fetchProjects(forArea: rawID, in: database) : nil,
              todos: includeItems ? try fetchTodos(forArea: rawID, in: database) : nil,
              url: Self.showURL(rawID),
              tags: try fetchAreaTagTitles(for: rawID, in: database),
              allMatchingTags: try fetchAreaTagTitles(for: rawID, in: database)
            )
          )
        }
        guard !matches.isEmpty else { throw ThingsServiceError.entityNotFound(idOrTitle) }
        guard matches.count == 1 else { throw ThingsServiceError.ambiguousReference(idOrTitle) }
        return matches[0]
      }
    }
  }

  func getTag(idOrTitle: String, includeItems: Bool) throws -> ThingsTag {
    let parsed = ThingsEntityID.parse(idOrTitle)
    let byID = parsed.kind != nil || Self.looksLikeThingsID(parsed.rawID)
    return try databaseAccess.withReadableDatabaseURL { databaseURL in
      try withDatabase(at: databaseURL.path) { database in
        let statement = try prepareStatement(
          in: database,
          sql:
            "SELECT uuid, title, shortcut FROM TMTag WHERE \(byID ? "uuid" : "title") = ? COLLATE NOCASE"
        )
        defer { sqlite3_finalize(statement) }
        try bind([.text(parsed.rawID)], to: statement, in: database)
        var matches: [ThingsTag] = []
        while try step(statement, in: database) {
          let rawID = Self.stringValue(statement, column: 0) ?? ""
          let todos = try fetchTaggedItems(forTag: rawID, type: 0, kind: .todo, in: database)
          let projects = try fetchTaggedItems(forTag: rawID, type: 1, kind: .project, in: database)
          matches.append(
            ThingsTag(
              id: ThingsEntityID.make(.tag, rawID: rawID),
              type: .tag,
              title: Self.stringValue(statement, column: 1) ?? "",
              shortcut: Self.stringValue(statement, column: 2),
              todoCount: todos.count,
              projectCount: projects.count,
              todos: includeItems ? todos : nil,
              projects: includeItems ? projects : nil,
              url: Self.showURL(rawID),
              parent: try fetchTagParent(for: rawID, in: database),
              children: try fetchTagChildren(for: rawID, in: database),
              path: try fetchTagPath(for: rawID, in: database)
            )
          )
        }
        guard !matches.isEmpty else { throw ThingsServiceError.entityNotFound(idOrTitle) }
        guard matches.count == 1 else { throw ThingsServiceError.ambiguousReference(idOrTitle) }
        return matches[0]
      }
    }
  }

  private func fetchTagParent(for rawID: String, in database: OpaquePointer) throws
    -> ThingsReference?
  {
    let statement = try prepareStatement(
      in: database,
      sql: """
        SELECT PARENT.uuid, PARENT.title
        FROM TMTag AS TAG
        JOIN TMTag AS PARENT ON TAG.parent = PARENT.uuid
        WHERE TAG.uuid = ?
        """
    )
    defer { sqlite3_finalize(statement) }
    try bind([.text(rawID)], to: statement, in: database)
    guard try step(statement, in: database) else { return nil }
    return Self.reference(
      kind: .tag,
      id: Self.stringValue(statement, column: 0),
      title: Self.stringValue(statement, column: 1)
    )
  }

  private func fetchTagChildren(for rawID: String, in database: OpaquePointer) throws
    -> [ThingsReference]
  {
    try fetchReferences(
      sql: "SELECT uuid, title FROM TMTag WHERE parent = ? ORDER BY \"index\", uuid",
      bindings: [.text(rawID)],
      kind: .tag,
      in: database
    )
  }

  private func fetchTagPath(for rawID: String, in database: OpaquePointer) throws
    -> [ThingsReference]
  {
    var path: [ThingsReference] = []
    var nextID: String? = rawID
    var visited = Set<String>()
    while let currentID = nextID, visited.insert(currentID).inserted, path.count < 64 {
      let statement = try prepareStatement(
        in: database,
        sql: "SELECT uuid, title, parent FROM TMTag WHERE uuid = ?"
      )
      defer { sqlite3_finalize(statement) }
      try bind([.text(currentID)], to: statement, in: database)
      guard try step(statement, in: database) else { break }
      let id = Self.stringValue(statement, column: 0) ?? currentID
      path.append(
        ThingsReference(
          id: ThingsEntityID.make(.tag, rawID: id),
          title: Self.stringValue(statement, column: 1) ?? ""
        ))
      nextID = Self.stringValue(statement, column: 2)
    }
    return path.reversed()
  }
}
