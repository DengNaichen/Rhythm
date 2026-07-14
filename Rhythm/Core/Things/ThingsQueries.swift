import Foundation

struct ThingsSearchQuery: Equatable, Sendable {
  let query: String
  let type: ThingsEntityKind
  let includeCompleted: Bool
  let includeCanceled: Bool
  let page: ThingsPageRequest
  var includeTrashed = false
}

struct ThingsTodoQuery: Equatable, Sendable {
  var list: ThingsBuiltinList = .all
  var query: String?
  var status: ThingsItemStatus = .incomplete
  var project: String?
  var area: String?
  var heading: String?
  var tag: String?
  var includeInheritedTags = true
  var evening: Bool?
  var hasReminder: Bool?
  var reminderFrom: String?
  var reminderTo: String?
  var isLogged: Bool?
  var createdFrom: String?
  var createdTo: String?
  var updatedFrom: String?
  var updatedTo: String?
  var completedFrom: String?
  var completedTo: String?
  var scheduledOn: String?
  var scheduledFrom: String?
  var scheduledTo: String?
  var deadlineOn: String?
  var deadlineFrom: String?
  var deadlineTo: String?
  var orderBy: ThingsOrderBy = .things
  var orderDirection: ThingsOrderDirection = .ascending
  var page = ThingsPageRequest()
}

struct ThingsProjectQuery: Equatable, Sendable {
  var query: String?
  var status: ThingsItemStatus = .incomplete
  var area: String?
  var tag: String?
  var includeInheritedTags = true
  var evening: Bool?
  var hasReminder: Bool?
  var reminderFrom: String?
  var reminderTo: String?
  var isLogged: Bool?
  var createdFrom: String?
  var createdTo: String?
  var updatedFrom: String?
  var updatedTo: String?
  var completedFrom: String?
  var completedTo: String?
  var when: ThingsBuiltinList = .all
  var deadlineFrom: String?
  var deadlineTo: String?
  var includeTodos = false
  var orderBy: ThingsOrderBy = .things
  var orderDirection: ThingsOrderDirection = .ascending
  var page = ThingsPageRequest()
}

struct ThingsHeadingQuery: Equatable, Sendable {
  var query: String?
  var status: ThingsItemStatus = .all
  var project: String?
  var isLogged: Bool?
  var includeTrashed = false
  var includeTodos = false
  var orderBy: ThingsOrderBy = .things
  var orderDirection: ThingsOrderDirection = .ascending
  var page = ThingsPageRequest()
}

struct ThingsDirectoryQuery: Equatable, Sendable {
  var query: String?
  var includeItems = false
  var page = ThingsPageRequest()
}
