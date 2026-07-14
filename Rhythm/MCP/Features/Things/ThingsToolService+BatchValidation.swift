import Foundation
import OrderedCollections

extension ThingsToolService {
  func validateJSONTags(_ items: [ThingsJSONItem]) async throws {
    let tags = items.flatMap(\.referencedTagNames)
    guard !tags.isEmpty else { return }
    try await validateWriteTags(.value(tags), additional: nil)
  }

  func validateJSONItems(_ items: [ThingsJSONItem]) throws {
    for (index, item) in items.enumerated() {
      let path = "items[\(index)]"
      switch item.operation {
      case .create:
        if item.id != nil {
          throw ThingsServiceError.invalidValue(
            "\(path).id", reason: "IDs are only valid for update operations")
        }
      case .update:
        guard let id = item.id else {
          throw ThingsServiceError.invalidValue(
            "\(path).id", reason: "an ID is required for updates")
        }
        _ = try ThingsEntityID.rawID(id, expectedKind: item.entityKind)
      }
      try validateURLLength(item.id, key: "\(path).id")

      switch item {
      case .todo(let operation, _, let attributes):
        try validateJSONTodoAttributes(attributes, operation: operation, path: path, nested: false)
      case .project(let operation, _, let attributes):
        try validateJSONProjectAttributes(attributes, operation: operation, path: path)
      }
    }
  }

  func validateJSONValueShapes(_ values: [Value]) throws {
    let commonKeys: Set<String> = ["type", "operation", "id", "attributes"]
    let todoKeys: Set<String> = [
      "title", "notes", "when", "deadline", "tags", "checklist-items", "list-id", "list",
      "heading-id", "heading", "completed", "canceled", "creation-date", "completion-date",
      "prepend-notes", "append-notes", "add-tags", "prepend-checklist-items",
      "append-checklist-items",
    ]
    let projectKeys: Set<String> = [
      "title", "notes", "when", "deadline", "tags", "area-id", "area", "completed",
      "canceled", "creation-date", "completion-date", "items", "prepend-notes", "append-notes",
      "add-tags",
    ]

    for (index, value) in values.enumerated() {
      let path = "items[\(index)]"
      guard let object = value.objectValue else {
        throw ThingsServiceError.invalidType(path, expected: "object")
      }
      try rejectUnknownKeys(in: object, allowed: commonKeys, path: path)
      guard let type = object["type"]?.stringValue else { continue }
      guard let attributes = object["attributes"]?.objectValue else { continue }
      switch type {
      case "to-do":
        try rejectUnknownKeys(in: attributes, allowed: todoKeys, path: "\(path).attributes")
        if let checklist = attributes["checklist-items"]?.arrayValue {
          try validateJSONLeafValueShapes(
            checklist,
            path: "\(path).attributes.checklist-items",
            allowed: ["title", "completed", "canceled"]
          )
        }
      case "project":
        try rejectUnknownKeys(in: attributes, allowed: projectKeys, path: "\(path).attributes")
        if let children = attributes["items"]?.arrayValue {
          try validateJSONChildValueShapes(
            children, path: "\(path).attributes.items", todoKeys: todoKeys)
        }
      default:
        break
      }
    }
  }

  private func validateJSONChildValueShapes(
    _ values: [Value],
    path: String,
    todoKeys: Set<String>
  ) throws {
    let commonKeys: Set<String> = ["type", "attributes"]
    let headingKeys: Set<String> = ["title", "archived"]
    let checklistKeys: Set<String> = ["title", "completed", "canceled"]
    for (index, value) in values.enumerated() {
      let itemPath = "\(path)[\(index)]"
      guard let object = value.objectValue else {
        throw ThingsServiceError.invalidType(itemPath, expected: "object")
      }
      try rejectUnknownKeys(in: object, allowed: commonKeys, path: itemPath)
      guard let type = object["type"]?.stringValue,
        let attributes = object["attributes"]?.objectValue
      else { continue }
      switch type {
      case "to-do":
        try rejectUnknownKeys(in: attributes, allowed: todoKeys, path: "\(itemPath).attributes")
        if let checklist = attributes["checklist-items"]?.arrayValue {
          try validateJSONLeafValueShapes(
            checklist, path: "\(itemPath).attributes.checklist-items", allowed: checklistKeys)
        }
      case "heading":
        try rejectUnknownKeys(
          in: attributes, allowed: headingKeys, path: "\(itemPath).attributes")
      default:
        break
      }
    }
  }

