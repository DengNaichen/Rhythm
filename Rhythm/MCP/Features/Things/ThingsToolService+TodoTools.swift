import Foundation
import JSONSchema
import OrderedCollections

extension ThingsToolService {
  func saveTodoTool() -> Tool {
    Tool(
      name: "things_save_todo",
      title: "Save Things Todo",
      description:
        "Create or update a Things todo. Omit id to create; provide id to update. Omitted fields are unchanged and null clears a field.",
      systemImage: "square.and.pencil",
      inputSchema: .object(
        properties: [
          "id": .string(description: "Todo ID or todo:<id>. Omit when creating."),
          "title": .string(description: "Todo title. Required when creating."),
          "titles": .array(
            description: "Create multiple todos with the same metadata. Create only.",
            items: .string(),
            maxItems: 250
          ),
          "notes": nullableStringSchema("Replacement notes. Null clears notes."),
          "prepend_notes": .string(
            description: "Text to prepend to existing notes. Updates only."),
          "append_notes": .string(
            description: "Text to append to existing notes. Updates only."),
          "when": nullableStringSchema(
            "Schedule value: today, tomorrow, evening, anytime, someday, a date, or date@time. Null clears scheduling."
          ),
          "deadline": nullableStringSchema(
            "Deadline in YYYY-MM-DD format. Null clears the deadline."),
          "tags": nullableStringArraySchema(
            "Replacement tag names. Empty array or null clears all tags."),
          "add_tags": .array(
            description: "Tag names to add without replacing existing tags. Updates only.",
            items: .string()),
          "checklist_items": nullableStringArraySchema(
            "Replacement checklist item titles. Empty array or null clears the checklist.",
            maxItems: 100
          ),
          "prepend_checklist_items": .array(
            description: "Checklist item titles to prepend. Updates only.",
            items: .string(),
            maxItems: 100
          ),
          "append_checklist_items": .array(
            description: "Checklist item titles to append. Updates only.",
            items: .string(),
            maxItems: 100
          ),
          "project": nullableStringSchema(
            "Destination project ID or title. Null removes the project assignment."),
          "area": nullableStringSchema(
            "Destination area ID or title. Null removes the area assignment."),
          "heading": nullableStringSchema(
            "Destination heading ID or title. Null removes the heading assignment."),
          "status": enumSchema(
            ThingsItemStatus.self,
            excluding: [.all],
            description: "Todo lifecycle status."
          ),
          "use_clipboard": enumSchema(
            ThingsClipboardMode.self,
            description: "Populate title, notes, or checklist from the clipboard. Create only."
          ),
          "show_quick_entry": .boolean(
            description: "Open a populated Quick Entry window instead of saving immediately.",
            default: false
          ),
          "duplicate": .boolean(
            description: "Duplicate the existing todo before applying updates. Update only.",
            default: false
          ),
          "creation_date": .string(
            description: "ISO 8601 creation timestamp to preserve during import."),
          "completion_date": .string(
            description: "ISO 8601 completion timestamp for completed or canceled items."),
          "reveal": .boolean(
            description: "Reveal the todo in Things after saving.", default: false),
        ],
        additionalProperties: false
      ),
      destructiveHint: true,
      idempotentHint: false,
      openWorldHint: false
    ) { arguments in
      var request = try self.todoSaveRequest(arguments)
      let options = try self.todoURLCommandOptions(arguments)
      try self.validateTodoURLCommandConflicts(request, options: options)
      try self.validateTodoURLContract(request, options: options)
      let authToken: String?
      if request.isCreate {
        authToken = nil
      } else {
        try await self.activate()
        authToken = try self.repository.authToken()
      }
      try self.validateTodoWriteSemantics(request, options: options)
      try await self.validateWriteTags(request.tags, additional: request.addTags)
      request = try await self.normalizedTodoWriteReferences(request, arguments: arguments)
      try self.validateTodoChecklistLimit(request)
      let url = try self.urlBuilder.saveTodoURL(
        for: request,
        authToken: authToken,
        options: options
      )
      let callback = try await self.callbackExecutor.execute(
        url,
        timeout: options.showQuickEntry ? .seconds(600) : nil
      )
      var rawIDs = callback.thingsIDs
      if rawIDs.isEmpty, let id = request.id {
        rawIDs = [try ThingsEntityID.rawID(id, expectedKind: .todo)]
      }
      let refs = rawIDs.map { ThingsEntityID.make(.todo, rawID: $0) }
      return ThingsWriteResult(
        operation: request.isCreate ? "create" : "update",
        type: .todo,
        ref: refs.first,
        refs: refs,
        title: request.title,
        acknowledged: true,
        verified: false,
        parameters: callback.parameters,
        message: request.isCreate
          ? "Things acknowledged the todo creation command. Read the todo back to verify applied fields."
          : "Things acknowledged the todo update command. Read the todo back to verify applied fields."
      )
    }
  }

