import Foundation
import JSONSchema
import OrderedCollections

extension ThingsToolService {
  func saveProjectTool() -> Tool {
    Tool(
      name: "things_save_project",
      title: "Save Things Project",
      description:
        "Create or update a Things project. Omit id to create; provide id to update. Omitted fields are unchanged and null clears a field.",
      systemImage: "folder.badge.plus",
      inputSchema: .object(
        properties: [
          "id": .string(description: "Project ID or project:<id>. Omit when creating."),
          "title": .string(description: "Project title. Required when creating."),
          "notes": nullableStringSchema("Replacement notes. Null clears notes."),
          "prepend_notes": .string(
            description: "Text to prepend to existing notes. Updates only."),
          "append_notes": .string(
            description: "Text to append to existing notes. Updates only."),
          "when": nullableStringSchema("Schedule value. Null clears scheduling."),
          "deadline": nullableStringSchema(
            "Deadline in YYYY-MM-DD format. Null clears the deadline."),
          "tags": nullableStringArraySchema(
            "Replacement tag names. Empty array or null clears all tags."),
          "add_tags": .array(
            description: "Tag names to add without replacing existing tags. Updates only.",
            items: .string()),
          "area": nullableStringSchema("Area ID or title. Null removes the area assignment."),
          "initial_todos": .array(
            description: "Todo titles to create inside a new project. Create only.",
            items: .string(),
            maxItems: 250
          ),
          "status": enumSchema(
            ThingsItemStatus.self,
            excluding: [.all],
            description: "Project lifecycle status."
          ),
          "duplicate": .boolean(
            description: "Duplicate the existing project before applying updates. Update only.",
            default: false
          ),
          "creation_date": .string(
            description: "ISO 8601 creation timestamp to preserve during import."),
          "completion_date": .string(
            description: "ISO 8601 completion timestamp for completed or canceled projects."),
          "reveal": .boolean(
            description: "Reveal the project in Things after saving.", default: false),
        ],
        additionalProperties: false
      ),
      destructiveHint: true,
      idempotentHint: false,
      openWorldHint: false
    ) { arguments in
      var request = try self.projectSaveRequest(arguments)
      let options = try self.projectURLCommandOptions(arguments)
      try self.validateProjectURLContract(request, options: options)
      let authToken: String?
      if request.isCreate {
        authToken = nil
      } else {
        try await self.activate()
        authToken = try self.repository.authToken()
      }
      try self.validateProjectWriteSemantics(request, options: options)
      try await self.validateWriteTags(request.tags, additional: request.addTags)
      request = try await self.normalizedProjectWriteReferences(request, arguments: arguments)
      let url = try self.urlBuilder.saveProjectURL(
        for: request,
        authToken: authToken,
        options: options
      )
      let callback = try await self.callbackExecutor.execute(url)
      var rawIDs = callback.thingsIDs
      if rawIDs.isEmpty, let id = request.id {
        rawIDs = [try ThingsEntityID.rawID(id, expectedKind: .project)]
      }
      let refs = rawIDs.map { ThingsEntityID.make(.project, rawID: $0) }
      return ThingsWriteResult(
        operation: request.isCreate ? "create" : "update",
        type: .project,
        ref: refs.first,
        refs: refs,
        title: request.title,
        acknowledged: true,
        verified: false,
        parameters: callback.parameters,
        message: request.isCreate
          ? "Things acknowledged the project creation command. Read the project back to verify applied fields."
          : "Things acknowledged the project update command. Read the project back to verify applied fields."
      )
    }
  }

  private func projectSaveRequest(_ arguments: [String: Value]) throws -> ThingsProjectSaveRequest {
    let decoder = ToolArgumentsDecoder(arguments: arguments)
    var request = ThingsProjectSaveRequest()
    request.id = try decoder.optionalString("id")
    request.title = try decoder.optionalString("title")
    request.notes = try patchNotes("notes", arguments: arguments)
    request.prependNotes = try optionalNotesMutation("prepend_notes", arguments: arguments)
    request.appendNotes = try optionalNotesMutation("append_notes", arguments: arguments)
    request.when = try patchString("when", arguments: arguments)
    request.deadline = try patchString("deadline", arguments: arguments)
    request.tags = try patchStringArray("tags", arguments: arguments)
    request.addTags = try normalizedArray("add_tags", decoder: decoder)
    request.area = try patchString("area", arguments: arguments)
    try validateReferencePatch(request.area, argument: "area", expectedKind: .area)
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

    if request.isCreate {
      guard request.title != nil else {
        throw ThingsServiceError.missingRequiredArgument("title")
      }
      if let updateOnlyArgument = firstProjectUpdateOnlyArgument(request) {
        throw ThingsServiceError.invalidValue(
          updateOnlyArgument, reason: "only valid when id is provided")
      }
    } else {
      _ = try ThingsEntityID.rawID(request.id ?? "", expectedKind: .project)
      let hasExtendedChange =
        (try ToolArgumentsDecoder(arguments: arguments).optionalBool("duplicate") ?? false)
        || arguments["creation_date"] != nil
        || arguments["completion_date"] != nil
      guard projectRequestHasChanges(request) || hasExtendedChange else {
        throw ThingsServiceError.noChanges
      }
    }
    return request
  }

