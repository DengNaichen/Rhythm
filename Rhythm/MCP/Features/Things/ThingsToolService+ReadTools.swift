import Foundation
import JSONSchema
import OrderedCollections

extension ThingsToolService {
  func searchTool() -> Tool {
    Tool(
      name: "things_search",
      title: "Search Things",
      description:
        "Full-text search across Things todos, projects, areas, and tags. Use list tools for structured filtering.",
      systemImage: "magnifyingglass",
      inputSchema: .object(
        properties: [
          "query": .string(description: "Keyword or phrase to search for."),
          "type": enumSchema(
            ThingsEntityKind.self,
            description: "Entity type to search.",
            defaultValue: ThingsEntityKind.all.rawValue
          ),
          "include_completed": .boolean(
            description: "Include completed todos and projects.",
            default: false
          ),
          "include_canceled": .boolean(
            description: "Include canceled todos and projects.",
            default: false
          ),
          "include_trashed": .boolean(
            description: "Include entities currently in the Things Trash.",
            default: false
          ),
          "cursor": .string(description: "Opaque cursor from a previous response."),
          "limit": .integer(
            description: "Maximum results to return.",
            default: .int(10),
            minimum: 1,
            maximum: 50
          ),
        ],
        required: ["query"],
        additionalProperties: false
      ),
      readOnlyHint: true,
      openWorldHint: false
    ) { arguments in
      try await self.activate()
      let decoder = ToolArgumentsDecoder(arguments: arguments)
      var query = ThingsSearchQuery(
        query: try decoder.requiredString("query"),
        type: try decoder.enumValue(for: "type", default: ThingsEntityKind.all),
        includeCompleted: try decoder.optionalBool("include_completed") ?? false,
        includeCanceled: try decoder.optionalBool("include_canceled") ?? false,
        page: try self.pageRequest(arguments, defaultLimit: 10, maximumLimit: 50)
      )
      query.includeTrashed = try decoder.optionalBool("include_trashed") ?? false
      return try self.repository.search(query)
    }
  }

  func fetchTool() -> Tool {
    Tool(
      name: "things_fetch",
      title: "Fetch Things Entity",
      description:
        "Fetch full details for a todo, project, heading, area, or tag returned by things_search.",
      systemImage: "doc.text.magnifyingglass",
      inputSchema: .object(
        properties: [
          "ref": .string(
            description:
              "Entity reference such as todo:<id> or project:<id>. Raw Things IDs are also accepted."
          ),
          "include_items": .boolean(
            description: "Include child items for projects, areas, and tags.",
            default: false
          ),
        ],
        required: ["ref"],
        additionalProperties: false
      ),
      readOnlyHint: true,
      openWorldHint: false
    ) { arguments in
      try await self.activate()
      let decoder = ToolArgumentsDecoder(arguments: arguments)
      return try self.repository.fetch(
        try decoder.requiredString("ref"),
        includeItems: try decoder.optionalBool("include_items") ?? false
      )
    }
  }