  private func validateJSONLeafValueShapes(
    _ values: [Value],
    path: String,
    allowed: Set<String>
  ) throws {
    let commonKeys: Set<String> = ["type", "attributes"]
    for (index, value) in values.enumerated() {
      let itemPath = "\(path)[\(index)]"
      guard let object = value.objectValue else {
        throw ThingsServiceError.invalidType(itemPath, expected: "object")
      }
      try rejectUnknownKeys(in: object, allowed: commonKeys, path: itemPath)
      if let attributes = object["attributes"]?.objectValue {
        try rejectUnknownKeys(in: attributes, allowed: allowed, path: "\(itemPath).attributes")
      }
    }
  }

  private func rejectUnknownKeys(
    in object: [String: Value],
    allowed: Set<String>,
    path: String
  ) throws {
    let unknown = Set(object.keys).subtracting(allowed).sorted()
    guard unknown.isEmpty else {
      throw ThingsServiceError.invalidValue(
        path, reason: "unsupported fields: \(unknown.joined(separator: ", "))")
    }
  }

  private func validateJSONTodoAttributes(
    _ attributes: ThingsJSONTodoAttributes,
    operation: ThingsJSONOperation,
    path: String,
    nested: Bool
  ) throws {
    try validateExclusiveJSONStatuses(
      completed: attributes.completed,
      canceled: attributes.canceled,
      key: "\(path).attributes"
    )
    try validateURLLength(attributes.title, key: "\(path).attributes.title")
    try validateJSONNotes(attributes.notes, key: "\(path).attributes.notes")
    try validateJSONNotes(attributes.prependNotes, key: "\(path).attributes.prepend-notes")
    try validateJSONNotes(attributes.appendNotes, key: "\(path).attributes.append-notes")
    try validateJSONCommaSeparatedTags(
      attributes.addTags, key: "\(path).attributes.add-tags")
    try validateURLLength(attributes.when, key: "\(path).attributes.when")
    try validateURLLength(attributes.deadline, key: "\(path).attributes.deadline")
    try validateJSONStringArray(attributes.tags, key: "\(path).attributes.tags")
    try validateURLLength(attributes.listID, key: "\(path).attributes.list-id")
    try validateURLLength(attributes.list, key: "\(path).attributes.list")
    try validateURLLength(attributes.headingID, key: "\(path).attributes.heading-id")
    try validateURLLength(attributes.heading, key: "\(path).attributes.heading")
    try validateURLLength(
      attributes.prependChecklistItems, key: "\(path).attributes.prepend-checklist-items")
    try validateURLLength(
      attributes.appendChecklistItems, key: "\(path).attributes.append-checklist-items")
    try validateJSONSchedule(attributes.when, key: "\(path).attributes.when")
    try validateJSONTimestamp(attributes.creationDate, key: "\(path).attributes.creation-date")
    try validateJSONTimestamp(attributes.completionDate, key: "\(path).attributes.completion-date")
    for (index, item) in (attributes.checklistItems ?? []).enumerated() {
      try validateURLLength(
        item.title, key: "\(path).attributes.checklist-items[\(index)].attributes.title")
      try validateExclusiveJSONStatuses(
        completed: item.completed,
        canceled: item.canceled,
        key: "\(path).attributes.checklist-items[\(index)].attributes"
      )
    }
    if operation == .create, attributes.completionDate != nil,
      !jsonCreateIsFinished(completed: attributes.completed, canceled: attributes.canceled)
    {
      throw ThingsServiceError.invalidValue(
        "\(path).attributes.completion-date",
        reason: "the todo must be completed or canceled"
      )
    }
    if let checklistItems = attributes.checklistItems, checklistItems.count > 100 {
      throw ThingsServiceError.invalidValue(
        "\(path).attributes.checklist-items",
        reason: "a todo can contain at most 100 checklist items"
      )
    }
    if attributes.listID != nil, attributes.list != nil {
      throw ThingsServiceError.conflictingArguments("\(path).attributes.list-id", "list")
    }
    if attributes.headingID != nil, attributes.heading != nil {
      throw ThingsServiceError.conflictingArguments("\(path).attributes.heading-id", "heading")
    }

    let updateOnlyFields: [(String, Bool)] = [
      ("prepend-notes", attributes.prependNotes != nil),
      ("append-notes", attributes.appendNotes != nil),
      ("add-tags", attributes.addTags != nil),
      ("prepend-checklist-items", attributes.prependChecklistItems != nil),
      ("append-checklist-items", attributes.appendChecklistItems != nil),
    ]
    if operation == .create, let field = updateOnlyFields.first(where: { $0.1 })?.0 {
      throw ThingsServiceError.invalidValue(
        "\(path).attributes.\(field)", reason: "only valid for update operations")
    }

    if nested {
      let ignoredParentFields: [(String, Bool)] = [
        ("list-id", attributes.listID != nil),
        ("list", attributes.list != nil),
        ("heading-id", attributes.headingID != nil),
        ("heading", attributes.heading != nil),
      ]
      if let field = ignoredParentFields.first(where: { $0.1 })?.0 {
        throw ThingsServiceError.invalidValue(
          "\(path).attributes.\(field)",
          reason: "Things ignores parent and heading fields for todos nested inside a project"
        )
      }
    }
  }

