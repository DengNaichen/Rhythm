import Foundation

nonisolated enum ThingsClipboardMode: String, Codable, CaseIterable, Sendable {
  case replaceTitle = "replace-title"
  case replaceNotes = "replace-notes"
  case replaceChecklistItems = "replace-checklist-items"
}

nonisolated struct ThingsURLCallbacks: Equatable, Sendable {
  var success: URL?
  var error: URL?
  var cancel: URL?

  init(success: URL? = nil, error: URL? = nil, cancel: URL? = nil) {
    self.success = success
    self.error = error
    self.cancel = cancel
  }
}

/// URL-scheme fields that are intentionally not part of the Linear-style todo model.
nonisolated struct ThingsTodoURLCommandOptions: Equatable, Sendable {
  var titles: [String]?
  var useClipboard: ThingsClipboardMode?
  var showQuickEntry = false
  var duplicate = false
  var creationDate: String?
  var completionDate: String?
  var callbacks: ThingsURLCallbacks?

  init(
    titles: [String]? = nil,
    useClipboard: ThingsClipboardMode? = nil,
    showQuickEntry: Bool = false,
    duplicate: Bool = false,
    creationDate: String? = nil,
    completionDate: String? = nil,
    callbacks: ThingsURLCallbacks? = nil
  ) {
    self.titles = titles
    self.useClipboard = useClipboard
    self.showQuickEntry = showQuickEntry
    self.duplicate = duplicate
    self.creationDate = creationDate
    self.completionDate = completionDate
    self.callbacks = callbacks
  }
}

/// URL-scheme fields that are intentionally not part of the Linear-style project model.
nonisolated struct ThingsProjectURLCommandOptions: Equatable, Sendable {
  var initialTodos: [String]?
  var duplicate = false
  var creationDate: String?
  var completionDate: String?
  var callbacks: ThingsURLCallbacks?

  init(
    initialTodos: [String]? = nil,
    duplicate: Bool = false,
    creationDate: String? = nil,
    completionDate: String? = nil,
    callbacks: ThingsURLCallbacks? = nil
  ) {
    self.initialTodos = initialTodos
    self.duplicate = duplicate
    self.creationDate = creationDate
    self.completionDate = completionDate
    self.callbacks = callbacks
  }
}

nonisolated enum ThingsJSONOperation: String, Codable, Sendable {
  case create
  case update
}

nonisolated struct ThingsJSONCommandRequest: Equatable, Sendable {
  var items: [ThingsJSONItem]
  var authToken: String?
  var reveal: Bool
  var callbacks: ThingsURLCallbacks?

  init(
    items: [ThingsJSONItem],
    authToken: String? = nil,
    reveal: Bool = false,
    callbacks: ThingsURLCallbacks? = nil
  ) {
    self.items = items
    self.authToken = authToken
    self.reveal = reveal
    self.callbacks = callbacks
  }
}

nonisolated enum ThingsJSONItem: Codable, Equatable, Sendable {
  case todo(
    operation: ThingsJSONOperation = .create,
    id: String? = nil,
    attributes: ThingsJSONTodoAttributes
  )
  case project(
    operation: ThingsJSONOperation = .create,
    id: String? = nil,
    attributes: ThingsJSONProjectAttributes
  )

  private enum CodingKeys: String, CodingKey {
    case type
    case operation
    case id
    case attributes
  }

  private enum ObjectType: String, Codable {
    case todo = "to-do"
    case project
  }

  var operation: ThingsJSONOperation {
    switch self {
    case .todo(let operation, _, _), .project(let operation, _, _):
      return operation
    }
  }

  var id: String? {
    switch self {
    case .todo(_, let id, _), .project(_, let id, _):
      return id
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .todo(let operation, let id, let attributes):
      try container.encode(ObjectType.todo, forKey: .type)
      if operation == .update {
        try container.encode(operation, forKey: .operation)
      }
      try container.encodeIfPresent(id, forKey: .id)
      try container.encode(attributes, forKey: .attributes)
    case .project(let operation, let id, let attributes):
      try container.encode(ObjectType.project, forKey: .type)
      if operation == .update {
        try container.encode(operation, forKey: .operation)
      }
      try container.encodeIfPresent(id, forKey: .id)
      try container.encode(attributes, forKey: .attributes)
    }
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let type = try container.decode(ObjectType.self, forKey: .type)
    let operation =
      try container.decodeIfPresent(ThingsJSONOperation.self, forKey: .operation)
      ?? .create
    let id = try container.decodeIfPresent(String.self, forKey: .id)
    switch type {
    case .todo:
      self = .todo(
        operation: operation,
        id: id,
        attributes: try container.decode(ThingsJSONTodoAttributes.self, forKey: .attributes)
      )
    case .project:
      self = .project(
        operation: operation,
        id: id,
        attributes: try container.decode(ThingsJSONProjectAttributes.self, forKey: .attributes)
      )
    }
  }
}

