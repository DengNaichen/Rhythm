import Foundation

nonisolated extension ThingsURLBuilder {
  func saveTodoURL(for request: ThingsTodoSaveRequest, authToken: String?) throws -> URL {
    try saveTodoURL(for: request, authToken: authToken, options: ThingsTodoURLCommandOptions())
  }

  func saveTodoURL(
    for request: ThingsTodoSaveRequest,
    authToken: String?,
    options: ThingsTodoURLCommandOptions
  ) throws -> URL {
    if request.isCreate,
      request.prependNotes != nil || request.appendNotes != nil || request.addTags != nil
        || request.prependChecklistItems != nil || request.appendChecklistItems != nil
    {
      throw ThingsServiceError.invalidValue(
        "update-only fields", reason: "prepend, append, and add operations require an id")
    }
    if request.isCreate, options.duplicate {
      throw ThingsServiceError.invalidValue("duplicate", reason: "requires an id")
    }
    if !request.isCreate,
      options.titles != nil || options.useClipboard != nil || options.showQuickEntry
    {
      throw ThingsServiceError.invalidValue(
        "add-only fields", reason: "titles, use-clipboard, and show-quick-entry require no id")
    }
    if options.titles != nil, request.title != nil {
      throw ThingsServiceError.conflictingArguments("title", "titles")
    }
    if options.titles != nil, options.showQuickEntry {
      throw ThingsServiceError.conflictingArguments("titles", "show-quick-entry")
    }
    if options.showQuickEntry, request.reveal {
      throw ThingsServiceError.conflictingArguments("show-quick-entry", "reveal")
    }
    if let useClipboard = options.useClipboard {
      switch useClipboard {
      case .replaceTitle:
        if request.title != nil || options.titles != nil || request.notes.isChanged {
          throw ThingsServiceError.conflictingArguments("use-clipboard", "title/titles/notes")
        }
      case .replaceNotes:
        if request.notes.isChanged {
          throw ThingsServiceError.conflictingArguments("use-clipboard", "notes")
        }
      case .replaceChecklistItems:
        if request.checklistItems.isChanged {
          throw ThingsServiceError.conflictingArguments("use-clipboard", "checklist-items")
        }
      }
    }
    try validateLineSeparatedValues(options.titles, key: "titles", maximumCount: 250)
    try validateLineSeparatedValues(
      request.checklistItems, key: "checklist-items", maximumCount: 100)
    try validateLineSeparatedValues(
      request.prependChecklistItems, key: "prepend-checklist-items", maximumCount: 100)
    try validateLineSeparatedValues(
      request.appendChecklistItems, key: "append-checklist-items", maximumCount: 100)
    try validateDelimitedValues(request.tags, key: "tags", delimiter: ",")
    try validateDelimitedValues(request.addTags, key: "add-tags", delimiter: ",")

    var queryItems: [(String, String)] = []
    let command: String

    if let id = request.id {
      command = "update"
      guard let authToken, !authToken.isEmpty else {
        throw ThingsServiceError.missingAuthToken
      }
      queryItems.append(("id", try ThingsEntityID.rawID(id, expectedKind: .todo)))
      queryItems.append(("auth-token", authToken))
    } else {
      command = "add"
    }

    if let title = request.title {
      queryItems.append(("title", title))
    }
    if let titles = options.titles {
      queryItems.append(("titles", titles.joined(separator: "\n")))
    }

    append(request.notes, key: "notes", to: &queryItems)
    append(request.when, key: "when", to: &queryItems)
    append(request.deadline, key: "deadline", to: &queryItems)
    append(request.tags, key: "tags", separator: ",", to: &queryItems)
    append(request.checklistItems, key: "checklist-items", separator: "\n", to: &queryItems)

    if let prependNotes = request.prependNotes {
      queryItems.append(("prepend-notes", prependNotes))
    }
    if let appendNotes = request.appendNotes {
      queryItems.append(("append-notes", appendNotes))
    }
    if let addTags = request.addTags {
      queryItems.append(("add-tags", addTags.joined(separator: ",")))
    }
    if let items = request.prependChecklistItems {
      queryItems.append(("prepend-checklist-items", items.joined(separator: "\n")))
    }
    if let items = request.appendChecklistItems {
      queryItems.append(("append-checklist-items", items.joined(separator: "\n")))
    }

    appendDestination(request.destination, to: &queryItems)
    appendHeading(request.heading, to: &queryItems)
    appendStatus(request.status, to: &queryItems)

    if let useClipboard = options.useClipboard {
      queryItems.append(("use-clipboard", useClipboard.rawValue))
    }
    if options.showQuickEntry {
      queryItems.append(("show-quick-entry", "true"))
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