  private func validateJSONProjectAttributes(
    _ attributes: ThingsJSONProjectAttributes,
    operation: ThingsJSONOperation,
    path: String
  ) throws {
    try validateExclusiveJSONStatuses(
      completed: attributes.completed,
      canceled: attributes.canceled,
      key: "\(path).attributes"
    )
    try validateURLLength(attributes.title, key: "\(path).attributes.title")
    try validateJSONNotes(attributes.notes, key: "\(path).attributes.notes")
    try validateJSONNotes(attributes.prependNotes, key: "\(path).attributes.prepend-notes")
    try validateJSONNotes(attributes.appendNotes, key: "\(path).attributes.append-notes")
    try validateJSONCommaSeparatedTags(
      attributes.addTags, key: "\(path).attributes.add-tags")
    try validateURLLength(attributes.when, key: "\(path).attributes.when")
    try validateURLLength(attributes.deadline, key: "\(path).attributes.deadline")
    try validateJSONStringArray(attributes.tags, key: "\(path).attributes.tags")
    try validateURLLength(attributes.areaID, key: "\(path).attributes.area-id")
    try validateURLLength(attributes.area, key: "\(path).attributes.area")
    try validateJSONSchedule(attributes.when, key: "\(path).attributes.when")
    try validateJSONTimestamp(attributes.creationDate, key: "\(path).attributes.creation-date")
    try validateJSONTimestamp(attributes.completionDate, key: "\(path).attributes.completion-date")
    if operation == .create, attributes.completionDate != nil,
      !jsonCreateIsFinished(completed: attributes.completed, canceled: attributes.canceled)
    {
      throw ThingsServiceError.invalidValue(
        "\(path).attributes.completion-date",
        reason: "the project must be completed or canceled"
      )
    }
    if let items = attributes.items, items.count > 250 {
      throw ThingsServiceError.invalidValue(
        "\(path).attributes.items", reason: "a project can contain at most 250 items")
    }
    if attributes.areaID != nil, attributes.area != nil {
      throw ThingsServiceError.conflictingArguments("\(path).attributes.area-id", "area")
    }
    if operation == .create {
      let updateOnlyFields: [(String, Bool)] = [
        ("prepend-notes", attributes.prependNotes != nil),
        ("append-notes", attributes.appendNotes != nil),
        ("add-tags", attributes.addTags != nil),
      ]
      if let field = updateOnlyFields.first(where: { $0.1 })?.0 {
        throw ThingsServiceError.invalidValue(
          "\(path).attributes.\(field)", reason: "only valid for update operations")
      }
    } else if attributes.items != nil {
      throw ThingsServiceError.invalidValue(
        "\(path).attributes.items", reason: "only valid for create operations")
    }

    for (childIndex, child) in (attributes.items ?? []).enumerated() {
      switch child {
      case .todo(let todo):
        try validateJSONTodoAttributes(
          todo,
          operation: .create,
          path: "\(path).attributes.items[\(childIndex)]",
          nested: true
        )
      case .heading(let heading):
        try validateURLLength(
          heading.title, key: "\(path).attributes.items[\(childIndex)].attributes.title")
      }
    }
    if operation == .create,
      jsonCreateIsFinished(completed: attributes.completed, canceled: attributes.canceled)
    {
      for (childIndex, child) in (attributes.items ?? []).enumerated() {
        switch child {
        case .todo(let todo)
        where !jsonCreateIsFinished(completed: todo.completed, canceled: todo.canceled):
          throw ThingsServiceError.invalidValue(
            "\(path).attributes.items[\(childIndex)].attributes",
            reason: "all child todos must be completed or canceled before completing the project"
          )
        case .heading(let heading) where heading.archived != true:
          throw ThingsServiceError.invalidValue(
            "\(path).attributes.items[\(childIndex)].attributes.archived",
            reason: "all child headings must be archived before completing the project"
          )
        default:
          continue
        }
      }
    }
    try validateJSONArchivedHeadings(attributes.items ?? [], path: path)
  }