nonisolated struct ThingsJSONTodoAttributes: Codable, Equatable, Sendable {
  var title: String?
  var notes: String?
  var when: String?
  var deadline: String?
  var tags: [String]?
  var checklistItems: [ThingsJSONChecklistItem]?
  var listID: String?
  var list: String?
  var headingID: String?
  var heading: String?
  var completed: Bool?
  var canceled: Bool?
  var creationDate: String?
  var completionDate: String?
  var prependNotes: String?
  var appendNotes: String?
  var addTags: String?
  var prependChecklistItems: String?
  var appendChecklistItems: String?

  init(
    title: String? = nil,
    notes: String? = nil,
    when: String? = nil,
    deadline: String? = nil,
    tags: [String]? = nil,
    checklistItems: [ThingsJSONChecklistItem]? = nil,
    listID: String? = nil,
    list: String? = nil,
    headingID: String? = nil,
    heading: String? = nil,
    completed: Bool? = nil,
    canceled: Bool? = nil,
    creationDate: String? = nil,
    completionDate: String? = nil,
    prependNotes: String? = nil,
    appendNotes: String? = nil,
    addTags: String? = nil,
    prependChecklistItems: String? = nil,
    appendChecklistItems: String? = nil
  ) {
    self.title = title
    self.notes = notes
    self.when = when
    self.deadline = deadline
    self.tags = tags
    self.checklistItems = checklistItems
    self.listID = listID
    self.list = list
    self.headingID = headingID
    self.heading = heading
    self.completed = completed
    self.canceled = canceled
    self.creationDate = creationDate
    self.completionDate = completionDate
    self.prependNotes = prependNotes
    self.appendNotes = appendNotes
    self.addTags = addTags
    self.prependChecklistItems = prependChecklistItems
    self.appendChecklistItems = appendChecklistItems
  }

  enum CodingKeys: String, CodingKey {
    case title
    case notes
    case when
    case deadline
    case tags
    case checklistItems = "checklist-items"
    case listID = "list-id"
    case list
    case headingID = "heading-id"
    case heading
    case completed
    case canceled
    case creationDate = "creation-date"
    case completionDate = "completion-date"
    case prependNotes = "prepend-notes"
    case appendNotes = "append-notes"
    case addTags = "add-tags"
    case prependChecklistItems = "prepend-checklist-items"
    case appendChecklistItems = "append-checklist-items"
  }
}

