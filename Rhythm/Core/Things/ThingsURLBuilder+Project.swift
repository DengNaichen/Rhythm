import Foundation

nonisolated extension ThingsURLBuilder {
  func saveProjectURL(for request: ThingsProjectSaveRequest, authToken: String?) throws -> URL {
    try saveProjectURL(
      for: request,
      authToken: authToken,
      options: ThingsProjectURLCommandOptions()
    )
  }

  func saveProjectURL(
    for request: ThingsProjectSaveRequest,
    authToken: String?,
    options: ThingsProjectURLCommandOptions
  ) throws -> URL {
    if request.isCreate,
      request.prependNotes != nil || request.appendNotes != nil || request.addTags != nil
    {
      throw ThingsServiceError.invalidValue(
        "update-only fields", reason: "prepend, append, and add operations require an id")
    }
    if request.isCreate, options.duplicate {
      throw ThingsServiceError.invalidValue("duplicate", reason: "requires an id")
    }
    if !request.isCreate, options.initialTodos != nil {
      throw ThingsServiceError.invalidValue("initialTodos", reason: "requires no id")
    }
    try validateLineSeparatedValues(options.initialTodos, key: "to-dos", maximumCount: 250)
    try validateDelimitedValues(request.tags, key: "tags", delimiter: ",")
    try validateDelimitedValues(request.addTags, key: "add-tags", delimiter: ",")

    var queryItems: [(String, String)] = []
    let command: String

    if let id = request.id {
      command = "update-project"
      guard let authToken, !authToken.isEmpty else {
        throw ThingsServiceError.missingAuthToken
      }
      queryItems.append(("id", try ThingsEntityID.rawID(id, expectedKind: .project)))
      queryItems.append(("auth-token", authToken))
    } else {
      command = "add-project"
    }

    if let title = request.title {
      queryItems.append(("title", title))
    }

    append(request.notes, key: "notes", to: &queryItems)
    append(request.when, key: "when", to: &queryItems)
    append(request.deadline, key: "deadline", to: &queryItems)
    append(request.tags, key: "tags", separator: ",", to: &queryItems)

    if let prependNotes = request.prependNotes {
      queryItems.append(("prepend-notes", prependNotes))
    }
    if let appendNotes = request.appendNotes {
      queryItems.append(("append-notes", appendNotes))
    }
    if let addTags = request.addTags {
      queryItems.append(("add-tags", addTags.joined(separator: ",")))
    }

    appendArea(request.area, to: &queryItems)
    appendStatus(request.status, to: &queryItems)

    if let initialTodos = options.initialTodos {
      queryItems.append(("to-dos", initialTodos.joined(separator: "\n")))
    }
    if options.duplicate {
      queryItems.append(("duplicate", "true"))
    }
    if let creationDate = options.creationDate {
      queryItems.append(("creation-date", creationDate))
    }
    if let completionDate = options.completionDate {
      queryItems.append(("completion-date", completionDate))
    }

    if request.reveal {
      queryItems.append(("reveal", "true"))
    }
    appendCallbacks(options.callbacks, to: &queryItems)

    return try buildURL(command: command, queryItems: queryItems)
  }
}