  func updateChecklistTool() -> Tool {
    let mutationSchema = JSONSchema.object(
      properties: [
        "id": .string(description: "Checklist item ID returned by things_get_todo."),
        "title": .string(description: "Replacement title."),
        "status": enumSchema(
          ThingsItemStatus.self,
          excluding: [.all],
          description: "Replacement checklist item status."
        ),
      ],
      required: ["id"],
      additionalProperties: false
    )
    let additionSchema = JSONSchema.object(
      properties: [
        "title": .string(description: "New checklist item title."),
        "status": enumSchema(
          ThingsItemStatus.self,
          excluding: [.all],
          description: "Initial checklist item status."
        ),
      ],
      required: ["title"],
      additionalProperties: false
    )

    return Tool(
      name: "things_update_checklist",
      title: "Update Things Checklist",
      description:
        "Update, add, remove, or reorder checklist rows by stable checklist item ID while preserving every row's status.",
      systemImage: "checklist.checked",
      inputSchema: .object(
        properties: [
          "id": .string(description: "Todo ID or todo:<id>."),
          "set": .array(description: "Existing checklist rows to modify.", items: mutationSchema),
          "add": .array(
            description: "Checklist rows to append.", items: additionSchema, maxItems: 100),
          "remove_ids": .array(
            description: "Checklist item IDs to remove.", items: .string(), uniqueItems: true),
          "order": .array(
            description:
              "Checklist item IDs in desired order. Unlisted retained rows follow in their current order.",
            items: .string(),
            uniqueItems: true
          ),
          "reveal": .boolean(description: "Reveal the todo after updating.", default: false),
        ],
        required: ["id"],
        additionalProperties: false
      ),
      destructiveHint: true,
      idempotentHint: false,
      openWorldHint: false
    ) { arguments in
      try await self.activate()
      let decoder = ToolArgumentsDecoder(arguments: arguments)
      let id = try decoder.requiredString("id")
      let rawID = try ThingsEntityID.rawID(id, expectedKind: .todo)
      let todo = try self.repository.getTodo(id: id)
      let mutations = try self.checklistMutations(arguments["set"])
      let additions = try self.checklistAdditions(arguments["add"])
      let removals = Set(try decoder.optionalStringArray("remove_ids") ?? [])
      let order = try decoder.optionalStringArray("order")
      guard !mutations.isEmpty || !additions.isEmpty || !removals.isEmpty || order != nil else {
        throw ThingsServiceError.noChanges
      }

      var items = todo.checklistItems.map {
        MutableThingsChecklistItem(id: $0.id, title: $0.title, status: $0.status)
      }
      let knownIDs = Set(items.compactMap(\.id))
      for removal in removals where !knownIDs.contains(removal) {
        throw ThingsServiceError.invalidValue(
          "remove_ids", reason: "unknown checklist item id \(removal)")
      }
      items.removeAll { item in item.id.map(removals.contains) ?? false }

      for mutation in mutations {
        guard let index = items.firstIndex(where: { $0.id == mutation.id }) else {
          throw ThingsServiceError.invalidValue(
            "set", reason: "unknown checklist item id \(mutation.id)")
        }
        if let title = mutation.title { items[index].title = title }
        if let status = mutation.status { items[index].status = status }
      }
      items.append(contentsOf: additions)

      if let order {
        let orderSet = Set(order)
        guard orderSet.count == order.count else {
          throw ThingsServiceError.invalidValue("order", reason: "IDs must be unique")
        }
        for orderedID in order where !items.contains(where: { $0.id == orderedID }) {
          throw ThingsServiceError.invalidValue(
            "order", reason: "unknown checklist item id \(orderedID)")
        }
        let byID = Dictionary(
          uniqueKeysWithValues: items.compactMap { item in
            item.id.map { ($0, item) }
          })
        let explicitlyOrdered = order.compactMap { byID[$0] }
        let remaining = items.filter { item in
          guard let id = item.id else { return true }
          return !orderSet.contains(id)
        }
        items = explicitlyOrdered + remaining
      }
      guard items.count <= 100 else {
        throw ThingsServiceError.invalidValue(
          "add", reason: "a todo can contain at most 100 checklist items")
      }

      let checklistItems = items.map { item in
        ThingsJSONChecklistItem(
          title: item.title,
          completed: item.status == .completed,
          canceled: item.status == .canceled
        )
      }
      let token = try self.repository.authToken()
      let request = ThingsJSONCommandRequest(
        items: [
          .todo(
            operation: .update,
            id: rawID,
            attributes: ThingsJSONTodoAttributes(checklistItems: checklistItems)
          )
        ],
        authToken: token,
        reveal: try decoder.optionalBool("reveal") ?? false
      )
      let callback = try await self.callbackExecutor.execute(
        try self.urlBuilder.jsonURL(for: request))
      return ThingsWriteResult(
        operation: "update_checklist",
        type: .todo,
        ref: ThingsEntityID.make(.todo, rawID: rawID),
        refs: [ThingsEntityID.make(.todo, rawID: rawID)],
        title: todo.title,
        acknowledged: true,
        verified: false,
        parameters: callback.parameters,
        message:
          "Things acknowledged the checklist update command. Read the todo back to verify applied rows."
      )
    }
  }