  func listTodosTool() -> Tool {
    Tool(
      name: "things_list_todos",
      title: "List Things Todos",
      description:
        "List and filter Things todos. This replaces separate Today, Inbox, and date-specific tools.",
      systemImage: "checklist",
      inputSchema: .object(
        properties: [
          "list": enumSchema(
            ThingsBuiltinList.self,
            description: "Built-in Things list to read.",
            defaultValue: ThingsBuiltinList.all.rawValue
          ),
          "query": .string(description: "Search todo title and notes."),
          "status": enumSchema(
            ThingsItemStatus.self,
            description: "Todo status. Defaults to all for Logbook or Trash, otherwise incomplete."
          ),
          "project": .string(description: "Project ID, reference, or exact title."),
          "area": .string(description: "Area ID, reference, or exact title."),
          "heading": .string(description: "Heading ID or exact title."),
          "tag": .string(description: "Tag ID, reference, or exact title."),
          "include_inherited_tags": .boolean(
            description: "Match tags inherited from a project or area.", default: true),
          "evening": .boolean(description: "Filter by This Evening placement."),
          "has_reminder": .boolean(description: "Filter by reminder presence."),
          "reminder_from": .string(description: "Inclusive ISO 8601 reminder lower bound."),
          "reminder_to": .string(description: "Inclusive ISO 8601 reminder upper bound."),
          "is_logged": .boolean(description: "Filter by actual Logbook membership."),
          "created_from": .string(description: "Inclusive ISO 8601 creation lower bound."),
          "created_to": .string(description: "Inclusive ISO 8601 creation upper bound."),
          "updated_from": .string(description: "Inclusive ISO 8601 modification lower bound."),
          "updated_to": .string(description: "Inclusive ISO 8601 modification upper bound."),
          "completed_from": .string(description: "Inclusive ISO 8601 completion lower bound."),
          "completed_to": .string(description: "Inclusive ISO 8601 completion upper bound."),
          "scheduled_on": dateSchema("Exact scheduled date."),
          "scheduled_from": dateSchema("Inclusive scheduled-date lower bound."),
          "scheduled_to": dateSchema("Inclusive scheduled-date upper bound."),
          "deadline_on": dateSchema("Exact deadline date."),
          "deadline_from": dateSchema("Inclusive deadline lower bound."),
          "deadline_to": dateSchema("Inclusive deadline upper bound."),
          "order_by": enumSchema(
            ThingsOrderBy.self,
            description: "Sort field.",
            defaultValue: ThingsOrderBy.things.rawValue
          ),
          "order_direction": enumSchema(
            ThingsOrderDirection.self,
            description: "Sort direction.",
            defaultValue: ThingsOrderDirection.ascending.rawValue
          ),
          "cursor": .string(description: "Opaque cursor from a previous response."),
          "limit": pageLimitSchema(),
        ],
        additionalProperties: false
      ),
      readOnlyHint: true,
      openWorldHint: false
    ) { arguments in
      try await self.activate()
      let decoder = ToolArgumentsDecoder(arguments: arguments)
      let list = try decoder.enumValue(for: "list", default: ThingsBuiltinList.all)
      let defaultStatus: ThingsItemStatus =
        (list == .logbook || list == .trash) ? .all : .incomplete
      var query = ThingsTodoQuery()
      query.list = list
      query.query = try decoder.optionalString("query")
      query.status = try decoder.enumValue(for: "status", default: defaultStatus)
      query.project = try decoder.optionalString("project")
      query.area = try decoder.optionalString("area")
      query.heading = try decoder.optionalString("heading")
      query.tag = try decoder.optionalString("tag")
      query.includeInheritedTags = try decoder.optionalBool("include_inherited_tags") ?? true
      query.evening = try decoder.optionalBool("evening")
      query.hasReminder = try decoder.optionalBool("has_reminder")
      query.reminderFrom = try decoder.optionalString("reminder_from")
      query.reminderTo = try decoder.optionalString("reminder_to")
      query.isLogged = try decoder.optionalBool("is_logged")
      query.createdFrom = try decoder.optionalString("created_from")
      query.createdTo = try decoder.optionalString("created_to")
      query.updatedFrom = try decoder.optionalString("updated_from")
      query.updatedTo = try decoder.optionalString("updated_to")
      query.completedFrom = try decoder.optionalString("completed_from")
      query.completedTo = try decoder.optionalString("completed_to")
      query.scheduledOn = try decoder.optionalString("scheduled_on")
      query.scheduledFrom = try decoder.optionalString("scheduled_from")
      query.scheduledTo = try decoder.optionalString("scheduled_to")
      query.deadlineOn = try decoder.optionalString("deadline_on")
      query.deadlineFrom = try decoder.optionalString("deadline_from")
      query.deadlineTo = try decoder.optionalString("deadline_to")
      try self.validateTodoDateFilters(query)
      query.orderBy = try decoder.enumValue(for: "order_by", default: ThingsOrderBy.things)
      query.orderDirection = try decoder.enumValue(
        for: "order_direction",
        default: ThingsOrderDirection.ascending
      )
      query.page = try self.pageRequest(arguments)
      return try self.repository.listTodos(query)
    }
  }