  func validateJSONUpdateSemantics(_ items: [ThingsJSONItem]) throws {
    var todoStatuses: [String: ThingsItemStatus] = [:]
    var projectStatuses: [String: ThingsItemStatus] = [:]
    for (index, item) in items.enumerated() {
      let path = "items[\(index)].attributes"
      switch item {
      case .todo(.update, let id?, let attributes):
        let touchesRepeatingField =
          attributes.when != nil || attributes.deadline != nil
          || attributes.completed != nil || attributes.canceled != nil
          || attributes.completionDate != nil
        guard touchesRepeatingField
        else { continue }
        let rawID = try ThingsEntityID.rawID(id, expectedKind: .todo)
        let todo = try repository.getTodo(id: id)
        if todo.repeating != nil {
          throw ThingsServiceError.invalidValue(
            path,
            reason:
              "Things cannot apply scheduling, status, or completion dates to a repeating todo")
        }
        guard
          attributes.completed != nil || attributes.canceled != nil
            || attributes.completionDate != nil
        else { continue }
        let current = todoStatuses[rawID] ?? todo.status
        let final = jsonUpdatedStatus(
          current: current,
          completed: attributes.completed,
          canceled: attributes.canceled
        )
        if attributes.completionDate != nil, final != .completed && final != .canceled {
          throw ThingsServiceError.invalidValue(
            "\(path).completion-date", reason: "the todo must be completed or canceled")
        }
        todoStatuses[rawID] = final

      case .project(.update, let id?, let attributes):
        let touchesRepeatingField =
          attributes.when != nil || attributes.deadline != nil
          || attributes.completed != nil || attributes.canceled != nil
          || attributes.completionDate != nil
        guard touchesRepeatingField
        else { continue }
        let rawID = try ThingsEntityID.rawID(id, expectedKind: .project)
        let project = try repository.getProject(idOrTitle: id, includeTodos: true)
        if project.repeating != nil {
          throw ThingsServiceError.invalidValue(
            path,
            reason:
              "Things cannot apply scheduling, status, or completion dates to a repeating project"
          )
        }
        guard
          attributes.completed != nil || attributes.canceled != nil
            || attributes.completionDate != nil
        else { continue }
        let current = projectStatuses[rawID] ?? project.status
        let final = jsonUpdatedStatus(
          current: current,
          completed: attributes.completed,
          canceled: attributes.canceled
        )
        if attributes.completed == true || attributes.canceled == true {
          try validateProjectChildrenFinished(
            project,
            includeHeadings: true,
            key: "\(path).completed/canceled",
            predictedTodoStatuses: todoStatuses
          )
        }
        if attributes.completionDate != nil, final != .completed && final != .canceled {
          throw ThingsServiceError.invalidValue(
            "\(path).completion-date", reason: "the project must be completed or canceled")
        }
        projectStatuses[rawID] = final

      case .todo, .project:
        continue
      }
    }
  }

  private func validateExclusiveJSONStatuses(
    completed: Bool?,
    canceled: Bool?,
    key: String
  ) throws {
    guard completed != nil, canceled != nil else { return }
    throw ThingsServiceError.conflictingArguments("\(key).completed", "\(key).canceled")
  }

  private func validateJSONNotes(_ value: String?, key: String) throws {
    try validateURLLength(value, key: key, maximum: 10_000)
  }