  private func todoSaveRequest(_ arguments: [String: Value]) throws -> ThingsTodoSaveRequest {
    let decoder = ToolArgumentsDecoder(arguments: arguments)
    var request = ThingsTodoSaveRequest()
    request.id = try decoder.optionalString("id")
    request.title = try decoder.optionalString("title")
    request.notes = try patchNotes("notes", arguments: arguments)
    request.prependNotes = try optionalNotesMutation("prepend_notes", arguments: arguments)
    request.appendNotes = try optionalNotesMutation("append_notes", arguments: arguments)
    request.when = try patchString("when", arguments: arguments)
    request.deadline = try patchString("deadline", arguments: arguments)
    request.tags = try patchStringArray("tags", arguments: arguments)
    request.addTags = try normalizedArray("add_tags", decoder: decoder)
    request.checklistItems = try patchStringArray("checklist_items", arguments: arguments)
    request.prependChecklistItems = try normalizedArray("prepend_checklist_items", decoder: decoder)
    request.appendChecklistItems = try normalizedArray("append_checklist_items", decoder: decoder)

    let project = try patchString("project", arguments: arguments)
    let area = try patchString("area", arguments: arguments)
    try validateReferencePatch(project, argument: "project", expectedKind: .project)
    try validateReferencePatch(area, argument: "area", expectedKind: .area)
    if project.isChanged && area.isChanged {
      throw ThingsServiceError.conflictingArguments("project", "area")
    }
    request.destination = project.isChanged ? project : area
    request.heading = try patchString("heading", arguments: arguments)
    try validateReferencePatch(request.heading, argument: "heading", expectedKind: .heading)
    if case .value = request.heading {
      if area.isChanged {
        throw ThingsServiceError.conflictingArguments("heading", "area")
      }
      if case .clear = project {
        throw ThingsServiceError.conflictingArguments("heading", "project")
      }
    }
    request.status = try optionalMutableStatus("status", decoder: decoder)
    request.reveal = try decoder.optionalBool("reveal") ?? false

    try validateTextMutationConflicts(
      replacement: request.notes,
      prepend: request.prependNotes,
      append: request.appendNotes,
      field: "notes"
    )
    if request.tags.isChanged && request.addTags != nil {
      throw ThingsServiceError.conflictingArguments("tags", "add_tags")
    }
    if request.checklistItems.isChanged
      && (request.prependChecklistItems != nil || request.appendChecklistItems != nil)
    {
      throw ThingsServiceError.conflictingArguments(
        "checklist_items",
        "prepend_checklist_items/append_checklist_items"
      )
    }

    if request.isCreate {
      let hasBulkTitles =
        try normalizedArray(
          "titles", decoder: ToolArgumentsDecoder(arguments: arguments)) != nil
      let usesClipboard =
        try ToolArgumentsDecoder(arguments: arguments)
        .optionalString("use_clipboard") != nil
      let showsQuickEntry =
        try ToolArgumentsDecoder(arguments: arguments).optionalBool("show_quick_entry") ?? false
      guard request.title != nil || hasBulkTitles || usesClipboard || showsQuickEntry else {
        throw ThingsServiceError.missingRequiredArgument("title")
      }
      if let updateOnlyArgument = firstTodoUpdateOnlyArgument(request) {
        throw ThingsServiceError.invalidValue(
          updateOnlyArgument, reason: "only valid when id is provided")
      }
      if case .value = request.heading, case .value = project {
        // A project destination makes the heading meaningful on create.
      } else if case .value = request.heading {
        throw ThingsServiceError.invalidValue(
          "heading", reason: "creating under a heading also requires project")
      }
    } else {
      _ = try ThingsEntityID.rawID(request.id ?? "", expectedKind: .todo)
      let hasExtendedChange =
        (try ToolArgumentsDecoder(arguments: arguments).optionalBool("duplicate") ?? false)
        || arguments["creation_date"] != nil
        || arguments["completion_date"] != nil
      guard todoRequestHasChanges(request) || hasExtendedChange else {
        throw ThingsServiceError.noChanges
      }
    }
    return request
  }