  func getTodoTool() -> Tool {
    Tool(
      name: "things_get_todo",
      title: "Get Things Todo",
      description: "Get a complete Things todo by ID.",
      systemImage: "checkmark.square",
      inputSchema: .object(
        properties: [
          "id": .string(description: "Todo ID or todo:<id> reference.")
        ],
        required: ["id"],
        additionalProperties: false
      ),
      readOnlyHint: true,
      openWorldHint: false
    ) { arguments in
      try await self.activate()
      return try self.repository.getTodo(
        id: ToolArgumentsDecoder(arguments: arguments).requiredString("id")
      )
    }
  }

  func listHeadingsTool() -> Tool {
    Tool(
      name: "things_list_headings",
      title: "List Things Headings",
      description: "List and filter project headings as first-class entities.",
      systemImage: "text.alignleft",
      inputSchema: .object(
        properties: [
          "query": .string(description: "Search heading titles."),
          "status": enumSchema(
            ThingsItemStatus.self,
            description: "Heading lifecycle status.",
            defaultValue: ThingsItemStatus.all.rawValue
          ),
          "project": .string(description: "Project ID, reference, or exact title."),
          "is_logged": .boolean(description: "Filter by whether the heading is in Logbook."),
          "include_trashed": .boolean(
            description: "Include headings currently in the Things Trash.", default: false),
          "include_todos": .boolean(
            description: "Include child todo references.", default: false),
          "order_by": enumSchema(
            ThingsOrderBy.self,
            description: "Sort field.",
            defaultValue: ThingsOrderBy.things.rawValue
          ),
          "order_direction": enumSchema(
            ThingsOrderDirection.self,
            description: "Sort direction.",
            defaultValue: ThingsOrderDirection.ascending.rawValue
          ),
          "cursor": .string(description: "Opaque cursor from a previous response."),
          "limit": pageLimitSchema(),
        ],
        additionalProperties: false
      ),
      readOnlyHint: true,
      openWorldHint: false
    ) { arguments in
      try await self.activate()
      let decoder = ToolArgumentsDecoder(arguments: arguments)
      var query = ThingsHeadingQuery()
      query.query = try decoder.optionalString("query")
      query.status = try decoder.enumValue(for: "status", default: ThingsItemStatus.all)
      query.project = try decoder.optionalString("project")
      query.isLogged = try decoder.optionalBool("is_logged")
      query.includeTrashed = try decoder.optionalBool("include_trashed") ?? false
      query.includeTodos = try decoder.optionalBool("include_todos") ?? false
      query.orderBy = try decoder.enumValue(for: "order_by", default: ThingsOrderBy.things)
      query.orderDirection = try decoder.enumValue(
        for: "order_direction", default: ThingsOrderDirection.ascending)
      query.page = try self.pageRequest(arguments)
      return try self.repository.listHeadings(query)
    }
  }

  func getHeadingTool() -> Tool {
    Tool(
      name: "things_get_heading",
      title: "Get Things Heading",
      description: "Get a Things heading by ID or unique exact title.",
      systemImage: "text.alignleft",
      inputSchema: .object(
        properties: [
          "id": .string(description: "Heading ID, heading:<id>, or unique exact title."),
          "include_todos": .boolean(
            description: "Include child todo references.", default: false),
        ],
        required: ["id"],
        additionalProperties: false
      ),
      readOnlyHint: true,
      openWorldHint: false
    ) { arguments in
      try await self.activate()
      let decoder = ToolArgumentsDecoder(arguments: arguments)
      return try self.repository.getHeading(
        idOrTitle: try decoder.requiredString("id"),
        includeTodos: try decoder.optionalBool("include_todos") ?? false
      )
    }
  }