  private func validateJSONCommaSeparatedTags(_ value: String?, key: String) throws {
    guard let value else { return }
    try validateURLLength(value, key: key)
    let tags = value.split(separator: ",", omittingEmptySubsequences: false)
    for (index, tag) in tags.enumerated() {
      guard !tag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw ThingsServiceError.invalidValue(
          "\(key)[\(index)]", reason: "comma-separated tag names must not be empty")
      }
      try validateURLLength(String(tag), key: "\(key)[\(index)]")
    }
  }

  private func validateJSONStringArray(_ values: [String]?, key: String) throws {
    for (index, value) in (values ?? []).enumerated() {
      guard !value.isEmpty else {
        throw ThingsServiceError.invalidValue("\(key)[\(index)]", reason: "value must not be empty")
      }
      try validateURLLength(value, key: "\(key)[\(index)]")
    }
  }

  private func validateJSONSchedule(_ value: String?, key: String) throws {
    guard let value, value.contains("@") else { return }
    let bucket =
      value.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
      .first.map(String.init)?.lowercased() ?? ""
    guard bucket == "anytime" || bucket == "someday" else { return }
    throw ThingsServiceError.invalidValue(
      key, reason: "Things ignores reminder times combined with anytime or someday")
  }

  private func validateJSONTimestamp(_ value: String?, key: String) throws {
    guard let value else { return }
    guard parseISO8601(value) != nil else {
      throw ThingsServiceError.invalidValue(key, reason: "expected an ISO 8601 timestamp")
    }
    try validateNotFuture(value, key: key)
  }

  private func jsonCreateIsFinished(completed: Bool?, canceled: Bool?) -> Bool {
    canceled == true || completed == true
  }

  private func jsonUpdatedStatus(
    current: ThingsItemStatus,
    completed: Bool?,
    canceled: Bool?
  ) -> ThingsItemStatus {
    if canceled == true { return .canceled }
    if completed == true { return .completed }
    if completed == false || canceled == false { return .incomplete }
    return current
  }

  private func validateJSONArchivedHeadings(
    _ items: [ThingsJSONProjectItem],
    path: String
  ) throws {
    for (index, item) in items.enumerated() {
      guard case .heading(let heading) = item, heading.archived == true else { continue }
      var childIndex = index + 1
      while childIndex < items.count {
        switch items[childIndex] {
        case .heading:
          childIndex = items.count
        case .todo(let todo):
          guard jsonCreateIsFinished(completed: todo.completed, canceled: todo.canceled) else {
            throw ThingsServiceError.invalidValue(
              "\(path).attributes.items[\(index)].attributes.archived",
              reason: "all todos under an archived heading must be completed or canceled"
            )
          }
          childIndex += 1
        }
      }
    }
  }

  func validateJSONChecklistLimits(_ items: [ThingsJSONItem]) throws {
    var updatedCounts: [String: Int] = [:]
    for (index, item) in items.enumerated() {
      switch item {
      case .todo(let operation, let id, let attributes):
        let changesChecklist =
          attributes.checklistItems != nil
          || attributes.prependChecklistItems != nil
          || attributes.appendChecklistItems != nil
        guard changesChecklist else { continue }
        let baseCount: Int
        if let replacement = attributes.checklistItems {
          baseCount = replacement.count
        } else if operation == .update, let id {
          let rawID = try ThingsEntityID.rawID(id, expectedKind: .todo)
          if let priorCount = updatedCounts[rawID] {
            baseCount = priorCount
          } else {
            baseCount = try repository.getTodo(id: id).checklistItems.count
          }
        } else {
          baseCount = 0
        }

        let finalCount =
          baseCount
          + checklistLineCount(attributes.prependChecklistItems)
          + checklistLineCount(attributes.appendChecklistItems)
        guard finalCount <= 100 else {
          throw ThingsServiceError.invalidValue(
            "items[\(index)].attributes.checklist-items",
            reason: "a todo can contain at most 100 checklist items"
          )
        }
        if operation == .update, let id {
          updatedCounts[try ThingsEntityID.rawID(id, expectedKind: .todo)] = finalCount
        }
      case .project(_, _, let attributes):
        for (childIndex, child) in (attributes.items ?? []).enumerated() {
          guard case .todo(let todo) = child else { continue }
          let count =
            (todo.checklistItems?.count ?? 0)
            + checklistLineCount(todo.prependChecklistItems)
            + checklistLineCount(todo.appendChecklistItems)
          guard count <= 100 else {
            throw ThingsServiceError.invalidValue(
              "items[\(index)].attributes.items[\(childIndex)].attributes.checklist-items",
              reason: "a todo can contain at most 100 checklist items"
            )
          }
        }
      }
    }
  }

  private func checklistLineCount(_ value: String?) -> Int {
    value?.split(whereSeparator: \Character.isNewline).count ?? 0
  }
}

extension ThingsJSONItem {
  fileprivate var referencedTagNames: [String] {
    switch self {
    case .todo(_, _, let attributes):
      return attributes.referencedTagNames
    case .project(_, _, let attributes):
      return attributes.referencedTagNames
    }
  }
}

extension ThingsJSONTodoAttributes {
  fileprivate var referencedTagNames: [String] {
    (tags ?? []) + Self.commaSeparatedTags(addTags)
  }

  fileprivate static func commaSeparatedTags(_ value: String?) -> [String] {
    value?
      .split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      ?? []
  }
}

extension ThingsJSONProjectAttributes {
  fileprivate var referencedTagNames: [String] {
    var values = (tags ?? []) + ThingsJSONTodoAttributes.commaSeparatedTags(addTags)
    for item in items ?? [] {
      if case .todo(let attributes) = item {
        values.append(contentsOf: attributes.referencedTagNames)
      }
    }
    return values
  }
}
