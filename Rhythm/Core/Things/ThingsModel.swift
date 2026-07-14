import Foundation

enum ThingsEntityKind: String, CaseIterable, Codable, Sendable {
  case all
  case todo
  case heading
  case project
  case area
  case tag
}

enum ThingsItemStatus: String, CaseIterable, Codable, Sendable {
  case incomplete
  case completed
  case canceled
  case all
}

enum ThingsBuiltinList: String, CaseIterable, Codable, Sendable {
  case all
  case inbox
  case today
  case tomorrow
  case upcoming
  case anytime
  case someday
  case deadlines
  case logbook
  case repeating
  case trash
}

enum ThingsShowList: String, CaseIterable, Sendable {
  case inbox
  case today
  case tomorrow
  case upcoming
  case anytime
  case someday
  case deadlines
  case logbook
  case repeating
  case allProjects = "all-projects"
  case loggedProjects = "logged-projects"
}

enum ThingsOrderBy: String, CaseIterable, Codable, Sendable {
  case things
  case createdAt = "created_at"
  case updatedAt = "updated_at"
  case scheduledDate = "scheduled_date"
  case reminderAt = "reminder_at"
  case deadline
  case completedAt = "completed_at"
  case title
}

enum ThingsOrderDirection: String, CaseIterable, Codable, Sendable {
  case ascending = "asc"
  case descending = "desc"
}

struct ThingsPageRequest: Equatable, Sendable {
  nonisolated static let defaultLimit = 50
  nonisolated static let maximumLimit = 250

  let offset: Int
  let limit: Int

  init(offset: Int = 0, limit: Int = defaultLimit) {
    self.offset = max(offset, 0)
    self.limit = max(limit, 1)
  }
}

struct ThingsPage<Item: Encodable>: Encodable {
  let count: Int
  let items: [Item]
  let nextCursor: String?
  let hasMore: Bool

  enum CodingKeys: String, CodingKey {
    case count
    case items
    case nextCursor = "next_cursor"
    case hasMore = "has_more"
  }

  init(items: [Item], nextCursor: String?) {
    self.count = items.count
    self.items = items
    self.nextCursor = nextCursor
    self.hasMore = nextCursor != nil
  }
}

nonisolated enum ThingsEntityID {
  static func make(_ kind: ThingsEntityKind, rawID: String) -> String {
    "\(kind.rawValue):\(rawID)"
  }

  static func parse(_ value: String) -> (kind: ThingsEntityKind?, rawID: String) {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let separator = trimmed.firstIndex(of: ":") else {
      return (nil, trimmed)
    }

    let prefix = String(trimmed[..<separator])
    let rawID = String(trimmed[trimmed.index(after: separator)...])
    guard let kind = ThingsEntityKind(rawValue: prefix), kind != .all else {
      return (nil, trimmed)
    }
    return (kind, rawID)
  }

  static func rawID(_ value: String, expectedKind: ThingsEntityKind? = nil) throws -> String {
    let parsed = parse(value)
    if let expectedKind, let actualKind = parsed.kind, actualKind != expectedKind {
      throw ThingsServiceError.entityTypeMismatch(
        expected: expectedKind.rawValue,
        actual: actualKind.rawValue
      )
    }

    guard !parsed.rawID.isEmpty else {
      throw ThingsServiceError.invalidIdentifier(value)
    }
    return parsed.rawID
  }
}

enum ThingsServiceError: Error, LocalizedError {
  case invalidDate(String)
  case invalidCursor(String)
  case invalidIdentifier(String)
  case entityNotFound(String)
  case ambiguousReference(String)
  case entityTypeMismatch(expected: String, actual: String)
  case missingAuthToken
  case missingRequiredArgument(String)
  case invalidType(String, expected: String)
  case invalidValue(String, reason: String)
  case conflictingArguments(String, String)
  case noChanges

  var errorDescription: String? {
    switch self {
    case .invalidDate(let value):
      return "Invalid date \(value): expected a real date in YYYY-MM-DD format."
    case .invalidCursor(let value):
      return "Invalid cursor: \(value)"
    case .invalidIdentifier(let value):
      return "Invalid Things identifier: \(value)"
    case .entityNotFound(let value):
      return "No Things entity found for: \(value)"
    case .ambiguousReference(let value):
      return "Multiple Things entities matched: \(value)"
    case .entityTypeMismatch(let expected, let actual):
      return "Expected a \(expected) reference, received \(actual)."
    case .missingAuthToken:
      return "Could not read the Things URL auth token."
    case .missingRequiredArgument(let argument):
      return "Missing required argument: \(argument)"
    case .invalidType(let argument, let expected):
      return "Invalid argument type for \(argument): expected \(expected)"
    case .invalidValue(let argument, let reason):
      return "Invalid value for \(argument): \(reason)"
    case .conflictingArguments(let first, let second):
      return "Arguments \(first) and \(second) cannot be used together."
    case .noChanges:
      return "No changes were provided."
    }
  }
}

protocol ThingsRepository: AnyObject {
  func search(_ query: ThingsSearchQuery) throws -> ThingsPage<ThingsSearchHit>
  func fetch(_ reference: String, includeItems: Bool) throws -> ThingsEntity
  func listTodos(_ query: ThingsTodoQuery) throws -> ThingsPage<ThingsTodo>
  func getTodo(id: String) throws -> ThingsTodo
  func listHeadings(_ query: ThingsHeadingQuery) throws -> ThingsPage<ThingsHeading>
  func getHeading(idOrTitle: String, includeTodos: Bool) throws -> ThingsHeading
  func listProjects(_ query: ThingsProjectQuery) throws -> ThingsPage<ThingsProject>
  func getProject(idOrTitle: String, includeTodos: Bool) throws -> ThingsProject
  func listAreas(_ query: ThingsDirectoryQuery) throws -> ThingsPage<ThingsArea>
  func listTags(_ query: ThingsDirectoryQuery) throws -> ThingsPage<ThingsTag>
  func resolveShowTarget(_ target: String) throws -> ThingsReference
  func authToken() throws -> String?
}

extension ThingsRepository {
  func listHeadings(_ query: ThingsHeadingQuery) throws -> ThingsPage<ThingsHeading> {
    throw ThingsServiceError.entityNotFound("headings")
  }

  func getHeading(idOrTitle: String, includeTodos: Bool) throws -> ThingsHeading {
    throw ThingsServiceError.entityNotFound(idOrTitle)
  }
}