  func listProjectsTool() -> Tool {
    Tool(
      name: "things_list_projects",
      title: "List Things Projects",
      description: "List and filter Things projects.",
      systemImage: "folder",
      inputSchema: .object(
        properties: [
          "query": .string(description: "Search project title and notes."),
          "status": enumSchema(
            ThingsItemStatus.self,
            description:
              "Project status. Defaults to all for Logbook or Trash, otherwise incomplete."
          ),
          "area": .string(description: "Area ID, reference, or exact title."),
          "tag": .string(description: "Tag ID, reference, or exact title."),
          "include_inherited_tags": .boolean(
            description: "Match tags inherited from the containing area.", default: true),
          "evening": .boolean(description: "Filter by This Evening placement."),
          "has_reminder": .boolean(description: "Filter by reminder presence."),
          "reminder_from": .string(description: "Inclusive ISO 8601 reminder lower bound."),
          "reminder_to": .string(description: "Inclusive ISO 8601 reminder upper bound."),
          "is_logged": .boolean(description: "Filter by actual Logbook membership."),
          "created_from": .string(description: "Inclusive ISO 8601 creation lower bound."),
          "created_to": .string(description: "Inclusive ISO 8601 creation upper bound."),
          "updated_from": .string(description: "Inclusive ISO 8601 modification lower bound."),
          "updated_to": .string(description: "Inclusive ISO 8601 modification upper bound."),
          "completed_from": .string(description: "Inclusive ISO 8601 completion lower bound."),
          "completed_to": .string(description: "Inclusive ISO 8601 completion upper bound."),
          "when": enumSchema(
            ThingsBuiltinList.self,
            description: "Schedule bucket.",
            defaultValue: ThingsBuiltinList.all.rawValue
          ),
          "deadline_from": dateSchema("Inclusive deadline lower bound."),
          "deadline_to": dateSchema("Inclusive deadline upper bound."),
          "include_todos": .boolean(description: "Include child todo references.", default: false),
          "order_by": enumSchema(
            ThingsOrderBy.self,
            description: "Sort field.",
            defaultValue: ThingsOrderBy.things.rawValue
          ),
          "order_direction": enumSchema(
            ThingsOrderDirection.self,
            description: "Sort direction.",
            defaultValue: ThingsOrderDirection.ascending.rawValue
          ),
          "cursor": .string(description: "Opaque cursor from a previous response."),
          "limit": pageLimitSchema(),
        ],
        additionalProperties: false
      ),
      readOnlyHint: true,
      openWorldHint: false
    ) { arguments in
      try await self.activate()
      let decoder = ToolArgumentsDecoder(arguments: arguments)
      var query = ThingsProjectQuery()
      query.query = try decoder.optionalString("query")
      query.area = try decoder.optionalString("area")
      query.tag = try decoder.optionalString("tag")
      query.includeInheritedTags = try decoder.optionalBool("include_inherited_tags") ?? true
      query.evening = try decoder.optionalBool("evening")
      query.hasReminder = try decoder.optionalBool("has_reminder")
      query.reminderFrom = try decoder.optionalString("reminder_from")
      query.reminderTo = try decoder.optionalString("reminder_to")
      query.isLogged = try decoder.optionalBool("is_logged")
      query.createdFrom = try decoder.optionalString("created_from")
      query.createdTo = try decoder.optionalString("created_to")
      query.updatedFrom = try decoder.optionalString("updated_from")
      query.updatedTo = try decoder.optionalString("updated_to")
      query.completedFrom = try decoder.optionalString("completed_from")
      query.completedTo = try decoder.optionalString("completed_to")
      query.when = try decoder.enumValue(for: "when", default: ThingsBuiltinList.all)
      let defaultStatus: ThingsItemStatus =
        (query.when == .logbook || query.when == .trash) ? .all : .incomplete
      query.status = try decoder.enumValue(for: "status", default: defaultStatus)
      query.deadlineFrom = try decoder.optionalString("deadline_from")
      query.deadlineTo = try decoder.optionalString("deadline_to")
      try self.validateProjectDateFilters(query)
      query.includeTodos = try decoder.optionalBool("include_todos") ?? false
      query.orderBy = try decoder.enumValue(for: "order_by", default: ThingsOrderBy.things)
      query.orderDirection = try decoder.enumValue(
        for: "order_direction",
        default: ThingsOrderDirection.ascending
      )
      query.page = try self.pageRequest(arguments)
      return try self.repository.listProjects(query)
    }
  }

