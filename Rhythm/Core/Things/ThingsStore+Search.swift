import Foundation

extension ThingsStore {
  func search(_ query: ThingsSearchQuery) throws -> ThingsPage<ThingsSearchHit> {
    let searchPage = ThingsPageRequest(limit: Int.max - 1)
    var statuses: [ThingsItemStatus] = [.incomplete]
    if query.includeCompleted { statuses.append(.completed) }
    if query.includeCanceled { statuses.append(.canceled) }
    var hits: [ThingsSearchHit] = []

    if query.type == .all || query.type == .todo {
      var todos: [ThingsTodo] = []
      for status in statuses {
        var todoQuery = ThingsTodoQuery()
        todoQuery.query = query.query
        todoQuery.status = status
        todoQuery.page = searchPage
        todos.append(contentsOf: try listTodos(todoQuery).items)
        todoQuery.list = .repeating
        todos.append(contentsOf: try listTodos(todoQuery).items)
        if query.includeTrashed {
          todoQuery.list = .trash
          todos.append(contentsOf: try listTodos(todoQuery).items)
        }
      }
      hits.append(
        contentsOf: todos.map { todo in
          ThingsSearchHit(
            ref: todo.id,
            id: ThingsEntityID.parse(todo.id).rawID,
            type: .todo,
            title: todo.title,
            status: todo.status,
            context: todo.project?.title ?? todo.area?.title ?? todo.list,
            url: todo.url
          )
        })
    }

    if query.type == .all || query.type == .heading {
      var headings: [ThingsHeading] = []
      for status in statuses {
        var headingQuery = ThingsHeadingQuery()
        headingQuery.query = query.query
        headingQuery.status = status
        headingQuery.includeTrashed = query.includeTrashed
        headingQuery.page = searchPage
        headings.append(contentsOf: try listHeadings(headingQuery).items)
      }
      hits.append(
        contentsOf: headings.map { heading in
          ThingsSearchHit(
            ref: heading.id,
            id: ThingsEntityID.parse(heading.id).rawID,
            type: .heading,
            title: heading.title,
            status: heading.status,
            context: heading.project.title,
            url: heading.url
          )
        })
    }

    if query.type == .all || query.type == .project {
      var projects: [ThingsProject] = []
      for status in statuses {
        var projectQuery = ThingsProjectQuery()
        projectQuery.query = query.query
        projectQuery.status = status
        projectQuery.page = searchPage
        projects.append(contentsOf: try listProjects(projectQuery).items)
        projectQuery.when = .repeating
        projects.append(contentsOf: try listProjects(projectQuery).items)
        if query.includeTrashed {
          projectQuery.when = .trash
          projects.append(contentsOf: try listProjects(projectQuery).items)
        }
      }
      hits.append(
        contentsOf: projects.map { project in
          ThingsSearchHit(
            ref: project.id,
            id: ThingsEntityID.parse(project.id).rawID,
            type: .project,
            title: project.title,
            status: project.status,
            context: project.area?.title ?? project.list,
            url: project.url
          )
        })
    }

    if query.type == .all || query.type == .area {
      var areaQuery = ThingsDirectoryQuery()
      areaQuery.query = query.query
      areaQuery.page = searchPage
      hits.append(
        contentsOf: try listAreas(areaQuery).items.map { area in
          ThingsSearchHit(
            ref: area.id,
            id: ThingsEntityID.parse(area.id).rawID,
            type: .area,
            title: area.title,
            status: nil,
            context: "\(area.projectCount) projects, \(area.todoCount) todos",
            url: area.url
          )
        })
    }

    if query.type == .all || query.type == .tag {
      var tagQuery = ThingsDirectoryQuery()
      tagQuery.query = query.query
      tagQuery.page = searchPage
      hits.append(
        contentsOf: try listTags(tagQuery).items.map { tag in
          ThingsSearchHit(
            ref: tag.id,
            id: ThingsEntityID.parse(tag.id).rawID,
            type: .tag,
            title: tag.title,
            status: nil,
            context: "\(tag.todoCount) todos, \(tag.projectCount) projects",
            url: tag.url
          )
        })
    }

    var seen = Set<String>()
    hits = hits.filter { seen.insert($0.ref).inserted }

    let needle = query.query.folding(
      options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    hits.sort { lhs, rhs in
      let lhsScore = Self.searchScore(title: lhs.title, needle: needle)
      let rhsScore = Self.searchScore(title: rhs.title, needle: needle)
      if lhsScore != rhsScore { return lhsScore < rhsScore }
      if lhs.type != rhs.type { return lhs.type.rawValue < rhs.type.rawValue }
      return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    return Self.page(hits, request: query.page)
  }

  func fetch(_ reference: String, includeItems: Bool) throws -> ThingsEntity {
    let parsed = ThingsEntityID.parse(reference)
    switch parsed.kind {
    case .todo:
      return .todo(try getTodo(id: parsed.rawID))
    case .heading:
      return .heading(try getHeading(idOrTitle: parsed.rawID, includeTodos: includeItems))
    case .project:
      return .project(try getProject(idOrTitle: parsed.rawID, includeTodos: includeItems))
    case .area:
      return .area(try getArea(idOrTitle: parsed.rawID, includeItems: includeItems))
    case .tag:
      return .tag(try getTag(idOrTitle: parsed.rawID, includeItems: includeItems))
    case .all:
      throw ThingsServiceError.invalidIdentifier(reference)
    case nil:
      if let todo = try entityIfPresent({ try getTodo(id: parsed.rawID) }) {
        return .todo(todo)
      }
      if let heading = try entityIfPresent({
        try getHeading(idOrTitle: parsed.rawID, includeTodos: includeItems)
      }) {
        return .heading(heading)
      }
      if let project = try entityIfPresent({
        try getProject(idOrTitle: parsed.rawID, includeTodos: includeItems)
      }) {
        return .project(project)
      }
      if let area = try entityIfPresent({
        try getArea(idOrTitle: parsed.rawID, includeItems: includeItems)
      }) {
        return .area(area)
      }
      if let tag = try entityIfPresent({
        try getTag(idOrTitle: parsed.rawID, includeItems: includeItems)
      }) {
        return .tag(tag)
      }
      throw ThingsServiceError.entityNotFound(reference)
    }
  }

  private func entityIfPresent<Entity>(_ operation: () throws -> Entity) throws -> Entity? {
    do {
      return try operation()
    } catch ThingsServiceError.entityNotFound {
      return nil
    }
  }

  private static func page<Item: Encodable>(
    _ values: [Item],
    request: ThingsPageRequest
  ) -> ThingsPage<Item> {
    guard request.offset < values.count else { return ThingsPage(items: [], nextCursor: nil) }
    let end = min(request.offset + request.limit, values.count)
    let items = Array(values[request.offset..<end])
    let cursor = end < values.count ? String(end) : nil
    return ThingsPage(items: items, nextCursor: cursor)
  }

  private static func searchScore(title: String, needle: String) -> Int {
    let value = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    if value == needle { return 0 }
    if value.hasPrefix(needle) { return 1 }
    if value.contains(needle) { return 2 }
    return 3
  }
}