  private func projectURLCommandOptions(
    _ arguments: [String: Value]
  ) throws -> ThingsProjectURLCommandOptions {
    let decoder = ToolArgumentsDecoder(arguments: arguments)
    let initialTodos = try normalizedArray("initial_todos", decoder: decoder)
    try validateMaximumCount(initialTodos, key: "initial_todos", maximum: 250)
    return ThingsProjectURLCommandOptions(
      initialTodos: initialTodos,
      duplicate: try decoder.optionalBool("duplicate") ?? false,
      creationDate: try iso8601String("creation_date", decoder: decoder),
      completionDate: try iso8601String("completion_date", decoder: decoder)
    )
  }

  private func validateProjectURLContract(
    _ request: ThingsProjectSaveRequest,
    options: ThingsProjectURLCommandOptions
  ) throws {
    try validateURLLength(request.title, key: "title")
    try validateURLLength(request.notes, key: "notes", maximum: 10_000)
    try validateURLLength(request.prependNotes, key: "prepend_notes", maximum: 10_000)
    try validateURLLength(request.appendNotes, key: "append_notes", maximum: 10_000)
    try validateURLLength(request.when, key: "when")
    try validateURLLength(request.deadline, key: "deadline")
    try validateJoinedURLValues(request.tags, key: "tags", separator: ",")
    try validateJoinedURLValues(request.addTags, key: "add_tags", separator: ",")
    try validateURLLength(request.area, key: "area")
    try validateLineSeparatedURLValues(
      options.initialTodos, key: "initial_todos", maximumCount: 250)
    try validateURLLength(options.creationDate, key: "creation_date")
    try validateURLLength(options.completionDate, key: "completion_date")
    try validateSchedule(request.when, key: "when", isCreate: request.isCreate)
  }

  private func validateProjectWriteSemantics(
    _ request: ThingsProjectSaveRequest,
    options: ThingsProjectURLCommandOptions
  ) throws {
    try validateNotFuture(options.creationDate, key: "creation_date")
    try validateNotFuture(options.completionDate, key: "completion_date")

    let requiresExisting =
      !request.isCreate
      && (request.when.isChanged || request.deadline.isChanged || request.status != nil
        || options.duplicate || options.completionDate != nil)
    let existing =
      requiresExisting
      ? try repository.getProject(idOrTitle: request.id ?? "", includeTodos: true)
      : nil
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
          forbidden, reason: "Things cannot apply this field to a repeating project")
      }
    }

    if let existing, request.status == .completed || request.status == .canceled {
      try validateProjectChildrenFinished(existing, includeHeadings: true, key: "status")
    }
    if options.completionDate != nil {
      let finalStatus = request.status ?? existing?.status
      guard finalStatus == .completed || finalStatus == .canceled else {
        throw ThingsServiceError.invalidValue(
          "completion_date", reason: "the project must be completed or canceled")
      }
    }
  }

  private func firstProjectUpdateOnlyArgument(_ request: ThingsProjectSaveRequest) -> String? {
    if request.prependNotes != nil { return "prepend_notes" }
    if request.appendNotes != nil { return "append_notes" }
    if request.addTags != nil { return "add_tags" }
    return nil
  }

  private func projectRequestHasChanges(_ request: ThingsProjectSaveRequest) -> Bool {
    request.title != nil
      || request.notes.isChanged
      || request.prependNotes != nil
      || request.appendNotes != nil
      || request.when.isChanged
      || request.deadline.isChanged
      || request.tags.isChanged
      || request.addTags != nil
      || request.area.isChanged
      || request.status != nil
      || request.reveal
  }
}
