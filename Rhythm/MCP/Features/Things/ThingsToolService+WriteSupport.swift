import Foundation
import OrderedCollections

extension ThingsToolService {
  func iso8601String(
    _ key: String,
    decoder: ToolArgumentsDecoder
  ) throws -> String? {
    guard let value = try decoder.optionalString(key) else { return nil }
    guard parseISO8601(value) != nil else {
      throw ThingsServiceError.invalidValue(key, reason: "expected an ISO 8601 timestamp")
    }
    return value
  }

  func validateProjectChildrenFinished(
    _ project: ThingsProject,
    includeHeadings: Bool,
    key: String,
    predictedTodoStatuses: [String: ThingsItemStatus] = [:]
  ) throws {
    for todoReference in project.todos ?? [] {
      let rawID = ThingsEntityID.parse(todoReference.id).rawID
      let status =
        try predictedTodoStatuses[rawID] ?? repository.getTodo(id: todoReference.id).status
      guard status == .completed || status == .canceled else {
        throw ThingsServiceError.invalidValue(
          key, reason: "all child todos must be completed or canceled")
      }
    }
    guard includeHeadings else { return }
    for headingReference in project.headings {
      let heading = try repository.getHeading(idOrTitle: headingReference.id, includeTodos: false)
      guard heading.status == .completed else {
        throw ThingsServiceError.invalidValue(key, reason: "all child headings must be archived")
      }
    }
  }

  func validateSchedule(
    _ patch: ThingsPatch<String>,
    key: String,
    isCreate: Bool
  ) throws {
    guard case .value(let value) = patch else { return }
    let bucket =
      value.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
      .first.map(String.init)?.lowercased() ?? ""
    if value.contains("@"), bucket == "anytime" || bucket == "someday" {
      throw ThingsServiceError.invalidValue(
        key, reason: "Things ignores reminder times combined with anytime or someday")
    }
    if !isCreate, bucket == "anytime" {
      throw ThingsServiceError.invalidValue(
        key, reason: "anytime is not supported by update URLs; use null to clear scheduling")
    }
  }

  func validateURLLength(
    _ value: String?,
    key: String,
    maximum: Int = 4_000
  ) throws {
    guard let value, value.count > maximum else { return }
    throw ThingsServiceError.invalidValue(
      key, reason: "maximum unencoded length is \(maximum) characters")
  }

  func validateURLLength(
    _ patch: ThingsPatch<String>,
    key: String,
    maximum: Int = 4_000
  ) throws {
    guard case .value(let value) = patch else { return }
    try validateURLLength(value, key: key, maximum: maximum)
  }