  private func todoURLCommandOptions(
    _ arguments: [String: Value]
  ) throws -> ThingsTodoURLCommandOptions {
    let decoder = ToolArgumentsDecoder(arguments: arguments)
    let titles = try normalizedArray("titles", decoder: decoder)
    try validateMaximumCount(titles, key: "titles", maximum: 250)
    return ThingsTodoURLCommandOptions(
      titles: titles,
      useClipboard: try decoder.optionalEnumValue(
        for: "use_clipboard", as: ThingsClipboardMode.self),
      showQuickEntry: try decoder.optionalBool("show_quick_entry") ?? false,
      duplicate: try decoder.optionalBool("duplicate") ?? false,
      creationDate: try iso8601String("creation_date", decoder: decoder),
      completionDate: try iso8601String("completion_date", decoder: decoder)
    )
  }

  private func validateTodoURLCommandConflicts(
    _ request: ThingsTodoSaveRequest,
    options: ThingsTodoURLCommandOptions
  ) throws {
    if options.titles != nil, request.title != nil {
      throw ThingsServiceError.conflictingArguments("title", "titles")
    }
    if options.titles != nil, options.showQuickEntry {
      throw ThingsServiceError.conflictingArguments("titles", "show_quick_entry")
    }
    if options.showQuickEntry, request.reveal {
      throw ThingsServiceError.conflictingArguments("show_quick_entry", "reveal")
    }
    guard let useClipboard = options.useClipboard else { return }
    switch useClipboard {
    case .replaceTitle:
      if request.title != nil || options.titles != nil || request.notes.isChanged {
        throw ThingsServiceError.conflictingArguments("use_clipboard", "title/titles/notes")
      }
    case .replaceNotes:
      if request.notes.isChanged {
        throw ThingsServiceError.conflictingArguments("use_clipboard", "notes")
      }
    case .replaceChecklistItems:
      if request.checklistItems.isChanged {
        throw ThingsServiceError.conflictingArguments("use_clipboard", "checklist_items")
      }
    }
  }

  private func validateTodoURLContract(
    _ request: ThingsTodoSaveRequest,
    options: ThingsTodoURLCommandOptions
  ) throws {
    try validateURLLength(request.title, key: "title")
    try validateLineSeparatedURLValues(options.titles, key: "titles", maximumCount: 250)
    try validateURLLength(request.notes, key: "notes", maximum: 10_000)
    try validateURLLength(request.prependNotes, key: "prepend_notes", maximum: 10_000)
    try validateURLLength(request.appendNotes, key: "append_notes", maximum: 10_000)
    try validateURLLength(request.when, key: "when")
    try validateURLLength(request.deadline, key: "deadline")
    try validateJoinedURLValues(request.tags, key: "tags", separator: ",")
    try validateJoinedURLValues(request.addTags, key: "add_tags", separator: ",")
    try validateLineSeparatedURLValues(
      request.checklistItems, key: "checklist_items", maximumCount: 100)
    try validateLineSeparatedURLValues(
      request.prependChecklistItems, key: "prepend_checklist_items", maximumCount: 100)
    try validateLineSeparatedURLValues(
      request.appendChecklistItems, key: "append_checklist_items", maximumCount: 100)
    try validateURLLength(request.destination, key: "project/area")
    try validateURLLength(request.heading, key: "heading")
    try validateURLLength(options.creationDate, key: "creation_date")
    try validateURLLength(options.completionDate, key: "completion_date")
    try validateSchedule(request.when, key: "when", isCreate: request.isCreate)
  }

  private func validateTodoWriteSemantics(
    _ request: ThingsTodoSaveRequest,
    options: ThingsTodoURLCommandOptions
  ) throws {
    try validateNotFuture(options.creationDate, key: "creation_date")
    try validateNotFuture(options.completionDate, key: "completion_date")

    let requiresExisting =
      !request.isCreate
      && (request.when.isChanged || request.deadline.isChanged || request.status != nil
        || options.duplicate || options.completionDate != nil)
    let existing = requiresExisting ? try repository.getTodo(id: request.id ?? "") : nil
    if existing?.repeating != nil {
      let forbidden: String?
      if request.when.isChanged {
        forbidden = "when"
      } else if request.deadline.isChanged {
        forbidden = "deadline"
      } else if request.status != nil {
        forbidden = "status"
      } else if options.duplicate {
        forbidden = "duplicate"
      } else if options.completionDate != nil {
        forbidden = "completion_date"
      } else {
        forbidden = nil
      }
      if let forbidden {
        throw ThingsServiceError.invalidValue(
          forbidden, reason: "Things cannot apply this field to a repeating todo")
      }
    }

    if options.completionDate != nil {
      let finalStatus = request.status ?? existing?.status
      guard finalStatus == .completed || finalStatus == .canceled else {
        throw ThingsServiceError.invalidValue(
          "completion_date", reason: "the todo must be completed or canceled")
      }
    }
  }