nonisolated struct ThingsJSONProjectAttributes: Codable, Equatable, Sendable {
  var title: String?
  var notes: String?
  var when: String?
  var deadline: String?
  var tags: [String]?
  var areaID: String?
  var area: String?
  var completed: Bool?
  var canceled: Bool?
  var creationDate: String?
  var completionDate: String?
  var items: [ThingsJSONProjectItem]?
  var prependNotes: String?
  var appendNotes: String?
  var addTags: String?

  init(
    title: String? = nil,
    notes: String? = nil,
    when: String? = nil,
    deadline: String? = nil,
    tags: [String]? = nil,
    areaID: String? = nil,
    area: String? = nil,
    completed: Bool? = nil,
    canceled: Bool? = nil,
    creationDate: String? = nil,
    completionDate: String? = nil,
    items: [ThingsJSONProjectItem]? = nil,
    prependNotes: String? = nil,
    appendNotes: String? = nil,
    addTags: String? = nil
  ) {
    self.title = title
    self.notes = notes
    self.when = when
    self.deadline = deadline
    self.tags = tags
    self.areaID = areaID
    self.area = area
    self.completed = completed
    self.canceled = canceled
    self.creationDate = creationDate
    self.completionDate = completionDate
    self.items = items
    self.prependNotes = prependNotes
    self.appendNotes = appendNotes
    self.addTags = addTags
  }

  enum CodingKeys: String, CodingKey {
    case title
    case notes
    case when
    case deadline
    case tags
    case areaID = "area-id"
    case area
    case completed
    case canceled
    case creationDate = "creation-date"
    case completionDate = "completion-date"
    case items
    case prependNotes = "prepend-notes"
    case appendNotes = "append-notes"
    case addTags = "add-tags"
  }
}

nonisolated enum ThingsJSONProjectItem: Codable, Equatable, Sendable {
  case todo(ThingsJSONTodoAttributes)
  case heading(ThingsJSONHeadingAttributes)

  private enum CodingKeys: String, CodingKey {
    case type
    case attributes
  }

  private enum ObjectType: String, Codable {
    case todo = "to-do"
    case heading
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .todo(let attributes):
      try container.encode(ObjectType.todo, forKey: .type)
      try container.encode(attributes, forKey: .attributes)
    case .heading(let attributes):
      try container.encode(ObjectType.heading, forKey: .type)
      try container.encode(attributes, forKey: .attributes)
    }
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(ObjectType.self, forKey: .type) {
    case .todo:
      self = .todo(
        try container.decode(ThingsJSONTodoAttributes.self, forKey: .attributes))
    case .heading:
      self = .heading(
        try container.decode(ThingsJSONHeadingAttributes.self, forKey: .attributes))
    }
  }
}

nonisolated struct ThingsJSONHeadingAttributes: Codable, Equatable, Sendable {
  var title: String?
  var archived: Bool?

  init(title: String? = nil, archived: Bool? = nil) {
    self.title = title
    self.archived = archived
  }
}

nonisolated struct ThingsJSONChecklistItem: Codable, Equatable, Sendable {
  var title: String?
  var completed: Bool?
  var canceled: Bool?

  init(title: String? = nil, completed: Bool? = nil, canceled: Bool? = nil) {
    self.title = title
    self.completed = completed
    self.canceled = canceled
  }

  private enum CodingKeys: String, CodingKey {
    case type
    case attributes
  }

  private enum AttributeKeys: String, CodingKey {
    case title
    case completed
    case canceled
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode("checklist-item", forKey: .type)
    var attributes = container.nestedContainer(keyedBy: AttributeKeys.self, forKey: .attributes)
    try attributes.encodeIfPresent(title, forKey: .title)
    try attributes.encodeIfPresent(completed, forKey: .completed)
    try attributes.encodeIfPresent(canceled, forKey: .canceled)
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let type = try container.decode(String.self, forKey: .type)
    guard type == "checklist-item" else {
      throw DecodingError.dataCorruptedError(
        forKey: .type,
        in: container,
        debugDescription: "Expected checklist-item, got \(type)."
      )
    }
    let attributes = try container.nestedContainer(keyedBy: AttributeKeys.self, forKey: .attributes)
    title = try attributes.decodeIfPresent(String.self, forKey: .title)
    completed = try attributes.decodeIfPresent(Bool.self, forKey: .completed)
    canceled = try attributes.decodeIfPresent(Bool.self, forKey: .canceled)
  }
}