  func getProjectTool() -> Tool {
    Tool(
      name: "things_get_project",
      title: "Get Things Project",
      description: "Get a Things project by ID or unique exact title.",
      systemImage: "folder.badge.gearshape",
      inputSchema: .object(
        properties: [
          "id": .string(description: "Project ID, project:<id> reference, or unique exact title."),
          "include_todos": .boolean(description: "Include child todo references.", default: false),
        ],
        required: ["id"],
        additionalProperties: false
      ),
      readOnlyHint: true,
      openWorldHint: false
    ) { arguments in
      try await self.activate()
      let decoder = ToolArgumentsDecoder(arguments: arguments)
      return try self.repository.getProject(
        idOrTitle: try decoder.requiredString("id"),
        includeTodos: try decoder.optionalBool("include_todos") ?? false
      )
    }
  }

  func listAreasTool() -> Tool {
    directoryTool(
      name: "things_list_areas",
      title: "List Things Areas",
      description: "List Things areas.",
      systemImage: "square.grid.2x2",
      implementation: { query in try self.repository.listAreas(query) }
    )
  }

  func listTagsTool() -> Tool {
    directoryTool(
      name: "things_list_tags",
      title: "List Things Tags",
      description: "List Things tags.",
      systemImage: "tag",
      implementation: { query in try self.repository.listTags(query) }
    )
  }

  private func directoryTool<Result: Encodable>(
    name: String,
    title: String,
    description: String,
    systemImage: String,
    implementation: @escaping (ThingsDirectoryQuery) throws -> Result
  ) -> Tool {
    Tool(
      name: name,
      title: title,
      description: description,
      systemImage: systemImage,
      inputSchema: .object(
        properties: [
          "query": .string(description: "Filter by title."),
          "include_items": .boolean(
            description: "Include related item references.", default: false),
          "cursor": .string(description: "Opaque cursor from a previous response."),
          "limit": pageLimitSchema(),
        ],
        additionalProperties: false
      ),
      readOnlyHint: true,
      openWorldHint: false
    ) { arguments in
      try await self.activate()
      let decoder = ToolArgumentsDecoder(arguments: arguments)
      var query = ThingsDirectoryQuery()
      query.query = try decoder.optionalString("query")
      query.includeItems = try decoder.optionalBool("include_items") ?? false
      query.page = try self.pageRequest(arguments)
      return try implementation(query)
    }
  }

  private func validateTodoDateFilters(_ query: ThingsTodoQuery) throws {
    let calendar = Calendar.current
    try validateDateRange(
      exactKey: "scheduled_on",
      exact: query.scheduledOn,
      fromKey: "scheduled_from",
      from: query.scheduledFrom,
      toKey: "scheduled_to",
      to: query.scheduledTo,
      expected: "YYYY-MM-DD",
      parser: { value, _ in ThingsDateTimeInput.date(value, calendar: calendar) }
    )
    try validateDateRange(
      exactKey: "deadline_on",
      exact: query.deadlineOn,
      fromKey: "deadline_from",
      from: query.deadlineFrom,
      toKey: "deadline_to",
      to: query.deadlineTo,
      expected: "YYYY-MM-DD",
      parser: { value, _ in ThingsDateTimeInput.date(value, calendar: calendar) }
    )
    try validateDateRange(
      fromKey: "reminder_from",
      from: query.reminderFrom,
      toKey: "reminder_to",
      to: query.reminderTo,
      expected: "local YYYY-MM-DDTHH:MM or RFC 3339",
      parser: { value, upperBound in
        ThingsDateTimeInput.reminder(value, upperBound: upperBound, calendar: calendar)
      }
    )
    try validateTimestampRanges(
      createdFrom: query.createdFrom,
      createdTo: query.createdTo,
      updatedFrom: query.updatedFrom,
      updatedTo: query.updatedTo,
      completedFrom: query.completedFrom,
      completedTo: query.completedTo,
      calendar: calendar
    )
  }

