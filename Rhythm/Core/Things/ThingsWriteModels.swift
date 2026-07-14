import Foundation

nonisolated enum ThingsPatch<Value: Equatable & Sendable>: Equatable, Sendable {
  case unchanged
  case clear
  case value(Value)

  var isChanged: Bool {
    self != .unchanged
  }
}

struct ThingsTodoSaveRequest: Equatable, Sendable {
  var id: String?
  var title: String?
  var notes: ThingsPatch<String> = .unchanged
  var prependNotes: String?
  var appendNotes: String?
  var when: ThingsPatch<String> = .unchanged
  var deadline: ThingsPatch<String> = .unchanged
  var tags: ThingsPatch<[String]> = .unchanged
  var addTags: [String]?
  var checklistItems: ThingsPatch<[String]> = .unchanged
  var prependChecklistItems: [String]?
  var appendChecklistItems: [String]?
  var destination: ThingsPatch<String> = .unchanged
  var heading: ThingsPatch<String> = .unchanged
  var status: ThingsItemStatus?
  var reveal = false

  nonisolated var isCreate: Bool { id == nil }
}

struct ThingsProjectSaveRequest: Equatable, Sendable {
  var id: String?
  var title: String?
  var notes: ThingsPatch<String> = .unchanged
  var prependNotes: String?
  var appendNotes: String?
  var when: ThingsPatch<String> = .unchanged
  var deadline: ThingsPatch<String> = .unchanged
  var tags: ThingsPatch<[String]> = .unchanged
  var addTags: [String]?
  var area: ThingsPatch<String> = .unchanged
  var status: ThingsItemStatus?
  var reveal = false

  nonisolated var isCreate: Bool { id == nil }
}

struct ThingsSaveResult: Encodable, Equatable, Sendable {
  let operation: String
  let type: ThingsEntityKind
  let ref: String?
  let title: String?
  let dispatched: Bool
  let message: String
}

struct ThingsShowResult: Encodable, Equatable, Sendable {
  let dispatched: Bool
  let ref: String
  let title: String
  let message: String
}
