import Foundation

struct ThingsReference: Codable, Equatable, Sendable {
  let id: String
  let title: String
}

struct ThingsChecklistItem: Codable, Equatable, Sendable {
  let title: String
  let status: ThingsItemStatus
  var id: String? = nil
  var index: Int? = nil
  var completedAt: String? = nil
  var createdAt: String? = nil
  var updatedAt: String? = nil

  enum CodingKeys: String, CodingKey {
    case id
    case index
    case title
    case status
    case completedAt = "completed_at"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }
}

struct ThingsRepeatingMetadata: Codable, Equatable, Sendable {
  let isTemplate: Bool
  let template: ThingsReference?
  let paused: Bool?
  let nextOccurrence: String?
  let instanceCreationStart: String?
  let instanceCount: Int?
  let afterCompletionReferenceAt: String?
  let deadlineOffsetDays: Int?
  let ruleDataBase64: String?

  enum CodingKeys: String, CodingKey {
    case isTemplate = "is_template"
    case template
    case paused
    case nextOccurrence = "next_occurrence"
    case instanceCreationStart = "instance_creation_start"
    case instanceCount = "instance_count"
    case afterCompletionReferenceAt = "after_completion_reference_at"
    case deadlineOffsetDays = "deadline_offset_days"
    case ruleDataBase64 = "rule_data_base64"
  }
}

struct ThingsTodo: Codable, Equatable, Sendable {
  let id: String
  let type: ThingsEntityKind
  let title: String
  let status: ThingsItemStatus
  let list: String?
  let when: String?
  let deadline: String?
  let completedAt: String?
  let createdAt: String?
  let updatedAt: String?
  let notes: String?
  let area: ThingsReference?
  let project: ThingsReference?
  let heading: ThingsReference?
  let tags: [String]
  let checklistItems: [ThingsChecklistItem]
  let url: String
  var evening = false
  var reminderTime: String? = nil
  var reminderAt: String? = nil
  var isLogged = false
  var allMatchingTags: [String] = []
  var repeating: ThingsRepeatingMetadata? = nil

  enum CodingKeys: String, CodingKey {
    case id
    case type
    case title
    case status
    case list
    case when
    case deadline
    case completedAt = "completed_at"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
    case notes
    case area
    case project
    case heading
    case tags
    case checklistItems = "checklist_items"
    case url
    case evening
    case reminderTime = "reminder_time"
    case reminderAt = "reminder_at"
    case isLogged = "is_logged"
    case allMatchingTags = "all_matching_tags"
    case repeating
  }
}

struct ThingsProject: Codable, Equatable, Sendable {
  let id: String
  let type: ThingsEntityKind
  let title: String
  let status: ThingsItemStatus
  let list: String?
  let when: String?
  let deadline: String?
  let completedAt: String?
  let notes: String?
  let area: ThingsReference?
  let tags: [String]
  let createdAt: String?
  let updatedAt: String?
  let headings: [ThingsReference]
  let todos: [ThingsReference]?
  let url: String
  var evening = false
  var reminderTime: String? = nil
  var reminderAt: String? = nil
  var isLogged = false
  var allMatchingTags: [String] = []
  var repeating: ThingsRepeatingMetadata? = nil

  enum CodingKeys: String, CodingKey {
    case id
    case type
    case title
    case status
    case list
    case when
    case deadline
    case completedAt = "completed_at"
    case notes
    case area
    case tags
    case createdAt = "created_at"
    case updatedAt = "updated_at"
    case headings
    case todos
    case url
    case evening
    case reminderTime = "reminder_time"
    case reminderAt = "reminder_at"
    case isLogged = "is_logged"
    case allMatchingTags = "all_matching_tags"
    case repeating
  }
}

struct ThingsHeading: Codable, Equatable, Sendable {
  let id: String
  let type: ThingsEntityKind
  let title: String
  let status: ThingsItemStatus
  let isLogged: Bool
  let completedAt: String?
  let createdAt: String?
  let updatedAt: String?
  let project: ThingsReference
  let todos: [ThingsReference]?
  let url: String

  enum CodingKeys: String, CodingKey {
    case id
    case type
    case title
    case status
    case isLogged = "is_logged"
    case completedAt = "completed_at"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
    case project
    case todos
    case url
  }
}

struct ThingsArea: Codable, Equatable, Sendable {
  let id: String
  let type: ThingsEntityKind
  let title: String
  let projectCount: Int
  let todoCount: Int
  let projects: [ThingsReference]?
  let todos: [ThingsReference]?
  let url: String
  var tags: [String] = []
  var allMatchingTags: [String] = []

  enum CodingKeys: String, CodingKey {
    case id
    case type
    case title
    case projectCount = "project_count"
    case todoCount = "todo_count"
    case projects
    case todos
    case url
    case tags
    case allMatchingTags = "all_matching_tags"
  }
}

struct ThingsTag: Codable, Equatable, Sendable {
  let id: String
  let type: ThingsEntityKind
  let title: String
  let shortcut: String?
  let todoCount: Int
  let projectCount: Int
  let todos: [ThingsReference]?
  let projects: [ThingsReference]?
  let url: String
  var parent: ThingsReference? = nil
  var children: [ThingsReference] = []
  var path: [ThingsReference] = []

  enum CodingKeys: String, CodingKey {
    case id
    case type
    case title
    case shortcut
    case todoCount = "todo_count"
    case projectCount = "project_count"
    case todos
    case projects
    case url
    case parent
    case children
    case path
  }
}

enum ThingsEntity: Encodable, Equatable, Sendable {
  case todo(ThingsTodo)
  case heading(ThingsHeading)
  case project(ThingsProject)
  case area(ThingsArea)
  case tag(ThingsTag)

  func encode(to encoder: Encoder) throws {
    switch self {
    case .todo(let value):
      try value.encode(to: encoder)
    case .heading(let value):
      try value.encode(to: encoder)
    case .project(let value):
      try value.encode(to: encoder)
    case .area(let value):
      try value.encode(to: encoder)
    case .tag(let value):
      try value.encode(to: encoder)
    }
  }
}

struct ThingsSearchHit: Codable, Equatable, Sendable {
  let ref: String
  let id: String
  let type: ThingsEntityKind
  let title: String
  let status: ThingsItemStatus?
  let context: String?
  let url: String
}
