import Foundation

nonisolated extension ThingsURLBuilder {
  func jsonURL(for request: ThingsJSONCommandRequest) throws -> URL {
    try validateJSONValueLengths(request.items)
    let items = try request.items.map(normalizedJSONItem)
    for item in items where item.operation == .update && item.id == nil {
      throw ThingsServiceError.invalidValue("data", reason: "JSON updates require an id")
    }
    let requiresAuthToken = items.contains { $0.operation == .update }
    if requiresAuthToken, request.authToken?.isEmpty != false {
      throw ThingsServiceError.missingAuthToken
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(items)
    guard let json = String(data: data, encoding: .utf8) else {
      throw ThingsURLBuilderError.invalidURL
    }

    var queryItems: [(String, String)] = [("data", json)]
    if let authToken = request.authToken, !authToken.isEmpty {
      queryItems.append(("auth-token", authToken))
    }
    if request.reveal {
      queryItems.append(("reveal", "true"))
    }
    appendCallbacks(request.callbacks, to: &queryItems)
    return try buildURL(command: "json", queryItems: queryItems)
  }

  private func normalizedJSONItem(_ item: ThingsJSONItem) throws -> ThingsJSONItem {
    switch item {
    case .todo(let operation, let id, let attributes):
      return try .todo(
        operation: operation,
        id: id.map { try ThingsEntityID.rawID($0, expectedKind: .todo) },
        attributes: normalizedJSONTodoAttributes(attributes)
      )
    case .project(let operation, let id, let attributes):
      return try .project(
        operation: operation,
        id: id.map { try ThingsEntityID.rawID($0, expectedKind: .project) },
        attributes: normalizedJSONProjectAttributes(attributes)
      )
    }
  }

  private func validateJSONValueLengths(_ items: [ThingsJSONItem]) throws {
    for (index, item) in items.enumerated() {
      try validateStringLength(item.id, key: "items[\(index)].id")
      switch item {
      case .todo(_, _, let attributes):
        try validateJSONTodoValueLengths(attributes, path: "items[\(index)].attributes")
      case .project(_, _, let attributes):
        try validateJSONProjectValueLengths(attributes, path: "items[\(index)].attributes")
      }
    }
  }

  private func validateJSONTodoValueLengths(
    _ attributes: ThingsJSONTodoAttributes,
    path: String
  ) throws {
    try validateStringLength(attributes.title, key: "\(path).title")
    try validateStringLength(attributes.notes, key: "\(path).notes", maximum: 10_000)
    try validateStringLength(attributes.when, key: "\(path).when")
    try validateStringLength(attributes.deadline, key: "\(path).deadline")
    try validateStringLengths(attributes.tags, key: "\(path).tags")
    try validateStringLength(attributes.listID, key: "\(path).list-id")
    try validateStringLength(attributes.list, key: "\(path).list")
    try validateStringLength(attributes.headingID, key: "\(path).heading-id")
    try validateStringLength(attributes.heading, key: "\(path).heading")
    try validateStringLength(attributes.creationDate, key: "\(path).creation-date")
    try validateStringLength(attributes.completionDate, key: "\(path).completion-date")
    try validateStringLength(attributes.prependNotes, key: "\(path).prepend-notes", maximum: 10_000)
    try validateStringLength(attributes.appendNotes, key: "\(path).append-notes", maximum: 10_000)
    try validateStringLength(attributes.addTags, key: "\(path).add-tags")
    try validateStringLength(
      attributes.prependChecklistItems, key: "\(path).prepend-checklist-items")
    try validateStringLength(
      attributes.appendChecklistItems, key: "\(path).append-checklist-items")
    for (index, item) in (attributes.checklistItems ?? []).enumerated() {
      try validateStringLength(item.title, key: "\(path).checklist-items[\(index)].title")
    }
  }

  private func validateJSONProjectValueLengths(
    _ attributes: ThingsJSONProjectAttributes,
    path: String
  ) throws {
    try validateStringLength(attributes.title, key: "\(path).title")
    try validateStringLength(attributes.notes, key: "\(path).notes", maximum: 10_000)
    try validateStringLength(attributes.when, key: "\(path).when")
    try validateStringLength(attributes.deadline, key: "\(path).deadline")
    try validateStringLengths(attributes.tags, key: "\(path).tags")
    try validateStringLength(attributes.areaID, key: "\(path).area-id")
    try validateStringLength(attributes.area, key: "\(path).area")
    try validateStringLength(attributes.creationDate, key: "\(path).creation-date")
    try validateStringLength(attributes.completionDate, key: "\(path).completion-date")
    try validateStringLength(attributes.prependNotes, key: "\(path).prepend-notes", maximum: 10_000)
    try validateStringLength(attributes.appendNotes, key: "\(path).append-notes", maximum: 10_000)
    try validateStringLength(attributes.addTags, key: "\(path).add-tags")
    for (index, item) in (attributes.items ?? []).enumerated() {
      switch item {
      case .todo(let todo):
        try validateJSONTodoValueLengths(todo, path: "\(path).items[\(index)].attributes")
      case .heading(let heading):
        try validateStringLength(heading.title, key: "\(path).items[\(index)].attributes.title")
      }
    }
  }

  private func validateStringLengths(_ values: [String]?, key: String) throws {
    for (index, value) in (values ?? []).enumerated() {
      try validateStringLength(value, key: "\(key)[\(index)]")
    }
  }

  private func normalizedJSONTodoAttributes(
    _ attributes: ThingsJSONTodoAttributes
  ) throws -> ThingsJSONTodoAttributes {
    var normalized = attributes
    if let listID = normalized.listID {
      let parsed = ThingsEntityID.parse(listID)
      if let kind = parsed.kind, kind != .project && kind != .area {
        throw ThingsServiceError.entityTypeMismatch(
          expected: "project or area", actual: kind.rawValue)
      }
      normalized.listID = parsed.rawID
    }
    if let headingID = normalized.headingID {
      normalized.headingID = try ThingsEntityID.rawID(headingID, expectedKind: .heading)
    }
    return normalized
  }

  private func normalizedJSONProjectAttributes(
    _ attributes: ThingsJSONProjectAttributes
  ) throws -> ThingsJSONProjectAttributes {
    var normalized = attributes
    if let areaID = normalized.areaID {
      normalized.areaID = try ThingsEntityID.rawID(areaID, expectedKind: .area)
    }
    normalized.items = try normalized.items?.map { item in
      switch item {
      case .todo(let attributes):
        return .todo(try normalizedJSONTodoAttributes(attributes))
      case .heading:
        return item
      }
    }
    return normalized
  }
}