  private func checklistMutations(_ value: Value?) throws -> [ThingsChecklistMutation] {
    guard let value else { return [] }
    guard let values = value.arrayValue else {
      throw ThingsServiceError.invalidType("set", expected: "array")
    }
    return try values.enumerated().map { index, value in
      guard let object = value.objectValue else {
        throw ThingsServiceError.invalidType("set[\(index)]", expected: "object")
      }
      let decoder = ToolArgumentsDecoder(arguments: object)
      let id = try decoder.requiredString("id")
      let title = try decoder.optionalString("title")
      let status = try decoder.optionalEnumValue(for: "status", as: ThingsItemStatus.self)
      if status == .all {
        throw ThingsServiceError.invalidValue("set[\(index)].status", reason: "all is read-only")
      }
      guard title != nil || status != nil else {
        throw ThingsServiceError.invalidValue(
          "set[\(index)]", reason: "title or status is required")
      }
      return ThingsChecklistMutation(id: id, title: title, status: status)
    }
  }

  private func checklistAdditions(_ value: Value?) throws -> [MutableThingsChecklistItem] {
    guard let value else { return [] }
    guard let values = value.arrayValue else {
      throw ThingsServiceError.invalidType("add", expected: "array")
    }
    return try values.enumerated().map { index, value in
      guard let object = value.objectValue else {
        throw ThingsServiceError.invalidType("add[\(index)]", expected: "object")
      }
      let decoder = ToolArgumentsDecoder(arguments: object)
      let title = try decoder.requiredString("title")
      let status =
        try decoder.optionalEnumValue(for: "status", as: ThingsItemStatus.self)
        ?? .incomplete
      guard status != .all else {
        throw ThingsServiceError.invalidValue("add[\(index)].status", reason: "all is read-only")
      }
      return MutableThingsChecklistItem(id: nil, title: title, status: status)
    }
  }

  private func validateTodoChecklistLimit(_ request: ThingsTodoSaveRequest) throws {
    let replacementCount: Int?
    switch request.checklistItems {
    case .unchanged:
      replacementCount = nil
    case .clear:
      replacementCount = 0
    case .value(let values):
      replacementCount = values.count
    }

    let addedCount =
      (request.prependChecklistItems?.count ?? 0)
      + (request.appendChecklistItems?.count ?? 0)
    let finalCount: Int
    if let replacementCount {
      finalCount = replacementCount
    } else if addedCount > 0, let id = request.id {
      finalCount = try repository.getTodo(id: id).checklistItems.count + addedCount
    } else {
      finalCount = addedCount
    }

    guard finalCount <= 100 else {
      throw ThingsServiceError.invalidValue(
        "checklist_items", reason: "a todo can contain at most 100 checklist items")
    }
  }

  private func firstTodoUpdateOnlyArgument(_ request: ThingsTodoSaveRequest) -> String? {
    if request.prependNotes != nil { return "prepend_notes" }
    if request.appendNotes != nil { return "append_notes" }
    if request.addTags != nil { return "add_tags" }
    if request.prependChecklistItems != nil { return "prepend_checklist_items" }
    if request.appendChecklistItems != nil { return "append_checklist_items" }
    return nil
  }

  private func todoRequestHasChanges(_ request: ThingsTodoSaveRequest) -> Bool {
    request.title != nil
      || request.notes.isChanged
      || request.prependNotes != nil
      || request.appendNotes != nil
      || request.when.isChanged
      || request.deadline.isChanged
      || request.tags.isChanged
      || request.addTags != nil
      || request.checklistItems.isChanged
      || request.prependChecklistItems != nil
      || request.appendChecklistItems != nil
      || request.destination.isChanged
      || request.heading.isChanged
      || request.status != nil
      || request.reveal
  }
}

private struct ThingsChecklistMutation {
  let id: String
  let title: String?
  let status: ThingsItemStatus?
}

private struct MutableThingsChecklistItem {
  let id: String?
  var title: String
  var status: ThingsItemStatus
}