  private func validateProjectDateFilters(_ query: ThingsProjectQuery) throws {
    let calendar = Calendar.current
    try validateDateRange(
      fromKey: "deadline_from",
      from: query.deadlineFrom,
      toKey: "deadline_to",
      to: query.deadlineTo,
      expected: "YYYY-MM-DD",
      parser: { value, _ in ThingsDateTimeInput.date(value, calendar: calendar) }
    )
    try validateDateRange(
      fromKey: "reminder_from",
      from: query.reminderFrom,
      toKey: "reminder_to",
      to: query.reminderTo,
      expected: "local YYYY-MM-DDTHH:MM or RFC 3339",
      parser: { value, upperBound in
        ThingsDateTimeInput.reminder(value, upperBound: upperBound, calendar: calendar)
      }
    )
    try validateTimestampRanges(
      createdFrom: query.createdFrom,
      createdTo: query.createdTo,
      updatedFrom: query.updatedFrom,
      updatedTo: query.updatedTo,
      completedFrom: query.completedFrom,
      completedTo: query.completedTo,
      calendar: calendar
    )
  }

  private func validateTimestampRanges(
    createdFrom: String?,
    createdTo: String?,
    updatedFrom: String?,
    updatedTo: String?,
    completedFrom: String?,
    completedTo: String?,
    calendar: Calendar
  ) throws {
    let parser: (String, Bool) -> Date? = { value, upperBound in
      ThingsDateTimeInput.timestamp(value, upperBound: upperBound, calendar: calendar)
    }
    try validateDateRange(
      fromKey: "created_from",
      from: createdFrom,
      toKey: "created_to",
      to: createdTo,
      expected: "local YYYY-MM-DD[THH:MM[:SS]] or RFC 3339",
      parser: parser
    )
    try validateDateRange(
      fromKey: "updated_from",
      from: updatedFrom,
      toKey: "updated_to",
      to: updatedTo,
      expected: "local YYYY-MM-DD[THH:MM[:SS]] or RFC 3339",
      parser: parser
    )
    try validateDateRange(
      fromKey: "completed_from",
      from: completedFrom,
      toKey: "completed_to",
      to: completedTo,
      expected: "local YYYY-MM-DD[THH:MM[:SS]] or RFC 3339",
      parser: parser
    )
  }

  private func validateDateRange(
    exactKey: String? = nil,
    exact: String? = nil,
    fromKey: String,
    from: String?,
    toKey: String,
    to: String?,
    expected: String,
    parser: (String, Bool) -> Date?
  ) throws {
    if let exact {
      if from != nil || to != nil {
        throw ThingsServiceError.conflictingArguments(
          exactKey ?? "exact",
          "\(fromKey)/\(toKey)"
        )
      }
      guard parser(exact, false) != nil else {
        throw ThingsServiceError.invalidValue(exactKey ?? "exact", reason: "expected \(expected)")
      }
      return
    }

    let lower = try from.map { value in
      guard let date = parser(value, false) else {
        throw ThingsServiceError.invalidValue(fromKey, reason: "expected \(expected)")
      }
      return date
    }
    let upper = try to.map { value in
      guard let date = parser(value, true) else {
        throw ThingsServiceError.invalidValue(toKey, reason: "expected \(expected)")
      }
      return date
    }
    if let lower, let upper, lower > upper {
      throw ThingsServiceError.invalidValue(
        "\(fromKey)/\(toKey)",
        reason: "lower bound must not be later than upper bound"
      )
    }
  }

  private func pageRequest(
    _ arguments: [String: Value],
    defaultLimit: Int = ThingsPageRequest.defaultLimit,
    maximumLimit: Int = ThingsPageRequest.maximumLimit
  ) throws -> ThingsPageRequest {
    let decoder = ToolArgumentsDecoder(arguments: arguments)
    let limit = try decoder.optionalInt("limit") ?? defaultLimit
    guard (1...maximumLimit).contains(limit) else {
      throw ThingsServiceError.invalidValue(
        "limit",
        reason: "expected a value from 1 through \(maximumLimit)"
      )
    }

    let offset: Int
    if let cursor = try decoder.optionalString("cursor") {
      guard let parsedOffset = Int(cursor), parsedOffset >= 0 else {
        throw ThingsServiceError.invalidCursor(cursor)
      }
      offset = parsedOffset
    } else {
      offset = 0
    }
    return ThingsPageRequest(offset: offset, limit: limit)
  }
}