  func validateJoinedURLValues(
    _ values: [String]?,
    key: String,
    separator: String
  ) throws {
    for (index, value) in (values ?? []).enumerated() {
      guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw ThingsServiceError.invalidValue("\(key)[\(index)]", reason: "value must not be empty")
      }
      guard !value.contains(separator) else {
        throw ThingsServiceError.invalidValue(
          "\(key)[\(index)]", reason: "the value contains the Things '\(separator)' delimiter")
      }
    }
    try validateURLLength(values?.joined(separator: separator), key: key)
  }

  func validateJoinedURLValues(
    _ patch: ThingsPatch<[String]>,
    key: String,
    separator: String
  ) throws {
    guard case .value(let values) = patch else { return }
    try validateJoinedURLValues(values, key: key, separator: separator)
  }

  func validateLineSeparatedURLValues(
    _ values: [String]?,
    key: String,
    maximumCount: Int
  ) throws {
    guard let values else { return }
    try validateMaximumCount(values, key: key, maximum: maximumCount)
    for (index, value) in values.enumerated() {
      guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw ThingsServiceError.invalidValue("\(key)[\(index)]", reason: "value must not be empty")
      }
      guard value.rangeOfCharacter(from: .newlines) == nil else {
        throw ThingsServiceError.invalidValue(
          "\(key)[\(index)]", reason: "embedded newlines would create additional items")
      }
    }
    try validateURLLength(values.joined(separator: "\n"), key: key)
  }

  func validateLineSeparatedURLValues(
    _ patch: ThingsPatch<[String]>,
    key: String,
    maximumCount: Int
  ) throws {
    guard case .value(let values) = patch else { return }
    try validateLineSeparatedURLValues(values, key: key, maximumCount: maximumCount)
  }

  func validateNotFuture(_ value: String?, key: String) throws {
    guard let value, let date = parseISO8601(value), date > Date() else { return }
    throw ThingsServiceError.invalidValue(key, reason: "Things ignores dates in the future")
  }

  func parseISO8601(_ value: String) -> Date? {
    let standard = ISO8601DateFormatter()
    if let date = standard.date(from: value) { return date }
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions.insert(.withFractionalSeconds)
    return fractional.date(from: value)
  }

  func validateWriteTags(
    _ patch: ThingsPatch<[String]>,
    additional: [String]?
  ) async throws {
    var requested: [String] = additional ?? []
    if case .value(let values) = patch { requested.append(contentsOf: values) }
    let unique = Set(requested.map { $0.lowercased() })
    guard !unique.isEmpty else { return }

    try await activate()
    var missing = unique
    var offset = 0
    repeat {
      var query = ThingsDirectoryQuery()
      query.page = ThingsPageRequest(offset: offset, limit: ThingsPageRequest.maximumLimit)
      let page = try repository.listTags(query)
      for tag in page.items {
        missing.remove(tag.title.lowercased())
      }
      guard let cursor = page.nextCursor, let nextOffset = Int(cursor) else { break }
      offset = nextOffset
    } while !missing.isEmpty

    guard missing.isEmpty else {
      throw ThingsServiceError.invalidValue(
        "tags",
        reason:
          "Things ignores unknown tags; create these tags first: \(missing.sorted().joined(separator: ", "))"
      )
    }
  }

  func patchString(
    _ key: String,
    arguments: [String: Value]
  ) throws -> ThingsPatch<String> {
    guard let value = arguments[key] else { return .unchanged }
    if value.isNull { return .clear }
    guard let string = value.stringValue else {
      throw ThingsServiceError.invalidType(key, expected: "string or null")
    }
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? .clear : .value(trimmed)
  }

  func patchNotes(
    _ key: String,
    arguments: [String: Value]
  ) throws -> ThingsPatch<String> {
    guard let value = arguments[key] else { return .unchanged }
    if value.isNull { return .clear }
    guard let string = value.stringValue else {
      throw ThingsServiceError.invalidType(key, expected: "string or null")
    }
    return string.isEmpty ? .clear : .value(string)
  }

  func optionalNotesMutation(
    _ key: String,
    arguments: [String: Value]
  ) throws -> String? {
    guard let value = arguments[key] else { return nil }
    guard let string = value.stringValue else {
      throw ThingsServiceError.invalidType(key, expected: "string")
    }
    return string.isEmpty ? nil : string
  }

  func patchStringArray(
    _ key: String,
    arguments: [String: Value]
  ) throws -> ThingsPatch<[String]> {
    guard let value = arguments[key] else { return .unchanged }
    if value.isNull { return .clear }
    guard let values = value.arrayValue else {
      throw ThingsServiceError.invalidType(key, expected: "array of strings or null")
    }
    let normalized = try values.enumerated().map { index, value -> String in
      guard let string = value.stringValue else {
        throw ThingsServiceError.invalidType("\(key)[\(index)]", expected: "string")
      }
      let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else {
        throw ThingsServiceError.invalidValue("\(key)[\(index)]", reason: "value must not be empty")
      }
      return trimmed
    }
    return normalized.isEmpty ? .clear : .value(normalized)
  }

  func normalizedArray(
    _ key: String,
    decoder: ToolArgumentsDecoder
  ) throws -> [String]? {
    guard let values = try decoder.optionalStringArray(key) else { return nil }
    guard !values.isEmpty else {
      throw ThingsServiceError.invalidValue(key, reason: "array must not be empty")
    }
    return values
  }

  func validateMaximumCount<T>(
    _ values: [T]?,
    key: String,
    maximum: Int
  ) throws {
    guard let values, values.count > maximum else { return }
    throw ThingsServiceError.invalidValue(key, reason: "maximum item count is \(maximum)")
  }

  func optionalMutableStatus(
    _ key: String,
    decoder: ToolArgumentsDecoder
  ) throws -> ThingsItemStatus? {
    let status = try decoder.optionalEnumValue(for: key, as: ThingsItemStatus.self)
    if status == .all {
      throw ThingsServiceError.invalidValue(key, reason: "all is only valid for reads")
    }
    return status
  }

  func validateTextMutationConflicts(
    replacement: ThingsPatch<String>,
    prepend: String?,
    append: String?,
    field: String
  ) throws {
    if replacement.isChanged && (prepend != nil || append != nil) {
      throw ThingsServiceError.conflictingArguments(field, "prepend_\(field)/append_\(field)")
    }
  }

  func validateReferencePatch(
    _ patch: ThingsPatch<String>,
    argument: String,
    expectedKind: ThingsEntityKind?
  ) throws {
    guard case .value(let value) = patch else { return }
    guard let actualKind = ThingsEntityID.parse(value).kind else { return }
    guard actualKind == expectedKind else {
      let expected = expectedKind?.rawValue ?? "unprefixed heading"
      throw ThingsServiceError.invalidValue(
        argument,
        reason: "expected \(expected) ID or title, received \(actualKind.rawValue) reference"
      )
    }
  }
}

struct ThingsWriteResult: Encodable, Sendable {
  let operation: String
  let type: ThingsEntityKind
  let ref: String?
  let refs: [String]
  let title: String?
  let acknowledged: Bool
  let verified: Bool
  let parameters: [String: [String]]
  let message: String
}
